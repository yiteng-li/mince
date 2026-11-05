import Foundation
import Supabase

/// Single shared Supabase client. Reads SUPABASE_URL / SUPABASE_ANON_KEY from Info.plist
/// (see README "Supabase setup").
enum SupabaseService {
    static let shared: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty
        else {
            fatalError("Missing SUPABASE_URL / SUPABASE_ANON_KEY in Info.plist. See README \"Supabase setup\".")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }()

    /// The signed-in user's id. Services are only used behind the auth gate.
    static var userId: UUID {
        get throws {
            guard let id = shared.auth.currentUser?.id else { throw AppError.signedOut }
            return id
        }
    }
}

enum AppError: LocalizedError {
    case signedOut
    case goldRequired
    case message(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "You're signed out. Sign in again to continue."
        case .goldRequired: "This needs mince Gold."
        case .message(let m): m
        }
    }

    /// Maps the database's `gold_required` exception to `.goldRequired`.
    static func wrap(_ error: Error) -> Error {
        "\(error)".contains("gold_required") ? AppError.goldRequired : error
    }
}
