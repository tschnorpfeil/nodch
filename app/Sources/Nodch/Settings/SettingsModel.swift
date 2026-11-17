import AppKit
import Carbon.HIToolbox
import NodchCore
import Observation
import ServiceManagement

/// The Settings window's state: the address and token being edited, the last test, the prompt's shortcut and
/// dictation language, and the login item. The connection is stored only on Save, and Test connection sends one
/// GET /api/state with what is in the fields; a shortcut or a language takes effect as soon as it is chosen.
@MainActor @Observable final class SettingsModel {
    enum Test: Equatable {
        case idle
        case testing
        case done(ConnectionCheck, address: URL)
        /// The address could not be read, so nothing was sent.
        case invalid(String)
    }

    /// NOD_* variables that are set; when any is, the environment decides and the fields are read-only.
    let environment: [String]
    /// The address in effect when the environment decides.
    let environmentAddress: URL?
    var server: String { didSet { if server != oldValue { serverChanged() } } }
    /// A new token typed into the secure field; empty keeps whatever is stored.
    var tokenEntry = "" { didSet { if tokenEntry != oldValue { resetTest(); saved = nil } } }
    /// The token stored for the address in the field.
    private(set) var storedToken = false
    /// Remove was clicked: the stored token goes on Save.
    private(set) var removing = false
    var test = Test.idle
    /// After Save: nil before, "" on success, otherwise why it failed.
    var saved: String?
    /// After Save: the saved connection is tried; nil outside of that.
    enum SavedCheck: Equatable {
        case checking
        case done(ConnectionCheck, address: URL)
    }
    private(set) var savedCheck: SavedCheck?
    var loginError: String?
    /// "Save on this Mac": what became of keeping the environment's connection.
    enum Kept: Equatable {
        case no
        /// Saved; the saved connection is being tried without the environment.
        case checking
        case saved(ConnectionCheck, address: URL)
        /// Nothing was saved, and why.
        case failed(String)
    }
    private(set) var kept = Kept.no
    /// The environment's address and token are the saved ones already.
    private(set) var keepsEnvironment = false

    @ObservationIgnored private let environmentValues: [String: String]
    @ObservationIgnored let settings: ConnectionSettings
    @ObservationIgnored let commands: AppCommands
    @ObservationIgnored var tester: (NodConfiguration) async -> ConnectionCheck = { await ConnectionCheck.run($0) }
    /// Saved settings take effect: the running connection starts again with them.
    @ObservationIgnored var onSaved: () -> Void = {}
    @ObservationIgnored private var testRun = 0

    /// Settings opened by itself at the first run: the guidance leads the connection section.
    private(set) var firstRunLead = false
    /// The first action to take, until the person edits or checks the connection.
    private(set) var firstRunNextStep: String?

    /// The shortcut asked for and what became of it.
    private(set) var hotkey = HotkeyStatus.on(.standard)
    /// Why the shortcut does not work: at launch, or the one just chosen, which was then not kept.
    private(set) var hotkeyMessage: String?
    /// Waiting for the keys of a new shortcut; the current one is suspended meanwhile.
    private(set) var recording = false
    /// The keys just pressed cannot be a shortcut.
    private(set) var recordingHint: String?
    /// The dictation language; nil follows the system.
    private(set) var speechChoice: String?
    /// Where "Open Nod" goes.
    private(set) var openTarget = OpenTarget.automatic
    /// The languages the on-device model offers, grouped as in the microphone's menu.
    var speechLanguages: (yours: [String], others: [String]) = ([], [])

    @ObservationIgnored let defaults: SettingsDefaults
    /// The shortcut in effect.
    @ObservationIgnored var currentHotkey: () -> HotkeyStatus = { .on(.standard) }
    /// Registers a shortcut and saves it to the defaults given when it works; returns what became of it. The app
    /// passes `HotkeyCenter`; without it every shortcut is accepted.
    @ObservationIgnored var chooseHotkey: (HotkeySpec.Setting, SettingsDefaults) -> HotkeyStatus = { setting, defaults in
        PromptSettings.chooseHotkey(setting, previous: setting, defaults: defaults) { tried in
            if case .on(let spec) = tried { .on(spec) } else { .off }
        }.chosen
    }
    @ObservationIgnored var suspendHotkey: () -> Void = {}
    @ObservationIgnored var resumeHotkey: () -> Void = {}
    /// The shortcut in effect changed: the island's hint follows.
    @ObservationIgnored var onHotkeyChanged: (HotkeyStatus) -> Void = { _ in }
    /// The dictation language changed: the microphone follows.
    @ObservationIgnored var onSpeechLanguage: (String?) -> Void = { _ in }
    @ObservationIgnored var supportedLanguages: () async -> [String] = { await SpeechSupport.supported() }
    @ObservationIgnored private var keyMonitor: Any?

    init(settings: ConnectionSettings, commands: AppCommands, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.settings = settings
        self.commands = commands
        defaults = settings.defaults
        environmentValues = environment
        keepsEnvironment = settings.keeps(environment: environment)
        self.environment = ConnectionSettings.environmentInEffect(environment)
        environmentAddress = self.environment.isEmpty ? nil : (try? NodConfiguration.fromEnvironment(environment))?.baseURL
        // With the environment in charge the field shows the address in effect, read-only.
        server = (environmentAddress ?? settings.savedServer).map(ConnectionCheck.display) ?? ""
        storedToken = currentAddress.map { settings.token(for: $0) != nil } ?? false
        speechChoice = PromptSettings.speechLanguage(defaults)
        openTarget = OpenTarget.saved(defaults)
    }

    var usesEnvironment: Bool { !environment.isEmpty }

    /// "Using NOD_URL and NOD_AUTH_TOKEN from the environment".
    var environmentNote: String {
        let names = environment.count < 3 ? environment.joined(separator: " and ")
            : environment.dropLast().joined(separator: ", ") + " and " + environment.last!
        return "Using \(names) from the environment"
    }

    var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "nodch (development build)" }
        return "nodch \(short)"
    }

    /// A token being typed stays visible (as dots) in its field, also after the address changes: it is the one Test
    /// and Save use, never one hidden behind "Saved in Keychain".
    var showsStoredToken: Bool { storedToken && !removing && tokenEntry.isEmpty }

    /// Taken before the launch check starts: its result applies only if nothing was tested, saved or edited since.
    var firstRunStamp: Int { testRun }

    /// Show the launch failure only if the person has not already edited or checked the connection.
    @discardableResult
    func showFirstRun(_ check: ConnectionCheck, address: URL, since stamp: Int) -> Bool {
        guard !usesEnvironment, stamp == testRun, test == .idle, saved == nil else { return false }
        firstRunLead = true
        firstRunNextStep = check.message(address: address, inSettings: true) + " Then test the connection."
        return true
    }

    /// The guidance goes once the saved connection works.
    var showsFirstRunLead: Bool {
        if case .done(.connected, _) = savedCheck { return false }
        return firstRunLead
    }

    /// The fields differ from what is saved, so a good test is not yet a kept connection.
    var needsSave: Bool {
        guard let address = currentAddress else { return true }
        return tokenChange != .keep || settings.savedServer != address
    }

    /// How to ask once connected: the registered shortcut, or where to choose one.
    var askHint: String {
        hotkey.inEffect.map { "Press \($0.display) to ask Nod." } ?? "Choose a shortcut below to ask Nod."
    }

    /// A test still running belongs to inputs that are gone: its result is dropped.
    private func resetTest() {
        testRun += 1
        test = .idle
        savedCheck = nil
        firstRunNextStep = nil
    }

    private var currentAddress: URL? { try? ConnectionSettings.normalize(server) }

    private func serverChanged() {
        resetTest()
        saved = nil
        removing = false
        storedToken = currentAddress.map { settings.token(for: $0) != nil } ?? false
    }

    func removeToken() {
        removing = true
        tokenEntry = ""
        resetTest()
        saved = nil
    }

    func undoRemove() {
        removing = false
        resetTest()
        saved = nil
    }

    private var tokenChange: TokenChange {
        if !tokenEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .replace(tokenEntry) }
        return removing ? .remove : .keep
    }

    /// One GET /api/state with the address and token in the fields.
    func runTest() {
        guard !usesEnvironment else { return }
        firstRunNextStep = nil
        let address: URL
        do { address = try ConnectionSettings.normalize(server) } catch {
            test = .invalid(IslandModel.describe(error)); return
        }
        let token: String? = switch tokenChange {
        case .replace(let value): value.trimmingCharacters(in: .whitespacesAndNewlines)
        case .keep: settings.token(for: address)
        case .remove: nil
        }
        testRun += 1
        let run = testRun
        test = .testing
        Task {
            let result = await tester(NodConfiguration(baseURL: address, credential: token.map { .bearer($0) } ?? .none))
            guard run == testRun else { return }
            test = .done(result, address: address)
        }
    }

    func save() {
        guard !usesEnvironment else { return }
        firstRunNextStep = nil
        do {
            let address = try settings.save(server: server, token: tokenChange)
            // Setting the fields resets the test and the saved note, so the note comes last.
            server = ConnectionCheck.display(address)
            tokenEntry = ""
            removing = false
            storedToken = settings.token(for: address) != nil
            resetTest()
            saved = ""
            onSaved()
            checkSaved(address)
        } catch {
            saved = IslandModel.describe(error)
        }
    }

    /// One GET /api/state with what was just saved (the token from the Keychain), shown in place of the static note.
    private func checkSaved(_ address: URL) {
        let configuration = NodConfiguration(baseURL: address, credential: settings.token(for: address).map { .bearer($0) } ?? .none)
        let run = testRun
        savedCheck = .checking
        Task {
            let result = await ConnectionCheck.afterSave(configuration, tester: tester)
            // Edited since: the result belongs to inputs that are gone.
            guard run == testRun else { return }
            savedCheck = .done(result.check, address: address)
        }
    }

    /// The environment has a token that can be saved for starts without it.
    var canKeepEnvironment: Bool { ConnectionSettings.canKeep(environmentValues) }

    /// Saves the environment's address and token, then tries the saved connection the way a start from the Finder
    /// would use it: one GET /api/state without the environment.
    func keepEnvironment() {
        guard canKeepEnvironment, kept != .checking else { return }
        do {
            let address = try settings.keep(environment: environmentValues)
            keepsEnvironment = true
            storedToken = settings.token(for: address) != nil
            let saved = try settings.resolve(environment: [:])
            kept = .checking
            Task { kept = .saved(await tester(saved.configuration), address: address) }
        } catch {
            kept = .failed(IslandModel.describe(error))
        }
    }

    // MARK: Prompt

    /// When the window shows: the shortcut in effect (and why it does not work), and the language the microphone's
    /// menu may have changed meanwhile.
    func refreshPrompt() {
        hotkey = currentHotkey()
        hotkeyMessage = hotkey.message
        speechChoice = PromptSettings.speechLanguage(defaults)
        guard speechLanguages.yours.isEmpty, speechLanguages.others.isEmpty else { return }
        Task { speechLanguages = SpeechLanguage.menu(supported: await supportedLanguages(), system: Locale.preferredLanguages) }
    }

    static let recordingRule = "Use a letter, digit, Space, Return or Tab with at least one of ⌃ ⌥ ⇧ ⌘."

    /// The next key down with a modifier becomes the shortcut; Escape cancels. Keys reach only Settings meanwhile.
    func startRecording() {
        guard !recording else { return }
        recording = true
        recordingHint = nil
        suspendHotkey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = UInt32(event.keyCode), modifiers = Self.carbonModifiers(event.modifierFlags)
            MainActor.assumeIsolated { self?.pressed(keyCode: code, modifiers: modifiers) }
            return nil
        }
    }

    /// Also when the window closes or loses the keyboard mid-recording: the previous shortcut comes back.
    func cancelRecording() {
        guard recording else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recording = false
        recordingHint = nil
        resumeHotkey()
        // Registering again can turn out differently than before the recording: show what is in effect now.
        hotkey = currentHotkey()
        hotkeyMessage = hotkey.message
        onHotkeyChanged(hotkey)
    }

    func pressed(keyCode: UInt32, modifiers: UInt32) {
        if keyCode == UInt32(kVK_Escape) && modifiers == 0 { cancelRecording(); return }
        guard let spec = HotkeySpec.from(keyCode: keyCode, modifiers: modifiers) else {
            recordingHint = Self.recordingRule
            return
        }
        choose(.on(spec))
    }

    /// A recorded shortcut, Reset or Turn off. A taken shortcut is not kept, and the message says why.
    func choose(_ setting: HotkeySpec.Setting) {
        cancelRecording()
        let chosen = chooseHotkey(setting, defaults)
        hotkey = currentHotkey()
        hotkeyMessage = chosen.message
        onHotkeyChanged(hotkey)
    }

    /// Automatic (nil) removes the saved choice; the microphone's menu reads the same default.
    func chooseSpeechLanguage(_ id: String?) {
        guard id != speechChoice else { return }
        speechChoice = id
        PromptSettings.setSpeechLanguage(id, defaults: defaults)
        onSpeechLanguage(id)
    }

    nonisolated static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    /// Takes effect at the next "Open Nod".
    func chooseOpenTarget(_ target: OpenTarget) {
        guard target != openTarget else { return }
        openTarget = target
        OpenTarget.save(target, defaults: defaults)
    }

    // MARK: Start at login

    var loginStatus: SMAppService.Status { commands.loginStatus }

    func setStartsAtLogin(_ on: Bool) {
        loginError = commands.setStartsAtLogin(on)
    }

    func openLoginItems() { commands.loginItem?.openSystemSettings() }
}
