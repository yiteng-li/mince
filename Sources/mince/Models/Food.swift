import Foundation

/// A food in the shared database. All nutrient fields are PER 100g/100ml —
/// see 0002_foods.sql. `servingSizeG`/`servingName` are just a convenience
/// default for quick-add UI, not a separate nutrient basis.
///
/// Nutrients are plain columns rather than an EAV table: the tracked set is
/// fixed and small (macros + ~20 key micros, not Cronometer's full ~80), so
/// a join table would add query complexity without a matching payoff.
struct Food: Identifiable, Codable, Hashable {
    let id: UUID = UUID()
    var createdBy: UUID?
    var name: String
    var brand: String?
    var servingSizeG: Double = 100
    var servingName: String = "g"

    // Macros (per 100g)
    var caloriesKcal: Double
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double = 0
    var sugarG: Double = 0
    var saturatedFatG: Double = 0
    var cholesterolMg: Double = 0

    // Minerals (per 100g)
    var sodiumMg: Double = 0
    var potassiumMg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0
    var magnesiumMg: Double = 0
    var zincMg: Double = 0

    // Vitamins (per 100g)
    var vitaminAMcg: Double = 0
    var vitaminCMg: Double = 0
    var vitaminDMcg: Double = 0
    var vitaminEMg: Double = 0
    var vitaminKMcg: Double = 0
    var thiamineB1Mg: Double = 0
    var riboflavinB2Mg: Double = 0
    var niacinB3Mg: Double = 0
    var vitaminB6Mg: Double = 0
    var vitaminB12Mcg: Double = 0
    var folateMcg: Double = 0

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case createdBy = "created_by"
        case name, brand
        case servingSizeG = "serving_size_g"
        case servingName = "serving_name"
        case caloriesKcal = "calories_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case saturatedFatG = "saturated_fat_g"
        case cholesterolMg = "cholesterol_mg"
        case sodiumMg = "sodium_mg"
        case potassiumMg = "potassium_mg"
        case calciumMg = "calcium_mg"
        case ironMg = "iron_mg"
        case magnesiumMg = "magnesium_mg"
        case zincMg = "zinc_mg"
        case vitaminAMcg = "vitamin_a_mcg"
        case vitaminCMg = "vitamin_c_mg"
        case vitaminDMcg = "vitamin_d_mcg"
        case vitaminEMg = "vitamin_e_mg"
        case vitaminKMcg = "vitamin_k_mcg"
        case thiamineB1Mg = "thiamine_b1_mg"
        case riboflavinB2Mg = "riboflavin_b2_mg"
        case niacinB3Mg = "niacin_b3_mg"
        case vitaminB6Mg = "vitamin_b6_mg"
        case vitaminB12Mcg = "vitamin_b12_mcg"
        case folateMcg = "folate_mcg"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
