import Foundation

/// Nutrient amounts keyed by `nutrients.key`. Per 100 g on a food; absolute on a quick add or a total.
typealias Nutrients = [String: Double]

extension Dictionary where Key == String, Value == Double {
    func scaled(by factor: Double) -> Nutrients { mapValues { $0 * factor } }

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients { lhs.merging(rhs, uniquingKeysWith: +) }
    static func += (lhs: inout Nutrients, rhs: Nutrients) { lhs = lhs + rhs }

    subscript(key: NK) -> Double { self[key.rawValue] ?? 0 }

    /// Adds the derived keys the UI shows but sources rarely carry.
    var withDerived: Nutrients {
        var n = self
        if n["net_carbs"] == nil, let carbs = n["carbs"] { n["net_carbs"] = Swift.max(carbs - (n["fiber"] ?? 0), 0) }
        if n["omega_3"] == nil {
            let o3 = ["ala", "epa", "dha", "dpa"].compactMap { n[$0] }
            if !o3.isEmpty { n["omega_3"] = o3.reduce(0, +) }
        }
        if n["omega_6"] == nil {
            let o6 = ["la", "aa"].compactMap { n[$0] }
            if !o6.isEmpty { n["omega_6"] = o6.reduce(0, +) }
        }
        return n
    }
}

/// Nutrient keys the app refers to by name. The full list lives in the `nutrients` table.
enum NK: String {
    case energy, water, caffeine, alcohol
    case carbs, netCarbs = "net_carbs", fiber, sugars
    case fat, saturatedFat = "saturated_fat", omega3 = "omega_3", omega6 = "omega_6", ala, epa, dha
    case protein
    case vitaminA = "vitamin_a", vitaminC = "vitamin_c", vitaminD = "vitamin_d", vitaminE = "vitamin_e", vitaminK = "vitamin_k"
    case thiamin, riboflavin, niacin, pantothenicAcid = "pantothenic_acid", vitaminB6 = "vitamin_b6", biotin, folate, vitaminB12 = "vitamin_b12", choline
    case betaCarotene = "beta_carotene"
    case calcium, copper, iodine, iron, magnesium, manganese, phosphorus, potassium, selenium, sodium, zinc
}

enum NutrientCategory: String, Codable, CaseIterable, Identifiable {
    case general, carbohydrates, lipids, protein, vitamins, minerals, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Nutrient: Codable, Hashable, Identifiable {
    var key: String
    var name: String
    var unit: String
    var category: NutrientCategory
    var position: Int
    var id: String { key }
}

/// Default target row (RDA/AI and upper limit) for a sex and age band.
struct NutrientDRI: Codable, Hashable {
    var nutrientKey: String
    var sex: Sex
    var ageMin: Int
    var ageMax: Int
    var target: Double
    var upperLimit: Double?

    enum CodingKeys: String, CodingKey {
        case nutrientKey = "nutrient_key", sex, ageMin = "age_min", ageMax = "age_max", target, upperLimit = "upper_limit"
    }
}

/// The user's override of a default target.
struct NutrientTargetOverride: Codable, Hashable {
    var userId: UUID
    var nutrientKey: String
    var minAmount: Double?
    var maxAmount: Double?
    var enabled: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", nutrientKey = "nutrient_key", minAmount = "min_amount", maxAmount = "max_amount", enabled
    }
}

/// What a day's numbers are measured against.
struct NutrientGoal: Hashable {
    var min: Double?
    var max: Double?
}

/// One row from the `nutrient_totals` RPC.
struct NutrientTotalRow: Decodable, Hashable {
    var day: Day
    var nutrientKey: String
    var amount: Double
    enum CodingKeys: String, CodingKey { case day, nutrientKey = "nutrient_key", amount }
}

struct NutrientSourceRow: Decodable, Hashable, Identifiable {
    var foodId: UUID
    var name: String
    var amount: Double
    var id: UUID { foodId }
    enum CodingKeys: String, CodingKey { case foodId = "food_id", name, amount }
}
