import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onClearAICache: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showVolumeCalc = false
    @State private var cacheCleared = false
    @State private var apiKeyDraft = ""
    @FocusState private var volumeFocused: Bool

    /// Persist the edited key once (Keychain writes are relatively slow), rather
    /// than on every keystroke.
    private func commitAPIKey() {
        if apiKeyDraft != settings.apiKey { settings.apiKey = apiKeyDraft }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKeyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { commitAPIKey() }
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("This API key is used to generate AI recommendations and is stored securely in your device Keychain. Get a key at console.anthropic.com.")
                }

                Section("Pool") {
                    HStack {
                        Text("Volume")
                        Spacer()
                        TextField("e.g. 15000", text: $settings.poolVolumeGallons)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($volumeFocused)
                        Text("gal").foregroundStyle(.secondary)
                    }
                    Button {
                        showVolumeCalc = true
                    } label: {
                        Label("Calculate from dimensions", systemImage: "ruler")
                    }
                    Picker("Type", selection: $settings.poolType) {
                        ForEach(AppSettings.poolTypeOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Notes (e.g. spa, plaster, screen enclosure)", text: $settings.poolNotes)
                }

                Section {
                    Picker("Model", selection: $settings.model) {
                        ForEach(AppSettings.modelOptions, id: \.self) { model in
                            Text(modelLabel(model)).tag(model)
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Haiku 4.5 is fastest and cheapest. Sonnet 5 gives richer explanations at moderate cost. Opus 5 is highest quality but slower and more expensive.")
                }

                Section {
                    Button {
                        onClearAICache?()
                        cacheCleared = true
                    } label: {
                        Label(cacheCleared ? "AI Read Cache Cleared" : "Clear AI Read Cache",
                              systemImage: cacheCleared ? "checkmark.circle" : "trash")
                    }
                    .disabled(cacheCleared)
                } footer: {
                    Text("AI reads are cached per unique set of inputs (values, temperature, pool settings) so identical reads are instant and don't re-bill.")
                }

                Section("App") {
                    labeledValue("Version", "\(BuildInfo.version) (\(BuildInfo.build))")
                    labeledValue("Built", BuildInfo.builtAt)
                    labeledValue("Commit", BuildInfo.gitCommit)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { apiKeyDraft = settings.apiKey }
            .onDisappear { commitAPIKey() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { commitAPIKey(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { volumeFocused = false }
                }
            }
            .sheet(isPresented: $showVolumeCalc) {
                VolumeCalculatorView(settings: settings)
            }
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                // Let the value keep its full width; the short label yields first.
                .layoutPriority(1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modelLabel(_ model: String) -> String {
        switch model {
        case "claude-haiku-4-5": return "Haiku 4.5 (fast)"
        case "claude-sonnet-5": return "Sonnet 5"
        case "claude-opus-5": return "Opus 5"
        default: return model
        }
    }
}
