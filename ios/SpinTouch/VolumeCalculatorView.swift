import SwiftUI

/// Estimates pool volume (US gallons) from shape + dimensions and writes the
/// result back into Settings. Volume — not shape — is what matters for dosing,
/// so this is just a convenience to fill in the volume field.
struct VolumeCalculatorView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    enum Shape: String, CaseIterable, Identifiable {
        case rectangle = "Rectangle"
        case round = "Round"
        case oval = "Oval"
        var id: String { rawValue }
    }

    @State private var shape: Shape = .rectangle
    @State private var length = ""   // ft
    @State private var width = ""    // ft (diameter for round)
    @State private var shallow = ""  // ft
    @State private var deep = ""     // ft
    @FocusState private var fieldFocused: Bool

    private let gallonsPerCubicFoot = 7.48052

    private var avgDepth: Double? {
        let s = Double(shallow), d = Double(deep)
        switch (s, d) {
        case let (s?, d?): return (s + d) / 2
        case let (s?, nil): return s
        case let (nil, d?): return d
        default: return nil
        }
    }

    private var gallons: Double? {
        guard let depth = avgDepth, depth > 0 else { return nil }
        switch shape {
        case .rectangle:
            guard let l = Double(length), let w = Double(width), l > 0, w > 0 else { return nil }
            return l * w * depth * gallonsPerCubicFoot
        case .round:
            guard let dia = Double(width), dia > 0 else { return nil }
            let r = dia / 2
            return .pi * r * r * depth * gallonsPerCubicFoot
        case .oval:
            guard let l = Double(length), let w = Double(width), l > 0, w > 0 else { return nil }
            return .pi * (l / 2) * (w / 2) * depth * gallonsPerCubicFoot
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shape") {
                    Picker("Shape", selection: $shape) {
                        ForEach(Shape.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Dimensions (feet)") {
                    if shape == .round {
                        field("Diameter", $width)
                    } else {
                        field("Length", $length)
                        field(shape == .oval ? "Width" : "Width", $width)
                    }
                    field("Shallow depth", $shallow)
                    field("Deep depth", $deep)
                }

                Section {
                    HStack {
                        Text("Estimated volume")
                        Spacer()
                        Text(gallons.map { "\(Int($0.rounded())) gal" } ?? "—")
                            .bold()
                            .foregroundStyle(gallons == nil ? .secondary : .primary)
                    }
                } footer: {
                    Text("Average depth = (shallow + deep) ÷ 2. Estimates only.")
                }
            }
            .navigationTitle("Pool Volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let g = gallons { settings.poolVolumeGallons = String(Int(g.rounded())) }
                        dismiss()
                    }
                    .disabled(gallons == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($fieldFocused)
            Text("ft").foregroundStyle(.secondary)
        }
    }
}
