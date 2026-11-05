import SwiftUI

/// S12: log calories and macros without a food.
struct QuickAddView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    var entry: DiaryEntry?
    @State private var label = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var group: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label (optional)", text: $label)
                    NumberField(title: "Energy", value: $kcal, unit: "kcal")
                    NumberField(title: "Protein", value: $protein, unit: "g")
                    NumberField(title: "Carbs", value: $carbs, unit: "g")
                    NumberField(title: "Fat", value: $fat, unit: "g")
                } footer: {
                    if kcal == nil, let est = estimate { Text("Estimated from macros: \(Int(est)) kcal") }
                }
                Section { Picker("Group", selection: $group) { ForEach(app.groups) { Text($0.name).tag(UUID?.some($0.id)) } } }
            }
            .screenBackground()
            .navigationTitle("Quick add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled((kcal ?? estimate ?? 0) <= 0) }
            }
            .onAppear {
                group = entry?.groupId ?? groupId ?? app.defaultGroupId()
                if let n = entry?.nutrients {
                    label = entry?.title ?? ""
                    (kcal, protein, carbs, fat) = (n["energy"], n["protein"], n["carbs"], n["fat"])
                }
            }
        }
    }

    private var estimate: Double? {
        guard protein != nil || carbs != nil || fat != nil else { return nil }
        return (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
    }

    private func save() async {
        guard let uid = app.userId else { return }
        var n: Nutrients = ["energy": kcal ?? estimate ?? 0]
        if let protein { n["protein"] = protein }
        if let carbs { n["carbs"] = carbs }
        if let fat { n["fat"] = fat }
        var e = entry ?? DiaryEntry(userId: uid, day: app.selectedDay, kind: .quickAdd)
        e.nutrients = n
        e.title = label.isEmpty ? nil : label
        e.groupId = group
        if entry != nil {
            do { _ = try await DiaryService().update(e); app.diaryChanged(); dismiss() } catch { app.report(error) }
        } else if await app.log([e]) { dismiss() }
    }
}

/// S13: log a workout from the exercise catalogue (or a custom title).
struct ExerciseLogView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var entry: DiaryEntry?
    @State private var query = ""
    @State private var results: [Exercise] = []
    @State private var picked: Exercise?
    @State private var customTitle = ""
    @State private var minutes: Double? = 30
    @State private var kcalOverride: Double?

    var body: some View {
        NavigationStack {
            Form {
                if picked == nil && entry == nil { pickSection }
                if picked != nil || !customTitle.isEmpty || entry != nil { detailSection }
            }
            .screenBackground()
            .searchable(text: $query, prompt: "Search activities")
            .task(id: query) { results = (try? await ProfileService().exercises(matching: query)) ?? [] }
            .navigationTitle("Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled((kcalOverride ?? estimate ?? 0) <= 0) }
            }
            .onAppear {
                if let entry { minutes = entry.minutes; kcalOverride = entry.energyKcal }
            }
        }
    }

    @ViewBuilder private var pickSection: some View {
        Section("Pick an activity") {
            ForEach(results) { ex in
                Button { picked = ex } label: {
                    HStack {
                        Text(ex.name).foregroundStyle(Theme.Colors.text)
                        Spacer()
                        Text(ex.category.capitalized).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
            if results.isEmpty { Text("No activities match.").foregroundStyle(Theme.Colors.textMuted) }
        }
        Section("Or name your own") { TextField("e.g. Climbing session", text: $customTitle) }
    }

    private var activityName: String { picked?.name ?? entry?.exercise?.name ?? entry?.title ?? customTitle }

    private var detailSection: some View {
        Section {
            NumberField(title: "Duration", value: $minutes, unit: "min")
            NumberField(title: "Energy burned", value: $kcalOverride, unit: "kcal")
        } header: {
            Text(activityName)
        } footer: {
            if let est = estimate, kcalOverride == nil {
                Text("Estimated \(Int(est)) kcal for \(Units.weight(app.weightKg, app.unitSystem)). Enter your own number to override.")
            }
        }
    }

    private var estimate: Double? {
        guard let picked, let m = minutes, m > 0 else { return nil }
        return picked.energy(minutes: m, weightKg: app.weightKg)
    }

    private func save() async {
        guard let uid = app.userId else { return }
        var e = entry ?? DiaryEntry(userId: uid, day: app.selectedDay, kind: .exercise)
        e.exerciseId = picked?.id ?? e.exerciseId
        if let picked { e.exercise = .init(name: picked.name) }   // shown before the next reload
        e.title = picked == nil ? (customTitle.isEmpty ? e.title : customTitle) : nil
        e.minutes = minutes
        e.energyKcal = kcalOverride ?? estimate
        if entry != nil {
            do { _ = try await DiaryService().update(e); app.diaryChanged(); dismiss() } catch { app.report(error) }
        } else if await app.log([e]) { dismiss() }
    }
}

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
                        GoldRow(action: { creatingCustom = true }) { Label("Create a custom metric", systemImage: "plus") }
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

/// Gold: a user-defined biometric.
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

/// S15: a note in the diary.
struct NoteEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    var entry: DiaryEntry?
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                guard let uid = app.userId else { return }
                                var e = entry ?? DiaryEntry(userId: uid, day: app.selectedDay, kind: .note, groupId: groupId)
                                e.note = String(text.prefix(5000))
                                if entry != nil {
                                    do { _ = try await DiaryService().update(e); app.diaryChanged(); dismiss() } catch { app.report(error) }
                                } else if await app.log([e]) { dismiss() }
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { text = entry?.note ?? "" }
        }
    }
}

/// S16: log water. Stored as a quick add carrying only the water nutrient.
struct WaterLogView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var custom: Double?

    static func add(ml: Double, app: AppModel) async {
        guard let uid = app.userId else { return }
        await app.log([DiaryEntry(userId: uid, day: app.selectedDay, kind: .quickAdd, nutrients: ["water": ml], title: "Water")])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add") {
                    ForEach([250.0, 500, 750, 1000], id: \.self) { ml in
                        Button("\(Int(ml)) mL") { Task { await Self.add(ml: ml, app: app); dismiss() } }
                    }
                }
                Section("Other amount") {
                    NumberField(title: "Amount", value: $custom, unit: "mL")
                    Button("Add") { Task { await Self.add(ml: custom ?? 0, app: app); dismiss() } }.disabled((custom ?? 0) <= 0)
                }
            }
            .screenBackground()
            .navigationTitle("Water")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Tapping any diary row: the matching editor for its kind.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: DiaryEntry

    var body: some View {
        switch entry.kind {
        case .food:
            NavigationStack {
                if let food = entry.food {
                    FoodLogDetail(food: food, groupId: entry.groupId, entry: entry) { dismiss() }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                } else {
                    ContentUnavailableView("Food unavailable", systemImage: "questionmark")
                }
            }
        case .quickAdd:
            if entry.nutrients?.keys.sorted() == ["water"] {
                WaterLogView()
            } else {
                QuickAddView(groupId: entry.groupId, entry: entry)
            }
        case .exercise: ExerciseLogView(entry: entry)
        case .biometric: BiometricLogView(typeKey: nil, entry: entry)
        case .note: NoteEditorView(groupId: entry.groupId, entry: entry)
        }
    }
}
