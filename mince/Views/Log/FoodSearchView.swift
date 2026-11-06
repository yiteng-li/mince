import SwiftUI

@MainActor
@Observable
final class FoodSearchModel {
    enum Filter: String, CaseIterable { case all = "All", mine = "My foods", recipes = "Recipes", meals = "Meals" }

    var query = ""
    var filter = Filter.all
    var results: [Food] = []
    var recent: [Food] = []
    var meals: [Meal] = []
    var branded: [(Food, [FoodServing])] = []
    var isLoading = false
    var isSearchingBranded = false
    var error: String?

    func loadInitial() async {
        recent = (try? await FoodService().recent()) ?? []
        meals = (try? await FoodService().meals()) ?? []
    }

    func search() async {
        branded = []
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await Task.sleep(for: .milliseconds(250))   // debounce: cancelled by the next keystroke
            results = try await FoodService().search(q)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func searchBranded(userId: UUID) async {
        isSearchingBranded = true
        defer { isSearchingBranded = false }
        do {
            branded = try await OpenFoodFactsService().search(query).compactMap { OpenFoodFactsService.food(from: $0, userId: userId) }
            if branded.isEmpty { error = "No branded products matched." }
        } catch { self.error = error.localizedDescription }
    }

    var visible: [Food] {
        let base = query.count >= 2 ? results : recent
        switch filter {
        case .all: return base
        case .mine: return base.filter { $0.isMine && $0.kind == .food }
        case .recipes: return base.filter { $0.kind == .recipe }
        case .meals: return []
        }
    }
}

/// S07: find a food, recipe or meal and log it.
struct FoodSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    @State private var model = FoodSearchModel()
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $model.filter) {
                        ForEach(FoodSearchModel.Filter.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if model.filter == .meals {
                    mealsSection
                } else {
                    Section(model.query.count >= 2 ? "Results" : "Recent") {
                        if model.isLoading && model.results.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if model.visible.isEmpty {
                            Text(model.query.count >= 2 ? "No matches in the food database." : "Foods you log show up here.")
                                .foregroundStyle(Theme.Colors.textMuted)
                        }
                        ForEach(model.visible) { food in
                            NavigationLink { FoodLogDetail(food: food, groupId: groupId) { dismiss() } } label: { FoodResultRow(food: food) }
                        }
                    }
                    if model.query.count >= 2 { brandedSection }
                }

                Section {
                    Button { creating = true } label: { Label("Create a custom food", systemImage: "square.and.pencil") }
                    Button { dismiss(); app.open(.quickAdd(groupId: groupId)) } label: { Label("Quick add calories", systemImage: "bolt") }
                }
                if let e = model.error { Section { Text(e).foregroundStyle(Theme.Colors.danger) } }
            }
            .screenBackground()
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .task(id: model.query) { await model.search() }
            .task { await model.loadInitial() }
            .navigationTitle(app.group(id: groupId)?.name ?? "Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { dismiss(); app.open(.barcode(groupId: groupId)) } label: { Image(systemName: "barcode.viewfinder") }
                        .accessibilityLabel("Scan barcode")
                }
            }
            .sheet(isPresented: $creating) { CustomFoodEditor(food: nil, prefillName: model.query) { _ in creating = false } }
        }
    }

    @ViewBuilder private var mealsSection: some View {
        Section("Meals") {
            if model.meals.isEmpty { Text("Save a meal from the Foods tab or a diary group.").foregroundStyle(Theme.Colors.textMuted) }
            ForEach(model.meals) { meal in
                Button {
                    Task {
                        guard let uid = app.userId else { return }
                        let entries = (meal.items ?? []).map { l in
                            DiaryEntry(userId: uid, day: app.selectedDay, kind: .food, groupId: groupId ?? app.defaultGroupId(),
                                       foodId: l.foodId, servingId: l.servingId, servingQty: l.servingQty, amountG: l.amountG)
                        }
                        if await app.log(entries) { dismiss() }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(meal.name).foregroundStyle(Theme.Colors.text)
                            Text("\(meal.items?.count ?? 0) items").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                        }
                        Spacer()
                        Text(Units.energy(meal.nutrients[.energy], app.energyUnit)).font(Theme.Fonts.label.monospacedDigit())
                    }
                }
            }
        }
    }

    @ViewBuilder private var brandedSection: some View {
        Section {
            if model.branded.isEmpty {
                Button {
                    Task { if let uid = app.userId { await model.searchBranded(userId: uid) } }
                } label: {
                    HStack {
                        Label("Search branded products", systemImage: "cart")
                        Spacer()
                        if model.isSearchingBranded { ProgressView() }
                    }
                }
                .disabled(model.isSearchingBranded)
            }
            ForEach(model.branded, id: \.0.id) { food, servings in
                NavigationLink {
                    BrandedImportDetail(food: food, servings: servings, groupId: groupId) { dismiss() }
                } label: { FoodResultRow(food: food) }
            }
        } header: { Text("Branded") } footer: { Text("Branded data from Open Food Facts. Picking one saves a copy to your foods.") }
    }
}

struct FoodResultRow: View {
    @Environment(AppModel.self) private var app
    let food: Food

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(Theme.Fonts.body).lineLimit(2)
                HStack(spacing: Theme.Space.xxs) {
                    if let b = food.brand { Text(b) }
                    Text(food.kind == .recipe ? "Recipe" : food.isMine ? "My food" : food.source == .usda ? "USDA" : "")
                }
                .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
            }
            Spacer()
            let s = food.defaultServing
            VStack(alignment: .trailing) {
                Text(Units.energy(food.nutrients[.energy] * s.grams / 100, app.energyUnit)).font(Theme.Fonts.label.monospacedDigit())
                Text("per \(s.name == "g" ? "100 g" : s.name)").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .contentShape(Rectangle())   // the whole row is tappable, including the gap in the middle
        .accessibilityElement(children: .combine)
    }
}

/// An Open Food Facts result: saved as the user's own food, then logged.
struct BrandedImportDetail: View {
    @Environment(AppModel.self) private var app
    let food: Food
    let servings: [FoodServing]
    let groupId: UUID?
    var onLogged: () -> Void
    @State private var saved: Food?

    var body: some View {
        Group {
            if let saved {
                FoodLogDetail(food: saved, groupId: groupId, onLogged: onLogged)
            } else {
                ProgressView("Saving \(food.name)…")
            }
        }
        .task {
            do { saved = try await FoodService().save(food, servings: servings) } catch { app.report(error) }
        }
    }
}
