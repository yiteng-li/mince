import SwiftUI

/// S16: log water. Stored as a quick add carrying only the water nutrient.
struct WaterLogView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var custom: Double?

    static func add(ml: Double, app: AppModel) async {
        guard let uid = app.userId else { return }
        await app.log([DiaryEntry(userId: uid, day: app.selectedDay, kind: .quickAdd, nutrients: ["water": ml], title: "Water")])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add") {
                    ForEach([250.0, 500, 750, 1000], id: \.self) { ml in
                        Button("\(Int(ml)) mL") { Task { await Self.add(ml: ml, app: app); dismiss() } }
                    }
                }
                Section("Other amount") {
                    NumberField(title: "Amount", value: $custom, unit: "mL")
                    Button("Add") { Task { await Self.add(ml: custom ?? 0, app: app); dismiss() } }.disabled((custom ?? 0) <= 0)
                }
            }
            .screenBackground()
            .navigationTitle("Water")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
