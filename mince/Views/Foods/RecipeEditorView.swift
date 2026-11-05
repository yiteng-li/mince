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

/// S22 (Gold): paste a recipe URL or text; review matches in the recipe editor.
struct RecipeImporterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var text = ""
    @State private var working = false
    @State private var error: String?
    @State private var imported: AIService.ImportedRecipe?

    var body: some View {
        if let imported {
            RecipeEditorView(recipe: nil, imported: imported)
        } else {
            NavigationStack {
                Form {
                    Section("Recipe link") {
                        TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section("Or paste the recipe") { TextEditor(text: $text).frame(minHeight: 160) }
                    if let error { Section { Text(error).foregroundStyle(Theme.Colors.danger) } }
                    Section {
                        Button("Import") {
                            Task {
                                working = true
                                defer { working = false }
                                do {
                                    imported = try await AIService().importRecipe(url: url.isEmpty ? nil : url, text: text.isEmpty ? nil : text)
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.minced(.primary, loading: working))
                        .disabled((url.isEmpty && text.isEmpty) || working)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }
                .screenBackground()
                .navigationTitle("Import recipe")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
    }
}
