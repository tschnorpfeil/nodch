import Foundation
import NodchCore
import Observation
import ServiceManagement

/// The Settings window's state: the address and token being edited, the last test, and the login item. Nothing is
/// stored until Save, and Test connection sends one GET /api/state with what is in the fields.
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
    var tokenEntry = "" { didSet { if tokenEntry != oldValue { test = .idle; saved = nil } } }
    /// The token stored for the address in the field.
    private(set) var storedToken = false
    /// Remove was clicked: the stored token goes on Save.
    private(set) var removing = false
    var test = Test.idle
    /// After Save: nil before, "" on success, otherwise why it failed.
    var saved: String?
    var loginError: String?

    @ObservationIgnored let settings: ConnectionSettings
    @ObservationIgnored let commands: AppCommands
    @ObservationIgnored var tester: (NodConfiguration) async -> ConnectionCheck = { await ConnectionCheck.run($0) }
    /// Saved settings take effect: the running connection starts again with them.
    @ObservationIgnored var onSaved: () -> Void = {}
    @ObservationIgnored private var testRun = 0

    init(settings: ConnectionSettings, commands: AppCommands, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.settings = settings
        self.commands = commands
        self.environment = ConnectionSettings.environmentInEffect(environment)
        environmentAddress = self.environment.isEmpty ? nil : (try? NodConfiguration.fromEnvironment(environment))?.baseURL
        // With the environment in charge the field shows the address in effect, read-only.
        server = (environmentAddress ?? settings.savedServer).map(ConnectionCheck.display) ?? ""
        storedToken = currentAddress.map { settings.token(for: $0) != nil } ?? false
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

    var showsStoredToken: Bool { storedToken && !removing }

    private var currentAddress: URL? { try? ConnectionSettings.normalize(server) }

    private func serverChanged() {
        test = .idle
        saved = nil
        removing = false
        storedToken = currentAddress.map { settings.token(for: $0) != nil } ?? false
    }

    func removeToken() {
        removing = true
        tokenEntry = ""
        test = .idle
        saved = nil
    }

    func undoRemove() { removing = false }

    private var tokenChange: TokenChange {
        if !tokenEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .replace(tokenEntry) }
        return removing ? .remove : .keep
    }

    /// One GET /api/state with the address and token in the fields.
    func runTest() {
        guard !usesEnvironment else { return }
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
        do {
            let address = try settings.save(server: server, token: tokenChange)
            // Setting the fields resets the test and the saved note, so the note comes last.
            server = ConnectionCheck.display(address)
            tokenEntry = ""
            removing = false
            storedToken = settings.token(for: address) != nil
            saved = ""
            onSaved()
        } catch {
            saved = IslandModel.describe(error)
        }
    }

    // MARK: Start at login

    var loginStatus: SMAppService.Status { commands.loginStatus }

    func setStartsAtLogin(_ on: Bool) {
        loginError = commands.setStartsAtLogin(on)
    }

    func openLoginItems() { commands.loginItem?.openSystemSettings() }
}
