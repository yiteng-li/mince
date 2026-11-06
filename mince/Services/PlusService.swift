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
        if Demo.active { return Demo.repeatRules }
        return try await db.from("repeat_rules").select("*, foods(name), meals(name)").order("created_at").execute().value
    }

    func save(_ rule: RepeatRule) async throws {
        if Demo.active {
            var r = rule
            r.food = Demo.foods.first { $0.id == rule.foodId }.map { .init(name: $0.name) }
            Demo.upsert(r, into: &Demo.repeatRules)
            return
        }
        do { try await db.from("repeat_rules").upsert(rule).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ rule: RepeatRule) async throws {
        if Demo.active { Demo.repeatRules.removeAll { $0.id == rule.id }; return }
        try await db.from("repeat_rules").delete().eq("id", value: rule.id.uuidString).execute()
    }

    // MARK: Fasting

    func fasts(limit: Int = 60) async throws -> [Fast] {
        if Demo.active { return Demo.fasts.sorted { $0.startedAt > $1.startedAt } }
        return try await db.from("fasts").select().order("started_at", ascending: false).limit(limit).execute().value
    }

    func save(_ fast: Fast) async throws {
        if Demo.active {   // mirrors the one-open-fast unique index
            if fast.isOpen, Demo.fasts.contains(where: { $0.isOpen && $0.id != fast.id }) { throw AppError.message("A fast is already running.") }
            Demo.upsert(fast, into: &Demo.fasts)
            return
        }
        do { try await db.from("fasts").upsert(fast).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ fast: Fast) async throws {
        if Demo.active { Demo.fasts.removeAll { $0.id == fast.id }; return }
        try await db.from("fasts").delete().eq("id", value: fast.id.uuidString).execute()
    }

    func fastSchedules() async throws -> [FastSchedule] {
        if Demo.active { return Demo.fastSchedules }
        return try await db.from("fast_schedules").select().execute().value
    }

    func save(_ schedule: FastSchedule) async throws {
        if Demo.active { Demo.upsert(schedule, into: &Demo.fastSchedules); return }
        do { try await db.from("fast_schedules").upsert(schedule).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ schedule: FastSchedule) async throws {
        if Demo.active { Demo.fastSchedules.removeAll { $0.id == schedule.id }; return }
        try await db.from("fast_schedules").delete().eq("id", value: schedule.id.uuidString).execute()
    }

    // MARK: Custom charts

    func charts() async throws -> [CustomChart] {
        if Demo.active { return Demo.charts }
        return try await db.from("custom_charts").select().order("position").execute().value
    }

    func save(_ chart: CustomChart) async throws {
        if Demo.active { Demo.upsert(chart, into: &Demo.charts); return }
        do { try await db.from("custom_charts").upsert(chart).execute() } catch { throw AppError.wrap(error) }
    }

    func delete(_ chart: CustomChart) async throws {
        if Demo.active { Demo.charts.removeAll { $0.id == chart.id }; return }
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
