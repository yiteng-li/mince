import Foundation
import Supabase

/// NOTE: verify `signUp`/`signInWithPassword`/`authStateChanges` against
/// whatever supabase-swift version SPM resolves — GoTrue's auth API has
/// renamed methods across versions (e.g. `signIn` → `signInWithPassword`)
/// and this couldn't be compiled/checked here.
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var session: Session?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let client = SupabaseService.shared

    var isAuthenticated: Bool { session != nil }

    init() {
        Task { await observeAuthState() }
    }

    private func observeAuthState() async {
        for await state in client.auth.authStateChanges {
            session = state.session
        }
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // TODO: light validation (email format, password length) belongs here.
            try await client.auth.signUp(email: email, password: password)
            // If email confirmation is on, there's no session yet — the
            // profile row gets created on first login instead. If it's off,
            // this is safe to call now.
            if let userId = try? await client.auth.session.user.id {
                try? await ProfileService().createIfNeeded(userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logIn(email: String, password: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.auth.signInWithPassword(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
