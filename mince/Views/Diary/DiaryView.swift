import SwiftUI

@MainActor
@Observable
final class DiaryModel {
    var entries: [DiaryEntry] = []
    var isLoading = true
    var error: String?
    var completed = false
    var toast: Toast?

    func load(day: Day, gold: Bool) async {
        error = nil
        do {
            if gold { try? await DiaryService().materializeRepeats(on: day) }
            async let e = DiaryService().entries(on: day)
            async let c = DiaryService().completedDays(since: day)
            let (rows, done) = try await (e, c)
            entries = rows
            completed = done.contains(day)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    var consumed: Nutrients { entries.reduce(into: Nutrients()) { $0 += $1.consumed } }
    var exerciseKcal: Double { entries.filter { $0.kind == .exercise }.compactMap(\.energyKcal).reduce(0, +) }

    func entries(in group: DiaryGroup?, sortedByTime: Bool) -> [DiaryEntry] {
        let rows = entries.filter { [.food, .quickAdd, .note].contains($0.kind) && $0.groupId == group?.id }
        return sortedByTime ? rows.sorted { ($0.loggedAt ?? .distantFuture) < ($1.loggedAt ?? .distantFuture) } : rows
    }

    func delete(_ ids: Set<UUID>, app: AppModel) async {
        let removed = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        do {
            try await DiaryService().delete(ids: Array(ids))
            app.diaryChanged()
            toast = Toast(message: removed.count == 1 ? "Entry deleted" : "\(removed.count) entries deleted") { [weak self] in
                Task {
                    _ = try? await DiaryService().insert(removed)
                    self?.entries += removed
                    app.diaryChanged()
                }
            }
        } catch {
            entries += removed
            app.report(error)
        }
    }

    func paste(_ copied: [DiaryEntry], day: Day, groupId: UUID?, app: AppModel) async {
        do {
            let inserted = try await DiaryService().insert(copied.map { $0.copied(to: day, groupId: groupId) })
            entries += inserted
            app.diaryChanged()
            toast = Toast(message: "Pasted \(inserted.count) item\(inserted.count == 1 ? "" : "s")")
        } catch { app.report(error) }
    }

    func move(_ entry: DiaryEntry, to group: DiaryGroup, app: AppModel) async {
        var e = entry
        e.groupId = group.id
        do {
            let saved = try await DiaryService().update(e)
            if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i] = saved }
        } catch { app.report(error) }
    }

    func toggleComplete(day: Day, app: AppModel) async {
        do {
            try await DiaryService().setCompleted(!completed, day: day)
            completed.toggle()
            app.diaryChanged()
        } catch { app.report(error) }
    }
}

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

    private func reload() async { await model.load(day: app.selectedDay, gold: app.isGold) }

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
                Toggle(isOn: Binding(get: { sortByTime }, set: { v in app.requireGold { sortByTime = v } })) {
                    Label("Sort by time\(app.isGold ? "" : " (Gold)")", systemImage: "clock")
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
                // One text so it wraps at large sizes; the subtotal is Gold.
                let kcal = rows.reduce(0) { $0 + $1.consumed[.energy] }
                Text(app.isGold && !rows.isEmpty ? "\(group.name) · \(Units.energy(kcal, app.energyUnit))" : group.name)
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
        DiaryEntryRow(entry: entry, showTime: app.isGold)
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
                    Button { app.requireGold { repeatEntry = entry } } label: { Label("Repeat\(app.isGold ? "" : " (Gold)")", systemImage: "repeat") }
                }
                Button(role: .destructive) { Task { await model.delete([entry.id], app: app) } } label: { Label("Delete", systemImage: "trash") }
            }
    }
}

struct DiaryEntryRow: View {
    @Environment(AppModel.self) private var app
    let entry: DiaryEntry
    var showTime = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xxs) {
                    if entry.repeatRuleId != nil { Image(systemName: "repeat").font(.caption).foregroundStyle(Theme.Colors.textMuted).accessibilityLabel("Repeats") }
                    if entry.source == .health { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.Colors.danger).accessibilityLabel("From Apple Health") }
                    Text(title).font(Theme.Fonts.body).lineLimit(2)
                }
                if let subtitle { Text(subtitle).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted).lineLimit(3) }
                if showTime, let t = entry.loggedAt {
                    Text(t, style: .time).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing).font(Theme.Fonts.label.monospacedDigit())
                    .foregroundStyle(entry.kind == .exercise ? Theme.Colors.success : Theme.Colors.text)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isWater: Bool { entry.kind == .quickAdd && entry.nutrients?.keys.sorted() == ["water"] }

    private var title: String {
        switch entry.kind {
        case .food: entry.food?.displayName ?? "Food"
        case .quickAdd: isWater ? "Water" : entry.title ?? "Quick add"
        case .exercise: entry.exercise?.name ?? entry.title ?? "Exercise"
        case .biometric: app.biometricType(id: entry.biometricTypeId)?.name ?? "Biometric"
        case .note: entry.note ?? ""
        }
    }

    private var subtitle: String? {
        switch entry.kind {
        case .food:
            let g = Units.amount(entry.amountG ?? 0, unit: "g")
            if let q = entry.servingQty, let s = entry.serving?.name, s != "g" {
                return "\(q.formatted(.number.precision(.fractionLength(0...2)))) × \(s) · \(g)"
            }
            return g
        case .exercise: return entry.minutes.map { "\(Int($0)) min" }
        case .quickAdd where isWater: return nil
        case .quickAdd:
            let n = entry.nutrients ?? [:]
            return "P \(Int(n[.protein]))g · C \(Int(n[.carbs]))g · F \(Int(n[.fat]))g"
        default: return nil
        }
    }

    private var trailing: String? {
        switch entry.kind {
        case .quickAdd where isWater: "\(Int(entry.nutrients?["water"] ?? 0)) mL"
        case .food, .quickAdd: Units.energy(entry.consumed[.energy], app.energyUnit)
        case .exercise: "−" + Units.energy(entry.energyKcal ?? 0, app.energyUnit)
        case .biometric: BiometricFormat.value(entry, type: app.biometricType(id: entry.biometricTypeId), units: app.unitSystem)
        case .note: nil
        }
    }
}

enum BiometricFormat {
    static func value(_ e: DiaryEntry, type: BiometricType?, units: UnitSystem) -> String {
        guard let v = e.value, let type else { return "" }
        switch type.valueKind {
        case .pair: return "\(Int(v))/\(Int(e.value2 ?? 0)) \(type.unit)"
        case .minutes: return "\(Int(v) / 60) h \(Int(v) % 60) m"
        case .scale17, .scale110: return "\(Int(v)) / \(type.valueKind == .scale17 ? 7 : 10)"
        case .number:
            if type.key == "weight" { return Units.weight(v, units) }
            if ["waist", "hips", "chest", "neck", "bicep", "thigh", "calf"].contains(type.key), units != .metric {
                return "\((v / Units.cmPerInch).formatted(.number.precision(.fractionLength(0...1)))) in"
            }
            return "\(v.formatted(.number.precision(.fractionLength(0...1)))) \(type.unit)"
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
