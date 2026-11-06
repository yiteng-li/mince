import SwiftUI

/// Gallery of every primitive in every state. The design-system check:
/// open the preview in light, dark and an accessibility text size.
struct DesignSystemView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                section("Buttons") {
                    Button("Log food") {}.buttonStyle(.minced)
                    Button("Saving") {}.buttonStyle(.minced(.primary, loading: true))
                    Button("Cancel") {}.buttonStyle(.minced(.secondary))
                    Button("Delete entry") {}.buttonStyle(.minced(.destructive))
                    Button("Upgrade") {}.buttonStyle(.minced(.plus))
                    Button("Disabled") {}.buttonStyle(.minced).disabled(true)
                    PlusBadge()
                }
                section("Energy") {
                    HStack {
                        EnergyRing(consumed: 1240, target: 2100)
                        EnergyRing(consumed: 2400, target: 2100)
                    }
                }
                section("Nutrient bars") {
                    NutrientBar(name: "Protein", amount: 82, unit: "g", target: 120, tint: Theme.Colors.protein)
                    NutrientBar(name: "Carbs", amount: 240, unit: "g", target: 210, tint: Theme.Colors.carbs)
                    NutrientBar(name: "Fat", amount: 40, unit: "g", target: 70, tint: Theme.Colors.fat)
                    NutrientBar(name: "Sodium", amount: 2900, unit: "mg", target: 1500, max: 2300)
                    NutrientBar(name: "Caffeine", amount: 95, unit: "mg")
                }
                section("Empty state") {
                    EmptyStateView(symbol: "fork.knife", title: "Nothing logged yet",
                                   hint: "Tap + to add what you ate.", actionTitle: "Add food") {}
                }
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.Colors.bg)
        .foregroundStyle(Theme.Colors.text)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title).font(Theme.Fonts.title)
            content()
        }
        .card()
    }
}

#Preview("Light") { DesignSystemView() }
#Preview("Dark") { DesignSystemView().preferredColorScheme(.dark) }
#Preview("XXXL text") { DesignSystemView().dynamicTypeSize(.accessibility3) }
