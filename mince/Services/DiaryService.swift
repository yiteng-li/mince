import Foundation
import Supabase

/// diary_entries, diary_groups, days, and the aggregation RPCs.
struct DiaryService {
    private var db: SupabaseClient { SupabaseService.shared }

    func entries(on day: Day) async throws -> [DiaryEntry] {
        if Demo.active { return Demo.entries(on: day) }
        return try await db.from("diary_entries")
            .select(DiaryEntry.selectWithJoins)
            .eq("day", value: day.rawValue)
            .order("position").order("created_at")
            .execute().value
    }

    /// Entries of one kind over a range (biometric charts, exports).
    func entries(from: Day, to: Day, kind: DiaryEntry.Kind? = nil, biometricTypeId: UUID? = nil) async throws -> [DiaryEntry] {
        if Demo.active {
            return Demo.diary.filter { $0.day >= from && $0.day <= to && (kind == nil || $0.kind == kind) && (biometricTypeId == nil || $0.biometricTypeId == biometricTypeId) }
                .sorted { $0.day < $1.day }
        }
        var q = db.from("diary_entries").select(DiaryEntry.selectWithJoins)
            .gte("day", value: from.rawValue).lte("day", value: to.rawValue)
        if let kind { q = q.eq("kind", value: kind.rawValue) }
        if let biometricTypeId { q = q.eq("biometric_type_id", value: biometricTypeId.uuidString) }
        return try await q.order("day").order("logged_at").limit(10000).execute().value
    }

    /// Most recent value of a biometric (current weight).
    func latest(biometricTypeId: UUID) async throws -> DiaryEntry? {
        if Demo.active { return Demo.diary.filter { $0.biometricTypeId == biometricTypeId }.max { $0.day < $1.day } }
        let rows: [DiaryEntry] = try await db.from("diary_entries").select()
            .eq("kind", value: "biometric").eq("biometric_type_id", value: biometricTypeId.uuidString)
            .order("day", ascending: false).order("created_at", ascending: false).limit(1)
            .execute().value
        return rows.first
    }

    @discardableResult
    func insert(_ entries: [DiaryEntry]) async throws -> [DiaryEntry] {
        guard !entries.isEmpty else { return [] }
        if Demo.active { Demo.diary += entries; return entries }
        return try await db.from("diary_entries").insert(entries).select(DiaryEntry.selectWithJoins).execute().value
    }

    func update(_ entry: DiaryEntry) async throws -> DiaryEntry {
        if Demo.active { Demo.diary.removeAll { $0.id == entry.id }; Demo.diary.append(entry); return entry }
        return try await db.from("diary_entries").update(entry).eq("id", value: entry.id.uuidString)
            .select(DiaryEntry.selectWithJoins).single().execute().value
    }

    func delete(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        if Demo.active { Demo.diary.removeAll { ids.contains($0.id) }; return }
        try await db.from("diary_entries").delete().in("id", values: ids.map(\.uuidString)).execute()
    }

    /// Bulk delete everything logged between two days (inclusive).
    func deleteRange(from: Day, to: Day) async throws {
        if Demo.active { Demo.diary.removeAll { $0.day >= from && $0.day <= to }; return }
        try await db.from("diary_entries").delete()
            .gte("day", value: from.rawValue).lte("day", value: to.rawValue).execute()
    }

    /// Inserts today's Repeat Items (Gold; a no-op otherwise). Call before loading the day.
    @discardableResult
    func materializeRepeats(on day: Day) async throws -> Int {
        if Demo.active { return 0 }
        return try await db.rpc("materialize_repeats", params: ["p_day": day.rawValue]).execute().value
    }

    /// Per-day nutrient totals for a range. Ranges over 7 days need Gold.
    func totals(from: Day, to: Day) async throws -> [Day: Nutrients] {
        if Demo.active {
            if from.distance(to: to) >= 7 && !Demo.gold { throw AppError.goldRequired }
            return Demo.totals(from: from, to: to)
        }
        do {
            let rows: [NutrientTotalRow] = try await db.rpc("nutrient_totals", params: ["p_from": from.rawValue, "p_to": to.rawValue])
                .execute().value
            return rows.reduce(into: [:]) { $0[$1.day, default: [:]][$1.nutrientKey] = $1.amount }
        } catch { throw AppError.wrap(error) }
    }

    /// Foods in the diary that supplied the most of a nutrient.
    func sources(of key: String, from: Day, to: Day) async throws -> [NutrientSourceRow] {
        if Demo.active {
            let rows = Demo.diary.filter { $0.day >= from && $0.day <= to && $0.kind == .food }
            let byFood = Dictionary(grouping: rows) { $0.foodId! }.compactMap { id, es -> NutrientSourceRow? in
                let amount = es.reduce(0) { $0 + ($1.consumed[key] ?? 0) }
                return amount > 0 ? NutrientSourceRow(foodId: id, name: es[0].food?.name ?? "", amount: amount) : nil
            }
            return byFood.sorted { $0.amount > $1.amount }
        }
        struct Params: Encodable { let p_from: String, p_to: String, p_key: String, lim: Int }
        do {
            return try await db.rpc("nutrient_sources", params: Params(p_from: from.rawValue, p_to: to.rawValue, p_key: key, lim: 15))
                .execute().value
        } catch { throw AppError.wrap(error) }
    }

    // MARK: groups

    func groups() async throws -> [DiaryGroup] {
        if Demo.active { return Demo.groups.sorted { $0.position < $1.position } }
        return try await db.from("diary_groups").select().order("position").execute().value
    }

    func upsert(groups: [DiaryGroup]) async throws {
        if Demo.active { groups.forEach { Demo.upsert($0, into: &Demo.groups) }; Demo.groups.sort { $0.position < $1.position }; return }
        try await db.from("diary_groups").upsert(groups).execute()
    }

    func delete(group: DiaryGroup) async throws {
        if Demo.active {
            Demo.groups.removeAll { $0.id == group.id }
            for i in Demo.diary.indices where Demo.diary[i].groupId == group.id { Demo.diary[i].groupId = nil }
            return
        }
        try await db.from("diary_groups").delete().eq("id", value: group.id.uuidString).execute()
    }

    // MARK: days (complete / streak)

    func completedDays(since: Day) async throws -> Set<Day> {
        if Demo.active { return Demo.completed }
        let rows: [DayStatus] = try await db.from("days").select()
            .eq("completed", value: true).gte("day", value: since.rawValue).execute().value
        return Set(rows.map(\.day))
    }

    func setCompleted(_ completed: Bool, day: Day) async throws {
        if Demo.active { if completed { Demo.completed.insert(day) } else { Demo.completed.remove(day) }; return }
        try await db.from("days").upsert(DayStatus(userId: SupabaseService.userId, day: day, completed: completed)).execute()
    }

    /// Consecutive completed days ending today (or yesterday if today isn't done yet).
    static func streak(completed: Set<Day>, today: Day = .today) -> Int {
        var day = completed.contains(today) ? today : today.adding(days: -1)
        var n = 0
        while completed.contains(day) { n += 1; day = day.adding(days: -1) }
        return n
    }
}
