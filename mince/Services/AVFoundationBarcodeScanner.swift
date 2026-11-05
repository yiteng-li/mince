import AVFoundation

/// Real implementation of `BarcodeScannerService` using AVFoundation's
/// native barcode decoding — no third-party scanning library needed.
final class AVFoundationBarcodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    enum ScannerError: Error {
        case cameraAccessDenied
        case cameraUnavailable
    }

    let captureSession = AVCaptureSession()
    lazy var previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)

    private var continuation: CheckedContinuation<String, Error>?

    /// Suspends until a barcode is decoded. Requires
    /// `NSCameraUsageDescription` in Info.plist — see README/SPECIFICATION.
    func scan() async throws -> String {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            throw ScannerError.cameraAccessDenied
        }
        try configureSessionIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard !captureSession.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
                captureSession.startRunning()
            }
        }
    }

    private func configureSessionIfNeeded() throws {
        guard captureSession.inputs.isEmpty else { return }

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            throw ScannerError.cameraUnavailable
        }
        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else {
            throw ScannerError.cameraUnavailable
        }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = code.stringValue
        else { return }
        captureSession.stopRunning()
        continuation?.resume(returning: value)
        continuation = nil
    }
}
