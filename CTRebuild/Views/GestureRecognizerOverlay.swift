import SwiftUI
import UIKit

// MARK: - Gesture Recognizer Overlay
//
// Attaches UIKit gesture recognizers to the app window so multi-finger
// and shake gestures are detected globally without interfering with
// SwiftUI's own gesture system. The UIView itself is invisible and
// passes all hit-tests through, but stays first responder for shake.

struct GestureRecognizerOverlay: UIViewRepresentable {
    let onTrigger: (GestureTrigger) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTrigger: onTrigger) }

    func makeUIView(context: Context) -> GestureHostView {
        let view = GestureHostView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: GestureHostView, context: Context) {
        context.coordinator.onTrigger = onTrigger
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var onTrigger: (GestureTrigger) -> Void
        private(set) var attachedWindow: UIWindow?
        private var windowRecognizers: [UIGestureRecognizer] = []

        init(onTrigger: @escaping (GestureTrigger) -> Void) {
            self.onTrigger = onTrigger
        }

        func attachRecognizers(to window: UIWindow) {
            guard attachedWindow !== window else { return }
            detachRecognizers()
            attachedWindow = window
            var recs: [UIGestureRecognizer] = []

            // ── Two-finger swipes ──────────────────────────────────────────
            for dir: UISwipeGestureRecognizer.Direction in [.right, .left, .up, .down] {
                let r = makeSwipe(touches: 2, direction: dir)
                window.addGestureRecognizer(r)
                recs.append(r)
            }

            // ── Three-finger swipes ────────────────────────────────────────
            for dir: UISwipeGestureRecognizer.Direction in [.right, .left, .up, .down] {
                let r = makeSwipe(touches: 3, direction: dir)
                window.addGestureRecognizer(r)
                recs.append(r)
            }

            // ── Two-finger tap ─────────────────────────────────────────────
            let twoTap = makeTap(touches: 2, taps: 1)
            let twoDoubleTap = makeTap(touches: 2, taps: 2)
            twoTap.require(toFail: twoDoubleTap)   // wait to disambiguate
            window.addGestureRecognizer(twoDoubleTap)
            window.addGestureRecognizer(twoTap)
            recs.append(contentsOf: [twoTap, twoDoubleTap])

            // ── Three-finger tap ───────────────────────────────────────────
            let threeTap = makeTap(touches: 3, taps: 1)
            window.addGestureRecognizer(threeTap)
            recs.append(threeTap)

            // ── Two-finger long press ──────────────────────────────────────
            let twoLP = UILongPressGestureRecognizer(target: self,
                                                     action: #selector(handleLongPress(_:)))
            twoLP.numberOfTouchesRequired = 2
            twoLP.cancelsTouchesInView = false
            twoLP.delaysTouchesBegan = false
            window.addGestureRecognizer(twoLP)
            recs.append(twoLP)

            windowRecognizers = recs
        }

        func detachRecognizers() {
            windowRecognizers.forEach { attachedWindow?.removeGestureRecognizer($0) }
            windowRecognizers = []
            attachedWindow = nil
        }

        // MARK: Handlers

        @objc func handleSwipe(_ r: UISwipeGestureRecognizer) {
            let trigger: GestureTrigger?
            switch (r.numberOfTouchesRequired, r.direction) {
            case (2, .right): trigger = .twoFingerSwipeRight
            case (2, .left):  trigger = .twoFingerSwipeLeft
            case (2, .up):    trigger = .twoFingerSwipeUp
            case (2, .down):  trigger = .twoFingerSwipeDown
            case (3, .right): trigger = .threeFingerSwipeRight
            case (3, .left):  trigger = .threeFingerSwipeLeft
            case (3, .up):    trigger = .threeFingerSwipeUp
            case (3, .down):  trigger = .threeFingerSwipeDown
            default:          trigger = nil
            }
            if let t = trigger { fire(t) }
        }

        @objc func handleTap(_ r: UITapGestureRecognizer) {
            let trigger: GestureTrigger?
            switch (r.numberOfTouchesRequired, r.numberOfTapsRequired) {
            case (2, 1): trigger = .twoFingerTap
            case (2, 2): trigger = .twoFingerDoubleTap
            case (3, 1): trigger = .threeFingerTap
            default:     trigger = nil
            }
            if let t = trigger { fire(t) }
        }

        @objc func handleLongPress(_ r: UILongPressGestureRecognizer) {
            guard r.state == .began else { return }
            if r.numberOfTouchesRequired == 2 { fire(.twoFingerLongPress) }
        }

        func fire(_ trigger: GestureTrigger) {
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger(trigger)
            }
        }

        // MARK: Factory helpers

        private func makeSwipe(touches: Int,
                               direction: UISwipeGestureRecognizer.Direction) -> UISwipeGestureRecognizer {
            let r = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            r.numberOfTouchesRequired = touches
            r.direction = direction
            r.cancelsTouchesInView = false
            r.delaysTouchesBegan = false
            return r
        }

        private func makeTap(touches: Int, taps: Int) -> UITapGestureRecognizer {
            let r = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            r.numberOfTouchesRequired = touches
            r.numberOfTapsRequired = taps
            r.cancelsTouchesInView = false
            r.delaysTouchesBegan = false
            return r
        }
    }
}

// MARK: - Gesture Host View

/// Invisible UIView that attaches UIKit recognizers to the window and
/// becomes first responder so it can detect shake events.
final class GestureHostView: UIView {
    weak var coordinator: GestureRecognizerOverlay.Coordinator?

    override var canBecomeFirstResponder: Bool { true }

    /// Pass all hit-tests through so SwiftUI touches aren't blocked.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let w = window {
            coordinator?.attachRecognizers(to: w)
            DispatchQueue.main.async { self.becomeFirstResponder() }
        } else {
            coordinator?.detachRecognizers()
        }
    }

    /// Shake detection via UIResponder event.
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            coordinator?.fire(.shake)
        }
        super.motionEnded(motion, with: event)
    }
}
