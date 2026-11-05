import SwiftUI

/// S32: settings and everything that isn't a daily screen.
struct MoreView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if app.isGold {
                        Label("mince Gold is active", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.Colors.success)
                        Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    } else {
                        Button { app.showPaywall = true } label: {
                            HStack { Label("Upgrade to Gold", systemImage: "star.fill"); Spacer(); GoldBadge() }
                        }
                    }
                }
                Section("You") {
                    NavigationLink { ProfileSettingsView() } label: { Label("Profile & body", systemImage: "person") }
                    NavigationLink { TargetsSettingsView() } label: { Label("Energy & macro targets", systemImage: "target") }
                    NavigationLink { NutrientTargetsEditor() } label: { Label("Vitamin & mineral targets", systemImage: "list.bullet.clipboard") }
                    goldLink("Macro Scheduler", symbol: "calendar") { MacroSchedulerView() }
                }
                Section("Diary") {
                    NavigationLink { DiaryGroupsView() } label: { Label("Diary groups", systemImage: "rectangle.stack") }
                    goldLink("Repeat items", symbol: "repeat") { RepeatRulesView() }
                    goldLink("Fasting", symbol: "timer") { FastingView() }
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

    @ViewBuilder private func goldLink<D: View>(_ title: String, symbol: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        if app.isGold {
            NavigationLink { destination() } label: { Label(title, systemImage: symbol) }
        } else {
            GoldRow(action: {}) { Label(title, systemImage: symbol) }
        }
    }
}

struct ProfileSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var p = Profile(id: UUID())
    @State private var dob = Date()
    @State private var heightDisplay: Double?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: Binding($p.displayName, replacingNilWith: ""))
                Picker("Sex", selection: $p.sex) {
                    Text("Male").tag(Sex?.some(.male))
                    Text("Female").tag(Sex?.some(.female))
                }
                DatePicker("Date of birth", selection: $dob, in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!, displayedComponents: .date)
                NumberField(title: "Height", value: $heightDisplay, unit: p.unitSystem == .metric ? "cm" : "in")
                NumberField(title: "Body fat", value: $p.bodyFatPct, unit: "%")
            }
            Section {
                LabeledContent("Current weight", value: app.currentWeightKg.map { Units.weight($0, app.unitSystem) } ?? "Not logged")
                Button("Log weight") { app.open(.biometric(typeKey: "weight")) }
            } footer: { Text("Your latest weight entry is used for energy targets.") }
            Section("Units") {
                Picker("Body", selection: $p.unitSystem) { ForEach(UnitSystem.allCases) { Text($0.title).tag($0) } }
                Picker("Energy", selection: $p.energyUnit) {
                    Text("Calories (kcal)").tag(EnergyUnit.kcal)
                    Text("Kilojoules (kJ)").tag(EnergyUnit.kj)
                }
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            p = app.profile ?? p
            dob = p.dateOfBirth?.date ?? dob
            heightDisplay = p.heightCm.map { p.unitSystem == .metric ? $0 : $0 / Units.cmPerInch }
        }
        .onDisappear {
            var q = p
            q.dateOfBirth = Day(dob)
            q.heightCm = heightDisplay.map { app.profile?.unitSystem == .metric ? $0 : $0 * Units.cmPerInch }
            Task { await app.saveProfile(q) }
        }
    }
}

/// S27: energy and macro targets.
struct TargetsSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var p = Profile(id: UUID())
    @State private var customBMR: Double?

    var body: some View {
        let targets = TargetCalculator.targets(profile: p, weightKg: app.weightKg, dri: app.dri, overrides: app.overrides)
        Form {
            Section("Energy") {
                Picker("Resting energy formula", selection: $p.bmrMethod) { ForEach(BMRMethod.allCases) { Text($0.title).tag($0) } }
                if p.bmrMethod == .custom { NumberField(title: "Your BMR", value: $customBMR, unit: "kcal") }
                Picker("Daily activity", selection: $p.activityLevel) { ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) } }
                Toggle("Use Apple Health active energy", isOn: $p.useHealthActiveEnergy)
                Picker("Weight goal", selection: $p.goalKgPerWeek) {
                    ForEach([-1.0, -0.75, -0.5, -0.25, 0, 0.25, 0.5], id: \.self) { v in
                        Text(v == 0 ? "Maintain" : "\(v < 0 ? "Lose" : "Gain") \(abs(v).formatted()) kg / week").tag(v)
                    }
                }
                if let warning = TargetCalculator.guardrail(profile: p, weightKg: app.weightKg, heightCm: p.heightCm) {
                    Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Colors.warning).font(Theme.Fonts.footnote)
                }
                LabeledContent("Resting (BMR)", value: Units.energy(targets.bmr, p.energyUnit))
                LabeledContent("Daily target", value: Units.energy(targets.energyTarget, p.energyUnit))
            }

            Section {
                Picker("Diet preset", selection: Binding(get: { p.dietPreset }, set: { d in
                    p.dietPreset = d
                    let s = d.split
                    (p.macroMode, p.proteinPct, p.carbsPct, p.fatPct) = (s.mode, s.p, s.c, s.f)
                })) { ForEach(DietPreset.allCases) { Text($0.title).tag($0) } }
                Picker("Set macros as", selection: $p.macroMode) { ForEach(MacroMode.allCases) { Text($0.title).tag($0) } }
                switch p.macroMode {
                case .ratio:
                    Stepper("Protein \(p.proteinPct)%", value: $p.proteinPct, in: 5...80, step: 5)
                    Stepper("Carbs \(p.carbsPct)%", value: $p.carbsPct, in: 0...80, step: 5)
                    Stepper("Fat \(p.fatPct)%", value: $p.fatPct, in: 5...85, step: 5)
                    let sum = p.proteinPct + p.carbsPct + p.fatPct
                    if sum != 100 {
                        Label("Adds up to \(sum)%. Make it 100% to save.", systemImage: "exclamationmark.circle").foregroundStyle(Theme.Colors.danger)
                    }
                case .grams:
                    NumberField(title: "Protein", value: $p.proteinG, unit: "g")
                    NumberField(title: "Carbs", value: $p.carbsG, unit: "g")
                    NumberField(title: "Fat", value: $p.fatG, unit: "g")
                case .keto:
                    NumberField(title: "Net carbs limit", value: $p.carbsG, unit: "g")
                    NumberField(title: "Protein", value: $p.proteinG, unit: "g")
                    Text("Fat fills the rest of your energy target.").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                }
            } header: { Text("Macros") }

            Section("Resulting targets") {
                MacroBars(totals: [:], targets: targets)
            }
        }
        .navigationTitle("Targets")
        .onAppear { p = app.profile ?? p; customBMR = p.customBmrKcal.map(Double.init) }
        .onDisappear {
            p.customBmrKcal = customBMR.map { Int($0) }
            if p.macroMode == .ratio && p.proteinPct + p.carbsPct + p.fatPct != 100 { return }
            let saved = p
            Task { await app.saveProfile(saved) }
        }
    }
}

/// Override any vitamin/mineral target (or turn it off).
struct NutrientTargetsEditor: View {
    @Environment(AppModel.self) private var app
    @State private var editing: Nutrient?

    var body: some View {
        let goals = app.targets(for: .today).goals
        List {
            ForEach(NutrientCategory.allCases) { cat in
                Section(cat.title) {
                    ForEach(app.nutrients.filter { $0.category == cat }) { n in
                        Button { editing = n } label: {
                            HStack {
                                Text(n.name).foregroundStyle(Theme.Colors.text)
                                if app.overrides.contains(where: { $0.nutrientKey == n.key }) {
                                    Text("custom").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.accent)
                                }
                                Spacer()
                                Text(describe(goals[n.key], unit: n.unit)).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Nutrient targets")
        .sheet(item: $editing) { n in NutrientOverrideEditor(nutrient: n, current: goals[n.key]) }
    }

    private func describe(_ g: NutrientGoal?, unit: String) -> String {
        guard let g else { return "No target" }
        switch (g.min, g.max) {
        case let (min?, max?): return "\(Units.amount(min, unit: unit)) – \(Units.amount(max, unit: unit))"
        case let (min?, nil): return "≥ \(Units.amount(min, unit: unit))"
        case let (nil, max?): return "≤ \(Units.amount(max, unit: unit))"
        default: return "No target"
        }
    }
}

struct NutrientOverrideEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let nutrient: Nutrient
    let current: NutrientGoal?
    @State private var min: Double?
    @State private var max: Double?
    @State private var enabled = true

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Track a target", isOn: $enabled)
                if enabled {
                    NumberField(title: "At least", value: $min, unit: nutrient.unit)
                    NumberField(title: "No more than", value: $max, unit: nutrient.unit)
                }
                Section {
                    Button("Reset to default") {
                        Task { try? await ProfileService().resetOverride(key: nutrient.key); await app.refreshOverrides(); dismiss() }
                    }
                }
            }
            .navigationTitle(nutrient.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = app.userId else { return }
                            let o = NutrientTargetOverride(userId: uid, nutrientKey: nutrient.key, minAmount: min, maxAmount: max, enabled: enabled)
                            do { try await ProfileService().save(override: o); await app.refreshOverrides(); dismiss() } catch { app.report(error) }
                        }
                    }
                    .disabled(enabled && min != nil && max != nil && max! < min!)
                }
            }
            .onAppear { min = current?.min; max = current?.max; enabled = current != nil }
        }
        .presentationDetents([.medium])
    }
}

/// S28 (Gold): different macro templates per weekday.
struct MacroSchedulerView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: MacroTemplate?
    @State private var creating = false

    var body: some View {
        List {
            Section("Templates") {
                ForEach(app.macroTemplates) { t in
                    Button { editing = t } label: {
                        VStack(alignment: .leading) {
                            Text(t.name).foregroundStyle(Theme.Colors.text)
                            Text(summary(t)).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                        }
                    }
                }
                .onDelete { idx in
                    let gone = idx.map { app.macroTemplates[$0] }
                    Task { for t in gone { try? await ProfileService().delete(template: t) }; await app.refreshMacroSchedule() }
                }
                Button { creating = true } label: { Label("New template", systemImage: "plus") }
            }
            Section {
                ForEach(0..<7) { d in
                    Picker(Calendar.current.weekdaySymbols[d], selection: Binding(get: { app.macroSchedule[d] }, set: { id in
                        Task {
                            do { try await ProfileService().setSchedule(weekday: d, templateId: id); await app.refreshMacroSchedule() } catch { app.report(error) }
                        }
                    })) {
                        Text("Default targets").tag(UUID?.none)
                        ForEach(app.macroTemplates) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
            } header: { Text("Week") } footer: { Text("Days without a template use your normal targets.") }
        }
        .navigationTitle("Macro Scheduler")
        .task { await app.refreshMacroSchedule() }
        .sheet(item: $editing) { MacroTemplateEditor(template: $0) }
        .sheet(isPresented: $creating) { MacroTemplateEditor(template: nil) }
    }

    private func summary(_ t: MacroTemplate) -> String {
        [t.energyKcal.map { "\($0) kcal" }, t.proteinG.map { "P \(Int($0))g" }, t.carbsG.map { "C \(Int($0))g" }, t.fatG.map { "F \(Int($0))g" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

struct MacroTemplateEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let template: MacroTemplate?
    @State private var name = ""
    @State private var kcal: Double?
    @State private var p: Double?
    @State private var c: Double?
    @State private var f: Double?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Training day)", text: $name)
                NumberField(title: "Energy", value: $kcal, unit: "kcal")
                NumberField(title: "Protein", value: $p, unit: "g")
                NumberField(title: "Carbs", value: $c, unit: "g")
                NumberField(title: "Fat", value: $f, unit: "g")
            }
            .navigationTitle(template == nil ? "New template" : "Edit template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            guard let uid = app.userId else { return }
                            var t = template ?? MacroTemplate(userId: uid, name: name)
                            t.name = name; t.energyKcal = kcal.map { Int($0) }; t.proteinG = p; t.carbsG = c; t.fatG = f
                            do { try await ProfileService().save(template: t); await app.refreshMacroSchedule(); dismiss() } catch { app.report(error) }
                        }
                    }
                    .disabled(name.isEmpty || (kcal.map { $0 < 500 } ?? false))
                }
            }
            .onAppear {
                guard let t = template else { return }
                (name, kcal, p, c, f) = (t.name, t.energyKcal.map(Double.init), t.proteinG, t.carbsG, t.fatG)
            }
        }
    }
}

/// S29 management (Gold): every repeat rule.
struct RepeatRulesView: View {
    @Environment(AppModel.self) private var app
    @State private var rules: [RepeatRule] = []

    var body: some View {
        List {
            if rules.isEmpty {
                EmptyStateView(symbol: "repeat", title: "Nothing repeats yet", hint: "Long-press a food in your diary and choose Repeat.").listRowBackground(Color.clear)
            }
            ForEach(rules) { r in
                VStack(alignment: .leading) {
                    Text(r.title)
                    Text("\(r.cadence) · \(app.group(id: r.groupId)?.name ?? "No group")\(r.endsOn.map { " · until \($0.title)" } ?? "")")
                        .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .onDelete { idx in
                let gone = idx.map { rules[$0] }
                rules.remove(atOffsets: idx)
                Task { for r in gone { try? await GoldService().delete(r) } }
            }
        }
        .navigationTitle("Repeat items")
        .task { rules = (try? await GoldService().repeatRules()) ?? [] }
    }
}

struct DiaryGroupsView: View {
    @Environment(AppModel.self) private var app
    @State private var groups: [DiaryGroup] = []
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach($groups) { $g in TextField("Name", text: $g.name) }
                    .onMove { groups.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in
                        let gone = idx.map { groups[$0] }
                        groups.remove(atOffsets: idx)
                        Task { for g in gone { try? await DiaryService().delete(group: g) }; await app.refreshGroups() }
                    }
            } footer: { Text("Deleting a group keeps its entries; they move to Other.") }
            Section {
                HStack {
                    TextField("New group", text: $newName)
                    Button("Add") {
                        guard let uid = app.userId else { return }
                        groups.append(DiaryGroup(userId: uid, name: newName, position: groups.count))
                        newName = ""
                    }
                    .disabled(newName.isEmpty || groups.count >= 12)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Diary groups")
        .onAppear { groups = app.groups }
        .onDisappear {
            let rows = groups.enumerated().map { i, g in var x = g; x.position = i; x.name = x.name.isEmpty ? "Group" : String(x.name.prefix(40)); return x }
            Task { try? await DiaryService().upsert(groups: rows); await app.refreshGroups() }
        }
    }
}

struct PlusMenuEditor: View {
    @Environment(AppModel.self) private var app
    @State private var shown: [PlusAction] = []

    var body: some View {
        List {
            Section("Shown") {
                ForEach(shown) { Label($0.title, systemImage: $0.symbol) }
                    .onMove { shown.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in if shown.count - idx.count >= 1 { shown.remove(atOffsets: idx) } }
            }
            Section("Hidden") {
                ForEach(PlusAction.allCases.filter { !shown.contains($0) }) { a in
                    Button { shown.append(a) } label: { Label(a.title, systemImage: a.symbol) }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("+ menu")
        .onAppear { shown = PlusAction.ordered(app.profile?.plusMenu ?? []) }
        .onDisappear {
            guard var p = app.profile else { return }
            p.plusMenu = shown.map(\.rawValue)
            Task { await app.saveProfile(p) }
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section("Food data") {
                Text("Generic foods: USDA FoodData Central (public domain).")
                Text("Branded products and barcodes: Open Food Facts, available under the Open Database License (ODbL).")
            }
            Section("Targets") {
                Text("Default vitamin and mineral targets follow the Dietary Reference Intakes (RDA or AI, with upper limits where they apply to food).")
                Text("Exercise estimates use MET values from the Compendium of Physical Activities.")
            }
            Section {
                Text("mince is not medical advice. Talk to a professional before big changes to your diet.")
                    .foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .navigationTitle("About")
    }
}
