import Foundation

/// Energy expenditure and every nutrient target for one day.
struct DayTargets: Hashable {
    var bmr: Double
    var baselineActivity: Double
    /// Maintenance + weight-goal adjustment, before exercise is added.
    var energyTarget: Double
    var goals: [String: NutrientGoal]

    func goal(_ key: NK) -> NutrientGoal? { goals[key.rawValue] }
}

/// Energy, macro and micronutrient targets. Pure, so it can be checked without the app.
enum TargetCalculator {
    static let kcalPerKg = 7700.0

    /// Basal metabolic rate in kcal/day, or nil when the profile is missing an input.
    static func bmr(profile: Profile, weightKg: Double) -> Double? {
        if profile.bmrMethod == .custom, let custom = profile.customBmrKcal { return Double(custom) }
        guard let sex = profile.sex, let age = profile.age, let height = profile.heightCm else { return nil }
        let a = Double(age), male = sex == .male
        switch profile.bmrMethod {
        case .harrisBenedict:
            return male ? 88.362 + 13.397 * weightKg + 4.799 * height - 5.677 * a
                        : 447.593 + 9.247 * weightKg + 3.098 * height - 4.330 * a
        case .katchMcArdle:
            if let bf = profile.bodyFatPct { return 370 + 21.6 * weightKg * (1 - bf / 100) }
            fallthrough
        case .mifflin, .custom:
            return 10 * weightKg + 6.25 * height - 5 * a + (male ? 5 : -161)
        }
    }

    /// Daily energy change needed for the weight goal (negative = deficit).
    static func goalAdjustment(kgPerWeek: Double) -> Double { kgPerWeek * kcalPerKg / 7 }

    /// Warning for weight goals that are too aggressive. nil when fine.
    static func guardrail(profile: Profile, weightKg: Double, heightCm: Double?) -> String? {
        let rate = profile.goalKgPerWeek
        if rate < 0, -rate > weightKg * 0.01 {
            return "Losing more than 1% of body weight a week is hard to sustain and risks muscle loss."
        }
        if let h = heightCm, rate < 0 {
            let bmi = weightKg / pow(h / 100, 2)
            if bmi < 18.5 { return "Your BMI is already below 18.5. Talk to a doctor before aiming to lose weight." }
        }
        if let bmr = bmr(profile: profile, weightKg: weightKg) {
            let target = bmr * profile.activityLevel.multiplier + goalAdjustment(kgPerWeek: rate)
            if target < bmr { return "This target is below your resting energy needs." }
        }
        return nil
    }

    static func targets(
        profile: Profile,
        weightKg: Double,
        dri: [NutrientDRI],
        overrides: [NutrientTargetOverride],
        template: MacroTemplate? = nil,
        healthActiveEnergy: Bool = false
    ) -> DayTargets {
        let bmr = bmr(profile: profile, weightKg: weightKg) ?? 1600
        let baseline = healthActiveEnergy ? 0 : bmr * (profile.activityLevel.multiplier - 1)
        var energy = bmr + baseline + goalAdjustment(kgPerWeek: profile.goalKgPerWeek)
        if let t = template?.energyKcal { energy = Double(t) }
        energy = max(energy, 1000)

        var goals: [String: NutrientGoal] = [:]

        // Defaults from the DRI table for this sex and age.
        let sex = profile.sex ?? .female
        let age = profile.age ?? 30
        for row in dri where row.sex == sex && (row.ageMin...row.ageMax).contains(min(max(age, 13), 120)) {
            goals[row.nutrientKey] = NutrientGoal(min: row.target, max: row.upperLimit)
        }

        // Macros.
        var p: Double, c: Double, f: Double
        switch profile.macroMode {
        case .ratio:
            p = energy * Double(profile.proteinPct) / 100 / 4
            c = energy * Double(profile.carbsPct) / 100 / 4
            f = energy * Double(profile.fatPct) / 100 / 9
        case .grams:
            p = profile.proteinG ?? energy * 0.2 / 4
            c = profile.carbsG ?? energy * 0.5 / 4
            f = profile.fatG ?? energy * 0.3 / 9
        case .keto:
            p = profile.proteinG ?? weightKg * 1.4
            c = profile.carbsG ?? 25
            f = max((energy - 4 * p - 4 * c) / 9, 0)
        }
        if let t = template {
            p = t.proteinG ?? p
            c = t.carbsG ?? c
            f = t.fatG ?? f
        }
        goals[NK.energy.rawValue] = NutrientGoal(min: energy, max: nil)
        goals[NK.protein.rawValue] = NutrientGoal(min: p, max: nil)
        goals[NK.fat.rawValue] = NutrientGoal(min: f, max: nil)
        if profile.macroMode == .keto {
            goals[NK.netCarbs.rawValue] = NutrientGoal(min: nil, max: c)
        } else {
            goals[NK.carbs.rawValue] = NutrientGoal(min: c, max: nil)
        }
        goals[NK.saturatedFat.rawValue] = NutrientGoal(min: nil, max: energy * 0.1 / 9)
        goals[NK.water.rawValue] = goals[NK.water.rawValue] ?? NutrientGoal(min: Double(profile.waterTargetMl), max: nil)

        // The user's own overrides win.
        for o in overrides {
            if !o.enabled { goals[o.nutrientKey] = nil; continue }
            goals[o.nutrientKey] = NutrientGoal(min: o.minAmount, max: o.maxAmount)
        }

        return DayTargets(bmr: bmr, baselineActivity: baseline, energyTarget: energy, goals: goals)
    }
}

/// How a day's energy adds up.
struct EnergyBalance: Hashable {
    var consumed: Double
    var bmr: Double
    var baseline: Double
    var exercise: Double
    var target: Double          // energy target + exercise

    var burned: Double { bmr + baseline + exercise }
    var remaining: Double { target - consumed }

    init(consumed: Double, exercise: Double, targets: DayTargets) {
        self.consumed = consumed
        self.exercise = exercise
        bmr = targets.bmr
        baseline = targets.baselineActivity
        target = targets.energyTarget + exercise
    }
}
