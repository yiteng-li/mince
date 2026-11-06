import SwiftUI

struct DiaryGroupsView: View {
    @Environment(AppModel.self) private var app
    @State private var groups: [DiaryGroup] = []
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach($groups) { $g in TextField("Name", text: $g.name) }
                    .onMove { groups.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in
                        let gone = idx.map { groups[$0] }
                        groups.remove(atOffsets: idx)
                        Task { for g in gone { try? await DiaryService().delete(group: g) }; await app.refreshGroups() }
                    }
            } footer: { Text("Deleting a group keeps its entries; they move to Other.") }
            Section {
                HStack {
                    TextField("New group", text: $newName)
                    Button("Add") {
                        guard let uid = app.userId else { return }
                        groups.append(DiaryGroup(userId: uid, name: newName, position: groups.count))
                        newName = ""
                    }
                    .disabled(newName.isEmpty || groups.count >= 12)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Diary groups")
        .onAppear { groups = app.groups }
        .onDisappear {
            // Save in the order shown, with a name every group can display.
            let rows = groups.enumerated().map { index, group in
                var row = group
                row.position = index
                row.name = group.name.isEmpty ? "Group" : String(group.name.prefix(40))
                return row
            }
            Task { try? await DiaryService().upsert(groups: rows); await app.refreshGroups() }
        }
    }
}
