import SwiftUI

/// S08: choose amount, serving, group and time for a food, see what it adds, log it.
/// Also edits an existing food entry when `entry` is set.
struct FoodLogDetail: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let groupId: UUID?
    var entry: DiaryEntry?
    var onLogged: () -> Void

    @State private var qty: Double? = 1
    @State private var servingId: UUID?
    @State private var group: UUID?
    @State private var time = Date()
    @State private var useTime = false
    @State private var showAll = false
    @State private var saving = false
    @State private var editingFood = false

    init(food: Food, groupId: UUID?, entry: DiaryEntry? = nil, onLogged: @escaping () -> Void) {
        self.food = food
        self.groupId = groupId
        self.entry = entry
        self.onLogged = onLogged
    }

    private var serving: FoodServing {
        food.servingOptions.first { $0.id == servingId } ?? food.defaultServing
    }
    private var grams: Double { (qty ?? 0) * serving.grams }
    private var nutrients: Nutrients { food.nutrients.scaled(by: grams / 100) }

    var body: some View {
        let targets = app.targets(for: app.selectedDay)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(Theme.Fonts.title)
                    if let b = food.brand { Text(b).foregroundStyle(Theme.Colors.textMuted) }
                }
                NumberField(title: "Amount", value: $qty)
                Picker("Serving", selection: Binding(get: { serving.id }, set: { servingId = $0 })) {
                    ForEach(food.servingOptions) { s in
                        Text(s.name == "g" || s.name == "oz" ? s.name : "\(s.name) (\(Units.amount(s.grams, unit: "g")))").tag(s.id)
                    }
                }
                LabeledContent("Total weight", value: Units.amount(grams, unit: "g"))
                if (qty ?? 0) <= 0 { Text("Enter an amount above zero.").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.danger) }
            }

            Section {
                Picker("Group", selection: $group) {
                    ForEach(app.groups) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                if app.isGold {
                    Toggle("Time", isOn: $useTime)
                    if useTime { DatePicker("At", selection: $time, displayedComponents: .hourAndMinute) }
                } else {
                    GoldRow(action: {}) { Text("Time") }
                }
            }

            Section("This amount") {
                LabeledContent("Energy", value: Units.energy(nutrients[.energy], app.energyUnit))
                MacroBars(totals: nutrients, targets: targets)
            }

            Section {
                Toggle("Show every nutrient", isOn: $showAll)
            }
            if showAll {
                NutrientTargetsView(totals: nutrients, goals: targets.goals)
            }

            if food.isMine {
                Section { Button("Edit this food") { editingFood = true } }
            }
        }
        .screenBackground()
        .navigationTitle(entry == nil ? "Log food" : "Edit entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(entry == nil ? "Log" : "Save") { Task { await save() } }
                    .disabled((qty ?? 0) <= 0 || saving)
            }
        }
        .onAppear {
            group = entry?.groupId ?? groupId ?? app.defaultGroupId()
            if let entry {
                qty = entry.servingQty ?? (entry.amountG ?? 100) / serving.grams
                servingId = entry.servingId ?? (entry.servingQty == nil ? food.servingOptions.first { $0.name == "g" }?.id : nil)
                if entry.servingQty == nil { qty = entry.amountG }
                if let t = entry.loggedAt { time = t; useTime = true }
            }
        }
        .sheet(isPresented: $editingFood) {
            if food.kind == .recipe { RecipeEditorView(recipe: food) } else { CustomFoodEditor(food: food) { _ in editingFood = false } }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        guard var e = app.foodEntry(food, serving: serving, qty: qty ?? 0, groupId: group, at: useTime ? time : nil) else { return }
        if let entry {
            e.id = entry.id
            e.day = entry.day
            e.source = entry.source
            e.repeatRuleId = entry.repeatRuleId
            do { _ = try await DiaryService().update(e); app.diaryChanged(); onLogged() } catch { app.report(error) }
        } else if await app.log([e]) {
            onLogged()
        }
    }
}
