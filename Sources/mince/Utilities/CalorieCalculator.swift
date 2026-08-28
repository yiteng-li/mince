import Foundation

/// TODO: implement Mifflin-St Jeor (or your preferred formula):
///   Men:   10 * weightKg + 6.25 * heightCm - 5 * age + 5
///   Women: 10 * weightKg + 6.25 * heightCm - 5 * age - 161
/// Multiply by an activity-level factor for maintenance (TDEE), then offset
/// by goal (e.g. -500 kcal/day for cut, +300 for bulk). Both functions
/// return nil when the profile is missing fields the formula needs.
enum CalorieCalculator {
    static func maintenanceCalories(for profile: UserProfile) -> Double? {
        nil // TODO
    }

    static func targetCalories(for profile: UserProfile) -> Double? {
        nil // TODO
    }
}
