import AVFoundation
import SwiftUI
import UIKit

final class ScannerPreviewController: UIViewController {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}

struct BarcodeCameraView: UIViewControllerRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIViewController(context: Context) -> ScannerPreviewController {
        ScannerPreviewController(previewLayer: previewLayer)
    }

    func updateUIViewController(_ uiViewController: ScannerPreviewController, context: Context) {}
}
