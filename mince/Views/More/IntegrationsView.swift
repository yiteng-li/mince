import SwiftUI

/// S31: Apple Health import/export.
struct IntegrationsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("healthImport") private var importOn = false
    @AppStorage("healthExport") private var exportOn = false
    @State private var syncing = false
    @State private var status: String?

    var body: some View {
        Form {
            if !HealthService.isAvailable {
                Text("Apple Health isn't available on this device.").foregroundStyle(Theme.Colors.textMuted)
            } else {
                Section {
                    Toggle("Import workouts, weight, sleep and vitals", isOn: $importOn)
                    Toggle("Send nutrition to Apple Health", isOn: $exportOn)
                } footer: {
                    Text("Imported rows are marked with a heart in your diary. Turn on \"Use Apple Health active energy\" in Targets to avoid counting activity twice.")
                }
                Section {
                    Button("Sync the last 7 days") { Task { await sync() } }.disabled(syncing || !(importOn || exportOn))
                    if syncing { ProgressView() }
                    if let status { Text(status).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted) }
                }
            }
        }
        .navigationTitle("Apple Health")
        .onChange(of: importOn) { _, on in if on { Task { try? await HealthService().requestAccess() } } }
        .onChange(of: exportOn) { _, on in if on { Task { try? await HealthService().requestAccess() } } }
    }

    private func sync() async {
        guard let uid = app.userId else { return }
        syncing = true
        defer { syncing = false }
        var imported = 0
        let types = Dictionary(app.biometricTypes.filter { $0.userId == nil }.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        do {
            try await HealthService().requestAccess()
            for offset in 0..<7 {
                let day = Day.today.adding(days: -offset)
                if importOn {
                    let rows = try await HealthService().importRows(day: day, userId: uid, types: types, weightKg: app.weightKg)
                    for row in rows {   // one at a time so an already-imported sample doesn't block the rest
                        if (try? await DiaryService().insert([row])) != nil { imported += 1 }
                    }
                }
                if exportOn, let totals = try? await DiaryService().totals(from: day, to: day)[day] {
                    try await HealthService().export(day: day, totals: totals)
                }
            }
            status = "Done. \(imported) new item\(imported == 1 ? "" : "s") imported."
            await app.refreshWeight()
            app.diaryChanged()
        } catch {
            status = error.localizedDescription
        }
    }
}
