import Foundation

/// A food, or a recipe (kind = .recipe). Nutrients are per 100 g.
/// `userId == nil` means the shared database (USDA); otherwise it is the owner's private food.
struct Food: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case food, recipe }
    enum Source: String, Codable { case usda, off, custom, recipe, shared }

    var id = UUID()
    var userId: UUID?
    var kind: Kind = .food
    var source: Source = .custom
    var sourceId: String?
    var name: String
    var brand: String?
    var barcode: String?
    var nutrients: Nutrients = [:]
    var recipeYieldG: Double?
    var instructions: String?
    var shareToken: UUID?
    var archivedAt: Date?
    /// Embedded when selected with `food_servings(*)`; never written.
    var servings: [FoodServing]?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", kind, source, sourceId = "source_id", name, brand, barcode, nutrients
        case recipeYieldG = "recipe_yield_g", instructions, shareToken = "share_token", archivedAt = "archived_at"
        case servings = "food_servings"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(kind, forKey: .kind)
        try c.encode(source, forKey: .source)
        try c.encode(sourceId, forKey: .sourceId)
        try c.encode(name, forKey: .name)
        try c.encode(brand, forKey: .brand)
        try c.encode(barcode, forKey: .barcode)
        try c.encode(nutrients, forKey: .nutrients)
        try c.encode(recipeYieldG, forKey: .recipeYieldG)
        try c.encode(instructions, forKey: .instructions)
        try c.encode(shareToken, forKey: .shareToken)
        try c.encode(archivedAt, forKey: .archivedAt)
    }

    var isMine: Bool { userId != nil }
    var displayName: String { brand.map { "\(name) (\($0))" } ?? name }

    /// Servings to pick from: the food's own, then grams and ounces.
    var servingOptions: [FoodServing] {
        let own = (servings ?? []).sorted { ($0.isDefault ? 0 : 1, $0.position) < ($1.isDefault ? 0 : 1, $1.position) }
        return own + [FoodServing.gram(foodId: id), FoodServing.ounce(foodId: id)]
    }

    var defaultServing: FoodServing { servingOptions[0] }
}

struct FoodServing: Identifiable, Codable, Hashable {
    var id = UUID()
    var foodId: UUID
    var name: String
    var grams: Double
    var isDefault = false
    var position = 0

    enum CodingKeys: String, CodingKey {
        case id, foodId = "food_id", name, grams, isDefault = "is_default", position
    }

    /// Built-in units that are not rows in `food_servings`.
    static func gram(foodId: UUID) -> FoodServing {
        FoodServing(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, foodId: foodId, name: "g", grams: 1)
    }
    static func ounce(foodId: UUID) -> FoodServing {
        FoodServing(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, foodId: foodId, name: "oz", grams: 28.3495)
    }

    /// True for the built-in g/oz units (not stored, so never sent as serving_id).
    var isBuiltIn: Bool { id.uuidString.hasPrefix("00000000-0000-0000-0000-00000000000") }
    var storedId: UUID? { isBuiltIn ? nil : id }
}

/// A line of a recipe or a meal: food + amount.
struct FoodLine: Identifiable, Decodable, Hashable {
    var id = UUID()
    var parentId: UUID
    var foodId: UUID
    var servingId: UUID?
    var servingQty: Double?
    var amountG: Double
    var position = 0
    var food: Food?

    enum CodingKeys: String, CodingKey {
        case id, foodId = "food_id", servingId = "serving_id", servingQty = "serving_qty", amountG = "amount_g", position, food
        case recipeId = "recipe_id", mealId = "meal_id"
    }

    init(id: UUID = UUID(), parentId: UUID, foodId: UUID, servingId: UUID?, servingQty: Double?, amountG: Double, position: Int = 0, food: Food? = nil) {
        (self.id, self.parentId, self.foodId, self.servingId, self.servingQty, self.amountG, self.position, self.food) =
            (id, parentId, foodId, servingId, servingQty, amountG, position, food)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        parentId = try c.decodeIfPresent(UUID.self, forKey: .recipeId) ?? c.decode(UUID.self, forKey: .mealId)
        foodId = try c.decode(UUID.self, forKey: .foodId)
        servingId = try c.decodeIfPresent(UUID.self, forKey: .servingId)
        servingQty = try c.decodeIfPresent(Double.self, forKey: .servingQty)
        amountG = try c.decode(Double.self, forKey: .amountG)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        food = try c.decodeIfPresent(Food.self, forKey: .food)
    }

    var nutrients: Nutrients { (food?.nutrients ?? [:]).scaled(by: amountG / 100) }
}

struct Meal: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var name: String
    var items: [FoodLine]?

    enum CodingKeys: String, CodingKey { case id, userId = "user_id", name, items = "meal_items" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(name, forKey: .name)
    }

    var nutrients: Nutrients { (items ?? []).reduce(into: Nutrients()) { $0 += $1.nutrients } }
}
