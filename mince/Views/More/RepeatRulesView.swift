import SwiftUI

/// S29 management (mince+): every repeat rule.
struct RepeatRulesView: View {
    @Environment(AppModel.self) private var app
    @State private var rules: [RepeatRule] = []

    var body: some View {
        List {
            if rules.isEmpty {
                EmptyStateView(symbol: "repeat", title: "Nothing repeats yet", hint: "Long-press a food in your diary and choose Repeat.").listRowBackground(Color.clear)
            }
            ForEach(rules) { r in
                VStack(alignment: .leading) {
                    Text(r.title)
                    Text("\(r.cadence) · \(app.group(id: r.groupId)?.name ?? "No group")\(r.endsOn.map { " · until \($0.title)" } ?? "")")
                        .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .onDelete { idx in
                let gone = idx.map { rules[$0] }
                rules.remove(atOffsets: idx)
                Task { for r in gone { try? await PlusService().delete(r) } }
            }
        }
        .navigationTitle("Repeat items")
        .task { rules = (try? await PlusService().repeatRules()) ?? [] }
    }
}
