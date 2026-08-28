import Foundation

/// Extension point for a future barcode/QR scanner feature (explicitly out
/// of scope for now). Implement with AVFoundation + a barcode-reading
/// library when that feature gets built; nothing calls this protocol yet.
protocol BarcodeScannerService {
    /// Scans a barcode and returns whatever the scanner reads (e.g. a
    /// UPC/EAN string) so a caller can look it up against `foods`.
    func scan() async throws -> String
}
