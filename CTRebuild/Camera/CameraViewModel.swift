import AVFoundation
import Combine

// MARK: - Camera Mode

enum CameraMode: String, CaseIterable, Identifiable {
    case scan   = "Scan"
    case detect = "Detect"
    var id: Self { self }
}

// MARK: - Camera ViewModel

final class CameraViewModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {

    // Published state
    @Published var mode: CameraMode = .scan
    @Published var lastScannedCode: String?     // populated on successful scan

    // The session is passed to CameraPreviewView
    let session = AVCaptureSession()

    private let metadataOutput = AVCaptureMetadataOutput()
    private let sessionQueue   = DispatchQueue(label: "camera.session")

    // MARK: - Lifecycle

    /// Call when the panel becomes visible.
    func start() {
        requestPermissionIfNeeded { [weak self] granted in
            guard granted, let self else { return }
            self.sessionQueue.async { self.configureAndStart() }
        }
    }

    /// Call when the panel is dismissed.
    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Mode Switching

    func switchMode(to newMode: CameraMode) {
        mode = newMode
        switch newMode {
        case .scan:   startScanMode()
        case .detect: startDetectMode()
        }
    }

    // MARK: - Private Setup

    private func configureAndStart() {
        guard !session.isRunning else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Input — back camera
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        // Metadata output for scan mode
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            // Enable all common 1-D and 2-D barcode types
            metadataOutput.metadataObjectTypes = [
                .qr, .ean8, .ean13, .code39, .code93, .code128,
                .upce, .pdf417, .aztec, .dataMatrix, .interleaved2of5,
                .itf14
            ]
        }

        session.startRunning()
    }

    private func startScanMode() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Re-enable metadata delegate if it was cleared for detect mode
            self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        }
    }

    private func startDetectMode() {
        // TODO: add Vision / CoreML request here (VNRecognizeObjectsRequest etc.)
        // For now, suspend scan callbacks to avoid noise while in detect mode.
        metadataOutput.setMetadataObjectsDelegate(nil, queue: .main)
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            mode == .scan,
            let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let value = obj.stringValue
        else { return }

        lastScannedCode = value
        // TODO: forward to WarehouseAPIService and show result UI in BottomPanelView
    }

    // MARK: - Permission

    private func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        default:
            completion(false)
        }
    }
}
