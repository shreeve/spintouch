import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showVolumeCalc = false

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
                        Text("gal").foregroundStyle(.secondary)
                    }
                    Button {
                        showVolumeCalc = true
                    } label: {
                        Label("Calculate from dimensions", systemImage: "ruler")
                    }
                    TextField("Type / notes (e.g. saltwater, spa)", text: $settings.poolType)
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showVolumeCalc) {
                VolumeCalculatorView(settings: settings)
            }
        }
    }
}
