import SwiftUI

/// S09: scan (or type) a barcode, find the product, log it. Unknown codes go to the custom food editor.
struct BarcodeLogView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupId: UUID?

    enum Stage: Equatable { case scanning, looking(String), found(Food), notFound(String), failed(String) }
    @State private var stage = Stage.scanning
    @State private var manualCode = ""
    @State private var cameraFailed = false

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .scanning:
                    VStack(spacing: 0) {
                        if cameraFailed {
                            EmptyStateView(symbol: "camera.fill", title: "Camera unavailable",
                                           hint: "Allow camera access in Settings, or type the number under the barcode.")
                        } else {
                            ScannerPreview { code in Task { await lookUp(code) } } onError: { cameraFailed = true }
                        }
                        Form {
                            Section("Type the code") {
                                TextField("e.g. 0123456789012", text: $manualCode).keyboardType(.numberPad)
                                Button("Look up") { Task { await lookUp(manualCode) } }.disabled(manualCode.count < 8)
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                case .looking(let code):
                    ProgressView("Looking up \(code)…")
                case .found(let food):
                    FoodLogDetail(food: food, groupId: groupId) { dismiss() }
                case .notFound(let code):
                    CustomFoodEditor(food: nil, prefillBarcode: code) { saved in
                        if let saved { stage = .found(saved) } else { dismiss() }
                    }
                case .failed(let message):
                    EmptyStateView(symbol: "exclamationmark.triangle", title: "Lookup failed", hint: message, actionTitle: "Scan again") {
                        stage = .scanning
                    }
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func lookUp(_ raw: String) async {
        let code = raw.filter(\.isNumber)
        guard !code.isEmpty, let uid = app.userId else { return }
        stage = .looking(code)
        do {
            if let food = try await FoodService().findByBarcode(code) { stage = .found(food); return }
            if let product = try await OpenFoodFactsService().lookup(barcode: code),
               let (food, servings) = OpenFoodFactsService.food(from: product, userId: uid) {
                stage = .found(try await FoodService().save(food, servings: servings))
            } else {
                stage = .notFound(code)
            }
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}

/// Live camera preview that reports the first barcode it reads.
private struct ScannerPreview: View {
    var onCode: (String) -> Void
    var onError: () -> Void
    @State private var scanner = AVFoundationBarcodeScanner()

    var body: some View {
        BarcodeCameraView(previewLayer: scanner.previewLayer)
            .overlay { RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(.white, lineWidth: 2).frame(width: 260, height: 140) }
            .accessibilityLabel("Camera viewfinder. Point at a barcode.")
            .task {
                do { onCode(try await scanner.scan()) } catch { onError() }
            }
    }
}
