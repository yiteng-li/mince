import Foundation
import Supabase

/// profiles, targets, macro schedule, and the read-only catalogues.
struct ProfileService {
    private var db: SupabaseClient { SupabaseService.shared }

    func profile() async throws -> Profile {
        try await db.from("profiles").select().eq("id", value: SupabaseService.userId.uuidString).single().execute().value
    }

    func update(_ profile: Profile) async throws {
        try await db.from("profiles").update(profile).eq("id", value: profile.id.uuidString).execute()
    }

    // MARK: catalogues

    func nutrients() async throws -> [Nutrient] {
        try await db.from("nutrients").select().order("position").execute().value
    }

    func dri() async throws -> [NutrientDRI] {
        try await db.from("nutrient_dri").select().execute().value
    }

    func biometricTypes() async throws -> [BiometricType] {
        try await db.from("biometric_types").select().order("category").order("name").execute().value
    }

    func saveBiometricType(_ type: BiometricType) async throws {
        do { try await db.from("biometric_types").upsert(type).execute() } catch { throw AppError.wrap(error) }
    }

    func deleteBiometricType(_ type: BiometricType) async throws {
        try await db.from("biometric_types").delete().eq("id", value: type.id.uuidString).execute()
    }

    func exercises(matching query: String) async throws -> [Exercise] {
        if Demo.active {
            return [("Walking, 3.0 mph (moderate)", "walking", 3.5), ("Running, 6 mph (10 min/mile)", "running", 9.8), ("Cycling, moderate (12-14 mph)", "cycling", 8.0),
                    ("Weight training, vigorous", "strength", 6.0), ("Yoga, hatha", "flexibility", 2.5)]
                .map { Exercise(id: UUID(), name: $0.0, category: $0.1, met: $0.2) }
                .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        }
        var q = db.from("exercises").select()
        if !query.isEmpty { q = q.ilike("name", pattern: "%\(query)%") }
        return try await q.order("name").limit(100).execute().value
    }

    // MARK: nutrient target overrides

    func overrides() async throws -> [NutrientTargetOverride] {
        try await db.from("nutrient_targets").select().execute().value
    }

    func save(override o: NutrientTargetOverride) async throws {
        try await db.from("nutrient_targets").upsert(o).execute()
    }

    func resetOverride(key: String) async throws {
        try await db.from("nutrient_targets").delete().eq("nutrient_key", value: key).execute()
    }

    // MARK: Macro Scheduler (Gold)

    func macroTemplates() async throws -> [MacroTemplate] {
        if Demo.active { return [MacroTemplate(userId: Demo.userId, name: "Training day", energyKcal: 2300, proteinG: 140, carbsG: 260, fatG: 70)] }
        return try await db.from("macro_templates").select().order("name").execute().value
    }

    func save(template: MacroTemplate) async throws {
        do { try await db.from("macro_templates").upsert(template).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(template: MacroTemplate) async throws {
        try await db.from("macro_templates").delete().eq("id", value: template.id.uuidString).execute()
    }

    func macroSchedule() async throws -> [MacroScheduleDay] {
        if Demo.active { return [] }
        return try await db.from("macro_schedule").select().execute().value
    }

    func setSchedule(weekday: Int, templateId: UUID?) async throws {
        let uid = try SupabaseService.userId
        if let templateId {
            do { try await db.from("macro_schedule").upsert(MacroScheduleDay(userId: uid, weekday: weekday, templateId: templateId)).execute() }
            catch { throw AppError.wrap(error) }
        } else {
            try await db.from("macro_schedule").delete().eq("weekday", value: weekday).execute()
        }
    }
}
