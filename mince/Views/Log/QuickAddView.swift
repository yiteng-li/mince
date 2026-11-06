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
