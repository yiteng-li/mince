import SwiftUI

/// TODO: search existing foods (wire to FoodService.search), let the user
/// pick a result + quantity to log via DiaryService.add, or switch to a
/// "create custom food" form (the full nutrient set on `Food`) that calls
/// FoodService.create. None of that search/filter/form UX is built yet.
struct AddFoodView: View {
    var body: some View {
        NavigationStack {
            Text("Add Food — TODO")
                .foregroundStyle(.secondary)
                .navigationTitle("Add Food")
        }
    }
}
