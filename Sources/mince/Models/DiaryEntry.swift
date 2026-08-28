import Foundation

struct DiaryEntry: Identifiable, Codable, Hashable {
    let id: UUID = UUID()
    var userId: UUID
    var foodId: UUID
    /// yyyy-MM-dd — see the note on `UserProfile.dateOfBirth`.
    var loggedOn: String
    var mealType: MealType
    var quantityG: Double
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case foodId = "food_id"
        case loggedOn = "logged_on"
        case mealType = "meal_type"
        case quantityG = "quantity_g"
        case createdAt = "created_at"
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
}

/// A diary entry joined with its food — the shape PostgREST returns when
/// embedding (`select("id, quantity_g, meal_type, logged_on, food:foods(*)")`).
/// Use this for the diary list so you have both the logged quantity and the
/// food's per-100g nutrients without a second round trip.
struct DiaryEntryWithFood: Identifiable, Codable, Hashable {
    let id: UUID
    var quantityG: Double
    var mealType: MealType
    var loggedOn: String
    var food: Food

    enum CodingKeys: String, CodingKey {
        case id
        case quantityG = "quantity_g"
        case mealType = "meal_type"
        case loggedOn = "logged_on"
        case food
    }
}
