import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            Form {
                // TODO: profile fields (age/DOB, sex, height, weight,
                // activity level, goal) editing UI — wire to
                // ProfileService.fetch/.update, and surface
                // CalorieCalculator's targets here once implemented.

                Button("Log Out", role: .destructive) {
                    Task { await authViewModel.logOut() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
