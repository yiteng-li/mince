import SwiftUI

/// S05: one day of the diary.
struct DiaryView: View {
    @Environment(AppModel.self) private var app
    @State private var model = DiaryModel()
    @State private var selection = Set<UUID>()
    @State private var editMode = EditMode.inactive
    @State private var showNutrients = true
    @State private var detail: Nutrient?
    @State private var repeatEntry: DiaryEntry?
    @State private var mealFromGroup: DiaryGroup?
    @AppStorage("sortByTime") private var sortByTime = false

    var body: some View {
        @Bindable var app = app
        let targets = app.targets(for: app.selectedDay)
        NavigationStack {
            List(selection: $selection) {
                Section {
                    DateNavigator(day: $app.selectedDay, completed: model.completed)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    EnergySummaryCard(balance: EnergyBalance(consumed: model.consumed[.energy], exercise: model.exerciseKcal, targets: targets))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    MacroBars(totals: model.consumed, targets: targets).card()
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                .listRowSeparator(.hidden)

                if model.isLoading || model.error != nil {
                    LoadingView(isLoading: model.isLoading, error: model.error, retry: reload) { EmptyView() }
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(app.groups) { group in groupSection(group, targets: targets) }
                    ungroupedSection
                    exerciseSection
                    biometricSection
                    WaterRow(consumedMl: model.consumed[.water], targetMl: targets.goal(.water)?.min ?? 2500)

                    Section {
                        DisclosureGroup("Nutrients", isExpanded: $showNutrients) { EmptyView() }
                            .font(Theme.Fonts.heading)
                    }
                    if showNutrients {
                        NutrientTargetsView(totals: model.consumed, goals: targets.goals) { detail = $0 }
                    }

                    Section {
                        Button(model.completed ? "Mark day as not complete" : "Mark day complete") {
                            Task { await model.toggleComplete(day: app.selectedDay, app: app) }
                        }
                        .buttonStyle(.minced(model.completed ? .secondary : .primary))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    } footer: {
                        Text("Completed days count toward your streak.")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            // The Copy / Delete bar sits where the tab bar is; hide tabs while selecting so taps reach it.
            .toolbar(editMode.isEditing ? .hidden : .visible, for: .tabBar)
            .listStyle(.insetGrouped)
            .screenBackground()
            .navigationTitle("Diary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .refreshable { await reload() }
            .task(id: "\(app.selectedDay.rawValue)-\(app.diaryVersion)") { await reload() }
            .toast($model.toast)
            .sheet(item: $detail) { n in NutrientDetailView(nutrient: n, from: app.selectedDay, to: app.selectedDay) }
            .sheet(item: $repeatEntry) { e in RepeatRuleEditor(entry: e) }
            .sheet(item: $mealFromGroup) { g in
                MealEditorView(meal: nil, initialItems: model.entries(in: g, sortedByTime: false).filter { $0.kind == .food })
            }
            .gesture(DragGesture(minimumDistance: 40).onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                app.selectedDay = app.selectedDay.adding(days: v.translation.width < 0 ? 1 : -1)
            })
        }
    }

    private func reload() async { await model.load(day: app.selectedDay, hasPlus: app.hasPlus) }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                selection = []
            }
        }
        ToolbarItem(placement: .primaryAction) { PlusButton() }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: Binding(get: { sortByTime }, set: { v in app.requirePlus { sortByTime = v } })) {
                    Label("Sort by time\(app.hasPlus ? "" : " (mince+)")", systemImage: "clock")
                }
                if !app.clipboard.isEmpty {
                    Button { Task { await model.paste(app.clipboard, day: app.selectedDay, groupId: nil, app: app) } } label: {
                        Label("Paste \(app.clipboard.count) item\(app.clipboard.count == 1 ? "" : "s")", systemImage: "doc.on.clipboard")
                    }
                }
                Button { Task { await copyDay(from: app.selectedDay.adding(days: -1), group: nil) } } label: {
                    Label("Copy all of yesterday", systemImage: "arrow.uturn.backward")
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        if editMode.isEditing {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Copy") {
                    app.clipboard = model.entries.filter { selection.contains($0.id) }
                    model.toast = Toast(message: "Copied \(app.clipboard.count). Paste from the ⋯ menu on any day.")
                    editMode = .inactive
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button("Delete", role: .destructive) {
                    let ids = selection
                    Task { await model.delete(ids, app: app) }
                    editMode = .inactive
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private func copyDay(from: Day, group: DiaryGroup?) async {
        do {
            let rows = try await DiaryService().entries(on: from).filter { $0.kind != .biometric && (group == nil || $0.groupId == group?.id) }
            guard !rows.isEmpty else { model.toast = Toast(message: "Nothing logged on \(from.title.lowercased())"); return }
            await model.paste(rows, day: app.selectedDay, groupId: group?.id, app: app)
        } catch { app.report(error) }
    }

    @ViewBuilder private func groupSection(_ group: DiaryGroup, targets: DayTargets) -> some View {
        let rows = model.entries(in: group, sortedByTime: sortByTime)
        Section {
            ForEach(rows) { entryRow($0) }
            if rows.isEmpty {
                Button { app.open(.food(groupId: group.id)) } label: {
                    Label("Add food", systemImage: "plus").foregroundStyle(Theme.Colors.textMuted)
                }
            }
        } header: {
            HStack {
                // One text so it wraps at large sizes; the subtotal is mince+.
                let kcal = rows.reduce(0) { $0 + $1.consumed[.energy] }
                Text(app.hasPlus && !rows.isEmpty ? "\(group.name) · \(Units.energy(kcal, app.energyUnit))" : group.name)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Menu {
                    Button { app.open(.food(groupId: group.id)) } label: { Label("Add food", systemImage: "magnifyingglass") }
                    Button { app.open(.barcode(groupId: group.id)) } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
                    Button { app.open(.photo(groupId: group.id)) } label: { Label("Photo", systemImage: "camera") }
                    Button { app.open(.quickAdd(groupId: group.id)) } label: { Label("Quick add", systemImage: "bolt") }
                    Button { app.open(.note(groupId: group.id)) } label: { Label("Note", systemImage: "note.text") }
                    if !app.clipboard.isEmpty {
                        Button { Task { await model.paste(app.clipboard, day: app.selectedDay, groupId: group.id, app: app) } } label: {
                            Label("Paste here", systemImage: "doc.on.clipboard")
                        }
                    }
                    Button { Task { await copyDay(from: app.selectedDay.adding(days: -1), group: group) } } label: {
                        Label("Copy yesterday's \(group.name.lowercased())", systemImage: "arrow.uturn.backward")
                    }
                    if !rows.isEmpty {
                        Button { mealFromGroup = group } label: { Label("Save as meal", systemImage: "square.stack") }
                    }
                } label: {
                    Image(systemName: "plus.circle").font(.title3)
                }
                .accessibilityLabel("Add to \(group.name)")
            }
        }
    }

    @ViewBuilder private var ungroupedSection: some View {
        let rows = model.entries(in: nil, sortedByTime: sortByTime)
        if !rows.isEmpty {
            Section("Other") { ForEach(rows) { entryRow($0) } }
        }
    }

    @ViewBuilder private var exerciseSection: some View {
        let rows = model.entries.filter { $0.kind == .exercise }
        Section {
            ForEach(rows) { entryRow($0) }
            Button { app.open(.exercise) } label: { Label("Add exercise", systemImage: "plus").foregroundStyle(Theme.Colors.textMuted) }
        } header: { Text("Exercise") }
    }

    @ViewBuilder private var biometricSection: some View {
        let rows = model.entries.filter { $0.kind == .biometric }
        Section {
            ForEach(rows) { entryRow($0) }
            Button { app.open(.biometric(typeKey: nil)) } label: { Label("Add biometric", systemImage: "plus").foregroundStyle(Theme.Colors.textMuted) }
        } header: { Text("Biometrics") }
    }

    private func entryRow(_ entry: DiaryEntry) -> some View {
        DiaryEntryRow(entry: entry, showTime: app.hasPlus)
            .tag(entry.id)
            .contentShape(Rectangle())
            .onTapGesture {
                // This gesture would otherwise swallow the List's own selection taps in Select mode.
                if editMode.isEditing { selection.formSymmetricDifference([entry.id]) } else { app.open(.editEntry(entry)) }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { Task { await model.delete([entry.id], app: app) } } label: { Label("Delete", systemImage: "trash") }
            }
            .swipeActions(edge: .leading) {
                Button { app.clipboard = [entry]; model.toast = Toast(message: "Copied") } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .tint(Theme.Colors.accent)
            }
            .contextMenu {
                Button { app.open(.editEntry(entry)) } label: { Label("Edit", systemImage: "pencil") }
                Button { app.clipboard = [entry] } label: { Label("Copy", systemImage: "doc.on.doc") }
                if entry.kind == .food || entry.kind == .quickAdd || entry.kind == .note {
                    Menu("Move to") {
                        ForEach(app.groups.filter { $0.id != entry.groupId }) { g in
                            Button(g.name) { Task { await model.move(entry, to: g, app: app) } }
                        }
                    }
                }
                if entry.kind == .food {
                    Button { app.requirePlus { repeatEntry = entry } } label: { Label("Repeat\(app.hasPlus ? "" : " (mince+)")", systemImage: "repeat") }
                }
                Button(role: .destructive) { Task { await model.delete([entry.id], app: app) } } label: { Label("Delete", systemImage: "trash") }
            }
    }
}

/// Water progress with quick-add cups (S16 inline).
struct WaterRow: View {
    @Environment(AppModel.self) private var app
    let consumedMl: Double
    let targetMl: Double

    var body: some View {
        Section {
            HStack {
                NutrientBar(name: "Water", amount: consumedMl, unit: "mL", target: targetMl, tint: Theme.Colors.carbs)
                    .accessibilityIdentifier("waterTotal")
                Button { Task { await WaterLogView.add(ml: 250, app: app) } } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.Colors.accent)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Add a 250 millilitre glass")
            }
        } footer: { Text("Includes water in foods.") }
    }
}
