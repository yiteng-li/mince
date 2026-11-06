import SwiftUI

/// The editable ingredient list used by recipes and meals.
struct IngredientSection: View {
    @Environment(AppModel.self) private var app
    @Binding var lines: [FoodLine]
    @Binding var picking: Bool

    var body: some View {
        Section {
            ForEach(lines) { l in
                HStack {
                    VStack(alignment: .leading) {
                        Text(l.food?.name ?? "Food").lineLimit(2)
                        Text(Units.amount(l.amountG, unit: "g")).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                    }
                    Spacer()
                    Text(Units.energy(l.nutrients[.energy], app.energyUnit)).font(Theme.Fonts.label.monospacedDigit())
                }
            }
            .onDelete { lines.remove(atOffsets: $0) }
            .onMove { lines.move(fromOffsets: $0, toOffset: $1) }
            Button { picking = true } label: { Label("Add ingredient", systemImage: "plus") }
        } header: { Text("Ingredients") }
    }
}

/// Pick a food, then an amount, and return a line.
struct IngredientAdder: View {
    @Environment(\.dismiss) private var dismiss
    var initialQuery = ""
    var grams: Double?
    var onAdd: (FoodLine) -> Void
    @State private var food: Food?
    @State private var qty: Double? = 1
    @State private var servingId: UUID?

    var body: some View {
        if let food {
            NavigationStack {
                Form {
                    Text(food.name).font(Theme.Fonts.heading)
                    NumberField(title: "Amount", value: $qty)
                    Picker("Serving", selection: Binding(get: { servingId ?? food.defaultServing.id }, set: { servingId = $0 })) {
                        ForEach(food.servingOptions) { Text("\($0.name) (\(Units.amount($0.grams, unit: "g")))").tag($0.id) }
                    }
                }
                .navigationTitle("Amount")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let s = food.servingOptions.first { $0.id == servingId } ?? food.defaultServing
                            onAdd(FoodLine(parentId: UUID(), foodId: food.id, servingId: s.storedId, servingQty: qty, amountG: (qty ?? 0) * s.grams, food: food))
                            dismiss()
                        }
                        .disabled((qty ?? 0) <= 0)
                    }
                }
            }
        } else {
            FoodPicker(initialQuery: initialQuery) { f in
                food = f
                if let grams { qty = grams; servingId = FoodServing.gram(foodId: f.id).id }
            }
        }
    }
}
