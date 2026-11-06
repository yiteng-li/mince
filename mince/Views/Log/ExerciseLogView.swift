import SwiftUI

/// S13: log a workout from the exercise catalogue (or a custom title).
struct ExerciseLogView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var entry: DiaryEntry?
    @State private var query = ""
    @State private var results: [Exercise] = []
    @State private var picked: Exercise?
    @State private var customTitle = ""
    @State private var minutes: Double? = 30
    @State private var kcalOverride: Double?

    var body: some View {
        NavigationStack {
            Form {
                if picked == nil && entry == nil { pickSection }
                if picked != nil || !customTitle.isEmpty || entry != nil { detailSection }
            }
            .screenBackground()
            .searchable(text: $query, prompt: "Search activities")
            .task(id: query) { results = (try? await ProfileService().exercises(matching: query)) ?? [] }
            .navigationTitle("Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled((kcalOverride ?? estimate ?? 0) <= 0) }
            }
            .onAppear {
                if let entry { minutes = entry.minutes; kcalOverride = entry.energyKcal }
            }
        }
    }

    @ViewBuilder private var pickSection: some View {
        Section("Pick an activity") {
            ForEach(results) { ex in
                Button { picked = ex } label: {
                    HStack {
                        Text(ex.name).foregroundStyle(Theme.Colors.text)
                        Spacer()
                        Text(ex.category.capitalized).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                    }
                }
            }
            if results.isEmpty { Text("No activities match.").foregroundStyle(Theme.Colors.textMuted) }
        }
        Section("Or name your own") { TextField("e.g. Climbing session", text: $customTitle) }
    }

    private var activityName: String { picked?.name ?? entry?.exercise?.name ?? entry?.title ?? customTitle }

    private var detailSection: some View {
        Section {
            NumberField(title: "Duration", value: $minutes, unit: "min")
            NumberField(title: "Energy burned", value: $kcalOverride, unit: "kcal")
        } header: {
            Text(activityName)
        } footer: {
            if let est = estimate, kcalOverride == nil {
                Text("Estimated \(Int(est)) kcal for \(Units.weight(app.weightKg, app.unitSystem)). Enter your own number to override.")
            }
        }
    }

    private var estimate: Double? {
        guard let picked, let m = minutes, m > 0 else { return nil }
        return picked.energy(minutes: m, weightKg: app.weightKg)
    }

    private func save() async {
        guard let uid = app.userId else { return }
        var e = entry ?? DiaryEntry(userId: uid, day: app.selectedDay, kind: .exercise)
        e.exerciseId = picked?.id ?? e.exerciseId
        if let picked { e.exercise = .init(name: picked.name) }   // shown before the next reload
        e.title = picked == nil ? (customTitle.isEmpty ? e.title : customTitle) : nil
        e.minutes = minutes
        e.energyKcal = kcalOverride ?? estimate
        if entry != nil {
            do { _ = try await DiaryService().update(e); app.diaryChanged(); dismiss() } catch { app.report(error) }
        } else if await app.log([e]) { dismiss() }
    }
}
