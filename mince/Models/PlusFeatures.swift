import Foundation

struct MacroTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var name: String
    var energyKcal: Int?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", name, energyKcal = "energy_kcal", proteinG = "protein_g", carbsG = "carbs_g", fatG = "fat_g"
    }
}

struct MacroScheduleDay: Codable, Hashable {
    var userId: UUID
    var weekday: Int
    var templateId: UUID
    enum CodingKeys: String, CodingKey { case userId = "user_id", weekday, templateId = "template_id" }
}

struct RepeatRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var foodId: UUID?
    var mealId: UUID?
    var servingId: UUID?
    var servingQty: Double?
    var amountG: Double?
    var groupId: UUID?
    var weekdays: [Int]
    var startsOn: Day
    var endsOn: Day?
    var food: FoodName?
    var meal: FoodName?

    struct FoodName: Codable, Hashable { var name: String }

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", foodId = "food_id", mealId = "meal_id", servingId = "serving_id", servingQty = "serving_qty"
        case amountG = "amount_g", groupId = "group_id", weekdays, startsOn = "starts_on", endsOn = "ends_on", food = "foods", meal = "meals"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(foodId, forKey: .foodId)
        try c.encode(mealId, forKey: .mealId)
        try c.encode(servingId, forKey: .servingId)
        try c.encode(servingQty, forKey: .servingQty)
        try c.encode(amountG, forKey: .amountG)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(startsOn, forKey: .startsOn)
        try c.encode(endsOn, forKey: .endsOn)
    }

    var title: String { food?.name ?? meal?.name ?? "Item" }

    var cadence: String { Self.cadence(weekdays) }

    /// "Every day", "Weekdays" or "Mon, Wed".
    static func cadence(_ weekdays: [Int]) -> String {
        let set = Set(weekdays)
        if set.count == 7 { return "Every day" }
        if set == [1, 2, 3, 4, 5] { return "Weekdays" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().map { symbols[$0] }.joined(separator: ", ")
    }
}

struct Fast: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var startedAt: Date
    var endedAt: Date?
    var targetMinutes: Int

    enum CodingKeys: String, CodingKey { case id, userId = "user_id", startedAt = "started_at", endedAt = "ended_at", targetMinutes = "target_minutes" }

    var isOpen: Bool { endedAt == nil }
    func elapsed(now: Date = Date()) -> TimeInterval { (endedAt ?? now).timeIntervalSince(startedAt) }
    var target: TimeInterval { TimeInterval(targetMinutes * 60) }
}

struct FastSchedule: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var weekdays: [Int]
    /// "HH:mm:ss" local time.
    var startTime: String
    var targetMinutes: Int

    enum CodingKeys: String, CodingKey { case id, userId = "user_id", weekdays, startTime = "start_time", targetMinutes = "target_minutes" }

    var hour: Int { Int(startTime.prefix(2)) ?? 20 }
    var minute: Int { Int(startTime.dropFirst(3).prefix(2)) ?? 0 }
}

struct ChartSeries: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case nutrient, biometric }
    var type: Kind
    var key: String
    var id: String { "\(type.rawValue):\(key)" }
}

struct CustomChart: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var title: String
    var series: [ChartSeries]
    var rangeDays = 30
    var pinned = false
    var position = 0

    enum CodingKeys: String, CodingKey { case id, userId = "user_id", title, series, rangeDays = "range_days", pinned, position }
}

struct Snapshot: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var day: Day
    var storagePath: String
    enum CodingKeys: String, CodingKey { case id, userId = "user_id", day, storagePath = "storage_path" }
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
