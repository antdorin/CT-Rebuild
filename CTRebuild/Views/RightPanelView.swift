import SwiftUI

// MARK: - Right Panel

struct RightPanelView: View {
    let safeArea: EdgeInsets

    // true = Panel Page Picker is open; false = full-page content shown
    @State private var isPPOpen = false
    @AppStorage("rightPanelSelectedIndex") private var selectedIndex = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if !isPPOpen {
                    Color.black.ignoresSafeArea()
                }

                if isPPOpen {
                    RightWheelSelector(
                        selectedIndex: $selectedIndex,
                        isPPOpen: $isPPOpen,
                        panelSize: geo.size
                    )
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                } else {
                    RightPageContent(index: selectedIndex)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.pageTransition)
                        .onTapGesture(count: 2) {
                            withAnimation(.slideBck) {
                                isPPOpen = true
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

// MARK: - Right Panel Page Picker

private struct RightWheelSelector: View {
    @Binding var selectedIndex: Int
    @Binding var isPPOpen: Bool
    let panelSize: CGSize

    private let itemCount = 7
    private let cardW: CGFloat = 320
    private let cardH: CGFloat = 560
    private let spacing: CGFloat = 580

    @State private var virtualPage: Int = 0
    @State private var dragOffset: CGFloat = 0

    private var previewScale: CGFloat {
        guard panelSize.width > 0 else { return 1 }
        return cardW / panelSize.width
    }

    // Maps any virtual page to a real 0–(itemCount-1) index, wrapping circularly
    private func realIndex(_ page: Int) -> Int {
        let m = page % itemCount
        return m < 0 ? m + itemCount : m
    }

    var body: some View {
        ZStack {
            ForEach(-1...itemCount, id: \.self) { offset in
                let vp             = virtualPage - (virtualPage % itemCount) + offset
                let real           = realIndex(vp)
                let baseOffset     = CGFloat(vp - virtualPage) * spacing
                let totalOffset    = baseOffset + dragOffset
                let distCenter     = totalOffset / spacing

                RightPageContent(index: real)
                    .frame(width: panelSize.width, height: panelSize.height)
                    .scaleEffect(previewScale, anchor: .center)
                    .frame(width: cardW, height: cardH)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5))
                    .offset(y: totalOffset)
                    .rotation3DEffect(
                        .degrees(Double(distCenter) * -35),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.5
                    )
                    .scaleEffect(1.0 - abs(distCenter) * 0.15)
                    .opacity(1.0 - abs(distCenter) * 0.4)
                    .zIndex(1.0 - abs(distCenter) * 0.5)
                    .onTapGesture {
                        withAnimation(realIndex(virtualPage) == real ? .slideFwd : .spring(response: 0.3, dampingFraction: 0.85)) {
                            if realIndex(virtualPage) == real {
                                isPPOpen = false
                            } else {
                                virtualPage = vp
                                selectedIndex = real
                            }
                        }
                    }
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let dragMoves = -Int((value.translation.height / spacing).rounded())
                    let velocityDelta = value.predictedEndTranslation.height - value.translation.height
                    let flickBoost: Int = velocityDelta > 250 ? -1 : velocityDelta < -250 ? 1 : 0
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        virtualPage += dragMoves + flickBoost
                        selectedIndex = realIndex(virtualPage)
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            virtualPage = selectedIndex
        }
    }
}
