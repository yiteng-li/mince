import Foundation
import Supabase

/// Single shared Supabase client for the app. Reads config from Info.plist
/// keys that Xcode fills in from Secrets.xcconfig at build time — see
/// Secrets.xcconfig.example and the README's "Supabase setup" section for
/// the one-time Xcode wiring.
enum SupabaseService {
    static let shared: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !anonKey.isEmpty
        else {
            fatalError("""
                Missing SUPABASE_URL / SUPABASE_ANON_KEY in Info.plist. \
                Copy Secrets.xcconfig.example to Secrets.xcconfig, fill in your \
                project's values, and wire it into the target's build settings \
                (see README "Supabase setup").
                """)
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }()
}
