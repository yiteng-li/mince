import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = Tab.diary

    enum Tab: Hashable { case dashboard, diary, trends, foods, more }

    var body: some View {
        @Bindable var app = app
        TabView(selection: $tab) {
            DashboardView().tag(Tab.dashboard).tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            DiaryView().tag(Tab.diary).tabItem { Label("Diary", systemImage: "book.closed") }
            TrendsView().tag(Tab.trends).tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            FoodsHubView().tag(Tab.foods).tabItem { Label("Foods", systemImage: "fork.knife") }
            MoreView().tag(Tab.more).tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .sheet(isPresented: $app.showPlus) {
            PlusMenu { action in
                app.showPlus = false
                app.open(action.sheet)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $app.activeSheet) { sheet in
            LogSheetView(sheet: sheet)
        }
        .sheet(isPresented: $app.showPaywall) { PaywallView() }
        .onAppear(perform: openDemoRoute)
    }

    /// DEBUG `-demo -tab trends -sheet food`: jump straight to a screen for screenshots.
    private func openDemoRoute() {
        guard Demo.active else { return }
        let d = UserDefaults.standard
        tab = ["dashboard": .dashboard, "trends": .trends, "foods": .foods, "more": .more][d.string(forKey: "tab") ?? ""] ?? .diary
        switch d.string(forKey: "sheet") {
        case "food": app.activeSheet = .food(groupId: nil)
        case "quick": app.activeSheet = .quickAdd(groupId: nil)
        case "exercise": app.activeSheet = .exercise
        case "biometric": app.activeSheet = .biometric(typeKey: nil)
        case "voice": app.activeSheet = .voice(groupId: nil, text: nil)
        case "photo": app.activeSheet = .photo(groupId: nil)
        case "fasting": app.activeSheet = .fasting
        case "water": app.activeSheet = .water
        case "barcode": app.activeSheet = .barcode(groupId: nil)
        case "paywall": app.showPaywall = true
        case "plus": app.showPlus = true
        default: break
        }
    }
}

/// The view for each logging flow.
struct LogSheetView: View {
    let sheet: LogSheet

    var body: some View {
        switch sheet {
        case .food(let g): FoodSearchView(groupId: g)
        case .barcode(let g): BarcodeLogView(groupId: g)
        case .photo(let g): PhotoLogView(groupId: g)
        case .voice(let g, let text): VoiceLogView(groupId: g, initialText: text)
        case .quickAdd(let g): QuickAddView(groupId: g)
        case .exercise: ExerciseLogView()
        case .biometric(let key): BiometricLogView(typeKey: key)
        case .note(let g): NoteEditorView(groupId: g)
        case .water: WaterLogView()
        case .fasting: NavigationStack { FastingView() }
        case .editEntry(let e): EntryEditorView(entry: e)
        case .sharedFood(let token): SharedFoodImportView(token: token)
        }
    }
}

struct PlusMenu: View {
    @Environment(AppModel.self) private var app
    var onPick: (PlusAction) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Space.sm)], spacing: Theme.Space.sm) {
                    ForEach(PlusAction.ordered(app.profile?.plusMenu ?? [])) { action in
                        Button { onPick(action) } label: {
                            VStack(spacing: Theme.Space.xs) {
                                Image(systemName: action.symbol).font(.title2)
                                Text(action.title).font(Theme.Fonts.label).multilineTextAlignment(.center)
                                if action.needsPlus && !app.hasPlus { PlusBadge() }
                            }
                            .frame(maxWidth: .infinity, minHeight: 96)
                            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Colors.bg)
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Opens the add menu. Lives in the nav bar so it never covers content.
struct PlusButton: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Button { app.showPlus = true } label: { Image(systemName: "plus").fontWeight(.semibold) }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Add to diary")
    }
}
