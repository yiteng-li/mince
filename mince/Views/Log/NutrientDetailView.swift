import SwiftUI

/// Tapping a nutrient row: amount vs target, which logged foods supplied it, and (Gold) the best foods for it.
struct NutrientDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let nutrient: Nutrient
    let from: Day
    let to: Day

    @State private var sources: [NutrientSourceRow] = []
    @State private var oracle: [Food] = []
    @State private var perKcal = true
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if let goal = app.targets(for: to).goals[nutrient.key] {
                    Section("Target") {
                        if let min = goal.min { LabeledContent("At least", value: Units.amount(min, unit: nutrient.unit)) }
                        if let max = goal.max { LabeledContent("No more than", value: Units.amount(max, unit: nutrient.unit)) }
                    }
                }
                Section(from == to ? "Where it came from" : "Top sources in this range") {
                    if loading { ProgressView() }
                    else if sources.isEmpty { Text("Nothing logged supplied \(nutrient.name.lowercased()).").foregroundStyle(Theme.Colors.textMuted) }
                    ForEach(sources) { s in
                        LabeledContent(s.name, value: Units.amount(s.amount, unit: nutrient.unit))
                    }
                }
                Section {
                    if app.isGold {
                        Picker("Rank by", selection: $perKcal) {
                            Text("Per 100 kcal").tag(true)
                            Text("Per 100 g").tag(false)
                        }
                        .pickerStyle(.segmented)
                        ForEach(oracle.prefix(25)) { f in
                            let amount = (f.nutrients[nutrient.key] ?? 0) * (perKcal ? 100 / max(f.nutrients[.energy], 1) : 1)
                            LabeledContent(f.name, value: Units.amount(amount, unit: nutrient.unit))
                        }
                    } else {
                        GoldRow(action: {}) { Label("See the richest foods in \(nutrient.name.lowercased())", systemImage: "sparkle.magnifyingglass") }
                    }
                } header: { Text("Best sources") }
            }
            .screenBackground()
            .navigationTitle(nutrient.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                sources = (try? await DiaryService().sources(of: nutrient.key, from: from, to: to)) ?? []
                loading = false
            }
            .task(id: perKcal) {
                guard app.isGold else { return }
                do { oracle = try await FoodService().oracle(nutrient: nutrient.key, perKcal: perKcal) } catch { app.report(error) }
            }
        }
    }
}

/// S29 (Gold): make a diary food repeat on chosen weekdays.
struct RepeatRuleEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: DiaryEntry
    @State private var weekdays: Set<Int> = Set(0...6)
    @State private var hasEnd = false
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

    var body: some View {
        NavigationStack {
            Form {
                Section(entry.food?.name ?? "Item") {
                    Text("Adds this to \(app.group(id: entry.groupId)?.name ?? "your diary") automatically when you open each matching day.")
                        .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                }
                Section("Repeat on") {
                    ForEach(0..<7) { d in
                        Toggle(Calendar.current.weekdaySymbols[d], isOn: Binding(get: { weekdays.contains(d) }, set: { on in
                            if on { weekdays.insert(d) } else if weekdays.count > 1 { weekdays.remove(d) }
                        }))
                    }
                }
                Section {
                    Toggle("End date", isOn: $hasEnd)
                    if hasEnd { DatePicker("Ends", selection: $endDate, in: Date()..., displayedComponents: .date) }
                }
            }
            .navigationTitle("Repeat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = app.userId else { return }
                            let rule = RepeatRule(userId: uid, foodId: entry.foodId, servingId: entry.servingId, servingQty: entry.servingQty,
                                                  amountG: entry.amountG, groupId: entry.groupId, weekdays: weekdays.sorted(),
                                                  startsOn: entry.day.adding(days: 1), endsOn: hasEnd ? Day(endDate) : nil)
                            do { try await GoldService().save(rule); dismiss() } catch { app.report(error) }
                        }
                    }
                }
            }
        }
    }
}

/// Opening a mince://shared link: preview and copy a shared food into My foods.
struct SharedFoodImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let token: UUID
    @State private var imported: Food?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let imported {
                    FoodLogDetail(food: imported, groupId: nil) { dismiss() }
                } else if let error {
                    EmptyStateView(symbol: "link", title: "Couldn't open that link", hint: error)
                } else {
                    ProgressView("Adding to your foods…")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                do { imported = try await FoodService().importShared(token: token) } catch { self.error = error.localizedDescription }
            }
        }
    }
}
