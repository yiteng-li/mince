import SwiftUI

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
