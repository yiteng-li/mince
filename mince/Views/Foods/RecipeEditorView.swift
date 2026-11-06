import SwiftUI

/// S20: build a recipe from ingredients; S21: bundle foods into a meal. Same ingredient list, different save.
struct RecipeEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let recipe: Food?
    var imported: AIService.ImportedRecipe?

    @State private var name = ""
    @State private var lines: [FoodLine] = []
    @State private var servingsCount: Double? = 1
    @State private var cookedWeight: Double?
    @State private var instructions = ""
    @State private var picking = false
    @State private var unmatched: [AIService.ImportedRecipe.Ingredient] = []
    @State private var fixing: AIService.ImportedRecipe.Ingredient?
    @State private var saving = false
    @State private var loading = false

    private var rawWeight: Double { lines.reduce(0) { $0 + $1.amountG } }
    private var totals: Nutrients { lines.reduce(into: Nutrients()) { $0 += $1.nutrients } }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Recipe name", text: $name) }
                IngredientSection(lines: $lines, picking: $picking)
                if !unmatched.isEmpty {
                    Section {
                        ForEach(unmatched, id: \.line) { i in
                            Button { fixing = i } label: { Label(i.line, systemImage: "exclamationmark.circle").foregroundStyle(Theme.Colors.warning) }
                        }
                    } header: { Text("Needs a match") } footer: { Text("Tap a line to choose the food it means.") }
                }
                Section {
                    NumberField(title: "Servings it makes", value: $servingsCount)
                    NumberField(title: "Cooked weight (optional)", value: $cookedWeight, unit: "g")
                } footer: {
                    Text("Raw ingredients weigh \(Units.amount(rawWeight, unit: "g")). Weigh the finished dish if cooking changes its weight.")
                }
                Section("Per serving") {
                    let per = totals.scaled(by: 1 / max(servingsCount ?? 1, 1))
                    LabeledContent("Energy", value: Units.energy(per[.energy], app.energyUnit))
                    MacroBars(totals: per, targets: app.targets(for: app.selectedDay))
                }
                Section("Instructions") { TextEditor(text: $instructions).frame(minHeight: 100) }
            }
            .screenBackground()
            .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(name.isEmpty || lines.isEmpty || saving)
                }
            }
            .overlay { if loading { ProgressView() } }
            .task { await fill() }
            .sheet(isPresented: $picking) { IngredientAdder { lines.append($0) } }
            .sheet(item: $fixing) { ing in
                IngredientAdder(initialQuery: ing.name, grams: ing.grams) { line in
                    lines.append(line)
                    unmatched.removeAll { $0.line == ing.line }
                }
            }
        }
    }

    private func fill() async {
        if let recipe {
            name = recipe.name
            instructions = recipe.instructions ?? ""
            cookedWeight = recipe.recipeYieldG
            loading = true
            lines = (try? await FoodService().ingredients(of: recipe.id)) ?? []
            loading = false
            if let serving = recipe.servings?.first(where: { $0.name == "1 serving" }), serving.grams > 0 {
                servingsCount = ((recipe.recipeYieldG ?? rawWeight) / serving.grams).rounded()
            }
        } else if let imported {
            name = imported.name
            instructions = imported.instructions ?? ""
            servingsCount = imported.servings ?? 1
            loading = true
            for i in imported.ingredients {
                if let id = i.foodId, let g = i.grams, let food = try? await FoodService().food(id: id) {
                    lines.append(FoodLine(parentId: UUID(), foodId: id, servingId: nil, servingQty: g, amountG: g, food: food))
                } else {
                    unmatched.append(i)
                }
            }
            loading = false
        }
    }

    private func save() async {
        guard let uid = app.userId else { return }
        saving = true
        defer { saving = false }
        var r = recipe ?? Food(userId: uid, kind: .recipe, source: .recipe, name: name)
        r.name = name
        r.instructions = instructions.isEmpty ? nil : instructions
        r.recipeYieldG = cookedWeight
        let total = cookedWeight ?? rawWeight
        let count = max(servingsCount ?? 1, 1)
        let existing = recipe?.servings?.first { $0.name == "1 serving" }
        let serving = FoodServing(id: existing?.id ?? UUID(), foodId: r.id, name: "1 serving", grams: total / count, isDefault: true)
        let others = (recipe?.servings ?? []).filter { $0.name != "1 serving" }
        do {
            try await FoodService().saveRecipe(r, ingredients: lines, servings: [serving] + others)
            dismiss()
        } catch { app.report(error) }
    }
}

extension AIService.ImportedRecipe.Ingredient: Identifiable { var id: String { line } }
