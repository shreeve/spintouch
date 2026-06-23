import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onClearAICache: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showVolumeCalc = false
    @State private var cacheCleared = false
    @FocusState private var volumeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $settings.apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Stored securely in your device Keychain. Get a key at console.anthropic.com.")
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
                    TextField("claude-sonnet-4-5", text: $settings.model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Model")
                } footer: {
                    Text("If you get a model error, set this to a valid Anthropic model id.")
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
}
