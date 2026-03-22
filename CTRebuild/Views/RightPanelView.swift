import SwiftUI

struct RightPanelView: View {
    let safeArea: EdgeInsets

    @State private var isZoomedOut = false
    @AppStorage("rightPanelSelectedIndex") private var selectedIndex = 0
    @Namespace private var wheelNamespace

    // 7 distinct grey shades from dark → light
    let items: [Color] = [
        Color(white: 0.18),
        Color(white: 0.26),
        Color(white: 0.34),
        Color(white: 0.42),
        Color(white: 0.50),
        Color(white: 0.58),
        Color(white: 0.66),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isZoomedOut {
                VerticalWheelSelector(
                    selectedIndex: $selectedIndex,
                    isZoomedOut: $isZoomedOut,
                    namespace: wheelNamespace,
                    items: items
                )
                .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: 30)
                    .fill(items[selectedIndex])
                    .matchedGeometryEffect(id: "page_\(selectedIndex)", in: wheelNamespace)
                    .overlay(
                        Text("Page \(selectedIndex + 1)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    )
                    .ignoresSafeArea()
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            isZoomedOut = true
                        }
                    }
            }
        }
    }
}

// MARK: - Vertical Wheel Selector

private struct VerticalWheelSelector: View {
    @Binding var selectedIndex: Int
    @Binding var isZoomedOut: Bool
    var namespace: Namespace.ID
    let items: [Color]

    // @GestureState resets to 0 atomically when the gesture ends,
    // eliminating the one-frame jump caused by selectedIndex and dragOffset
    // updating in separate passes.
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<items.count, id: \.self) { index in
                let baseOffset         = CGFloat(index - selectedIndex) * 130
                let totalOffset        = baseOffset + dragOffset
                let distanceFromCenter = totalOffset / 130

                RoundedRectangle(cornerRadius: 20)
                    .fill(items[index])
                    .matchedGeometryEffect(id: "page_\(index)", in: namespace)
                    .frame(width: 280, height: 160)
                    .overlay(
                        Text("Page \(index + 1)")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                    )
                    .offset(y: totalOffset)
                    .rotation3DEffect(
                        .degrees(Double(distanceFromCenter) * -35),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.5
                    )
                    .scaleEffect(1.0 - abs(distanceFromCenter) * 0.15)
                    .opacity(1.0 - abs(distanceFromCenter) * 0.4)
                    .onTapGesture {
                        withAnimation(.spring()) {
                            if selectedIndex == index { isZoomedOut = false }
                            else { selectedIndex = index }
                        }
                    }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    // Base shift: how many 130-pt item slots did the finger cross?
                    let dragMoves = -Int((value.translation.height / 130).rounded())

                    // Flick boost: pure velocity delta (predicted minus actual).
                    // Only adds ±1 — never lets a fast swipe skip multiple pages.
                    let velocityDelta = value.predictedEndTranslation.height - value.translation.height
                    let flickBoost: Int = velocityDelta > 250 ? -1 : velocityDelta < -250 ? 1 : 0

                    let target = max(0, min(items.count - 1, selectedIndex + dragMoves + flickBoost))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        selectedIndex = target
                    }
                }
        )
    }
}
