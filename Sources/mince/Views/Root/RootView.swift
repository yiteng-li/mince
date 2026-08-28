import SwiftUI

/// Switches between the auth flow and the main app based on session state.
struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                LogInView()
            }
        }
    }
}
