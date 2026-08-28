import Foundation
import Supabase

struct ProfileService {
    private let client = SupabaseService.shared

    func fetch(userId: UUID) async throws -> UserProfile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
    }

    /// Call once right after sign-up to create the row `profiles` needs.
    /// `id` must equal `auth.uid()` per the RLS insert policy — see
    /// 0001_profiles.sql.
    func createIfNeeded(userId: UUID) async throws {
        try await client
            .from("profiles")
            .insert(["id": userId.uuidString])
            .execute()
    }

    func update(_ profile: UserProfile) async throws {
        try await client
            .from("profiles")
            .update(profile)
            .eq("id", value: profile.id.uuidString)
            .execute()
    }
}
