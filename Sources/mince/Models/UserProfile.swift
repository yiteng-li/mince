import Foundation

/// Raw profile inputs only — no stored calorie/macro targets. Targets are
/// derived from these fields by `CalorieCalculator` at read time, so they
/// never go stale when the user edits height/weight/activity/goal.
struct UserProfile: Identifiable, Codable, Hashable {
    let id: UUID // matches auth.users.id (see 0001_profiles.sql)
    var displayName: String?
    /// yyyy-MM-dd. Modeled as a string, not `Date`, to sidestep Supabase's
    /// default JSON date-decoding (tuned for timestamptz) — parse with a
    /// `yyyy-MM-dd` DateFormatter where you need an actual `Date`.
    var dateOfBirth: String?
    var sex: Sex?
    var heightCm: Double?
    var weightKg: Double?
    var activityLevel: ActivityLevel?
    var goal: Goal?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case dateOfBirth = "date_of_birth"
        case sex, goal
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case activityLevel = "activity_level"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum Sex: String, Codable, CaseIterable {
    case male, female
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary, light, moderate, active
    case veryActive = "very_active"
}

enum Goal: String, Codable, CaseIterable {
    case cut, maintain, bulk
}
