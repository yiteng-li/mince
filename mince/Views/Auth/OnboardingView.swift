import SwiftUI

/// S03: profile + target wizard. Writes the profile and a first weight entry.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var step = 0
    @State private var draft = Profile(id: UUID())
    @State private var weight: Double?
    @State private var heightText: Double?
    @State private var dob = Calendar.current.date(byAdding: .year, value: -30, to: Date())!
    @State private var saving = false

    private let steps = ["About you", "Body", "Activity", "Goal", "Diet"]

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case 0:
                    Section("What should we call you?") { TextField("Name (optional)", text: Binding($draft.displayName, replacingNilWith: "")) }
                    Section {
                        Picker("Sex", selection: $draft.sex) {
                            Text("Choose").tag(Sex?.none)
                            Text("Male").tag(Sex?.some(.male))
                            Text("Female").tag(Sex?.some(.female))
                        }
                        DatePicker("Date of birth", selection: $dob, in: ...Day.latestBirthDate, displayedComponents: .date)
                    } footer: { Text("Used for your energy needs and vitamin and mineral targets.") }
                    Section("Units") {
                        Picker("Units", selection: $draft.unitSystem) { ForEach(UnitSystem.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.inline).labelsHidden()
                    }
                case 1:
                    Section {
                        NumberField(title: "Height", value: $heightText, unit: draft.unitSystem == .metric ? "cm" : "in")
                        NumberField(title: "Current weight", value: $weight, unit: Units.weightUnit(draft.unitSystem))
                        NumberField(title: "Body fat (optional)", value: $draft.bodyFatPct, unit: "%")
                    }
                case 2:
                    Section {
                        Picker("Activity", selection: $draft.activityLevel) { ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.inline).labelsHidden()
                    } header: { Text("Outside of workouts, how active is a normal day?") }
                      footer: { Text("Log workouts separately; they add to your target on the days you do them.") }
                case 3:
                    goalStep
                default:
                    Section {
                        Picker("Diet", selection: $draft.dietPreset) { ForEach(DietPreset.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.inline).labelsHidden()
                    } header: { Text("Pick a starting macro split") } footer: { Text("You can fine-tune protein, carbs and fat later in More → Targets.") }
                }
            }
            .screenBackground()
            .navigationTitle(steps[step])
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 0 { Button("Back") { step -= 1 } }
                }
                ToolbarItem(placement: .principal) {
                    ProgressView(value: Double(step + 1), total: Double(steps.count)).frame(width: 120)
                        .accessibilityLabel("Step \(step + 1) of \(steps.count)")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(step == steps.count - 1 ? "Start tracking" : "Continue") { next() }
                    .buttonStyle(.minced(.primary, loading: saving))
                    .disabled(!canContinue || saving)
                    .padding(Theme.Space.md)
                    .background(Theme.Colors.bg)
            }
            .onAppear {
                guard let p = app.profile else { return }
                draft = p
                if let d = p.dateOfBirth { dob = d.date }
                heightText = p.heightCm.map { p.unitSystem == .metric ? $0 : $0 / Units.cmPerInch }
            }
        }
    }

    @ViewBuilder private var goalStep: some View {
        let kg = Units.weightKg(fromDisplay: weight ?? 70, draft.unitSystem)
        Section {
            Picker("Goal", selection: $draft.goalKgPerWeek) {
                Text("Lose 1 kg / 2 lb a week").tag(-1.0)
                Text("Lose 0.5 kg / 1 lb a week").tag(-0.5)
                Text("Lose 0.25 kg / 0.5 lb a week").tag(-0.25)
                Text("Maintain").tag(0.0)
                Text("Gain 0.25 kg / 0.5 lb a week").tag(0.25)
                Text("Gain 0.5 kg / 1 lb a week").tag(0.5)
            }
            .pickerStyle(.inline).labelsHidden()
        }
        if let warning = TargetCalculator.guardrail(profile: withDOB, weightKg: kg, heightCm: heightCm) {
            Section { Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.Colors.warning) }
        }
        Section("Your starting target") {
            let t = TargetCalculator.targets(profile: withDOB, weightKg: kg, dri: [], overrides: [])
            LabeledContent("Energy", value: Units.energy(t.energyTarget, draft.energyUnit))
            LabeledContent("Resting (BMR)", value: Units.energy(t.bmr, draft.energyUnit))
        }
    }

    private var heightCm: Double? {
        guard let h = heightText else { return nil }
        return draft.unitSystem == .metric ? h : h * Units.cmPerInch
    }

    private var withDOB: Profile {
        var p = draft
        p.dateOfBirth = Day(dob)
        p.heightCm = heightCm
        return p
    }

    private var canContinue: Bool {
        switch step {
        case 0: draft.sex != nil
        case 1: (heightCm ?? 0) > 50 && (weight ?? 0) > 20
        default: true
        }
    }

    private func next() {
        guard step == steps.count - 1 else { step += 1; return }
        Task {
            saving = true
            defer { saving = false }
            var p = withDOB
            let split = p.dietPreset.split
            (p.macroMode, p.proteinPct, p.carbsPct, p.fatPct) = (split.mode, split.p, split.c, split.f)
            if let id = app.userId {
                p = Profile(id: id, displayName: p.displayName, dateOfBirth: p.dateOfBirth, sex: p.sex, heightCm: p.heightCm,
                            bodyFatPct: p.bodyFatPct, activityLevel: p.activityLevel, goalKgPerWeek: p.goalKgPerWeek,
                            macroMode: p.macroMode, proteinPct: p.proteinPct, carbsPct: p.carbsPct, fatPct: p.fatPct,
                            dietPreset: p.dietPreset, unitSystem: p.unitSystem)
                if let w = weight, let type = app.biometricType("weight") {
                    let entry = DiaryEntry(userId: id, day: .today, kind: .biometric, biometricTypeId: type.id,
                                           value: Units.weightKg(fromDisplay: w, p.unitSystem))
                    do { try await DiaryService().insert([entry]) } catch { app.report(error) }
                }
            }
            await app.refreshWeight()
            await app.saveProfile(p)
        }
    }
}

extension Binding where Value == String {
    /// Edits an optional String as a plain one ("" means nil).
    init(_ source: Binding<String?>, replacingNilWith empty: String) {
        self.init(get: { source.wrappedValue ?? empty }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
