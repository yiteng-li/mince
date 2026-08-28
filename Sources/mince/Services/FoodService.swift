import Foundation
import Supabase

/// Talks to the `foods` table. Search/filter behavior is intentionally not
/// implemented — see the TODO below.
struct FoodService {
    private let client = SupabaseService.shared

    /// TODO: implement real search — likely `.textSearch("name", query:)`
    /// (backed by the `foods_name_search_idx` GIN index) or a simpler
    /// `.ilike("name", pattern: "%\(query)%")`. An empty query probably
    /// shouldn't return nothing — consider recent/frequently-logged foods.
    func search(query: String) async throws -> [Food] {
        try await client
            .from("foods")
            .select()
            .limit(50)
            .execute()
            .value
    }

    func create(_ food: Food) async throws -> Food {
        try await client
            .from("foods")
            .insert(food)
            .select()
            .single()
            .execute()
            .value
    }
}
