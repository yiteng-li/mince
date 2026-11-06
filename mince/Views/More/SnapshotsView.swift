import PhotosUI
import SwiftUI

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
                        Button("Delete", role: .destructive) { Task { try? await DiaryService().deleteSnapshot(s); await load() } }
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
                do { try await DiaryService().addSnapshot(jpeg: jpeg, day: .today); await load() } catch { app.report(error) }
            }
        }
    }

    private func load() async {
        snapshots = (try? await DiaryService().snapshots()) ?? []
        for s in snapshots where urls[s.id] == nil {
            urls[s.id] = try? await DiaryService().signedURL(bucket: "snapshots", path: s.storagePath)
        }
    }
}
