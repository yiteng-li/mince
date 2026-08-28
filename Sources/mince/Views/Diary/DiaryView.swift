import SwiftUI

/// TODO: this is a bare skeleton — design the real layout (meal-type
/// sections, per-entry rows with quantity/macros, totals header styling,
/// empty state, delete/edit, etc.)
struct DiaryView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel = DiaryViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Today's Totals") {
                    Text("\(Int(viewModel.totals.calories)) kcal")
                }

                Section("Entries") {
                    if viewModel.entries.isEmpty {
                        Text("No food logged yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.entries) { entry in
                            Text(entry.food.name)
                        }
                    }
                }
            }
            .navigationTitle("Diary")
            .task {
                if let userId = authViewModel.session?.user.id {
                    await viewModel.load(userId: userId)
                }
            }
        }
    }
}
