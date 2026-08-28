import Foundation
import Supabase

/// Talks to the `diary_entries` table, embedding `foods` so callers get
/// nutrient data without a second round trip.
struct DiaryService {
    private let client = SupabaseService.shared

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Everything the user logged on `day`.
    func entries(for userId: UUID, on day: Date = Date()) async throws -> [DiaryEntryWithFood] {
        try await client
            .from("diary_entries")
            .select("id, quantity_g, meal_type, logged_on, food:foods(*)")
            .eq("user_id", value: userId.uuidString)
            .eq("logged_on", value: Self.dayFormatter.string(from: day))
            .execute()
            .value
    }

    func add(_ entry: DiaryEntry) async throws {
        try await client
            .from("diary_entries")
            .insert(entry)
            .execute()
    }

    func delete(id: UUID) async throws {
        try await client
            .from("diary_entries")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}
