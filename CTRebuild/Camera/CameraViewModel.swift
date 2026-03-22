import AVFoundation

// MARK: - Scan Result

struct ScanResult: Equatable {
    let value: String
    let symbology: AVMetadataObject.ObjectType
}

// MARK: - Camera Permission State

enum CameraPermission {
    case undetermined, authorized, denied
}

// MARK: - CameraViewModel

final class CameraViewModel: NSObject, ObservableObject {

    // Public state observed by the UI
    @Published private(set) var permission: CameraPermission = .undetermined
    @Published private(set) var lastScan: ScanResult? = nil

    // Session exposed to the preview view
    let session = AVCaptureSession()

    // Background queue — session never runs on main thread
    private let sessionQueue = DispatchQueue(label: "com.ctrebuild.camera.session", qos: .userInitiated)
    private var isConfigured = false
    // Stored so we can nil its delegate on stop, breaking the AVFoundation retain cycle
    private var metadataOutput: AVCaptureMetadataOutput?

    // MARK: - Permission

    func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permission = granted ? .authorized : .denied
                    if granted { self?.startSession() }
                }
            }
        default:
            permission = .denied
        }
    }

    // MARK: - Session Control

    func startSession() {
        guard permission == .authorized else { return }
        configureSessionIfNeeded()
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Nil out the delegate first — this breaks the AVFoundation strong-reference
            // cycle so CameraViewModel can be deallocated when the panel closes.
            self.metadataOutput?.setMetadataObjectsDelegate(nil, queue: .main)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: - Session Configuration

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Supported barcode/QR symbologies
        let supported: [AVMetadataObject.ObjectType] = [
            .qr, .ean8, .ean13, .code128, .code39, .code93,
            .pdf417, .aztec, .dataMatrix, .itf14, .upce
        ]
        output.metadataObjectTypes = supported.filter { output.availableMetadataObjectTypes.contains($0) }
        output.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput = output
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension CameraViewModel: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              !value.isEmpty else { return }

        let result = ScanResult(value: value, symbology: object.type)
        guard result != lastScan else { return }   // de-duplicate rapid repeats
        lastScan = result
        print("[Scanner] \(object.type.rawValue): \(value)")
    }
}
