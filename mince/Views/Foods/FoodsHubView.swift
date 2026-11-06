import SwiftUI

/// S18: the user's custom foods, recipes and meals.
struct FoodsHubView: View {
    @Environment(AppModel.self) private var app
    enum Tab: String, CaseIterable { case foods = "My foods", recipes = "Recipes", meals = "Meals" }
    @State private var tab = Tab.foods
    @State private var foods: [Food] = []
    @State private var recipes: [Food] = []
    @State private var meals: [Meal] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var editingFood: Food?
    @State private var creatingFood = false
    @State private var editingRecipe: Food?
    @State private var creatingRecipe = false
    @State private var importing = false
    @State private var editingMeal: Meal?
    @State private var creatingMeal = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                LoadingView(isLoading: loading, error: error, retry: load) {
                    switch tab {
                    case .foods: foodList(filtered(foods), empty: "Foods you create or scan appear here.")
                    case .recipes: foodList(filtered(recipes), empty: "Build a recipe to log home cooking in one tap.")
                    case .meals: mealList
                    }
                }
            }
            .screenBackground()
            .searchable(text: $query, prompt: "Filter")
            .navigationTitle("Foods")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { creatingFood = true } label: { Label("Custom food", systemImage: "square.and.pencil") }
                        Button { creatingRecipe = true } label: { Label("Recipe", systemImage: "list.bullet.rectangle") }
                        Button { app.requirePlus { importing = true } } label: { Label("Import recipe\(app.hasPlus ? "" : " (mince+)")", systemImage: "link") }
                        Button { creatingMeal = true } label: { Label("Meal", systemImage: "square.stack") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create")
                }
            }
            .task(id: app.diaryVersion) { await load() }
            .refreshable { await load() }
            .sheet(item: $editingFood) { f in CustomFoodEditor(food: f) { _ in editingFood = nil; Task { await load() } } }
            .sheet(isPresented: $creatingFood) { CustomFoodEditor(food: nil) { _ in creatingFood = false; Task { await load() } } }
            .sheet(item: $editingRecipe, onDismiss: { Task { await load() } }) { RecipeEditorView(recipe: $0) }
            .sheet(isPresented: $creatingRecipe, onDismiss: { Task { await load() } }) { RecipeEditorView(recipe: nil) }
            .sheet(isPresented: $importing, onDismiss: { Task { await load() } }) { RecipeImporterView() }
            .sheet(item: $editingMeal, onDismiss: { Task { await load() } }) { MealEditorView(meal: $0) }
            .sheet(isPresented: $creatingMeal, onDismiss: { Task { await load() } }) { MealEditorView(meal: nil) }
            .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
        }
    }

    private func filtered(_ list: [Food]) -> [Food] {
        query.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.brand ?? "").localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder private func foodList(_ list: [Food], empty: String) -> some View {
        if list.isEmpty { EmptyStateView(symbol: "fork.knife", title: "Nothing here yet", hint: empty).listRowBackground(Color.clear) }
        ForEach(list) { food in
            Button { if food.kind == .recipe { editingRecipe = food } else { editingFood = food } } label: { FoodResultRow(food: food) }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        Task { do { try await FoodService().archive(food); await load() } catch { app.report(error) } }
                    } label: { Label("Delete", systemImage: "trash") }
                    Button {
                        app.requirePlus { Task { do { shareURL = try await FoodService().share(food) } catch { app.report(error) } } }
                    } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .tint(Theme.Colors.accent)
                }
        }
    }

    @ViewBuilder private var mealList: some View {
        let list = query.isEmpty ? meals : meals.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if list.isEmpty { EmptyStateView(symbol: "square.stack", title: "No meals yet", hint: "Bundle foods you eat together, like your usual breakfast.").listRowBackground(Color.clear) }
        ForEach(list) { meal in
            Button { editingMeal = meal } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(meal.name).foregroundStyle(Theme.Colors.text)
                        Text((meal.items ?? []).compactMap { $0.food?.name }.joined(separator: ", "))
                            .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
                    }
                    Spacer()
                    Text(Units.energy(meal.nutrients[.energy], app.energyUnit)).font(Theme.Fonts.label.monospacedDigit())
                }
            }
            .swipeActions {
                Button(role: .destructive) { Task { try? await FoodService().deleteMeal(meal); await load() } } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func load() async {
        do {
            async let f = FoodService().mine(kind: .food)
            async let r = FoodService().mine(kind: .recipe)
            async let m = FoodService().meals()
            (foods, recipes, meals) = try await (f, r, m)
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
