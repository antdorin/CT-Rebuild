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
        // Keep coordinator closure current after re-renders
        context.coordinator.onScan = onScan
        // Defer start/stop — calling startScanning() synchronously during SwiftUI
        // layout (before the VC view is in the window) causes an internal crash.
        let shouldScan = isScanning
        DispatchQueue.main.async {
            if shouldScan {
                try? vc.startScanning()
            } else {
                vc.stopScanning()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
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
