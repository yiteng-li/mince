import SwiftUI

struct PlusMenuEditor: View {
    @Environment(AppModel.self) private var app
    @State private var shown: [PlusAction] = []

    var body: some View {
        List {
            Section("Shown") {
                ForEach(shown) { Label($0.title, systemImage: $0.symbol) }
                    .onMove { shown.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in if shown.count - idx.count >= 1 { shown.remove(atOffsets: idx) } }
            }
            Section("Hidden") {
                ForEach(PlusAction.allCases.filter { !shown.contains($0) }) { a in
                    Button { shown.append(a) } label: { Label(a.title, systemImage: a.symbol) }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("+ menu")
        .onAppear { shown = PlusAction.ordered(app.profile?.plusMenu ?? []) }
        .onDisappear {
            guard var p = app.profile else { return }
            p.plusMenu = shown.map(\.rawValue)
            Task { await app.saveProfile(p) }
        }
    }
}
