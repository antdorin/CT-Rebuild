import SwiftUI

// MARK: - Right Panel

struct RightPanelView: View {
    let safeArea: EdgeInsets

    @State private var isZoomedOut = false
    @AppStorage("rightPanelSelectedIndex") private var selectedIndex = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if isZoomedOut {
                    RightWheelSelector(
                        selectedIndex: $selectedIndex,
                        isZoomedOut: $isZoomedOut,
                        panelSize: geo.size
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    RightPageContent(index: selectedIndex)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.pageTransition)
                        .onTapGesture(count: 2) {
                            withAnimation(.slideBck) {
                                isZoomedOut = true
                            }
                        }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Right Page Content

/// Full-page content for each right-panel slot.
/// Replace the body per index as real content is added.
struct RightPageContent: View {
    let index: Int

    private let shades: [Color] = [
        Color(white: 0.18), Color(white: 0.26), Color(white: 0.34),
        Color(white: 0.42), Color(white: 0.50), Color(white: 0.58), Color(white: 0.66),
    ]

    var body: some View {
        ZStack {
            shades[index % shades.count].ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Page \(index + 1)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Right Wheel Selector

private struct RightWheelSelector: View {
    @Binding var selectedIndex: Int
    @Binding var isZoomedOut: Bool
    let panelSize: CGSize

    private let itemCount = 7
    private let cardW: CGFloat = 320
    private let cardH: CGFloat = 560
    private let spacing: CGFloat = 580

    @GestureState private var dragOffset: CGFloat = 0

    private var previewScale: CGFloat {
        guard panelSize.width > 0 else { return 1 }
        return cardW / panelSize.width
    }

    var body: some View {
        ZStack {
            ForEach(0..<itemCount, id: \.self) { index in
                let baseOffset         = CGFloat(index - selectedIndex) * spacing
                let totalOffset        = baseOffset + dragOffset
                let distanceFromCenter = totalOffset / spacing

                RightPageContent(index: index)
                    .frame(width: panelSize.width, height: panelSize.height)
                    .scaleEffect(previewScale, anchor: .center)
                    .frame(width: cardW, height: cardH)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    .offset(y: totalOffset)
                    .rotation3DEffect(
                        .degrees(Double(distanceFromCenter) * -35),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.5
                    )
                    .scaleEffect(1.0 - abs(distanceFromCenter) * 0.15)
                    .opacity(1.0 - abs(distanceFromCenter) * 0.4)
                    .onTapGesture {
                        withAnimation(selectedIndex == index ? .slideFwd : .spring(response: 0.3, dampingFraction: 0.85)) {
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
                    let dragMoves = -Int((value.translation.height / spacing).rounded())
                    let velocityDelta = value.predictedEndTranslation.height - value.translation.height
                    let flickBoost: Int = velocityDelta > 250 ? -1 : velocityDelta < -250 ? 1 : 0
                    let target = max(0, min(itemCount - 1, selectedIndex + dragMoves + flickBoost))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        selectedIndex = target
                    }
                }
        )
    }
}
