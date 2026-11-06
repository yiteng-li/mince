// App <-> database contract check.
//   harness encode            -> prints every payload the app writes, keyed by table (real model types, SDK coder settings)
//   harness decode rows.json  -> decodes what Postgres returns for every read shape the app uses into the real model types
import Foundation

// Same coder settings as supabase-swift (Helpers/Codable.swift, DateFormatter.swift).
extension Date.ISO8601FormatStyle {
    fileprivate func currentTimestamp(includingFractionalSeconds: Bool) -> Self {
        year().month().day().dateTimeSeparator(.standard).time(includingFractionalSeconds: includingFractionalSeconds)
    }
}
let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .custom { date, enc in
        var c = enc.singleValueContainer()
        try c.encode(date.formatted(.iso8601.currentTimestamp(includingFractionalSeconds: true)))
    }
    return e
}()
let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { dec in
        let c = try dec.singleValueContainer()
        let s = try c.decode(String.self)
        if let d = try? Date(s, strategy: .iso8601.currentTimestamp(includingFractionalSeconds: true)) { return d }
        if let d = try? Date(s, strategy: .iso8601.currentTimestamp(includingFractionalSeconds: false)) { return d }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date format: \(s)")
    }
    return d
}()

let U = { (s: String) in UUID(uuidString: s)! }
let uid = U("00000000-0000-0000-0000-00000000000A")
let F1 = U("F0000000-0000-0000-0000-000000000001"), S1 = U("5E000000-0000-0000-0000-000000000001")
let R1 = U("F0000000-0000-0000-0000-0000000000AA"), M1 = U("ED000000-0000-0000-0000-000000000001")
let G1 = U("6A000000-0000-0000-0000-000000000001"), BT = U("B7000000-0000-0000-0000-000000000001")
let T1 = U("7E000000-0000-0000-0000-000000000001")
let today = Day(rawValue: "2026-11-05")!

func payloads() throws -> [String: [Any]] {
    func j<T: Encodable>(_ v: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(v)) }
    var p = Profile(id: uid)
    p.displayName = "Contract"; p.sex = .female; p.dateOfBirth = Day(rawValue: "1990-05-01"); p.heightCm = 170
    p.macroMode = .keto; p.proteinPct = 25; p.carbsPct = 5; p.fatPct = 70; p.carbsG = 20; p.selectedScores = ["bone", "heart"]; p.plusMenu = ["food", "water"]
    var food = Food(id: F1, userId: uid, source: .custom, name: "Test bar", brand: "Acme", barcode: "0123456789012", nutrients: ["energy": 380, "protein": 33, "magnesium": 90])
    food.servings = [FoodServing(id: S1, foodId: F1, name: "1 bar", grams: 60, isDefault: true)]   // must not be encoded
    let recipe = Food(id: R1, userId: uid, kind: .recipe, source: .recipe, name: "Trail mix", recipeYieldG: 200, instructions: "Mix.")
    var entry = DiaryEntry(userId: uid, day: today, kind: .food, groupId: G1, loggedAt: Date(), foodId: F1, servingId: S1, servingQty: 1.5, amountG: 90)
    entry.food = food   // embedded on read only; must not be encoded
    let quick = DiaryEntry(userId: uid, day: today, kind: .quickAdd, nutrients: ["energy": 250, "water": 500], title: "Cake")
    let exercise = DiaryEntry(userId: uid, day: today, kind: .exercise, title: "Climbing", minutes: 45, energyKcal: 320)
    let bio = DiaryEntry(userId: uid, day: today, kind: .biometric, biometricTypeId: BT, value: 120, value2: 80)
    let note = DiaryEntry(userId: uid, day: today, kind: .note, groupId: G1, note: "Felt great")
    let health = DiaryEntry(userId: uid, day: today, kind: .exercise, loggedAt: Date(), title: "Run", minutes: 30, energyKcal: 300, source: .health, externalId: "HK-1")
    return [
        "profiles": [try j(p)],
        "diary_groups": [try j(DiaryGroup(id: G1, userId: uid, name: "Second breakfast", position: 4))],
        "foods": [try j(food), try j(recipe)],
        "food_servings": [try j(FoodServing(id: S1, foodId: F1, name: "1 bar", grams: 60, isDefault: true))],
        "recipe_ingredients": [try j(FoodLineRow(id: UUID(), foodId: F1, servingId: S1, servingQty: 2, amountG: 120, position: 0, recipeId: R1, mealId: nil))],
        "meals": [try j(Meal(id: M1, userId: uid, name: "Usual breakfast"))],
        "meal_items": [try j(FoodLineRow(id: UUID(), foodId: F1, servingId: nil, servingQty: 30, amountG: 30, position: 0, recipeId: nil, mealId: M1))],
        "biometric_types": [try j(BiometricType(id: BT, userId: uid, key: "custom_bp_home", name: "Home BP", unit: "mmHg", category: "custom", valueKind: .pair))],
        "diary_entries": [try j(entry), try j(quick), try j(exercise), try j(bio), try j(note), try j(health)],
        "days": [try j(DayStatus(userId: uid, day: today, completed: true))],
        "repeat_rules": [try j(RepeatRule(userId: uid, foodId: F1, servingId: S1, servingQty: 1, amountG: 60, groupId: G1, weekdays: [1, 3, 5], startsOn: today, endsOn: today.adding(days: 30)))],
        "fasts": [try j(Fast(userId: uid, startedAt: Date().addingTimeInterval(-3600), targetMinutes: 960))],
        "fast_schedules": [try j(FastSchedule(userId: uid, weekdays: [0, 6], startTime: "20:00:00", targetMinutes: 960))],
        "custom_charts": [try j(CustomChart(userId: uid, title: "Mg vs BP", series: [.init(type: .nutrient, key: "magnesium"), .init(type: .biometric, key: "custom_bp_home")]))],
        "snapshots": [try j(Snapshot(userId: uid, day: today, storagePath: "\(uid.uuidString.lowercased())/x.jpg"))],
        "macro_templates": [try j(MacroTemplate(id: T1, userId: uid, name: "Training", energyKcal: 2600, proteinG: 160, carbsG: 280, fatG: 80))],
        "macro_schedule": [try j(MacroScheduleDay(userId: uid, weekday: 2, templateId: T1))],
        "nutrient_targets": [try j(NutrientTargetOverride(userId: uid, nutrientKey: "iron", minAmount: 10, maxAmount: 40, enabled: true))],
    ]
}

var failures = 0
func check<T: Decodable>(_ name: String, _ type: T.Type, _ rows: [String: Any]) {
    guard let raw = rows[name] else { print("MISSING \(name)"); failures += 1; return }
    do {
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed])
        _ = try decoder.decode(T.self, from: data)
        print("ok      \(name) -> \(T.self)")
    } catch {
        failures += 1
        print("FAIL    \(name) -> \(T.self): \(error)")
    }
}

let args = CommandLine.arguments
if args.count > 1 && args[1] == "encode" {
    let out = try JSONSerialization.data(withJSONObject: try payloads(), options: [.sortedKeys])
    FileHandle.standardOutput.write(out)
} else if args.count > 2 && args[1] == "decode" {
    let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
    check("profile", Profile.self, rows)
    check("nutrients", [Nutrient].self, rows)
    check("nutrient_dri", [NutrientDRI].self, rows)
    check("nutrient_targets", [NutrientTargetOverride].self, rows)
    check("biometric_types", [BiometricType].self, rows)
    check("exercises", [Exercise].self, rows)
    check("diary_groups", [DiaryGroup].self, rows)
    check("foods_with_servings", [Food].self, rows)
    check("food_single", Food.self, rows)
    check("diary_entries_joined", [DiaryEntry].self, rows)
    check("recipe_ingredients_joined", [FoodLine].self, rows)
    check("meals_joined", [Meal].self, rows)
    check("repeat_rules_joined", [RepeatRule].self, rows)
    check("days", [DayStatus].self, rows)
    check("fasts", [Fast].self, rows)
    check("fast_schedules", [FastSchedule].self, rows)
    check("custom_charts", [CustomChart].self, rows)
    check("snapshots", [Snapshot].self, rows)
    check("macro_templates", [MacroTemplate].self, rows)
    check("macro_schedule", [MacroScheduleDay].self, rows)
    check("rpc_search_foods", [Food].self, rows)
    check("rpc_recent_foods", [Food].self, rows)
    check("rpc_oracle", [Food].self, rows)
    check("rpc_nutrient_totals", [NutrientTotalRow].self, rows)
    check("rpc_nutrient_sources", [NutrientSourceRow].self, rows)
    check("rpc_get_shared_food", [SharedFoodRow].self, rows)
    check("rpc_has_plus", Bool.self, rows)
    check("rpc_materialize_repeats", Int.self, rows)
    print(failures == 0 ? "decode: all passed" : "decode: \(failures) failed")
    exit(failures == 0 ? 0 : 1)
} else {
    print("usage: harness encode | harness decode rows.json")
}
