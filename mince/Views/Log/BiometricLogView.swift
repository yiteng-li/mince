import SwiftUI

/// S14: log weight, measurements, labs, mood, sleep, stool or a custom metric.
struct BiometricLogView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let typeKey: String?
    var entry: DiaryEntry?
    @State private var type: BiometricType?
    @State private var value: Double?
    @State private var value2: Double?
    @State private var hours: Double?
    @State private var creatingCustom = false

    var body: some View {
        NavigationStack {
            Form {
                if let type {
                    Section(type.name) { input(for: type) }
                } else {
                    ForEach(Dictionary(grouping: app.biometricTypes, by: \.category).sorted { $0.key < $1.key }, id: \.key) { category, types in
                        Section(category.capitalized) {
                            ForEach(types) { t in Button(t.name) { self.type = t }.foregroundStyle(Theme.Colors.text) }
                        }
                    }
                    Section {
                        PlusRow(action: { creatingCustom = true }) { Label("Create a custom metric", systemImage: "plus") }
                    }
                }
            }
            .screenBackground()
            .navigationTitle(type?.name ?? "Biometric")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if type != nil { ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!isValid) } }
            }
            .onAppear {
                if let entry {
                    type = app.biometricType(id: entry.biometricTypeId)
                    value = entry.value.map { type?.key == "weight" ? Units.weightValue($0, app.unitSystem) : $0 }
                    value2 = entry.value2
                    if type?.valueKind == .minutes { hours = (entry.value ?? 0) / 60 }
                } else if let typeKey {
                    type = app.biometricType(typeKey)
                }
            }
            .sheet(isPresented: $creatingCustom) { CustomBiometricEditor() }
        }
    }

    @ViewBuilder private func input(for t: BiometricType) -> some View {
        switch t.valueKind {
        case .pair:
            NumberField(title: "Systolic", value: $value, unit: t.unit)
            NumberField(title: "Diastolic", value: $value2, unit: t.unit)
        case .minutes:
            NumberField(title: "Hours", value: $hours, unit: "h")
        case .scale17, .scale110:
            let maxValue = t.valueKind == .scale17 ? 7.0 : 10.0
            Stepper(value: Binding(get: { value ?? (maxValue / 2).rounded() }, set: { value = $0 }), in: 1...maxValue) {
                LabeledContent(t.name, value: "\(Int(value ?? (maxValue / 2).rounded())) / \(Int(maxValue))")
            }
            if t.key == "stool" {
                Text("1–2 hard, 3–4 normal, 5–7 loose (Bristol scale)").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
            }
        case .number:
            NumberField(title: t.name, value: $value, unit: t.key == "weight" ? Units.weightUnit(app.unitSystem) : t.unit)
        }
    }

    private var isValid: Bool {
        guard let type else { return false }
        switch type.valueKind {
        case .pair: return (value ?? 0) > 0 && (value2 ?? 0) > 0
        case .minutes: return (hours ?? 0) > 0
        case .scale17, .scale110: return true
        case .number: return value != nil
        }
    }

    private func save() async {
        guard let uid = app.userId, let type else { return }
        var e = entry ?? DiaryEntry(userId: uid, day: app.selectedDay, kind: .biometric)
        e.biometricTypeId = type.id
        switch type.valueKind {
        case .minutes: e.value = (hours ?? 0) * 60
        case .scale17, .scale110: e.value = value ?? (type.valueKind == .scale17 ? 4 : 5)
        case .number: e.value = type.key == "weight" ? Units.weightKg(fromDisplay: value ?? 0, app.unitSystem) : value
        case .pair: e.value = value
        }
        e.value2 = type.valueKind == .pair ? value2 : nil
        let ok: Bool
        if entry != nil {
            do { _ = try await DiaryService().update(e); app.diaryChanged(); ok = true } catch { app.report(error); ok = false }
        } else { ok = await app.log([e]) }
        if ok {
            if type.key == "weight" { await app.refreshWeight() }
            dismiss()
        }
    }
}

/// mince+: a user-defined biometric.
struct CustomBiometricEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = ""
    @State private var kind = BiometricType.ValueKind.number

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Headache)", text: $name)
                TextField("Unit (e.g. 1-10, mg/dL)", text: $unit)
                Picker("Type", selection: $kind) {
                    Text("Number").tag(BiometricType.ValueKind.number)
                    Text("Scale 1-10").tag(BiometricType.ValueKind.scale110)
                    Text("Two numbers").tag(BiometricType.ValueKind.pair)
                    Text("Duration").tag(BiometricType.ValueKind.minutes)
                }
            }
            .navigationTitle("Custom metric")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = app.userId else { return }
                            let key = "custom_" + name.lowercased().filter { $0.isLetter || $0.isNumber }
                            let t = BiometricType(userId: uid, key: key, name: name, unit: unit.isEmpty ? "-" : unit, category: "custom", valueKind: kind)
                            do { try await ProfileService().saveBiometricType(t); await app.refreshBiometricTypes(); dismiss() } catch { app.report(error) }
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
