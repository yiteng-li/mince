import SwiftUI

/// S21: a saved bundle of foods that logs as separate entries.
struct MealEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let meal: Meal?
    var initialItems: [DiaryEntry] = []
    @State private var name = ""
    @State private var lines: [FoodLine] = []
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Meal name (e.g. Usual breakfast)", text: $name) }
                IngredientSection(lines: $lines, picking: $picking)
                Section("Total") {
                    let n = lines.reduce(into: Nutrients()) { $0 += $1.nutrients }
                    LabeledContent("Energy", value: Units.energy(n[.energy], app.energyUnit))
                }
            }
            .screenBackground()
            .navigationTitle(meal == nil ? "New meal" : "Edit meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = app.userId else { return }
                            var m = meal ?? Meal(userId: uid, name: name)
                            m.name = name
                            do { try await FoodService().saveMeal(m, items: lines); dismiss() } catch { app.report(error) }
                        }
                    }
                    .disabled(name.isEmpty || lines.isEmpty)
                }
            }
            .sheet(isPresented: $picking) { IngredientAdder { lines.append($0) } }
            .onAppear {
                name = meal?.name ?? ""
                lines = meal?.items ?? initialItems.compactMap { e in
                    guard let fid = e.foodId, let g = e.amountG else { return nil }
                    return FoodLine(parentId: UUID(), foodId: fid, servingId: e.servingId, servingQty: e.servingQty, amountG: g, food: e.food)
                }
            }
        }
    }
}
