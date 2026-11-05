import Foundation
import Supabase

/// foods, food_servings, recipes, meals, sharing and the food RPCs.
struct FoodService {
    private var db: SupabaseClient { SupabaseService.shared }
    static let withServings = "*, food_servings(*)"

    struct SearchParams: Encodable { let q: String; let lim: Int; let off: Int }

    func search(_ query: String, limit: Int = 40, offset: Int = 0) async throws -> [Food] {
        if Demo.active { return Demo.foods.filter { $0.name.localizedCaseInsensitiveContains(query) } }
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
        let rows: [Food] = try await db.from("foods").select(Self.withServings)
            .eq("barcode", value: barcode).is("archived_at", value: nil).limit(1).execute().value
        return rows.first
    }

    /// The user's own foods and recipes.
    func mine(kind: Food.Kind) async throws -> [Food] {
        if Demo.active { return Demo.foods.filter { $0.isMine && $0.kind == kind } }
        return try await db.from("foods").select(Self.withServings)
            .eq("user_id", value: SupabaseService.userId.uuidString)
            .eq("kind", value: kind.rawValue).is("archived_at", value: nil)
            .order("name").execute().value
    }

    /// Inserts or updates a food and syncs its servings. Servings keep their ids so past
    /// diary entries that used them keep their serving name; the first one becomes the default.
    @discardableResult
    func save(_ food: Food, servings: [FoodServing]) async throws -> Food {
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
        try await db.from("foods").update(["archived_at": Date().ISO8601Format()]).eq("id", value: food.id.uuidString).execute()
    }

    // MARK: recipes

    func ingredients(of recipeId: UUID) async throws -> [FoodLine] {
        try await db.from("recipe_ingredients").select("*, food:foods(\(Self.withServings))")
            .eq("recipe_id", value: recipeId.uuidString).order("position").execute().value
    }

    private struct LineRow: Encodable {
        let id: UUID, food_id: UUID, serving_id: UUID?, serving_qty: Double?, amount_g: Double, position: Int
        let recipe_id: UUID?, meal_id: UUID?
        func encode(to encoder: Encoder) throws {
            enum K: String, CodingKey { case id, food_id, serving_id, serving_qty, amount_g, position, recipe_id, meal_id }
            var c = encoder.container(keyedBy: K.self)
            try c.encode(id, forKey: .id); try c.encode(food_id, forKey: .food_id)
            try c.encode(serving_id, forKey: .serving_id); try c.encode(serving_qty, forKey: .serving_qty)
            try c.encode(amount_g, forKey: .amount_g); try c.encode(position, forKey: .position)
            if let recipe_id { try c.encode(recipe_id, forKey: .recipe_id) }
            if let meal_id { try c.encode(meal_id, forKey: .meal_id) }
        }
    }

    /// Saves a recipe (a food of kind .recipe) with its ingredients, then recomputes its nutrients.
    @discardableResult
    func saveRecipe(_ recipe: Food, ingredients: [FoodLine], servings: [FoodServing]) async throws -> Food {
        var r = recipe
        r.kind = .recipe
        r.source = r.source == .shared ? .shared : .recipe
        try await db.from("foods").upsert(r).execute()
        try await db.from("recipe_ingredients").delete().eq("recipe_id", value: r.id.uuidString).execute()
        let rows = ingredients.enumerated().map { i, l in
            LineRow(id: UUID(), food_id: l.foodId, serving_id: l.servingId, serving_qty: l.servingQty, amount_g: l.amountG,
                    position: i, recipe_id: r.id, meal_id: nil)
        }
        if !rows.isEmpty { try await db.from("recipe_ingredients").insert(rows).execute() }
        try await db.rpc("recompute_recipe", params: ["p_recipe": r.id.uuidString]).execute()
        return try await save(try await food(id: r.id), servings: servings)
    }

    // MARK: meals

    func meals() async throws -> [Meal] {
        if Demo.active {
            let items = [0, 1, 2].map { i in FoodLine(parentId: Demo.userId, foodId: Demo.foods[i].id, servingId: nil, servingQty: 1, amountG: Demo.foods[i].defaultServing.grams, food: Demo.foods[i]) }
            return [Meal(userId: Demo.userId, name: "Usual breakfast", items: items)]
        }
        return try await db.from("meals").select("*, meal_items(*, food:foods(\(Self.withServings)))").order("name").execute().value
    }

    func saveMeal(_ meal: Meal, items: [FoodLine]) async throws {
        try await db.from("meals").upsert(meal).execute()
        try await db.from("meal_items").delete().eq("meal_id", value: meal.id.uuidString).execute()
        let rows = items.enumerated().map { i, l in
            LineRow(id: UUID(), food_id: l.foodId, serving_id: l.servingId, serving_qty: l.servingQty, amount_g: l.amountG,
                    position: i, recipe_id: nil, meal_id: meal.id)
        }
        if !rows.isEmpty { try await db.from("meal_items").insert(rows).execute() }
    }

    func deleteMeal(_ meal: Meal) async throws {
        try await db.from("meals").delete().eq("id", value: meal.id.uuidString).execute()
    }

    // MARK: sharing (Gold)

    /// Turns sharing on and returns the link.
    func share(_ food: Food) async throws -> URL {
        var f = food
        let token = f.shareToken ?? UUID()
        if f.shareToken == nil {
            f.shareToken = token
            do { try await db.from("foods").update(["share_token": token.uuidString]).eq("id", value: f.id.uuidString).execute() }
            catch { throw AppError.wrap(error) }
        }
        return URL(string: "mince://shared/\(token.uuidString)")!
    }

    private struct SharedRow: Decodable { let food: Food; let servings: [FoodServing] }

    /// Copies someone's shared food into the user's own foods.
    func importShared(token: UUID) async throws -> Food {
        let rows: [SharedRow] = try await db.rpc("get_shared_food", params: ["p_token": token.uuidString]).execute().value
        guard let row = rows.first else { throw AppError.message("That share link no longer works.") }
        var copy = row.food
        copy.id = UUID()
        copy.userId = try SupabaseService.userId
        copy.kind = .food        // shared recipes arrive as a flat food (ingredients stay private)
        copy.source = .shared
        copy.shareToken = nil
        copy.servings = nil
        return try await save(copy, servings: row.servings)
    }

    // MARK: Oracle (Gold)

    func oracle(nutrient key: String, perKcal: Bool) async throws -> [Food] {
        if Demo.active {
            return Demo.foods.filter { ($0.nutrients[key] ?? 0) > 0 }.sorted {
                ($0.nutrients[key]! / (perKcal ? max($0.nutrients[.energy], 1) : 1)) > ($1.nutrients[key]! / (perKcal ? max($1.nutrients[.energy], 1) : 1))
            }
        }
        struct P: Encodable { let p_key: String; let per: String; let lim: Int }
        do {
            return try await db.rpc("oracle", params: P(p_key: key, per: perKcal ? "kcal" : "g", lim: 40))
                .select(Self.withServings).execute().value
        } catch { throw AppError.wrap(error) }
    }
}
