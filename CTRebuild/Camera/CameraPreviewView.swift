import SwiftUI
import AVFoundation

/// A SwiftUI view that hosts an AVCaptureVideoPreviewLayer.
/// Accepts the full CameraViewModel so it can wire up the previewLayer reference
/// needed for bounding-box coordinate transforms.
struct CameraPreviewView: UIViewRepresentable {
    let viewModel: CameraViewModel

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = viewModel.session
        view.previewLayer.videoGravity = .resizeAspectFill
        viewModel.previewLayer = view.previewLayer
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

