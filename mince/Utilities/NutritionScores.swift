import Foundation

/// mince's own composite scores (0-100): how well a day or range covers a group of nutrients.
/// Formula: mean of min(amount / target, 1) across the group, minus 10 points for each upper
/// limit exceeded. Not Cronometer's formulas.
struct NutritionScore: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let nutrients: [NK]
    var limits: [NK] = []

    static let all: [NutritionScore] = [
        .init(id: "overall", name: "Micronutrient coverage", summary: "Every vitamin and mineral with a target.",
              nutrients: [.vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .thiamin, .riboflavin, .niacin, .pantothenicAcid,
                          .vitaminB6, .folate, .vitaminB12, .choline, .calcium, .copper, .iron, .magnesium, .manganese,
                          .phosphorus, .potassium, .selenium, .zinc], limits: [.sodium]),
        .init(id: "vitamins", name: "Vitamins", summary: "Fat- and water-soluble vitamins.",
              nutrients: [.vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .thiamin, .riboflavin, .niacin, .vitaminB6, .folate, .vitaminB12]),
        .init(id: "minerals", name: "Minerals", summary: "Major and trace minerals.",
              nutrients: [.calcium, .copper, .iron, .magnesium, .manganese, .phosphorus, .potassium, .selenium, .zinc]),
        .init(id: "electrolytes", name: "Electrolytes", summary: "Potassium, magnesium and calcium, with sodium kept in range.",
              nutrients: [.potassium, .magnesium, .calcium, .water], limits: [.sodium]),
        .init(id: "bone", name: "Bone health", summary: "Calcium, vitamin D, vitamin K, magnesium, phosphorus and protein.",
              nutrients: [.calcium, .vitaminD, .vitaminK, .magnesium, .phosphorus, .protein]),
        .init(id: "immune", name: "Immune support", summary: "Vitamins A, C, D, E plus zinc and selenium.",
              nutrients: [.vitaminA, .vitaminC, .vitaminD, .vitaminE, .zinc, .selenium]),
        .init(id: "antioxidants", name: "Antioxidants", summary: "Vitamins C and E, selenium, manganese and copper.",
              nutrients: [.vitaminC, .vitaminE, .selenium, .manganese, .copper]),
        .init(id: "energy_metabolism", name: "Energy metabolism", summary: "B vitamins, iron and magnesium.",
              nutrients: [.thiamin, .riboflavin, .niacin, .pantothenicAcid, .vitaminB6, .vitaminB12, .iron, .magnesium]),
        .init(id: "heart", name: "Heart health", summary: "Fiber, potassium, magnesium and omega-3, with sodium and saturated fat in range.",
              nutrients: [.fiber, .potassium, .magnesium, .ala], limits: [.sodium, .saturatedFat]),
        .init(id: "plant_based", name: "Plant-based essentials", summary: "Nutrients that are harder to get without animal foods.",
              nutrients: [.vitaminB12, .iron, .zinc, .calcium, .vitaminD, .iodine, .ala, .protein]),
        .init(id: "womens_health", name: "Women's health", summary: "Iron, folate, calcium, vitamin D, B12 and choline.",
              nutrients: [.iron, .folate, .calcium, .vitaminD, .vitaminB12, .choline]),
        .init(id: "mens_health", name: "Men's health", summary: "Zinc, selenium, magnesium, vitamin D and potassium.",
              nutrients: [.zinc, .selenium, .magnesium, .vitaminD, .potassium]),
        .init(id: "keto", name: "Keto", summary: "Net carbs under target, electrolytes covered.",
              nutrients: [.fat, .protein, .potassium, .magnesium, .sodium], limits: [.netCarbs]),
    ]

    static let maxSelected = 8

    /// Score for `totals` (absolute amounts, already averaged for a range). nil when no listed nutrient has a target.
    func score(totals: Nutrients, goals: [String: NutrientGoal]) -> Int? {
        var ratios: [Double] = []
        for k in nutrients {
            guard let target = goals[k.rawValue]?.min, target > 0 else { continue }
            ratios.append(min(totals[k] / target, 1))
        }
        guard !ratios.isEmpty else { return nil }
        var s = ratios.reduce(0, +) / Double(ratios.count) * 100
        for k in limits {
            if let max = goals[k.rawValue]?.max, totals[k] > max { s -= 10 }
        }
        return Int(min(max(s, 0), 100).rounded())
    }

    /// The listed nutrients furthest below target (for "what to eat more of").
    func gaps(totals: Nutrients, goals: [String: NutrientGoal]) -> [NK] {
        nutrients
            .compactMap { k -> (NK, Double)? in
                guard let t = goals[k.rawValue]?.min, t > 0 else { return nil }
                return (k, totals[k] / t)
            }
            .filter { $0.1 < 1 }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
