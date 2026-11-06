import Foundation

struct DiaryGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var name: String
    var position: Int

    enum CodingKeys: String, CodingKey { case id, userId = "user_id", name, position }
}

/// One row of the diary: food, quick add, exercise, biometric or note.
struct DiaryEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case food, quickAdd = "quick_add", exercise, biometric, note }
    enum Source: String, Codable { case manual, health, `repeat`, photo, voice, `import` }

    var id = UUID()
    var userId: UUID
    var day: Day
    var kind: Kind
    var groupId: UUID?
    var loggedAt: Date?
    var position = 0

    var foodId: UUID?
    var servingId: UUID?
    var servingQty: Double?
    var amountG: Double?
    var nutrients: Nutrients?          // quick add only (absolute amounts)

    var exerciseId: UUID?
    var title: String?
    var minutes: Double?
    var energyKcal: Double?

    var biometricTypeId: UUID?
    var value: Double?
    var value2: Double?

    var note: String?
    var source: Source = .manual
    var externalId: String?
    var repeatRuleId: UUID?

    // Embedded on read, never written.
    var food: Food?
    var serving: ServingName?
    var exercise: ExerciseName?

    struct ServingName: Codable, Hashable { var name: String }
    struct ExerciseName: Codable, Hashable { var name: String }

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", day, kind, groupId = "group_id", loggedAt = "logged_at", position
        case foodId = "food_id", servingId = "serving_id", servingQty = "serving_qty", amountG = "amount_g", nutrients
        case exerciseId = "exercise_id", title, minutes, energyKcal = "energy_kcal"
        case biometricTypeId = "biometric_type_id", value, value2
        case note, source, externalId = "external_id", repeatRuleId = "repeat_rule_id"
        case food, serving, exercise
    }

    /// Writes every column explicitly: nil becomes null, so updates can clear a field and bulk inserts
    /// (whose column list PostgREST takes from the first row) keep every column. Embedded joins are never sent.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(day, forKey: .day)
        try c.encode(kind, forKey: .kind)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(loggedAt, forKey: .loggedAt)
        try c.encode(position, forKey: .position)
        try c.encode(foodId, forKey: .foodId)
        try c.encode(servingId, forKey: .servingId)
        try c.encode(servingQty, forKey: .servingQty)
        try c.encode(amountG, forKey: .amountG)
        try c.encode(nutrients, forKey: .nutrients)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(title, forKey: .title)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(energyKcal, forKey: .energyKcal)
        try c.encode(biometricTypeId, forKey: .biometricTypeId)
        try c.encode(value, forKey: .value)
        try c.encode(value2, forKey: .value2)
        try c.encode(note, forKey: .note)
        try c.encode(source, forKey: .source)
        try c.encode(externalId, forKey: .externalId)
        try c.encode(repeatRuleId, forKey: .repeatRuleId)
    }

    /// Absolute nutrients this entry contributes to the day.
    var consumed: Nutrients {
        switch kind {
        case .food: (food?.nutrients ?? [:]).scaled(by: (amountG ?? 0) / 100)
        case .quickAdd: nutrients ?? [:]
        default: [:]
        }
    }

    /// A copy for another day/group with a fresh id (copy/paste, copy day).
    func copied(to day: Day, groupId: UUID?) -> DiaryEntry {
        var e = self
        e.id = UUID()
        e.day = day
        e.groupId = groupId ?? self.groupId
        e.source = .manual
        e.externalId = nil
        e.repeatRuleId = nil
        if day != self.day { e.loggedAt = nil }
        return e
    }

    static let selectWithJoins = "*, food:foods(*, food_servings(*)), serving:food_servings(name), exercise:exercises(name)"
}

struct DayStatus: Codable, Hashable {
    var userId: UUID
    var day: Day
    var completed: Bool
    enum CodingKeys: String, CodingKey { case userId = "user_id", day, completed }
}

struct Exercise: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var category: String
    var met: Double

    /// kcal = MET x kg x hours (Compendium of Physical Activities).
    func energy(minutes: Double, weightKg: Double) -> Double { met * weightKg * minutes / 60 }
}

struct BiometricType: Identifiable, Codable, Hashable {
    enum ValueKind: String, Codable { case number, pair, scale17 = "scale_1_7", scale110 = "scale_1_10", minutes }

    var id = UUID()
    var userId: UUID?
    var key: String
    var name: String
    var unit: String
    var category: String
    var valueKind: ValueKind = .number

    enum CodingKeys: String, CodingKey { case id, userId = "user_id", key, name, unit, category, valueKind = "value_kind" }

    var isCustom: Bool { userId != nil }
}

/// A progress photo. The image lives in the private `snapshots` bucket under `<user_id>/`.
struct Snapshot: Identifiable, Codable, Hashable {
    var id = UUID()
    var userId: UUID
    var day: Day
    var storagePath: String
    enum CodingKeys: String, CodingKey { case id, userId = "user_id", day, storagePath = "storage_path" }
}
