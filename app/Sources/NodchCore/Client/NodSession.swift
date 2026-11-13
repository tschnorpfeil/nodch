import AppKit
import Foundation

@MainActor public final class NodSession: NodActions {
    public let store: IslandStore
    public let client: NodClient
    private var mapper: NodStateMapper
    private var latest: NodState?
    private var connectionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var fetchTask: Task<NodState, Error>?
    private var doneTask: Task<Void, Never>?
    private var retryWait: Task<Void, Never>?
    private var refreshPending = false
    private var generation = 0
    private let reconnectBase: TimeInterval
    private let reconnectCap: TimeInterval
    private let retryBase: TimeInterval
    private let retryCap: TimeInterval

    public init(client: NodClient, store: IslandStore = IslandStore(), doneDuration: TimeInterval = 3,
                reconnectBase: TimeInterval = 0.5, reconnectCap: TimeInterval = 15,
                retryBase: TimeInterval = 1, retryCap: TimeInterval = 30) {
        self.client = client; self.store = store; self.mapper = NodStateMapper(doneDuration: doneDuration)
        self.reconnectBase = max(0.01, reconnectBase)
        self.reconnectCap = max(self.reconnectBase, reconnectCap)
        self.retryBase = max(0.01, retryBase)
        self.retryCap = max(self.retryBase, retryCap)
        store.actions = self
    }

    deinit { connectionTask?.cancel(); refreshTask?.cancel(); retryWait?.cancel(); fetchTask?.cancel(); doneTask?.cancel() }

    /// Start once after constructing the session; disconnect when its owner stops observing.
    public func start() {
        guard connectionTask == nil else { return }
        let base = reconnectBase, cap = reconnectCap
        connectionTask = Task { [weak self, client] in
            var delay = base
            while !Task.isCancelled {
                let connectedAt = Date()
                do {
                    for try await event in client.events() {
                        guard !Task.isCancelled else { return }
                        switch event {
                        case .connected: self?.requestRefresh()
                        case .update(let type):
                            if ["refresh", "working", "activity"].contains(type) { self?.requestRefresh() }
                        }
                    }
                    if !Task.isCancelled { self?.show(NodClientError.network("Event stream disconnected.")) }
                } catch {
                    if Task.isCancelled { return }
                    self?.show(error)
                }
                if Date().timeIntervalSince(connectedAt) > 30 { delay = base }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                delay = min(cap, delay * 2)
            }
        }
    }

    public func disconnect() {
        generation += 1
        connectionTask?.cancel(); connectionTask = nil
        refreshTask?.cancel(); refreshTask = nil
        retryWait?.cancel(); retryWait = nil
        fetchTask?.cancel(); fetchTask = nil
        doneTask?.cancel(); doneTask = nil
        refreshPending = false
    }

    /// Concurrent refresh requests share one GET; no mutation uses this retry path.
    public func refresh() async throws {
        if let fetchTask { _ = try await fetchTask.value; return }
        let currentGeneration = generation
        let task = Task { [weak self, client] () throws -> NodState in
            do {
                let state = try await client.state()
                try Task.checkCancellation()
                guard let self, self.generation == currentGeneration else { throw CancellationError() }
                self.fetchTask = nil
                self.latest = state
                self.apply(state)
                return state
            } catch {
                if let self, self.generation == currentGeneration {
                    self.fetchTask = nil
                    if !(error is CancellationError) { self.show(error) }
                }
                throw error
            }
        }
        fetchTask = task
        _ = try await task.value
    }

    /// A failed fetch is retried with backoff (retryBase doubling up to retryCap), because the event
    /// stream may stay connected and quiet. A new request or event cuts the wait short. This also covers
    /// 401 and missing credentials: Nod may restart with a new key, and the cap keeps it to a few GETs a minute.
    private func requestRefresh() {
        refreshPending = true
        retryWait?.cancel()
        guard refreshTask == nil else { return }
        let currentGeneration = generation
        refreshTask = Task { [weak self] in
            await Task.yield()
            var delay = self?.retryBase ?? 1
            while !Task.isCancelled, let self, self.generation == currentGeneration, self.refreshPending {
                self.refreshPending = false
                do { try await self.refresh(); delay = self.retryBase }
                catch {
                    if error is CancellationError || self.refreshPending { continue }
                    let wait = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(delay)) }
                    self.retryWait = wait
                    await wait.value
                    if self.retryWait == wait { self.retryWait = nil }
                    // Slept the full time: try again. Cancelled: a new request already set refreshPending.
                    if !wait.isCancelled { self.refreshPending = true }
                    delay = min(self.retryCap, delay * 2)
                }
            }
            if self?.generation == currentGeneration { self?.refreshTask = nil }
        }
    }

    /// After a change: a fetch already in flight predates it, so wait that out and then fetch again.
    private func refreshAfterChange() {
        let older = fetchTask
        Task { [weak self] in
            if let older { _ = try? await older.value }
            self?.requestRefresh()
        }
    }

    private func apply(_ state: NodState) {
        store.state = mapper.map(state)
        store.answer = mapper.answer(state)
        if case .done = store.state {
            guard doneTask == nil else { return }
            doneTask = Task { [weak self] in
                guard let duration = self?.mapper.doneDuration else { return }
                do { try await Task.sleep(for: .seconds(duration)) } catch { return }
                guard let self, let latest = self.latest else { return }
                self.store.state = self.mapper.map(latest)
                self.doneTask = nil
            }
        } else { doneTask?.cancel(); doneTask = nil }
    }

    private func show(_ error: Error) {
        doneTask?.cancel(); doneTask = nil
        store.state = .offline(reason: error.localizedDescription)
    }

    public func send(prompt: String, attachments: [NodAttachment]) async throws {
        do { _ = try await client.send(prompt: prompt, attachments: attachments); refreshAfterChange() }
        catch { handleActionError(error); throw error }
    }

    public func upload(file: URL) async throws -> NodAttachment {
        do { return try await client.upload(file: file) }
        catch { handleActionError(error); throw error }
    }

    public func answer(approval: PendingApproval, approved: Bool) async throws {
        do { _ = try await client.answer(approval: approval, approved: approved); refreshAfterChange() }
        catch let error as NodClientError { try await handleAnswerError(error) }
    }

    public func answer(question: NodAnswer, choices: [NodQuestion.Choice], text: String) async throws {
        do { _ = try await client.answer(question: question, choices: choices, text: text); refreshAfterChange() }
        catch let error as NodClientError { try await handleAnswerError(error) }
    }

    /// A 409 means the approval or question is gone (Nod: `question_unavailable` for questions).
    private func handleAnswerError(_ error: NodClientError) async throws -> Never {
        if case .conflict = error {
            // Wait out any older snapshot, then fetch after the conflict. Never repeat the POST.
            if let fetchTask { _ = try? await fetchTask.value }
            try? await refresh()
        } else { handleActionError(error) }
        throw error
    }

    public func stop() async throws {
        do { try await client.stop(); refreshAfterChange() }
        catch { handleActionError(error); throw error }
    }

    private func handleActionError(_ error: Error) {
        if let error = error as? NodClientError {
            switch error {
            case .unauthorized, .credentials, .network: show(error)
            default: break
            }
        }
    }

    public func openNod(path: String) {
        let workspace = NSWorkspace.shared
        let fallbackURL = client.configuration.browserURL(path: path)
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: "dev.nod.desktop") else {
            workspace.open(fallbackURL)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: appURL, configuration: configuration) { app, error in
            if app == nil || error != nil {
                Task { @MainActor in NSWorkspace.shared.open(fallbackURL) }
            }
        }
    }
}
