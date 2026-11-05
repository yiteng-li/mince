import Foundation
import Supabase

/// Gold-only tables (repeat rules, fasts, custom charts) plus snapshots and subscription status.
/// Writes to Gold tables fail with `.goldRequired` when the server says the user isn't Gold.
struct GoldService {
    private var db: SupabaseClient { SupabaseService.shared }

    /// Server-side truth for Gold (what RLS and RPCs check).
    func isGold() async throws -> Bool {
        if Demo.active { return Demo.gold }
        return try await db.rpc("is_gold").execute().value
    }

    // MARK: Repeat Items

    func repeatRules() async throws -> [RepeatRule] {
        if Demo.active { return [RepeatRule(userId: Demo.userId, foodId: Demo.foods[0].id, amountG: 40, groupId: Demo.groups[0].id, weekdays: [1, 2, 3, 4, 5], startsOn: .today, food: .init(name: Demo.foods[0].name))] }
        return try await db.from("repeat_rules").select("*, foods(name), meals(name)").order("created_at").execute().value
    }

    func save(_ rule: RepeatRule) async throws {
        do { try await db.from("repeat_rules").upsert(rule).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ rule: RepeatRule) async throws {
        try await db.from("repeat_rules").delete().eq("id", value: rule.id.uuidString).execute()
    }

    // MARK: Fasting

    func fasts(limit: Int = 60) async throws -> [Fast] {
        if Demo.active {
            return [Fast(userId: Demo.userId, startedAt: Date().addingTimeInterval(-11 * 3600), targetMinutes: 960),
                    Fast(userId: Demo.userId, startedAt: Date().addingTimeInterval(-36 * 3600), endedAt: Date().addingTimeInterval(-19 * 3600), targetMinutes: 960)]
        }
        return try await db.from("fasts").select().order("started_at", ascending: false).limit(limit).execute().value
    }

    func save(_ fast: Fast) async throws {
        do { try await db.from("fasts").upsert(fast).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ fast: Fast) async throws {
        try await db.from("fasts").delete().eq("id", value: fast.id.uuidString).execute()
    }

    func fastSchedules() async throws -> [FastSchedule] {
        if Demo.active { return [FastSchedule(userId: Demo.userId, weekdays: [1, 2, 3, 4, 5], startTime: "20:00:00", targetMinutes: 960)] }
        return try await db.from("fast_schedules").select().execute().value
    }

    func save(_ schedule: FastSchedule) async throws {
        do { try await db.from("fast_schedules").upsert(schedule).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ schedule: FastSchedule) async throws {
        try await db.from("fast_schedules").delete().eq("id", value: schedule.id.uuidString).execute()
    }

    // MARK: Custom charts

    func charts() async throws -> [CustomChart] {
        if Demo.active {
            return [CustomChart(userId: Demo.userId, title: "Magnesium vs weight", series: [.init(type: .nutrient, key: "magnesium"), .init(type: .biometric, key: "weight")], rangeDays: 14, pinned: true)]
        }
        return try await db.from("custom_charts").select().order("position").execute().value
    }

    func save(_ chart: CustomChart) async throws {
        do { try await db.from("custom_charts").upsert(chart).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ chart: CustomChart) async throws {
        try await db.from("custom_charts").delete().eq("id", value: chart.id.uuidString).execute()
    }

    // MARK: Snapshots (progress photos)

    func snapshots() async throws -> [Snapshot] {
        if Demo.active { return [] }
        return try await db.from("snapshots").select().order("day", ascending: false).execute().value
    }

    func addSnapshot(jpeg: Data, day: Day) async throws {
        let uid = try SupabaseService.userId
        let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString).jpg"
        try await db.storage.from("snapshots").upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        try await db.from("snapshots").insert(Snapshot(userId: uid, day: day, storagePath: path)).execute()
    }

    func deleteSnapshot(_ s: Snapshot) async throws {
        try await db.storage.from("snapshots").remove(paths: [s.storagePath])
        try await db.from("snapshots").delete().eq("id", value: s.id.uuidString).execute()
    }

    func signedURL(bucket: String, path: String) async throws -> URL {
        try await db.storage.from(bucket).createSignedURL(path: path, expiresIn: 3600)
    }
}
