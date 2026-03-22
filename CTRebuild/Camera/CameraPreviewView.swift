import SwiftUI
import VisionKit

/// UIViewControllerRepresentable wrapping DataScannerViewController.
/// - `isScanning` controls whether the camera feed is active.
/// - `onScan` fires with the decoded string value whenever a barcode/QR is recognized.
struct DataScannerView: UIViewControllerRepresentable {
    var isScanning: Bool
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerContainerViewController {
        let vc = ScannerContainerViewController()
        vc.dataScanner.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerContainerViewController, context: Context) {
        context.coordinator.onScan = onScan
        // Safely pass the requested state down; the container handles the timing.
        uiViewController.isScanning = isScanning
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
            if case .barcode(let b) = item {
                onScan(b.payloadStringValue ?? "")
            }
        }
    }
}

// MARK: - Native Container

final class ScannerContainerViewController: UIViewController {
    let dataScanner = DataScannerViewController(
        recognizedDataTypes: [.barcode()],
        qualityLevel: .fast,
        recognizesMultipleItems: false,
        isHighlightingEnabled: true
    )
    
    var isScanning: Bool = false {
        didSet {
            // Only toggle the scanner if we are actually visible on screen
            guard isViewLoaded, view.window != nil else { return }
            
            if isScanning && !dataScanner.isScanning {
                try? dataScanner.startScanning()
            } else if !isScanning && dataScanner.isScanning {
                dataScanner.stopScanning()
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(dataScanner)
        view.addSubview(dataScanner.view)
        
        dataScanner.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dataScanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            dataScanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dataScanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dataScanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        dataScanner.didMove(toParent: self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Now it's 100% physically on screen. Safe to start.
        if isScanning && !dataScanner.isScanning {
            try? dataScanner.startScanning()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if dataScanner.isScanning {
            dataScanner.stopScanning()
        }
    }
}

