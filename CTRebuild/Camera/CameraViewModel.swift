import AVFoundation
import Vision

// MARK: - OCR Result

struct OCRResult: Identifiable {
    let id = UUID()
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}

// MARK: - Scan Result

struct ScanResult: Equatable, Identifiable {
    var id: String { value }
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
    // Set by CameraPreviewView — used to transform bounding boxes to screen coords
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    @Published private(set) var scanTrackingRect: CGRect? = nil
    private var trackingClearWork: DispatchWorkItem?
    // Zoom
    private weak var captureDevice: AVCaptureDevice?
    @Published private(set) var zoomFactor: CGFloat = 1.0

    // Vision pipeline
    private var videoOutput: AVCaptureVideoDataOutput?
    private let visionQueue = DispatchQueue(label: "com.ctrebuild.camera.vision", qos: .userInitiated)
    @Published private(set) var ocrResults: [OCRResult] = []
    @Published private(set) var visionBarcodes: [ScanResult] = []

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
        trackingClearWork?.cancel()
        trackingClearWork = nil
        scanTrackingRect = nil
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
        captureDevice = device   // store for zoom control

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

        // Request 60 fps if the device supports it
        if let format = device.formats.last(where: {
            $0.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 60 })
        }) {
            try? device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            device.unlockForConfiguration()
        }

        // Vision video output — runs OCR + barcode detection per frame
        let vidOutput = AVCaptureVideoDataOutput()
        vidOutput.alwaysDiscardsLateVideoFrames = true
        vidOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if session.canAddOutput(vidOutput) {
            session.addOutput(vidOutput)
            vidOutput.setSampleBufferDelegate(self, queue: visionQueue)
            videoOutput = vidOutput
        }
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        guard let device = captureDevice else { return }
        let maxSetting = UserDefaults.standard.double(forKey: "cam_maxZoomLevel")
        let maxCap = maxSetting > 0 ? maxSetting : 10.0
        let minZ = device.minAvailableVideoZoomFactor
        let maxZ = min(device.maxAvailableVideoZoomFactor, maxCap)
        let clamped = max(minZ, min(maxZ, factor))
        sessionQueue.async {
            try? device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.zoomFactor = clamped
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Vision)

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ocrRequest = VNRecognizeTextRequest { [weak self] request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let results = observations.compactMap { obs -> OCRResult? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                return OCRResult(text: candidate.string,
                                 confidence: candidate.confidence,
                                 boundingBox: obs.boundingBox)
            }
            DispatchQueue.main.async { self?.ocrResults = results }
        }
        ocrRequest.recognitionLevel = .fast
        ocrRequest.usesLanguageCorrection = false

        let barcodeRequest = VNDetectBarcodesRequest { [weak self] request, _ in
            guard let observations = request.results as? [VNBarcodeObservation] else { return }
            let scans = observations.compactMap { obs -> ScanResult? in
                guard let payload = obs.payloadStringValue, !payload.isEmpty else { return nil }
                let symbology: AVMetadataObject.ObjectType
                switch obs.symbology {
                case .qr:        symbology = .qr
                case .ean8:      symbology = .ean8
                case .ean13:     symbology = .ean13
                case .code128:   symbology = .code128
                case .code39:    symbology = .code39
                case .code93:    symbology = .code93
                case .pdf417:    symbology = .pdf417
                case .aztec:     symbology = .aztec
                case .dataMatrix: symbology = .dataMatrix
                case .itf14:     symbology = .itf14
                case .upce:      symbology = .upce
                default:         symbology = .qr
                }
                return ScanResult(value: payload, symbology: symbology)
            }
            DispatchQueue.main.async { self?.visionBarcodes = scans }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([ocrRequest, barcodeRequest])
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

        // Transform barcode bounds from camera coords → preview-layer screen coords
        if let layer = previewLayer,
           let transformed = layer.transformedMetadataObject(for: object) {
            scanTrackingRect = transformed.bounds
            trackingClearWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.scanTrackingRect = nil }
            trackingClearWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
        }

        let result = ScanResult(value: value, symbology: object.type)
        guard result != lastScan else { return }   // de-duplicate rapid repeats
        lastScan = result
        print("[Scanner] \(object.type.rawValue): \(value)")
    }
}
