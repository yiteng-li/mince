import SwiftUI

/// Pick a food from search (used to fix AI matches and to add recipe/meal ingredients).
struct FoodPicker: View {
    @Environment(\.dismiss) private var dismiss
    var initialQuery = ""
    var onPick: (Food) -> Void
    @State private var query = ""
    @State private var results: [Food] = []

    var body: some View {
        NavigationStack {
            List(results) { food in
                Button { onPick(food) } label: { FoodResultRow(food: food) }.buttonStyle(.plain)
            }
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: query) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                results = query.count >= 2 ? ((try? await FoodService().search(query)) ?? []) : ((try? await FoodService().recent()) ?? [])
            }
            .onAppear { query = initialQuery }
            .navigationTitle("Choose food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
