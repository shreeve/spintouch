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
                    ScrollView {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle).foregroundStyle(.orange)
                            Text(message)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            Button("Try Again") { Task { await reader.run(reading: reading, settings: settings) } }
                                .buttonStyle(.borderedProminent)

                            let advice = Recommendations.evaluate(reading)
                            if !advice.isEmpty {
                                Divider().padding(.vertical, 4)
                                Text("Offline recommendations").font(.headline)
                                ForEach(advice) { a in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.title).font(.subheadline).bold()
                                        Text(a.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding()
                    }
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
