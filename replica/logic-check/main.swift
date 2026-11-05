// Self-check for the pure domain logic. Run: replica/logic-check/run.sh
import Foundation

func check(_ cond: Bool, _ msg: String, line: Int = #line) { if !cond { print("FAIL line \(line): \(msg)"); exit(1) } }
func near(_ a: Double, _ b: Double, _ tol: Double = 0.5) -> Bool { abs(a - b) <= tol }

// Day: local calendar, arithmetic, weekday matches Postgres dow
let d = Day(rawValue: "2026-11-05")!   // a Thursday
check(d.weekday == 4, "weekday \(d.weekday)")
check(d.adding(days: 1).rawValue == "2026-11-06", "add")
check(Day(rawValue: "2026-03-08")!.adding(days: 1).rawValue == "2026-03-09", "DST day add")
check(d.distance(to: Day(rawValue: "2026-11-12")!) == 7, "distance")
check(Day(rawValue: "2026-13-01") == nil, "invalid")
let enc = String(data: try! JSONEncoder().encode(d), encoding: .utf8)!
check(enc == "\"2026-11-05\"", "encode \(enc)")
check(try! JSONDecoder().decode(Day.self, from: Data("\"2026-11-05T00:00:00\"".utf8)) == d, "decode with time")

// BMR: Mifflin for a 30-year-old male, 80 kg, 180 cm = 1780
var p = Profile(id: UUID())
p.sex = .male; p.heightCm = 180
p.dateOfBirth = Day(Calendar.current.date(byAdding: .year, value: -30, to: Date())!.addingTimeInterval(-86400 * 2))
check(near(TargetCalculator.bmr(profile: p, weightKg: 80)!, 1780), "mifflin")
p.bmrMethod = .katchMcArdle; p.bodyFatPct = 20
check(near(TargetCalculator.bmr(profile: p, weightKg: 80)!, 370 + 21.6 * 64), "katch")
p.bmrMethod = .mifflin

// Targets: moderate activity, lose 0.5 kg/week, 30/40/30 split
p.activityLevel = .moderate; p.goalKgPerWeek = -0.5
let dri = [NutrientDRI(nutrientKey: "iron", sex: .male, ageMin: 19, ageMax: 30, target: 8, upperLimit: 45),
           NutrientDRI(nutrientKey: "iron", sex: .female, ageMin: 19, ageMax: 30, target: 18, upperLimit: 45),
           NutrientDRI(nutrientKey: "iron", sex: .male, ageMin: 31, ageMax: 50, target: 8, upperLimit: 45)]
let t = TargetCalculator.targets(profile: p, weightKg: 80, dri: dri, overrides: [])
check(near(t.energyTarget, 1780 * 1.55 - 550), "energy \(t.energyTarget)")
check(near(t.goal(.protein)!.min!, t.energyTarget * 0.3 / 4), "protein")
check(near(t.goal(.fat)!.min!, t.energyTarget * 0.3 / 9), "fat")
check(t.goals["iron"] == NutrientGoal(min: 8, max: 45), "dri male 19-30")
let o = NutrientTargetOverride(userId: UUID(), nutrientKey: "iron", minAmount: 10, maxAmount: nil, enabled: true)
check(TargetCalculator.targets(profile: p, weightKg: 80, dri: dri, overrides: [o]).goals["iron"] == NutrientGoal(min: 10, max: nil), "override")
let off = NutrientTargetOverride(userId: UUID(), nutrientKey: "iron", minAmount: nil, maxAmount: nil, enabled: false)
check(TargetCalculator.targets(profile: p, weightKg: 80, dri: dri, overrides: [off]).goals["iron"] == nil, "disabled")

// Keto: net carbs is a max, fat fills the rest
p.macroMode = .keto; p.carbsG = 20; p.proteinG = 120
let k = TargetCalculator.targets(profile: p, weightKg: 80, dri: [], overrides: [])
check(k.goal(.netCarbs)?.max == 20 && k.goal(.carbs) == nil, "keto carbs")
check(near(k.goal(.fat)!.min!, (k.energyTarget - 480 - 80) / 9), "keto fat")

// Macro schedule template overrides energy and grams
let tpl = MacroTemplate(userId: UUID(), name: "Training", energyKcal: 2800, proteinG: 180, carbsG: 300, fatG: nil)
p.macroMode = .ratio
let st = TargetCalculator.targets(profile: p, weightKg: 80, dri: [], overrides: [], template: tpl)
check(st.energyTarget == 2800 && st.goal(.protein)?.min == 180 && near(st.goal(.fat)!.min!, 2800 * 0.3 / 9), "template")

// Energy balance: exercise raises the target
let eb = EnergyBalance(consumed: 1500, exercise: 300, targets: t)
check(near(eb.remaining, t.energyTarget + 300 - 1500) && near(eb.burned, 1780 * 1.55 + 300), "balance")

// Guardrail: 1.5 kg/week on 80 kg is > 1%
p.goalKgPerWeek = -1
check(TargetCalculator.guardrail(profile: p, weightKg: 80, heightCm: 180) != nil, "guardrail fires")
p.goalKgPerWeek = -0.5
check(TargetCalculator.guardrail(profile: p, weightKg: 80, heightCm: 180) == nil, "guardrail quiet")

// Nutrients: scaling, derived keys
let food: Nutrients = ["carbs": 20, "fiber": 5, "ala": 0.1, "dha": 0.2]
check(food.scaled(by: 1.5)["carbs"] == 30, "scale")
check(food.withDerived["net_carbs"] == 15 && near(food.withDerived["omega_3"]!, 0.3, 1e-9), "derived")
check((["a": 1.0] + ["a": 2.0, "b": 1.0]) == ["a": 3, "b": 1], "add")

// Scores
let score = NutritionScore.all.first { $0.id == "bone" }!
let goals = ["calcium": NutrientGoal(min: 1000, max: 2500), "protein": NutrientGoal(min: 100, max: nil)]
check(score.score(totals: ["calcium": 500, "protein": 150], goals: goals) == 75, "score")
let heart = NutritionScore.all.first { $0.id == "heart" }!
check(heart.score(totals: ["fiber": 30, "sodium": 4000], goals: ["fiber": .init(min: 30, max: nil), "sodium": .init(min: 1500, max: 2300)]) == 90, "limit penalty")
check(score.gaps(totals: ["calcium": 500, "protein": 150], goals: goals) == [.calcium], "gaps")

// Units
check(Units.weight(63.5, .uk) == "10 st 0 lb", Units.weight(63.5, .uk))
check(Units.height(180, .imperial) == "5 ft 11 in", Units.height(180, .imperial))
check(Units.energy(100, .kj) == "418 kJ", Units.energy(100, .kj))

// Food servings: own default first, then g and oz
var f = Food(name: "Rice")
f.servings = [FoodServing(foodId: f.id, name: "1 cup", grams: 158, isDefault: true)]
check(f.defaultServing.name == "1 cup" && f.servingOptions.map(\.name) == ["1 cup", "g", "oz"], "servings")
check(f.servingOptions[1].storedId == nil && f.servingOptions[0].storedId != nil, "built-in serving ids not stored")

print("logic-check: all passed")
