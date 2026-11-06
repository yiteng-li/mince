import SwiftUI

/// Tapping any diary row: the matching editor for its kind.
struct EntryEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let entry: DiaryEntry

    var body: some View {
        switch entry.kind {
        case .food:
            NavigationStack {
                if let food = entry.food {
                    FoodLogDetail(food: food, groupId: entry.groupId, entry: entry) { dismiss() }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                } else {
                    ContentUnavailableView("Food unavailable", systemImage: "questionmark")
                }
            }
        case .quickAdd:
            if entry.nutrients?.keys.sorted() == ["water"] {
                WaterLogView()
            } else {
                QuickAddView(groupId: entry.groupId, entry: entry)
            }
        case .exercise: ExerciseLogView(entry: entry)
        case .biometric: BiometricLogView(typeKey: nil, entry: entry)
        case .note: NoteEditorView(groupId: entry.groupId, entry: entry)
        }
    }
}
