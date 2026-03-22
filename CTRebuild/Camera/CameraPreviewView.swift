import SwiftUI
import VisionKit

/// UIViewControllerRepresentable wrapping DataScannerViewController.
/// - `isScanning` controls whether the camera feed is active.
/// - `onScan` fires with the decoded string value whenever a barcode/QR is recognized.
struct DataScannerView: UIViewControllerRepresentable {
    var isScanning: Bool
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],   // covers QR + all 1-D/2-D formats
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if isScanning {
            try? vc.startScanning()
        } else {
            vc.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let item = addedItems.first else { return }
            switch item {
            case .barcode(let b): onScan(b.payloadStringValue ?? "")
            default: break
            }
        }
    }
}
