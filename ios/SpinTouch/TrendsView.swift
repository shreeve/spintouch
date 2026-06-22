import SwiftUI
import Charts

/// Honest per-metric formatting, with a leading + for LSI.
private func metricFormat(_ v: Double, _ key: String) -> String {
    let s = MetricCatalog.format(v, key: key)
    return (key == "lsi" && v >= 0) ? "+\(s)" : s
}

struct TrendsView: View {
    @ObservedObject var store: ReadingStore
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

    private var availableMetrics: [Metric] {
        MetricCatalog.all.filter { !store.series(for: $0.key).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.readings.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Scan a few readings and they'll show up here as trends."))
                } else {
                    List {
                        Section {
                            ForEach(availableMetrics) { metric in
                                NavigationLink {
                                    MetricDetailView(metric: metric, store: store)
                                } label: {
                                    MetricRow(metric: metric, store: store)
                                }
                            }
                        } header: {
                            Text("\(store.readings.count) readings")
                        }
                    }
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let csv = try? store.exportCSVURL() {
                            ShareLink(item: csv) { Label("Export CSV", systemImage: "tablecells") }
                        }
                        if let json = try? store.exportJSONURL() {
                            ShareLink(item: json) { Label("Export JSON", systemImage: "curlybraces") }
                        }
                        Divider()
                        Button(role: .destructive) { showClearConfirm = true } label: {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(store.readings.isEmpty)
                }
            }
            .confirmationDialog("Delete all saved readings?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { store.clear() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

private struct MetricRow: View {
    let metric: Metric
    @ObservedObject var store: ReadingStore

    var body: some View {
        let series = store.series(for: metric.key)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name).font(.subheadline).bold()
                if let v = series.last?.value {
                    Text(metricFormat(v, metric.key) + metric.unitSuffix)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Sparkline(points: series, metric: metric)
                .frame(width: 96, height: 34)
        }
    }
}

private struct Sparkline: View {
    let points: [(date: Date, value: Double)]
    let metric: Metric

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("t", p.date), y: .value("v", p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.tint)
            }
            if let last = points.last {
                PointMark(x: .value("t", last.date), y: .value("v", last.value))
                    .symbolSize(18)
                    .foregroundStyle(.tint)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

struct MetricDetailView: View {
    let metric: Metric
    @ObservedObject var store: ReadingStore

    var body: some View {
        let series = store.series(for: metric.key)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let v = series.last?.value {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(metricFormat(v, metric.key))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(metric.unit ?? "").foregroundStyle(.secondary)
                    }
                }

                Chart {
                    if let lo = metric.idealLow, let hi = metric.idealHigh {
                        RectangleMark(
                            yStart: .value("low", lo),
                            yEnd: .value("high", hi))
                            .foregroundStyle(.green.opacity(0.10))
                    }
                    ForEach(Array(series.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Date", p.date), y: .value(metric.name, p.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.tint)
                        PointMark(x: .value("Date", p.date), y: .value(metric.name, p.value))
                            .symbolSize(28)
                            .foregroundStyle(.tint)
                    }
                }
                .frame(height: 240)
                .chartYScale(domain: .automatic(includesZero: false))

                if let lo = metric.idealLow, let hi = metric.idealHigh {
                    Text("Ideal range: \(trim(lo))–\(trim(hi))\(metric.unitSuffix)")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let lo = metric.idealLow {
                    Text("Ideal: ≥ \(trim(lo))\(metric.unitSuffix)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                historyList(series)
            }
            .padding()
        }
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyList(_ series: [(date: Date, value: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Readings").font(.headline)
            ForEach(Array(series.enumerated().reversed()), id: \.offset) { _, p in
                HStack {
                    Text(p.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(metricFormat(p.value, metric.key))
                        .font(.callout).monospacedDigit().bold()
                }
                Divider()
            }
        }
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
