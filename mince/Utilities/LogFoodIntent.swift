import AppIntents
import Foundation

/// "Hey Siri, log food in mince": takes what you ate as text and opens Voice Log to confirm it (Gold).
struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log food"
    static let description = IntentDescription("Describe what you ate; mince finds the foods for you to confirm.")

    @Parameter(title: "What did you eat?", requestValueDialog: "What did you eat?")
    var meal: String

    func perform() async throws -> some IntentResult & OpensIntent {
        var c = URLComponents()
        (c.scheme, c.host) = ("mince", "log")
        c.queryItems = [URLQueryItem(name: "text", value: meal)]
        return .result(opensIntent: OpenURLIntent(c.url!))
    }
}

struct MinceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFoodIntent(), phrases: ["Log food in \(.applicationName)", "Add a meal to \(.applicationName)"],
                    shortTitle: "Log food", systemImageName: "fork.knife")
    }
}
