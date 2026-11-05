import PhotosUI
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

/// S30: dated progress photos, stored privately.
struct SnapshotsView: View {
    @Environment(AppModel.self) private var app
    @State private var snapshots: [Snapshot] = []
    @State private var urls: [UUID: URL] = [:]
    @State private var pick: PhotosPickerItem?
    @State private var uploading = false

    var body: some View {
        ScrollView {
            if snapshots.isEmpty && !uploading {
                EmptyStateView(symbol: "photo.on.rectangle", title: "No progress photos", hint: "Photos stay private to your account.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.Space.xs)], spacing: Theme.Space.xs) {
                ForEach(snapshots) { s in
                    VStack(spacing: Theme.Space.xxs) {
                        AsyncImage(url: urls[s.id]) { img in img.resizable().scaledToFill() } placeholder: { Theme.Colors.track }
                            .frame(height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                            .accessibilityLabel("Progress photo from \(s.day.title)")
                        Text(s.day.title).font(Theme.Fonts.caption)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { Task { try? await GoldService().deleteSnapshot(s); await load() } }
                    }
                }
            }
            .padding(Theme.Space.md)
        }
        .background(Theme.Colors.bg)
        .navigationTitle("Progress photos")
        .toolbar {
            PhotosPicker(selection: $pick, matching: .images) { Image(systemName: "plus") }.accessibilityLabel("Add photo")
        }
        .overlay { if uploading { ProgressView("Uploading…") } }
        .task { await load() }
        .onChange(of: pick) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let jpeg = UIImage(data: data)?.resizedJPEG(maxSide: 1600) else { return }
                uploading = true
                defer { uploading = false }
                do { try await GoldService().addSnapshot(jpeg: jpeg, day: .today); await load() } catch { app.report(error) }
            }
        }
    }

    private func load() async {
        snapshots = (try? await GoldService().snapshots()) ?? []
        for s in snapshots where urls[s.id] == nil {
            urls[s.id] = try? await GoldService().signedURL(bucket: "snapshots", path: s.storagePath)
        }
    }
}

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
                GoldRow(action: { exporting = true }) { Label("Export a report or CSV", systemImage: "square.and.arrow.up") }
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
