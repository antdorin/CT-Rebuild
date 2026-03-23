import Foundation
import Combine

// MARK: - Gesture Action

enum GestureAction: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case none               = "No Action"
    case openLeft           = "Open Left Panel"
    case openRight          = "Open Right Panel"
    case openTop            = "Open Top Panel"
    case openBottom         = "Open Bottom Panel"
    case closePanel         = "Close Active Panel"
    case toggleLeft         = "Toggle Left Panel"
    case toggleRight        = "Toggle Right Panel"
    case toggleTop          = "Toggle Top Panel"
    case toggleBottom       = "Toggle Bottom Panel"
    case switchLeft         = "Switch to Left Panel"
    case switchRight        = "Switch to Right Panel"
    case switchTop          = "Switch to Top Panel"
    case switchBottom       = "Switch to Bottom Panel"
    case nextRightPage      = "Right Panel: Next Page"
    case prevRightPage      = "Right Panel: Prev Page"
    case openPagePicker     = "Right Panel: Page Picker"
    case haptic             = "Haptic Feedback Only"
    case dismissKeyboard    = "Dismiss Keyboard"
    case scrollToTop        = "Scroll to Top"

    var group: String {
        switch self {
        case .none:                                            return "Disabled"
        case .openLeft, .openRight, .openTop, .openBottom:    return "Open Panel"
        case .closePanel:                                     return "Close"
        case .toggleLeft, .toggleRight, .toggleTop, .toggleBottom: return "Toggle Panel"
        case .switchLeft, .switchRight, .switchTop, .switchBottom: return "Switch Panel"
        case .nextRightPage, .prevRightPage, .openPagePicker: return "Right Panel Pages"
        case .haptic, .dismissKeyboard, .scrollToTop:         return "Utility"
        }
    }
}

// MARK: - Gesture Trigger

enum GestureTrigger: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    // ── Single-finger swipes ───────────────────────────────────────────────
    case swipeRight             = "Swipe Right"
    case swipeLeft              = "Swipe Left"
    case swipeUp                = "Swipe Up"
    case swipeDown              = "Swipe Down"

    // ── Edge swipes ────────────────────────────────────────────────────────
    case edgeSwipeRight         = "Edge Swipe (Left Edge)"
    case edgeSwipeLeft          = "Edge Swipe (Right Edge)"
    case edgeSwipeUp            = "Edge Swipe (Bottom Edge)"
    case edgeSwipeDown          = "Edge Swipe (Top Edge)"

    // ── Long press + swipe ─────────────────────────────────────────────────
    case longPressSwipeRight    = "Long Press + Swipe Right"
    case longPressSwipeLeft     = "Long Press + Swipe Left"
    case longPressSwipeUp       = "Long Press + Swipe Up"
    case longPressSwipeDown     = "Long Press + Swipe Down"

    // ── Tap combos ─────────────────────────────────────────────────────────
    case doubleTap              = "Double Tap"
    case tripleTap              = "Triple Tap"
    case longPress              = "Long Press (No Swipe)"

    // ── Two-finger ─────────────────────────────────────────────────────────
    case twoFingerSwipeRight    = "Two-Finger Swipe Right"
    case twoFingerSwipeLeft     = "Two-Finger Swipe Left"
    case twoFingerSwipeUp       = "Two-Finger Swipe Up"
    case twoFingerSwipeDown     = "Two-Finger Swipe Down"
    case twoFingerTap           = "Two-Finger Tap"
    case twoFingerDoubleTap     = "Two-Finger Double Tap"
    case twoFingerLongPress     = "Two-Finger Long Press"

    // ── Three-finger ───────────────────────────────────────────────────────
    case threeFingerSwipeRight  = "Three-Finger Swipe Right"
    case threeFingerSwipeLeft   = "Three-Finger Swipe Left"
    case threeFingerSwipeUp     = "Three-Finger Swipe Up"
    case threeFingerSwipeDown   = "Three-Finger Swipe Down"
    case threeFingerTap         = "Three-Finger Tap"

    // ── Pinch & rotate ─────────────────────────────────────────────────────
    case pinchIn                = "Pinch In (Shrink)"
    case pinchOut               = "Pinch Out (Expand)"
    case rotationCW             = "Rotation Clockwise"
    case rotationCCW            = "Rotation Counter-Clockwise"

    // ── Device gestures ────────────────────────────────────────────────────
    case shake                  = "Shake Device"
    case forceTap               = "Force Press / Haptic Touch"

    // MARK: Default action

    var defaultAction: GestureAction {
        switch self {
        case .swipeRight, .edgeSwipeRight, .longPressSwipeRight:  return .openLeft
        case .swipeLeft,  .edgeSwipeLeft,  .longPressSwipeLeft:   return .openRight
        case .swipeUp,    .edgeSwipeUp,    .longPressSwipeUp:     return .openBottom
        case .swipeDown,  .edgeSwipeDown,  .longPressSwipeDown:   return .openTop
        case .longPress:                                           return .haptic
        default:                                                   return .none
        }
    }

    // MARK: Metadata

    var group: String {
        switch self {
        case .swipeRight, .swipeLeft, .swipeUp, .swipeDown:
            return "Single-Finger Swipe"
        case .edgeSwipeRight, .edgeSwipeLeft, .edgeSwipeUp, .edgeSwipeDown:
            return "Edge Swipe"
        case .longPressSwipeRight, .longPressSwipeLeft, .longPressSwipeUp, .longPressSwipeDown:
            return "Long Press + Swipe"
        case .doubleTap, .tripleTap, .longPress:
            return "Tap Combos"
        case .twoFingerSwipeRight, .twoFingerSwipeLeft, .twoFingerSwipeUp, .twoFingerSwipeDown,
             .twoFingerTap, .twoFingerDoubleTap, .twoFingerLongPress:
            return "Two-Finger"
        case .threeFingerSwipeRight, .threeFingerSwipeLeft, .threeFingerSwipeUp, .threeFingerSwipeDown,
             .threeFingerTap:
            return "Three-Finger"
        case .pinchIn, .pinchOut, .rotationCW, .rotationCCW:
            return "Pinch & Rotate"
        case .shake, .forceTap:
            return "Device Gestures"
        }
    }

    var systemImage: String {
        switch self {
        case .swipeRight, .edgeSwipeRight, .longPressSwipeRight,
             .twoFingerSwipeRight, .threeFingerSwipeRight:     return "arrow.right"
        case .swipeLeft, .edgeSwipeLeft, .longPressSwipeLeft,
             .twoFingerSwipeLeft, .threeFingerSwipeLeft:       return "arrow.left"
        case .swipeUp, .edgeSwipeUp, .longPressSwipeUp,
             .twoFingerSwipeUp, .threeFingerSwipeUp:           return "arrow.up"
        case .swipeDown, .edgeSwipeDown, .longPressSwipeDown,
             .twoFingerSwipeDown, .threeFingerSwipeDown:       return "arrow.down"
        case .doubleTap, .twoFingerTap, .twoFingerDoubleTap,
             .threeFingerTap:                                   return "hand.tap"
        case .tripleTap:                                        return "hand.tap"
        case .longPress, .twoFingerLongPress:                   return "hand.point.up.left"
        case .pinchIn:                   return "arrow.down.right.and.arrow.up.left"
        case .pinchOut:                  return "arrow.up.left.and.arrow.down.right"
        case .rotationCW:                return "arrow.clockwise"
        case .rotationCCW:               return "arrow.counterclockwise"
        case .shake:                     return "iphone.radiowaves.left.and.right"
        case .forceTap:                  return "hand.point.down"
        }
    }

    /// Whether this gesture is actively wired up in DashboardView.
    /// forceTap (3D Touch) is not available on modern iPhones — kept for future.
    var isImplemented: Bool {
        self != .forceTap
    }
}

// MARK: - Gesture Settings Store

final class GestureSettings: ObservableObject {

    static let shared = GestureSettings()

    // ── Per-trigger action storage ─────────────────────────────────────────
    @Published private var actions: [String: String] = [:]

    // ── Threshold calibration ──────────────────────────────────────────────
    @Published var swipeThreshold: Double {
        didSet { UserDefaults.standard.set(swipeThreshold, forKey: "gs_thresh_swipe") }
    }
    @Published var lpSwipeThreshold: Double {
        didSet { UserDefaults.standard.set(lpSwipeThreshold, forKey: "gs_thresh_lp") }
    }
    @Published var longPressDuration: Double {
        didSet { UserDefaults.standard.set(longPressDuration, forKey: "gs_thresh_lpDuration") }
    }
    @Published var edgeZoneWidth: Double {
        didSet { UserDefaults.standard.set(edgeZoneWidth, forKey: "gs_thresh_edge") }
    }

    private init() {
        let ud = UserDefaults.standard
        swipeThreshold   = ud.object(forKey: "gs_thresh_swipe")      .flatMap { $0 as? Double } ?? 40
        lpSwipeThreshold = ud.object(forKey: "gs_thresh_lp")         .flatMap { $0 as? Double } ?? 10
        longPressDuration = ud.object(forKey: "gs_thresh_lpDuration").flatMap { $0 as? Double } ?? 0.1
        edgeZoneWidth    = ud.object(forKey: "gs_thresh_edge")       .flatMap { $0 as? Double } ?? 44

        if let saved = ud.dictionary(forKey: "gs_actions") as? [String: String] {
            actions = saved
        }
    }

    // MARK: - Public API

    func action(for trigger: GestureTrigger) -> GestureAction {
        guard let raw = actions[trigger.rawValue],
              let action = GestureAction(rawValue: raw) else {
            return trigger.defaultAction
        }
        return action
    }

    func setAction(_ action: GestureAction, for trigger: GestureTrigger) {
        actions[trigger.rawValue] = action.rawValue
        UserDefaults.standard.set(actions, forKey: "gs_actions")
    }

    func resetToDefaults() {
        actions = [:]
        UserDefaults.standard.removeObject(forKey: "gs_actions")
        swipeThreshold    = 40
        lpSwipeThreshold  = 10
        longPressDuration = 0.1
        edgeZoneWidth     = 44
        UserDefaults.standard.removeObject(forKey: "gs_thresh_swipe")
        UserDefaults.standard.removeObject(forKey: "gs_thresh_lp")
        UserDefaults.standard.removeObject(forKey: "gs_thresh_lpDuration")
        UserDefaults.standard.removeObject(forKey: "gs_thresh_edge")
    }
}
