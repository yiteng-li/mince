import SwiftUI

/// S15: a note in the diary.
struct NoteEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    var entry: DiaryEntry?
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                guard let uid = app.userId else { return }
                                var e = entry ?? DiaryEntry(userId: uid, day: app.selectedDay, kind: .note, groupId: groupId)
                                e.note = String(text.prefix(5000))
                                if entry != nil {
                                    do { _ = try await DiaryService().update(e); app.diaryChanged(); dismiss() } catch { app.report(error) }
                                } else if await app.log([e]) { dismiss() }
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { text = entry?.note ?? "" }
        }
    }
}
