import SwiftUI

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
                DatePicker("Date of birth", selection: $dob, in: ...Day.latestBirthDate, displayedComponents: .date)
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
