import SwiftUI

/// Routes between launch, sign-in, onboarding and the app.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if Demo.active && UserDefaults.standard.string(forKey: "screen") == "design" {
                DesignSystemView()
            } else {
                content
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch app.phase {
        case .loading:
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.Colors.bg)
        case .signedOut:
            WelcomeView()
        case .onboarding:
            OnboardingView()
        case .ready:
            MainTabView()
        }
    }
}
