import SwiftUI

/// S32: settings and everything that isn't a daily screen.
struct MoreView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if app.hasPlus {
                        Label("mince+ is active", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.Colors.success)
                        Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    } else {
                        Button { app.showPaywall = true } label: {
                            HStack { Label("Upgrade to mince+", systemImage: "star.fill"); Spacer(); PlusBadge() }
                        }
                    }
                }
                Section("You") {
                    NavigationLink { ProfileSettingsView() } label: { Label("Profile & body", systemImage: "person") }
                    NavigationLink { TargetsSettingsView() } label: { Label("Energy & macro targets", systemImage: "target") }
                    NavigationLink { NutrientTargetsEditor() } label: { Label("Vitamin & mineral targets", systemImage: "list.bullet.clipboard") }
                    plusLink("Macro Scheduler", symbol: "calendar") { MacroSchedulerView() }
                }
                Section("Diary") {
                    NavigationLink { DiaryGroupsView() } label: { Label("Diary groups", systemImage: "rectangle.stack") }
                    plusLink("Repeat items", symbol: "repeat") { RepeatRulesView() }
                    plusLink("Fasting", symbol: "timer") { FastingView() }
                    NavigationLink { PlusMenuEditor() } label: { Label("Customise the + menu", systemImage: "plus.square.on.square") }
                    NavigationLink { SnapshotsView() } label: { Label("Progress photos", systemImage: "photo.on.rectangle") }
                }
                Section("Connections") {
                    NavigationLink { IntegrationsView() } label: { Label("Apple Health", systemImage: "heart") }
                }
                Section("Data") {
                    NavigationLink { DataSettingsView() } label: { Label("Export & delete", systemImage: "externaldrive") }
                }
                Section {
                    NavigationLink { AboutView() } label: { Label("About & data sources", systemImage: "info.circle") }
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
            }
            .screenBackground()
            .navigationTitle("More")
            .confirmationDialog("Sign out of mince?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            }
        }
    }

    @ViewBuilder private func plusLink<D: View>(_ title: String, symbol: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        if app.hasPlus {
            NavigationLink { destination() } label: { Label(title, systemImage: symbol) }
        } else {
            PlusRow(action: {}) { Label(title, systemImage: symbol) }
        }
    }
}
