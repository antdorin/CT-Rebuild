import SwiftUI

struct RightPanelView: View {
    let safeArea: EdgeInsets

    @State private var isZoomedOut = false
    @State private var selectedIndex = 0
    @Namespace private var wheelNamespace

    let items: [Color] = [.red, .blue, .green, .purple, .orange, .pink, .yellow]

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
                            .foregroundColor(.white)
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

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<items.count, id: \.self) { index in
                let baseOffset       = CGFloat(index - selectedIndex) * 130
                let totalOffset      = baseOffset + dragOffset
                let distanceFromCenter = totalOffset / 130

                RoundedRectangle(cornerRadius: 20)
                    .fill(items[index])
                    .matchedGeometryEffect(id: "page_\(index)", in: namespace)
                    .frame(width: 280, height: 160)
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
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let velocity  = value.predictedEndTranslation.height
                    let threshold: CGFloat = 65
                    let moveCount = -Int((velocity / threshold).rounded())

                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        let targetIndex = selectedIndex + moveCount
                        selectedIndex   = max(0, min(items.count - 1, targetIndex))
                        dragOffset      = 0
                    }
                }
        )
    }
}
