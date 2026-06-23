import SwiftUI

struct AIReadView: View {
    let reading: SpinTouchReading
    let collectionDate: Date
    let tempF: Double?
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

                case .streaming(let partial):
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(Markdown.plainText(fromHTML: partial))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .textSelection(.enabled)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .onChange(of: partial) { _, _ in
                            withAnimation(.linear(duration: 0.1)) { proxy.scrollTo("end", anchor: .bottom) }
                        }
                    }

                case .done(let text):
                    HTMLView(html: Markdown.html(from: text))
                        .padding(.horizontal, 12)

                case .failed(let message):
                    ScrollView {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle).foregroundStyle(.orange)
                            Text(message)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            Button("Try Again") { reader.start(reading: reading, settings: settings, collectionDate: collectionDate, tempF: tempF) }
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

}
