import SwiftUI

/// S19: enter a nutrition label. Values are typed per serving (as printed) and stored per 100 g.
struct CustomFoodEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let food: Food?
    var prefillName = ""
    var prefillBarcode: String?
    var onDone: (Food?) -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var barcode = ""
    @State private var servings: [FoodServing] = []
    @State private var labelGrams: Double? = 100
    @State private var values: [String: Double] = [:]
    @State private var showAll = false
    @State private var saving = false

    private static let common = ["energy", "fat", "saturated_fat", "trans_fat", "cholesterol", "sodium", "carbs", "fiber", "sugars",
                                 "added_sugars", "protein", "vitamin_d", "calcium", "iron", "potassium"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Barcode (optional)", text: $barcode).keyboardType(.numberPad)
                }
                Section {
                    ForEach($servings) { $s in
                        HStack {
                            TextField("Name (e.g. 1 cup)", text: $s.name)
                            NumberField(title: "", value: Binding(get: { s.grams }, set: { s.grams = $0 ?? 0 }), unit: "g").frame(maxWidth: 120)
                        }
                    }
                    .onDelete { servings.remove(atOffsets: $0) }
                    Button { servings.append(FoodServing(foodId: food?.id ?? UUID(), name: "", grams: 0)) } label: { Label("Add a serving size", systemImage: "plus") }
                } header: { Text("Serving sizes") } footer: {
                    Text("For drinks, enter the grams for the volume (1 mL of water ≈ 1 g). The first serving is the default.")
                }
                Section {
                    NumberField(title: "Nutrition values are for", value: $labelGrams, unit: "g")
                } footer: { Text("Use the serving size printed on the label, or 100 g.") }

                Section("Nutrition") {
                    ForEach(fields) { n in
                        NumberField(title: n.name, value: Binding(get: { values[n.key] }, set: { values[n.key] = $0 }), unit: n.unit)
                    }
                    Toggle("Show every nutrient", isOn: $showAll)
                }
            }
            .screenBackground()
            .navigationTitle(food == nil ? "New food" : "Edit food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone(nil); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || values["energy"] == nil || (labelGrams ?? 0) <= 0 || saving)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private var fields: [Nutrient] {
        showAll ? app.nutrients.filter { $0.key != "net_carbs" && $0.key != "omega_3" && $0.key != "omega_6" }
                : Self.common.compactMap { app.nutrient($0) }
    }

    private func fill() {
        name = food?.name ?? prefillName
        brand = food?.brand ?? ""
        barcode = food?.barcode ?? prefillBarcode ?? ""
        servings = (food?.servings ?? []).sorted { $0.position < $1.position }
        if let first = servings.first { labelGrams = first.grams }
        let factor = (labelGrams ?? 100) / 100
        values = (food?.nutrients ?? [:]).mapValues { ($0 * factor * 1000).rounded() / 1000 }
    }

    private func save() async {
        guard let uid = app.userId, let g = labelGrams, g > 0 else { return }
        saving = true
        defer { saving = false }
        var f = food ?? Food(userId: uid, source: .custom, name: name)
        f.name = name.trimmingCharacters(in: .whitespaces)
        f.brand = brand.isEmpty ? nil : brand
        f.barcode = barcode.filter(\.isNumber).isEmpty ? nil : barcode.filter(\.isNumber)
        f.nutrients = values.compactMapValues { $0 }.mapValues { $0 * 100 / g }
        let cleaned = servings.filter { !$0.name.isEmpty && $0.grams > 0 }
        do {
            let saved = try await FoodService().save(f, servings: cleaned)
            onDone(saved)
            dismiss()
        } catch { app.report(error) }
    }
}
