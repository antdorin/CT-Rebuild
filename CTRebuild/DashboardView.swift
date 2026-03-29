import SwiftUI

// MARK: - Panel State

enum Panel: Equatable {
    case none, left, right, top, bottom
}

// MARK: - Dashboard View

struct DashboardView: View {
    @State private var activePanel: Panel = .none
    @State private var longPressActive: Bool = false
    @ObservedObject private var gestureSettings = GestureSettings.shared
    @AppStorage("panel_hapticOnChange") private var panelHapticOnChange = false
    @AppStorage("panel_dimOnOpen")       private var panelDimOnOpen = true
    @AppStorage("panel_leftSizePercent")    private var leftSizePercent: Int = 97
    @AppStorage("panel_rightSizePercent")   private var rightSizePercent: Int = 97
    @AppStorage("panel_topSizePercent")     private var topSizePercent: Int = 97
    @AppStorage("panel_bottomSizePercent")  private var bottomSizePercent: Int = 97
    @AppStorage("panel_leftHeightPercent")  private var leftHeightPercent: Int = 97
    @AppStorage("panel_rightHeightPercent") private var rightHeightPercent: Int = 97
    @AppStorage("panel_topWidthPercent")    private var topWidthPercent: Int = 97
    @AppStorage("panel_bottomWidthPercent") private var bottomWidthPercent: Int = 97

    // Dashboard paged content
    @State private var isDashPickerOpen = false
    @AppStorage("dashboardSelectedIndex") private var dashSelectedIndex = 0
    @AppStorage("panel_autoPickerDash")   private var autoPickerDash    = false
    @AppStorage("panel_dashStartPage")    private var dashStartPage: Int = 0

    var body: some View {
        // GeometryReader ignores safe area so panels slide in from the true
        // physical edges (behind notch / home indicator). Safe area insets are
        // read from `geo` and passed explicitly to each content view so that
        // text and interactive elements are never obscured.
        GeometryReader { geo in
            let safe = geo.safeAreaInsets

            ZStack {
                // ── UIKit multi-touch & shake overlay ────────────────────────
                // Attaches window-level recognizers; hitTest passes through.
                GestureRecognizerOverlay(onTrigger: handleTrigger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                // ── Adaptive Background — black in dark mode, white in light ──
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                // ── Dashboard Center Content ──────────────────────────────────
                if isDashPickerOpen {
                    RightWheelSelector(
                        selectedIndex: $dashSelectedIndex,
                        isPPOpen: $isDashPickerOpen,
                        panelSize: geo.size,
                        safeArea: safe
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    RightPageContent(index: dashSelectedIndex, safeArea: safe)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                // ── Dim Backdrop (tap anywhere to dismiss) ────────────────────
                if activePanel != .none && panelDimOnOpen {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { activePanel = .none }
                        .transition(.opacity)
                        .zIndex(10)
                }

                // ── Left Panel (swipe RIGHT to open) ──────────────────────────
                if activePanel == .left {
                    panelContent(for: .left, safeArea: safe)
                        .frame(
                            width: geo.size.width * panelFraction(leftSizePercent),
                            height: geo.size.height * panelFraction(leftHeightPercent)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .zIndex(11)
                        .transition(.move(edge: .leading))
                }

                // ── Right Panel (swipe LEFT to open) ──────────────────────────
                if activePanel == .right {
                    panelContent(for: .right, safeArea: safe)
                        .frame(
                            width: geo.size.width * panelFraction(rightSizePercent),
                            height: geo.size.height * panelFraction(rightHeightPercent)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .zIndex(11)
                        .transition(.move(edge: .trailing))
                }

                // ── Top Panel (swipe DOWN to open) ────────────────────────────
                if activePanel == .top {
                    panelContent(for: .top, safeArea: safe)
                        .frame(
                            width: geo.size.width * panelFraction(topWidthPercent),
                            height: geo.size.height * panelFraction(topSizePercent)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(11)
                        .transition(.move(edge: .top))
                }

                // ── Bottom Panel (swipe UP to open) ───────────────────────────
                if activePanel == .bottom {
                    panelContent(for: .bottom, safeArea: safe)
                        .frame(
                            width: geo.size.width * panelFraction(bottomWidthPercent),
                            height: geo.size.height * panelFraction(bottomSizePercent)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .zIndex(11)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.07), value: activePanel)
            // LongPress fires haptic immediately at 0.07 s (no sequencing delay).
            // Drag reads longPressActive to decide threshold + switch behaviour.
            // simultaneousGesture ensures close swipe fires even when child views
            // (e.g. left-panel grid) have their own DragGestures active.
            .simultaneousGesture(dragGesture(surfaceSize: geo.size))
            .simultaneousGesture(longPressHapticGesture)
            // ── Double / triple tap ───────────────────────────────────────
            .simultaneousGesture(TapGesture(count: 3).onEnded { handleTrigger(.tripleTap) })
            .simultaneousGesture(TapGesture(count: 2).onEnded { handleTrigger(.doubleTap) })
            // ── Pinch ─────────────────────────────────────────────────────
            .simultaneousGesture(
                MagnificationGesture()
                    .onEnded { val in handleTrigger(val < 1.0 ? .pinchIn : .pinchOut) }
            )
            // ── Rotation ──────────────────────────────────────────────────
            .simultaneousGesture(
                RotationGesture()
                    .onEnded { angle in handleTrigger(angle.degrees >= 0 ? .rotationCW : .rotationCCW) }
            )
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear {
            if autoPickerDash { isDashPickerOpen = true }
            else { dashSelectedIndex = dashStartPage }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gestureActionFired)) { note in
            guard let raw = note.userInfo?["action"] as? String,
                  activePanel == .none else { return }
            let total = 7
            switch raw {
            case GestureAction.openPagePicker.rawValue:
                withAnimation(.slideBck) { isDashPickerOpen.toggle() }
            case GestureAction.nextRightPage.rawValue:
                withAnimation(.slideFwd) {
                    dashSelectedIndex = (dashSelectedIndex + 1) % total
                    isDashPickerOpen = false
                }
            case GestureAction.prevRightPage.rawValue:
                withAnimation(.slideBck) {
                    dashSelectedIndex = (dashSelectedIndex - 1 + total) % total
                    isDashPickerOpen = false
                }
            default: break
            }
        }
    }

    // MARK: - Panel Content (placeholder removed — dashboard now uses RightPageContent)

    private func panelFraction(_ percent: Int) -> CGFloat {
        let clamped = min(max(percent, 60), 100)
        return CGFloat(clamped) / 100
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(for panel: Panel, safeArea: EdgeInsets) -> some View {
        switch panel {
        case .left:
            LeftPanelView(safeArea: safeArea)
        case .top:
            TopPanelView(safeArea: safeArea)
        case .bottom:
            BottomPanelView(safeArea: safeArea)
        case .right:
            RightPanelView(safeArea: safeArea)
        default:
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    // MARK: - Drag Gesture
    // minimumDistance: 10 — the 40 pt threshold for plain swipes is enforced
    // inside resolveSwipe so long-press+drag stays responsive at low distances.

    private func dragGesture(surfaceSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let wasLongPress = longPressActive
                longPressActive = false
                resolveSwipe(value: value, allowSwitch: wasLongPress, surfaceSize: surfaceSize)
            }
    }

    // MARK: - Long Press Haptic Gesture
    // Duration is read from GestureSettings so the user can calibrate it.

    private var longPressHapticGesture: some Gesture {
        LongPressGesture(minimumDuration: gestureSettings.longPressDuration)
            .onEnded { _ in
                longPressActive = true
                let lpAction = gestureSettings.action(for: .longPress)
                executeAction(lpAction)
                // Always fire haptic to confirm long-press registered
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
    }

    // MARK: - Shared Resolution

    private func resolveSwipe(value: DragGesture.Value, allowSwitch: Bool, surfaceSize: CGSize) {
        let dx = value.translation.width
        let dy = value.translation.height
        let adx = abs(dx)
        let ady = abs(dy)

        // Use calibrated thresholds from GestureSettings
        let threshold: CGFloat = allowSwitch
            ? CGFloat(gestureSettings.lpSwipeThreshold)
            : CGFloat(gestureSettings.swipeThreshold)
        guard max(adx, ady) > threshold else { return }

        // Determine which direction was swiped (+ edge-zone detection)
        let isHorizontal = adx >= ady
        let trigger: GestureTrigger
        if allowSwitch {
            // Long-press swipes aren't classified as edge swipes
            trigger = isHorizontal
                ? (dx > 0 ? .longPressSwipeRight : .longPressSwipeLeft)
                : (dy > 0 ? .longPressSwipeDown  : .longPressSwipeUp)
        } else {
            let startX = value.startLocation.x
            let startY = value.startLocation.y
            let edge   = CGFloat(gestureSettings.edgeZoneWidth)
                if      isHorizontal && dx > 0 && startX <= edge                         { trigger = .edgeSwipeRight  }
                else if isHorizontal && dx < 0 && startX >= surfaceSize.width - edge     { trigger = .edgeSwipeLeft   }
                else if !isHorizontal && dy > 0 && startY <= edge                        { trigger = .edgeSwipeDown   }
                else if !isHorizontal && dy < 0 && startY >= surfaceSize.height - edge   { trigger = .edgeSwipeUp     }
            else { trigger = isHorizontal
                    ? (dx > 0 ? .swipeRight : .swipeLeft)
                    : (dy > 0 ? .swipeDown  : .swipeUp) }
        }

        let action = gestureSettings.action(for: trigger)

        // Keep legacy one-finger swipe-to-close when a panel is open and the
        // trigger is still mapped to its default open action. If the user
        // customized the trigger (e.g., Switch Panel), honor that mapping.
        if !allowSwitch, activePanel != .none, action == trigger.defaultAction {
            if closeActivePanelIfNeeded(dx: dx, dy: dy, adx: adx, ady: ady, predictedEndDy: value.predictedEndTranslation.height) {
                return
            }
        }

        executeAction(action)
    }

    private func closeActivePanelIfNeeded(
        dx: CGFloat,
        dy: CGFloat,
        adx: CGFloat,
        ady: CGFloat,
        predictedEndDy: CGFloat
    ) -> Bool {
        let t: CGFloat = 50
        switch activePanel {
        case .left where dx < -t && adx > ady:
            activePanel = .none
            return true
        case .right where dx > t && adx > ady:
            activePanel = .none
            return true
        case .top where dy < -t && ady > adx:
            activePanel = .none
            return true
        case .bottom where dy > t && ady > adx && predictedEndDy > 200:
            activePanel = .none
            return true
        default:
            return false
        }
    }

    // MARK: - Execute Action

    private func executeAction(_ action: GestureAction) {
        switch action {
        case .none: break
        case .openLeft:       if activePanel == .none { activePanel = .left;   if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
        case .openRight:      if activePanel == .none { activePanel = .right;  if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
        case .openTop:        if activePanel == .none { activePanel = .top;    if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
        case .openBottom:     if activePanel == .none { activePanel = .bottom; if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
        case .closePanel:     activePanel = .none;     if panelHapticOnChange { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        case .toggleLeft:     activePanel = activePanel == .left  ? .none : .left;   if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .toggleRight:    activePanel = activePanel == .right ? .none : .right;  if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .toggleTop:      activePanel = activePanel == .top   ? .none : .top;    if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .toggleBottom:   activePanel = activePanel == .bottom ? .none : .bottom; if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .switchLeft:     activePanel = .left;   if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .switchRight:    activePanel = .right;  if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .switchTop:      activePanel = .top;    if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .switchBottom:   activePanel = .bottom; if panelHapticOnChange { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .haptic:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .dismissKeyboard:
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        case .nextRightPage, .prevRightPage, .openPagePicker, .scrollToTop:
            // Right-panel page actions are handled inside RightPanelView via AppStorage.
            // Post a notification so the panel can observe it.
            NotificationCenter.default.post(
                name: .gestureActionFired,
                object: nil,
                userInfo: ["action": action.rawValue]
            )
        }
    }

    // MARK: - Trigger Bridge
    // Called by GestureRecognizerOverlay and SwiftUI gesture closures.

    private func handleTrigger(_ trigger: GestureTrigger) {
        executeAction(gestureSettings.action(for: trigger))
    }
}

extension Notification.Name {
    static let gestureActionFired = Notification.Name("CTGestureActionFired")
}

// MARK: - Preview

#Preview {
    DashboardView()
}
