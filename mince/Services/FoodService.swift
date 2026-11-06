import Foundation
import Supabase

/// foods, food_servings, recipes, meals, sharing and the food RPCs.
/// In demo mode (`-demo`) every method uses the in-memory data in Demo.swift instead.
struct FoodService {
    private var db: SupabaseClient { SupabaseService.shared }
    static let withServings = "*, food_servings(*)"

    struct SearchParams: Encodable { let q: String; let lim: Int; let off: Int }

    func search(_ query: String, limit: Int = 40, offset: Int = 0) async throws -> [Food] {
        if Demo.active { return Demo.foods.filter { $0.archivedAt == nil && $0.name.localizedCaseInsensitiveContains(query) } }
        return try await db.rpc("search_foods", params: SearchParams(q: query, lim: limit, off: offset))
            .select(Self.withServings).execute().value
    }

    func recent(limit: Int = 30) async throws -> [Food] {
        if Demo.active { return Array(Demo.foods.prefix(6)) }
        return try await db.rpc("recent_foods", params: ["lim": limit]).select(Self.withServings).execute().value
    }

    func food(id: UUID) async throws -> Food {
        if Demo.active, let f = Demo.foods.first(where: { $0.id == id }) { return f }
        return try await db.from("foods").select(Self.withServings).eq("id", value: id.uuidString).single().execute().value
    }

    func findByBarcode(_ barcode: String) async throws -> Food? {
        if Demo.active { return Demo.foods.first { $0.barcode == barcode && $0.archivedAt == nil } }
        let rows: [Food] = try await db.from("foods").select(Self.withServings)
            .eq("barcode", value: barcode).is("archived_at", value: nil).limit(1).execute().value
        return rows.first
    }

    /// The user's own foods and recipes.
    func mine(kind: Food.Kind) async throws -> [Food] {
        if Demo.active { return Demo.foods.filter { $0.isMine && $0.kind == kind && $0.archivedAt == nil }.sorted { $0.name < $1.name } }
        return try await db.from("foods").select(Self.withServings)
            .eq("user_id", value: SupabaseService.userId.uuidString)
            .eq("kind", value: kind.rawValue).is("archived_at", value: nil)
            .order("name").execute().value
    }

    /// Inserts or updates a food and syncs its servings. Servings keep their ids so past
    /// diary entries that used them keep their serving name; the first one becomes the default.
    @discardableResult
    func save(_ food: Food, servings: [FoodServing]) async throws -> Food {
        if Demo.active {
            var f = food
            f.servings = servings.filter { !$0.isBuiltIn }.enumerated().map { i, s in
                FoodServing(id: s.id, foodId: food.id, name: s.name, grams: s.grams, isDefault: i == 0, position: i)
            }
            Demo.upsert(f, into: &Demo.foods)
            return f
        }
        try await db.from("foods").upsert(food).execute()
        let rows = servings.filter { !$0.isBuiltIn }.enumerated().map { i, s in
            FoodServing(id: s.id, foodId: food.id, name: s.name, grams: s.grams, isDefault: i == 0, position: i)
        }
        var removed = db.from("food_servings").delete().eq("food_id", value: food.id.uuidString)
        if !rows.isEmpty { removed = removed.not("id", operator: .in, value: "(\(rows.map(\.id.uuidString).joined(separator: ",")))") }
        try await removed.execute()
        // Clear the old default first: only one default per food is allowed at a time.
        try await db.from("food_servings").update(["is_default": false]).eq("food_id", value: food.id.uuidString).execute()
        if !rows.isEmpty { try await db.from("food_servings").upsert(rows).execute() }
        return try await self.food(id: food.id)
    }

    /// Soft delete: diary rows keep pointing at it.
    func archive(_ food: Food) async throws {
        if Demo.active { if let i = Demo.foods.firstIndex(where: { $0.id == food.id }) { Demo.foods[i].archivedAt = Date() }; return }
        try await db.from("foods").update(["archived_at": Date().ISO8601Format()]).eq("id", value: food.id.uuidString).execute()
    }

    // MARK: recipes

    func ingredients(of recipeId: UUID) async throws -> [FoodLine] {
        if Demo.active { return Demo.recipeLines[recipeId] ?? [] }
        return try await db.from("recipe_ingredients").select("*, food:foods!food_id(\(Self.withServings))")
            .eq("recipe_id", value: recipeId.uuidString).order("position").execute().value
    }

    /// Saves a recipe (a food of kind .recipe) with its ingredients, then recomputes its nutrients.
    @discardableResult
    func saveRecipe(_ recipe: Food, ingredients: [FoodLine], servings: [FoodServing]) async throws -> Food {
        if Demo.active {   // same math as the recompute_recipe RPC
            var r = recipe
            (r.kind, r.source) = (.recipe, .recipe)
            let lines = ingredients.map { l in var l = l; l.food = l.food ?? Demo.foods.first { $0.id == l.foodId }; return l }
            let total = r.recipeYieldG ?? lines.reduce(0) { $0 + $1.amountG }
            r.nutrients = total > 0 ? lines.reduce(into: Nutrients()) { $0 += $1.nutrients }.scaled(by: 100 / total) : [:]
            Demo.recipeLines[r.id] = lines
            return try await save(r, servings: servings)
        }
        var r = recipe
        r.kind = .recipe
        r.source = r.source == .shared ? .shared : .recipe
        try await db.from("foods").upsert(r).execute()
        try await db.from("recipe_ingredients").delete().eq("recipe_id", value: r.id.uuidString).execute()
        let rows = ingredients.enumerated().map { index, line in
            FoodLineRow(id: UUID(), foodId: line.foodId, servingId: line.servingId, servingQty: line.servingQty,
                        amountG: line.amountG, position: index, recipeId: r.id, mealId: nil)
        }
        if !rows.isEmpty { try await db.from("recipe_ingredients").insert(rows).execute() }
        try await db.rpc("recompute_recipe", params: ["p_recipe": r.id.uuidString]).execute()
        return try await save(try await food(id: r.id), servings: servings)
    }

    // MARK: meals

    func meals() async throws -> [Meal] {
        if Demo.active { return Demo.meals.sorted { $0.name < $1.name } }
        return try await db.from("meals").select("*, meal_items(*, food:foods(\(Self.withServings)))").order("name").execute().value
    }

    func saveMeal(_ meal: Meal, items: [FoodLine]) async throws {
        if Demo.active {
            var m = meal
            m.items = items.map { l in var l = l; l.food = l.food ?? Demo.foods.first { $0.id == l.foodId }; return l }
            Demo.upsert(m, into: &Demo.meals)
            return
        }
        try await db.from("meals").upsert(meal).execute()
        try await db.from("meal_items").delete().eq("meal_id", value: meal.id.uuidString).execute()
        let rows = items.enumerated().map { index, line in
            FoodLineRow(id: UUID(), foodId: line.foodId, servingId: line.servingId, servingQty: line.servingQty,
                        amountG: line.amountG, position: index, recipeId: nil, mealId: meal.id)
        }
        if !rows.isEmpty { try await db.from("meal_items").insert(rows).execute() }
    }

    func deleteMeal(_ meal: Meal) async throws {
        if Demo.active { Demo.meals.removeAll { $0.id == meal.id }; return }
        try await db.from("meals").delete().eq("id", value: meal.id.uuidString).execute()
    }

    // MARK: sharing (mince+)

    /// Turns sharing on and returns the link.
    func share(_ food: Food) async throws -> URL {
        if Demo.active { return URL(string: "mince://shared/\(food.shareToken ?? UUID())")! }
        var f = food
        let token = f.shareToken ?? UUID()
        if f.shareToken == nil {
            f.shareToken = token
            do { try await db.from("foods").update(["share_token": token.uuidString]).eq("id", value: f.id.uuidString).execute() }
            catch { throw AppError.wrap(error) }
        }
        return URL(string: "mince://shared/\(token.uuidString)")!
    }

    /// Copies someone's shared food into the user's own foods.
    func importShared(token: UUID) async throws -> Food {
        let rows: [SharedFoodRow] = try await db.rpc("get_shared_food", params: ["p_token": token.uuidString]).execute().value
        guard let row = rows.first else { throw AppError.message("That share link no longer works.") }
        var copy = row.food
        copy.id = UUID()
        copy.userId = try SupabaseService.userId
        copy.kind = .food        // shared recipes arrive as a flat food (ingredients stay private)
        copy.source = .shared
        copy.shareToken = nil
        copy.servings = nil
        // New ids: the sharer's serving rows aren't ours to update.
        let servings = row.servings.map { s in var s = s; s.id = UUID(); s.foodId = copy.id; return s }
        return try await save(copy, servings: servings)
    }

    // MARK: Oracle (mince+)

    func oracle(nutrient key: String, perKcal: Bool) async throws -> [Food] {
        if Demo.active {
            // Same ranking as the oracle RPC: amount per 100 kcal, or per 100 g.
            let richness = { (f: Food) in (f.nutrients[key] ?? 0) / (perKcal ? max(f.nutrients[.energy], 1) : 1) }
            return Demo.foods.filter { (f: Food) in (f.nutrients[key] ?? 0) > 0 }.sorted { richness($0) > richness($1) }
        }
        struct P: Encodable { let p_key: String; let per: String; let lim: Int }
        do {
            return try await db.rpc("oracle", params: P(p_key: key, per: perKcal ? "kcal" : "g", lim: 40))
                .select(Self.withServings).execute().value
        } catch { throw AppError.wrap(error) }
    }
}
