import SwiftUI

struct AIReadView: View {
    let reading: SpinTouchReading
    @ObservedObject var settings: AppSettings
    @ObservedObject var reader: AIReader
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch reader.state {
                case .idle, .loading:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Asking Claude…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .done(let text):
                    ScrollView {
                        Text(markdown(text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .textSelection(.enabled)
                    }

                case .failed(let message):
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(message)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        Button("Try Again") { Task { await reader.run(reading: reading, settings: settings) } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .navigationTitle("AI Read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if case .done(let text) = reader.state {
                        Button { UIPasteboard.general.string = text } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
