import NodchCore
import ServiceManagement
import SwiftUI

/// nodch Settings: which Nod to talk to, Start at login, and what nodch is.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if model.usesEnvironment { environmentSection }
                connectionSection
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
        }
    }

    private var environmentDetail: String {
        "nodch ignores the fields below while the environment sets the connection. Change it where nodch is started, for example in its LaunchAgent."
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
                    status("Saved. nodch reconnects now.", symbol: "checkmark.circle.fill", color: .green)
                } else {
                    status(saved, symbol: "exclamationmark.triangle.fill", color: .red)
                }
            }
        case .testing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Testing…").foregroundStyle(.secondary) }
        case .done(.connected, _):
            status("Connected", symbol: "checkmark.circle.fill", color: .green)
        case .done(let check, let address):
            status(check.message(address: address), symbol: "exclamationmark.triangle.fill", color: .red)
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
