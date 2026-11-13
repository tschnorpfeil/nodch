import AppKit
import NodchCore
import ServiceManagement
import SwiftUI

/// `Nodch --snapshot`: the Settings window in its typical states, light and dark, at 2x. A dictionary stands in for
/// the Keychain, defaults come from a suite nothing writes to, and no test reaches a network.
@MainActor
enum SettingsSnapshots {
    final class MemoryTokens: TokenStore {
        var items: [String: String] = [:]
        func token(account: String) -> String? { items[account] }
        func setToken(_ token: String, account: String) throws { items[account] = token }
        func removeToken(account: String) throws { items[account] = nil }
    }

    final class MemoryDefaults: SettingsDefaults {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    struct Scene {
        var name: String
        var environment: [String: String] = [:]
        var server = ""
        var storedToken = false
        var tokenEntry = ""
        var test = SettingsModel.Test.idle
        var login = SMAppService.Status.notRegistered
    }

    static let scenes: [Scene] = [
        Scene(name: "settings-first-run"),
        Scene(name: "settings-saved-token", server: "http://localhost:4310", storedToken: true,
              test: .done(.connected, address: ConnectionSettings.defaultURL), login: .enabled),
        Scene(name: "settings-environment", environment: ["NOD_URL": "http://localhost:4310", "NOD_AUTH_TOKEN": "snapshot"],
              login: .requiresApproval),
        Scene(name: "settings-test-failed", server: "http://127.0.0.1:4310", tokenEntry: "snapshot-token",
              test: .done(.hostNotPermitted, address: URL(string: "http://127.0.0.1:4310")!)),
    ]

    /// Returns how many PNGs it wrote, out of `scenes.count * 2`.
    static func run(into folder: URL) async -> Int {
        var written = 0
        for scene in scenes {
            for dark in [false, true] {
                let file = folder.appendingPathComponent("\(scene.name)-\(dark ? "dark" : "light").png")
                if await render(scene, dark: dark, to: file) { written += 1 } else {
                    FileHandle.standardError.write(Data("nodch: could not write \(file.lastPathComponent)\n".utf8))
                }
            }
        }
        return written
    }

    private static func render(_ scene: Scene, dark: Bool, to file: URL) async -> Bool {
        let tokens = MemoryTokens()
        if scene.storedToken, let address = try? ConnectionSettings.normalize(scene.server) {
            tokens.items[ConnectionSettings.origin(address)] = "snapshot"
        }
        let settings = ConnectionSettings(defaults: MemoryDefaults(), tokens: tokens)
        let commands = AppCommands(loginItem: FixedLoginItem(scene.login))
        let model = SettingsModel(settings: settings, commands: commands, environment: scene.environment)
        model.tester = { _ in .unreachable }
        model.server = scene.server
        model.tokenEntry = scene.tokenEntry
        model.test = scene.test

        let controller = NSHostingController(rootView: SettingsView(model: model).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 460, height: 400), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentViewController = controller
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Measure until the height settles: the form measures its rows over a few passes.
        var size = NSSize(width: 460, height: 400)
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(100))
            let fit = controller.sizeThatFits(in: NSSize(width: 460, height: 4000))
            if fit.height > 10 { size = NSSize(width: 460, height: ceil(fit.height)) }
            window.setContentSize(size)
            controller.view.frame = NSRect(origin: .zero, size: size)
            controller.view.layoutSubtreeIfNeeded()
        }
        let host = controller.view
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: file) } catch { return false }
        return true
    }
}
