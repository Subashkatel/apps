import SwiftUI
import LocalSupport

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FrontierAppearance.key) private var appearance = "Dark"
    @State private var settings = AISettings()
    @State private var key = ""
    @State private var removeKey = false
    @State private var message: String?
    @State private var testing = false
    private var previewSettings: AISettings?

    init(previewSettings: AISettings? = nil) {
        self.previewSettings = previewSettings
        _settings = State(initialValue: previewSettings ?? AISettings())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.custom("Georgia", size: 26))
            Picker("Appearance", selection: $appearance) {
                ForEach(FrontierAppearance.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            Divider()
            Text("AI provider").font(.system(size: 13, weight: .medium))
            Picker("Use", selection: $settings.provider) {
                ForEach(AIProvider.allCases) { provider in Text(provider.title).tag(provider) }
            }.pickerStyle(.segmented)
            if settings.provider == .server {
                Text("Connect a local or hosted server that supports the OpenAI Chat Completions format.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("API base URL, e.g. http://localhost:1234/v1", text: $settings.endpoint)
                TextField("Model name", text: $settings.serverModel)
                SecureField("API key — leave empty to keep the saved key", text: $key)
                Toggle("Remove the saved key for this server", isOn: $removeKey)
                Text("Keys are stored in macOS Keychain. Your course text is sent to the server you choose when you generate lessons.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Uses your existing \(settings.provider.title) CLI login. Leave the model empty to use the provider default.")
                    .font(.callout).foregroundStyle(.secondary)
                if settings.provider == .claude {
                    TextField("Model (optional)", text: $settings.claudeModel)
                    TextField("Claude executable path (automatic if empty)", text: $settings.executablePath)
                } else if settings.provider == .gemini {
                    TextField("Model (optional)", text: Binding(get: { settings.geminiModel ?? "" }, set: { settings.geminiModel = $0 }))
                    TextField("Antigravity executable path (automatic if empty)", text: Binding(get: { settings.geminiExecutablePath ?? "" }, set: { settings.geminiExecutablePath = $0 }))
                    Text("Sign in through Antigravity CLI using the Google account with your AI Pro or student plan. Google retired the older Gemini CLI personal login.").font(.caption).foregroundStyle(.secondary)
                    Link("Antigravity installation and sign-in guide", destination: URL(string: "https://antigravity.google/docs/cli/install/")!)
                } else {
                    TextField("Model (optional)", text: $settings.codexModel)
                    TextField("Codex executable path (automatic if empty)", text: $settings.codexExecutablePath)
                }
                Button("Sign in in Terminal…") {
                    do { try settings.openLogin() } catch { message = error.localizedDescription }
                }.disabled(settings.executable == nil)
                Label(settings.executable == nil ? "CLI not found" : "CLI found · sign in through its Terminal command",
                      systemImage: settings.executable == nil ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.callout).textSelection(.enabled) }
            HStack {
                Button(testing ? "Testing…" : "Test connection") { test() }.disabled(testing)
                    .help("Sends a short test prompt; may use a small amount of your AI allowance.")
                Spacer()
                Button("Cancel") { dismiss() }.disabled(testing)
                Button("Save") {
                    do { try persist(); dismiss() } catch { message = error.localizedDescription }
                }.buttonStyle(LibraryPrimaryButton()).disabled(testing)
            }
        }
        .buttonStyle(LibrarySecondaryButton())
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 580)
        .background(LibraryTheme.paper).foregroundStyle(LibraryTheme.ink).tint(LibraryTheme.accent)
        .disabled(testing)
        .onAppear {
            guard previewSettings == nil else { return }
            do { settings = try AISettings.load() }
            catch { message = "Could not read existing AI settings. Saving will replace them: \(error.localizedDescription)" }
        }
        .onChange(of: appearance) { _, new in FrontierAppearance.apply(new) }
        .onChange(of: settings.endpoint) { _, _ in key = ""; removeKey = false; message = nil }
    }

    private func persist() throws {
        _ = try settings.validated()
        if settings.provider == .server, removeKey || !key.isEmpty {
            try AIKeychain.save(removeKey ? "" : key, for: settings.serverURL())
        }
        try settings.save()
    }

    private func test() {
        do { _ = try settings.validated() } catch { message = error.localizedDescription; return }
        let draft = settings, draftKey = key, shouldRemove = removeKey
        testing = true; message = nil
        Task {
            let result = await Task.detached { () -> String in
                do {
                    let prompt = "Reply with only: Connection OK"
                    // Testing a draft never changes saved settings or credentials.
                    if draft.provider == .server {
                        let saved = try shouldRemove ? nil : AIKeychain.read(for: draft.serverURL())
                        let request = try AIClient.request(settings: draft, prompt: prompt,
                            key: shouldRemove ? nil : (draftKey.isEmpty ? saved : draftKey), timeout: 90)
                        _ = try AIClient.send(request, timeout: 90)
                    } else { _ = try AIClient.ask(prompt, settings: draft, timeout: 90) }
                    return "Connection succeeded."
                } catch { return error.localizedDescription }
            }.value
            testing = false; message = result
        }
    }
}
