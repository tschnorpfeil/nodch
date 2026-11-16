import NodchCore
import ServiceManagement
import SwiftUI

/// nodch Settings: which Nod to talk to, the prompt's shortcut and dictation language, Start at login, and what nodch is.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if model.usesEnvironment { environmentSection }
                connectionSection
                openSection
                promptSection
                Section {
                    loginRow
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            footer
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var environmentSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.environmentNote).font(.body.weight(.semibold))
                    Text(environmentDetail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "terminal").foregroundStyle(.secondary)
            }
            if model.canKeepEnvironment { keepRow }
        }
    }

    private var environmentDetail: String {
        let rule = "nodch ignores the fields below while the environment sets the connection. Change it where nodch is started, for example in its LaunchAgent."
        guard model.canKeepEnvironment, !model.keepsEnvironment else { return rule }
        return rule + " Opened from the Finder, nodch has no environment: save the connection on this Mac to stay connected there too."
    }

    @ViewBuilder private var keepRow: some View {
        switch model.kept {
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Saved. Trying it without the environment…").foregroundStyle(.secondary) }
        case .saved(.connected, _):
            status("Saved on this Mac. nodch connects without the environment too.", symbol: "checkmark.circle.fill", color: .green)
        case .saved:
            // The fields below are locked here, so the usual advice to check them would lead nowhere.
            status("Saved on this Mac, but a try without the environment did not connect. nodch keeps using the environment.",
                   symbol: "exclamationmark.triangle.fill", color: .orange)
        case .failed(let reason):
            HStack(alignment: .firstTextBaseline) {
                status(reason, symbol: "exclamationmark.triangle.fill", color: .red)
                Spacer(minLength: 8)
                Button("Save on this Mac") { model.keepEnvironment() }
            }
        case .no:
            if model.keepsEnvironment {
                status("Also saved on this Mac, for when nodch starts without the environment.", symbol: "key.fill", color: .secondary)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Button("Save on this Mac") { model.keepEnvironment() }
                }
            }
        }
    }

    private var connectionSection: some View {
        Section {
            TextField("Server", text: $model.server, prompt: Text(verbatim: ConnectionCheck.display(ConnectionSettings.defaultURL)))
                .textContentType(.URL)
                .autocorrectionDisabled()
            tokenRow
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Test connection") { model.runTest() }
                    .disabled(model.test == .testing)
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
            if model.test != .idle || model.saved != nil {
                testResult.frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Nod")
        } footer: {
            Text("Use the address you open Nod at, for example http://localhost:4310. If your Nod uses a token, it is the NOD_AUTH_TOKEN in Nod’s .env.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(model.usesEnvironment)
    }

    /// Not in the connection section: it works while the environment decides the connection.
    private var openSection: some View {
        Section {
            Picker("Open Nod in", selection: Binding(get: { model.openTarget }, set: { model.chooseOpenTarget($0) })) {
                ForEach(OpenTarget.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } footer: {
            Text("Automatic opens the Nod app for a Nod on this Mac and the browser otherwise.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var promptSection: some View {
        Section {
            shortcutRow
            if let hint = model.recordingHint {
                Text(hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let message = model.hotkeyMessage, !model.recording {
                status(message, symbol: "exclamationmark.triangle.fill", color: .orange)
            }
            languageRow
        } header: {
            Text("Prompt")
        }
    }

    private var shortcutText: String {
        if model.recording { return "Press a shortcut…" }
        return model.hotkey.spec?.display ?? "Off"
    }

    private var shortcutRow: some View {
        LabeledContent("Shortcut") {
            HStack(spacing: 6) {
                Button {
                    if model.recording { model.cancelRecording() } else { model.startRecording() }
                } label: {
                    Text(shortcutText)
                        .foregroundStyle(model.recording || model.hotkey.spec == nil ? .secondary : .primary)
                        .frame(minWidth: 120)
                }
                .accessibilityLabel("Shortcut")
                .accessibilityValue(shortcutText)
                .accessibilityHint(model.recording ? "Press the new shortcut, or Escape to cancel" : "Click, then press a new shortcut")
                Menu {
                    Button("Reset to \(HotkeySpec.standard.display)") { model.choose(.on(.standard)) }
                        .disabled(model.hotkey == .on(.standard))
                    Button("Turn off") { model.choose(.off) }
                        .disabled(model.hotkey == .off)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Shortcut options")
            }
        }
    }

    private var languageRow: some View {
        let menu = model.speechLanguages
        let listed = menu.yours + menu.others
        return Picker("Dictation language", selection: Binding(get: { model.speechChoice }, set: { model.chooseSpeechLanguage($0) })) {
            Text(menu.yours.first.map { "Automatic (\(SpeechLanguage.name($0)))" } ?? "Automatic").tag(String?.none)
            if let choice = model.speechChoice, !listed.contains(choice) {
                Text(SpeechLanguage.name(choice)).tag(Optional(choice))
            }
            if !menu.yours.isEmpty {
                Divider()
                ForEach(menu.yours, id: \.self) { Text(SpeechLanguage.name($0)).tag(Optional($0)) }
            }
            if !menu.others.isEmpty {
                Section("Other Languages") {
                    ForEach(menu.others, id: \.self) { Text(SpeechLanguage.name($0)).tag(Optional($0)) }
                }
            }
        }
    }

    @ViewBuilder private var tokenRow: some View {
        if model.showsStoredToken {
            LabeledContent("Token") {
                HStack(spacing: 8) {
                    Label("Saved in Keychain", systemImage: "key.fill").foregroundStyle(.secondary)
                    Button("Remove") { model.removeToken() }
                }
            }
        } else {
            SecureField("Token", text: $model.tokenEntry, prompt: Text(model.usesEnvironment ? "Set by the environment" : model.removing ? "Removed when you save" : "Optional"))
            if model.removing {
                HStack {
                    Spacer()
                    Button("Keep the saved token") { model.undoRemove() }.buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    @ViewBuilder private var testResult: some View {
        switch model.test {
        case .idle:
            if let saved = model.saved {
                if saved.isEmpty {
                    switch model.savedCheck {
                    case .done(let check, let address):
                        status(check.savedMessage(address: address),
                               symbol: check == .connected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                               color: check == .connected ? .green : .red)
                    case .checking, nil:
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Saved. Trying the connection…").foregroundStyle(.secondary) }
                    }
                } else {
                    status(saved, symbol: "exclamationmark.triangle.fill", color: .red)
                }
            }
        case .testing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Testing…").foregroundStyle(.secondary) }
        case .done(.connected, _):
            status("Connected", symbol: "checkmark.circle.fill", color: .green)
        case .done(let check, let address):
            status(check.message(address: address, inSettings: true), symbol: "exclamationmark.triangle.fill", color: .red)
        case .invalid(let reason):
            status(reason, symbol: "exclamationmark.triangle.fill", color: .red)
        }
    }

    private func status(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var loginRow: some View {
        let status = model.loginStatus
        Toggle("Start at login", isOn: Binding(get: { [.enabled, .requiresApproval].contains(status) },
                                               set: { model.setStartsAtLogin($0) }))
            .disabled(status == .notFound)
        switch status {
        case .requiresApproval:
            HStack(alignment: .firstTextBaseline) {
                Text("macOS wants your approval: turn nodch on in System Settings › General › Login Items.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Open Login Items") { model.openLoginItems() }
            }
        case .notFound:
            Text("Available when nodch runs as Nodch.app.").font(.callout).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
        if let error = model.loginError {
            Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        Text("\(model.version)  ·  Unofficial, not affiliated with n8n.")
            .font(.caption).foregroundStyle(.secondary)
            .padding(.bottom, 16)
            .padding(.top, -4)
    }
}
