import SwiftUI

@main
struct MinceApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.Colors.accent)
                .onOpenURL { app.handle(url: $0) }
        }
    }
}
