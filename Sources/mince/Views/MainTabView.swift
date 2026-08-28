import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DiaryView()
                .tabItem { Label("Diary", systemImage: "fork.knife") }

            AddFoodView()
                .tabItem { Label("Add Food", systemImage: "plus.circle") }

            ProgressTabView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
