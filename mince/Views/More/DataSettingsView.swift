import SwiftUI

/// Export, bulk delete, delete account.
struct DataSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var from = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var to = Date()
    @State private var confirmRange = false
    @State private var confirmAccount = false
    @State private var exporting = false
    @State private var working = false

    var body: some View {
        Form {
            Section {
                PlusRow(action: { exporting = true }) { Label("Export a report or CSV", systemImage: "square.and.arrow.up") }
            }
            Section {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                Button("Delete diary entries in this range", role: .destructive) { confirmRange = true }
            } header: { Text("Clear diary") } footer: { Text("Foods, recipes and settings are kept.") }
            Section {
                Button("Delete my account", role: .destructive) { confirmAccount = true }
            } footer: { Text("Permanently deletes your account, diary, foods, photos and settings. An active subscription must be cancelled separately in the App Store.") }
            if working { ProgressView() }
        }
        .navigationTitle("Data")
        .confirmationDialog("Delete every entry from \(Day(from).title) to \(Day(to).title)?", isPresented: $confirmRange, titleVisibility: .visible) {
            Button("Delete entries", role: .destructive) {
                Task {
                    working = true
                    defer { working = false }
                    do { try await DiaryService().deleteRange(from: Day(from), to: Day(to)); app.diaryChanged() } catch { app.report(error) }
                }
            }
        }
        .confirmationDialog("Delete your account and all data? This can't be undone.", isPresented: $confirmAccount, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    working = true
                    defer { working = false }
                    do { try await app.deleteAccount() } catch { app.report(error) }
                }
            }
        }
        .sheet(isPresented: $exporting) {
            ExportView(from: Day(from), to: Day(to), daily: [:], targets: app.targets(for: .today))
        }
    }
}
