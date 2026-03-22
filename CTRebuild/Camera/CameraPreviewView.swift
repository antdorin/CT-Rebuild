import SwiftUI
import AVFoundation

/// A SwiftUI view that hosts an AVCaptureVideoPreviewLayer.
/// Pass in the shared `AVCaptureSession` from `CameraViewModel`.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Session changes are managed by CameraViewModel; nothing to update here.
    }
}

// MARK: - PreviewUIView

/// Plain UIView whose backing layer is AVCaptureVideoPreviewLayer.
final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

