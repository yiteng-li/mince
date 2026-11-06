import SwiftUI

/// Shared review step for Photo Log and Voice Log: fix names and grams, pick the matching food, log.
struct AIReviewList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    @Binding var items: [AIService.Item]
    var suggestions: [AIService.Item] = []
    var source: DiaryEntry.Source
    var allowSaveAsRecipe = false

    @State private var matches: [UUID: Food] = [:]
    @State private var picking: AIService.Item?
    @State private var saving = false
    @State private var saveAsRecipe = false
    @State private var recipeName = ""

    var body: some View {
        Form {
            Section {
                ForEach($items) { $item in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        TextField("Food", text: $item.name).font(Theme.Fonts.heading)
                        HStack {
                            NumberField(title: "Grams", value: Binding(get: { item.grams }, set: { item.grams = $0 ?? 0 }), unit: "g")
                        }
                        Button {
                            picking = item
                        } label: {
                            Label(matches[item.id]?.name ?? "Choose a matching food", systemImage: matches[item.id] == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                                .foregroundStyle(matches[item.id] == nil ? Theme.Colors.warning : Theme.Colors.success)
                                .font(Theme.Fonts.footnote)
                        }
                        .buttonStyle(.borderless)   // the row also holds text fields
                        if let note = item.note { Text(note).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted) }
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
            } header: { Text("Check what we found") } footer: { Text("Estimates from AI. Adjust amounts before logging.") }

            let extras = suggestions.filter { s in !items.contains { $0.name.lowercased() == s.name.lowercased() } }
            if !extras.isEmpty {
                Section("Often hidden in dishes like this") {
                    ForEach(extras) { s in
                        Button { items.append(s); Task { await match(s) } } label: {
                            Label("\(s.name), \(Int(s.grams)) g", systemImage: "plus.circle")
                        }
                    }
                }
            }

            if allowSaveAsRecipe {
                Section {
                    Toggle("Also save as a recipe", isOn: $saveAsRecipe)
                    if saveAsRecipe { TextField("Recipe name", text: $recipeName) }
                }
            }

            let kcal = items.reduce(0.0) { $0 + (matches[$1.id]?.nutrients[.energy] ?? 0) * $1.grams / 100 }
            Section { LabeledContent("Total", value: Units.energy(kcal, app.energyUnit)) }
        }
        .screenBackground()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log all") { Task { await logAll() } }
                    .disabled(saving || items.isEmpty || items.contains { matches[$0.id] == nil || $0.grams <= 0 })
            }
        }
        .task { for item in items where matches[item.id] == nil { await match(item) } }
        .sheet(item: $picking) { item in
            FoodPicker(initialQuery: item.name) { food in
                matches[item.id] = food
                picking = nil
            }
        }
    }

    private func match(_ item: AIService.Item) async {
        if let id = item.foodId, let food = try? await FoodService().food(id: id) { matches[item.id] = food; return }
        if let first = try? await FoodService().search(item.name, limit: 1).first { matches[item.id] = first }
    }

    private func logAll() async {
        guard let uid = app.userId else { return }
        saving = true
        defer { saving = false }
        let group = groupId ?? app.defaultGroupId()
        let entries = items.compactMap { item -> DiaryEntry? in
            guard let food = matches[item.id] else { return nil }
            return DiaryEntry(userId: uid, day: app.selectedDay, kind: .food, groupId: group, foodId: food.id, servingQty: item.grams,
                              amountG: item.grams, source: source)
        }
        if saveAsRecipe, !recipeName.isEmpty {
            let recipe = Food(userId: uid, kind: .recipe, source: .recipe, name: recipeName)
            let lines = items.compactMap { i in matches[i.id].map { FoodLine(parentId: recipe.id, foodId: $0.id, servingId: nil, servingQty: i.grams, amountG: i.grams) } }
            do { try await FoodService().saveRecipe(recipe, ingredients: lines, servings: []) } catch { app.report(error) }
        }
        if await app.log(entries) { dismiss() }
    }
}
