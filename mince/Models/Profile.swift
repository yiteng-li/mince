import Foundation

/// One row per user: body stats, energy + macro settings, preferences.
/// Current weight is not stored here; it is the latest weight biometric.
struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String?
    var dateOfBirth: Day?
    var sex: Sex?
    var heightCm: Double?
    var bodyFatPct: Double?

    var bmrMethod: BMRMethod = .mifflin
    var customBmrKcal: Int?
    var activityLevel: ActivityLevel = .sedentary
    var goalKgPerWeek: Double = 0
    var tefPct: Double = 10
    var useHealthActiveEnergy = false

    var macroMode: MacroMode = .ratio
    var proteinPct = 30
    var carbsPct = 40
    var fatPct = 30
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var dietPreset: DietPreset = .none

    var unitSystem: UnitSystem = .metric
    var energyUnit: EnergyUnit = .kcal
    var timezone = TimeZone.current.identifier
    var waterTargetMl = 2500
    var selectedScores: [String] = []
    var plusMenu: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", dateOfBirth = "date_of_birth", sex, heightCm = "height_cm", bodyFatPct = "body_fat_pct"
        case bmrMethod = "bmr_method", customBmrKcal = "custom_bmr_kcal", activityLevel = "activity_level"
        case goalKgPerWeek = "goal_kg_per_week", tefPct = "tef_pct", useHealthActiveEnergy = "use_health_active_energy"
        case macroMode = "macro_mode", proteinPct = "protein_pct", carbsPct = "carbs_pct", fatPct = "fat_pct"
        case proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g", dietPreset = "diet_preset"
        case unitSystem = "unit_system", energyUnit = "energy_unit", timezone, waterTargetMl = "water_target_ml"
        case selectedScores = "selected_scores", plusMenu = "plus_menu"
    }

    var age: Int? {
        guard let dob = dateOfBirth?.date else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year
    }

    /// Enough answers to compute targets.
    var isOnboarded: Bool { sex != nil && dateOfBirth != nil && heightCm != nil }
}

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
}

enum BMRMethod: String, Codable, CaseIterable, Identifiable {
    case mifflin, harrisBenedict = "harris_benedict", katchMcArdle = "katch_mcardle", custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mifflin: "Mifflin-St Jeor"
        case .harrisBenedict: "Harris-Benedict (revised)"
        case .katchMcArdle: "Katch-McArdle (needs body fat)"
        case .custom: "Custom"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive = "very_active"
    var id: String { rawValue }
    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
    var title: String {
        switch self {
        case .sedentary: "Sedentary (desk job, little walking)"
        case .light: "Lightly active (on your feet some of the day)"
        case .moderate: "Moderately active (on your feet most of the day)"
        case .active: "Active (physical job)"
        case .veryActive: "Very active (hard physical labour)"
        }
    }
}

enum MacroMode: String, Codable, CaseIterable, Identifiable {
    case ratio, grams, keto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ratio: "Percent of energy"
        case .grams: "Fixed grams"
        case .keto: "Keto (fixed carbs + protein, fat fills the rest)"
        }
    }
}

enum DietPreset: String, Codable, CaseIterable, Identifiable {
    case none, keto, vegan, vegetarian, pescatarian, lowCarb = "low_carb", highProtein = "high_protein", mediterranean
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Balanced"
        case .keto: "Ketogenic"
        case .vegan: "Vegan"
        case .vegetarian: "Vegetarian"
        case .pescatarian: "Pescatarian"
        case .lowCarb: "Low carb"
        case .highProtein: "High protein"
        case .mediterranean: "Mediterranean"
        }
    }

    /// Macro split this preset applies (protein, carbs, fat %), or keto grams.
    var split: (mode: MacroMode, p: Int, c: Int, f: Int) {
        switch self {
        case .none, .vegan, .vegetarian, .pescatarian: (.ratio, 20, 50, 30)
        case .keto: (.keto, 20, 5, 75)
        case .lowCarb: (.ratio, 30, 20, 50)
        case .highProtein: (.ratio, 35, 35, 30)
        case .mediterranean: (.ratio, 20, 45, 35)
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case metric, imperial, uk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .metric: "Metric (kg, cm)"
        case .imperial: "US (lb, ft/in)"
        case .uk: "UK (st/lb, ft/in)"
        }
    }
}

enum EnergyUnit: String, Codable, CaseIterable, Identifiable {
    case kcal, kj
    var id: String { rawValue }
}
