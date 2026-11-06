import PhotosUI
import SwiftUI
import UIKit

/// S10 (mince+): photograph a meal; AI lists the foods and amounts.
struct PhotoLogView: View {
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var analysing = false
    @State private var items: [AIService.Item] = []
    @State private var suggestions: [AIService.Item] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if !items.isEmpty {
                    AIReviewList(groupId: groupId, items: $items, suggestions: suggestions, source: .photo, allowSaveAsRecipe: true)
                } else {
                    VStack(spacing: Theme.Space.md) {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                                .frame(maxHeight: 320).accessibilityLabel("Your meal photo")
                        } else {
                            EmptyStateView(symbol: "camera.viewfinder", title: "Snap your meal", hint: "Shoot from above with everything on the plate in view.")
                        }
                        if analysing { ProgressView("Identifying foods…") }
                        if let error { Text(error).foregroundStyle(Theme.Colors.danger).multilineTextAlignment(.center) }
                        Spacer()
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take photo") { showCamera = true }.buttonStyle(.minced)
                        }
                        PhotosPicker("Choose from library", selection: $pickerItem, matching: .images).buttonStyle(.minced(.secondary))
                    }
                    .padding(Theme.Space.md)
                }
            }
            .navigationTitle("Photo log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) { await analyse(img) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in showCamera = false; if let img { Task { await analyse(img) } } }.ignoresSafeArea()
            }
        }
    }

    private func analyse(_ img: UIImage) async {
        image = img
        analysing = true
        error = nil
        defer { analysing = false }
        guard let jpeg = img.resizedJPEG(maxSide: 1280) else { error = "Couldn't read that photo."; return }
        do {
            let r = try await AIService().recognise(photo: jpeg)
            if r.items.isEmpty { error = "No food found in that photo. Try another angle." }
            items = r.items
            suggestions = r.suggestions ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}

extension UIImage {
    /// Downscales so the longest side is `maxSide` and encodes as JPEG (keeps uploads well under the 5 MB bucket limit).
    func resizedJPEG(maxSide: CGFloat, quality: CGFloat = 0.8) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }.jpegData(compressionQuality: quality)
    }
}
