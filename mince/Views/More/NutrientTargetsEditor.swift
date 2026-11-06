import SwiftUI

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
