import SwiftUI

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
