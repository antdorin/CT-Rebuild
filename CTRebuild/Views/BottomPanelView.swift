import SwiftUI
import AVFoundation

struct BottomPanelView: View {
    let safeArea: EdgeInsets

    @StateObject private var viewModel = CameraViewModel()
    @State private var zoomAtDragStart: CGFloat? = nil   // nil = not dragging
    @State private var showZoomBadge: Bool = false
    @State private var zoomBadgeTask: DispatchWorkItem? = nil
    @State private var isCamOverlayOpen = false
    // Drag zoom settings
    @AppStorage("cam_dragZoomSensitivity") private var dragZoomSensitivity: Double = 80
    @AppStorage("cam_maxZoomLevel") private var maxZoomLevel: Double = 10
    @AppStorage("panel_showMaterial")   private var showMaterial    = true
    @AppStorage("panel_materialStyle")  private var materialStyleRaw = "ultraThin"
    @AppStorage("panel_tintBottomR")    private var panelTintR: Double = 0
    @AppStorage("panel_tintBottomG")    private var panelTintG: Double = 0
    @AppStorage("panel_tintBottomB")    private var panelTintB: Double = 0
    @AppStorage("panel_tintBottomA")    private var panelTintA: Double = 0
    // Modal routing
    @State private var pendingScan: ScanResult? = nil
    @State private var recentScans: [ScanResult] = []
    private let maxRecent = 20
    // Active PDF sheet
    @ObservedObject private var binStore = BinDataStore.shared
    @ObservedObject private var scanStore = ScanStore.shared
    @State private var activePdfSheetOpen: Bool = false
    @State private var activePdfSheetTitle: String = ""
    @State private var activePdfSheetFilenames: [String] = []
    @State private var activePdfSheetPageCounts: [Int] = []
    @State private var activePdfSheetCurrentPage: Int = 0

    var body: some View {
        ZStack {
            // ── Translucent background ────────────────────────────────────────
            if showMaterial {
                (PanelMaterialStyle(rawValue: materialStyleRaw) ?? .ultraThin).background()
            }
            if panelTintA > 0.001 {
                Rectangle()
                    .fill(Color(red: panelTintR, green: panelTintG, blue: panelTintB, opacity: panelTintA))
                    .ignoresSafeArea()
            }

            GeometryReader { geo in
                VStack(spacing: 0) {

                    // ── Camera feed — top 70% ─────────────────────────────────
                    ZStack {
                        Color.black   // letterbox fill behind camera feed

                        switch viewModel.permission {
                        case .authorized:
                            CameraPreviewView(viewModel: viewModel)
                        case .denied:
                            deniedView
                        case .undetermined:
                            // Spinner while waiting for the dialog
                            ProgressView()
                                .tint(.white)
                        }

                        // ── Target lock-on reticle ────────────────────────
                        if let rect = viewModel.scanTrackingRect {
                            scanReticle(rect: rect)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }

                        // ── Zoom level badge ──────────────────────────────
                        if showZoomBadge {
                            Text(String(format: "%.1f×", viewModel.zoomFactor))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule())
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }

                        // ── Camera side overlay (30% wide, full camera height) ────
                        if isCamOverlayOpen {
                            HStack(spacing: 0) {
                                Spacer()
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.10))
                                                .frame(width: 0.5)
                                        }

                                    // ── Active PDF list ───────────────────
                                    VStack(spacing: 0) {
                                        Text("ACTIVE")
                                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                            .tracking(3)
                                            .padding(.top, 10)
                                            .padding(.bottom, 6)

                                        if binStore.activeEntries.isEmpty {
                                            Spacer()
                                            Text("None")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.25))
                                            Spacer()
                                        } else {
                                            ScrollView(showsIndicators: false) {
                                                VStack(spacing: 6) {
                                                    ForEach(binStore.activeEntries, id: \.id) { entry in
                                                        Button {
                                                            guard !entry.filenames.isEmpty,
                                                                  !entry.pageCounts.isEmpty else { return }
                                                            activePdfSheetTitle = entry.label
                                                            activePdfSheetFilenames = entry.filenames
                                                            activePdfSheetPageCounts = entry.pageCounts
                                                            activePdfSheetCurrentPage = 0
                                                            activePdfSheetOpen = true
                                                        } label: {
                                                            VStack(spacing: 2) {
                                                                Text(entry.label)
                                                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                                    .foregroundColor(.white.opacity(0.85))
                                                                    .lineLimit(2)
                                                                    .multilineTextAlignment(.center)
                                                                Text("\(entry.filenames.count) file\(entry.filenames.count == 1 ? "" : "s")")
                                                                    .font(.system(size: 8, design: .monospaced))
                                                                    .foregroundColor(.white.opacity(0.35))
                                                            }
                                                            .padding(.vertical, 8)
                                                            .padding(.horizontal, 6)
                                                            .frame(maxWidth: .infinity)
                                                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                                .padding(.horizontal, 6)
                                            }
                                        }
                                    }
                                }
                                .frame(width: geo.size.width * 0.30)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 10)
                                        .onEnded { value in
                                            let adx = abs(value.translation.width)
                                            let ady = abs(value.translation.height)
                                            guard adx > ady, value.translation.width > 50 else { return }
                                            withAnimation(.easeInOut(duration: 0.07)) {
                                                isCamOverlayOpen = false
                                            }
                                        }
                                )
                            }
                            .transition(.move(edge: .trailing))
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: viewModel.scanTrackingRect != nil)
                    .animation(.easeOut(duration: 0.2), value: showZoomBadge)
                    .animation(.easeInOut(duration: 0.07), value: isCamOverlayOpen)
                    .frame(height: geo.size.height * 0.70)
                    .clipped()
                    // Vertical drag to zoom (simultaneous so horizontal close still works)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                let adx = abs(value.translation.width)
                                let ady = abs(value.translation.height)
                                guard ady > adx else { return }
                                // Capture baseline on first vertical movement
                                if zoomAtDragStart == nil {
                                    zoomAtDragStart = viewModel.zoomFactor
                                }
                                if let base = zoomAtDragStart {
                                    let newZoom = base * pow(2.0, -value.translation.height / dragZoomSensitivity)
                                    viewModel.setZoom(newZoom)
                                }
                                showZoomBadge = true
                                zoomBadgeTask?.cancel()
                            }
                            .onEnded { _ in
                                zoomAtDragStart = nil
                                viewModel.setZoom(1.0)
                                // Auto-hide badge after 0.8 s
                                let task = DispatchWorkItem { showZoomBadge = false }
                                zoomBadgeTask = task
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
                            }
                    )
                    // Swipe left to open the camera side overlay
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                let adx = abs(value.translation.width)
                                let ady = abs(value.translation.height)
                                guard adx > ady, !isCamOverlayOpen,
                                      value.translation.width < -50 else { return }
                                withAnimation(.easeInOut(duration: 0.07)) {
                                    isCamOverlayOpen = true
                                }
                            }
                    )

                    // ── Results area — bottom 30% ─────────────────────────────
                    Group {
                        if recentScans.isEmpty {
                            VStack {
                                Spacer()
                                Text("AWAITING SCAN")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.4))
                                    .tracking(4)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, safeArea.bottom)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 0) {
                                    ForEach(recentScans.reversed()) { scan in
                                        recentScanRow(scan: scan)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.bottom, safeArea.bottom)
                            }
                        }
                    }
                    .frame(height: geo.size.height * 0.30)
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 8) {
                        Text("CONTEXT")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .tracking(2)
                        Text(scanStore.activeTicketCatalog.displayName)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, max(safeArea.bottom, 8))
                }
            }
        }
        .onAppear {
            viewModel.requestPermission()
            viewModel.startSession()
            Task { await scanStore.bootstrapLinkSync() }
        }
        .onDisappear {
            viewModel.stopSession()
        }
        // When a new scan arrives, pause duplicate firing and route to the correct modal
        .onChange(of: viewModel.lastScan) { scan in
            guard let scan else { return }
            // Append to recent list (dedupe consecutive identical scans, cap at max)
            if recentScans.last?.value != scan.value {
                recentScans.append(scan)
                if recentScans.count > maxRecent {
                    recentScans.removeFirst(recentScans.count - maxRecent)
                }
            }
            // Modal only opens when the user taps a row — not automatically on scan
        }
        .sheet(item: $pendingScan) { scan in
            if let record = scanStore.record(for: scan.value) {
                AssignedItemModal(record: record, catalogLink: nil) { pendingScan = nil }
            } else if let link = scanStore.catalogLink(for: scan.value) {
                AssignedItemModal(record: nil, catalogLink: link) { pendingScan = nil }
            } else {
                UnassignedItemModal(rawBarcode: scan.value) { pendingScan = nil }
            }
        }
        .sheet(isPresented: $activePdfSheetOpen) {
            ZStack {
                Color.black.ignoresSafeArea()
                PdfDetailView(
                    title: activePdfSheetTitle,
                    safeArea: .init(),
                    filenames: activePdfSheetFilenames,
                    pageCounts: activePdfSheetPageCounts,
                    currentPage: $activePdfSheetCurrentPage,
                    onBack: { activePdfSheetOpen = false }
                )
            }
        }
    }

    // MARK: - Scan Reticle

    private func scanReticle(rect: CGRect) -> some View {
        Canvas { ctx, _ in
            let arm: CGFloat = min(rect.width, rect.height) * 0.30
            let lw: CGFloat = 2.5
            let bright = GraphicsContext.Shading.color(.green.opacity(0.9))

            // Subtle full-box outline
            ctx.stroke(Path(rect), with: .color(.green.opacity(0.18)), lineWidth: 0.6)

            // Top-left corner
            var p = Path()
            p.move(to:    CGPoint(x: rect.minX,       y: rect.minY + arm))
            p.addLine(to: CGPoint(x: rect.minX,       y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
            ctx.stroke(p, with: bright, lineWidth: lw)

            // Top-right corner
            p = Path()
            p.move(to:    CGPoint(x: rect.maxX - arm, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX,       y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX,       y: rect.minY + arm))
            ctx.stroke(p, with: bright, lineWidth: lw)

            // Bottom-left corner
            p = Path()
            p.move(to:    CGPoint(x: rect.minX,       y: rect.maxY - arm))
            p.addLine(to: CGPoint(x: rect.minX,       y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
            ctx.stroke(p, with: bright, lineWidth: lw)

            // Bottom-right corner
            p = Path()
            p.move(to:    CGPoint(x: rect.maxX - arm, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX,       y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX,       y: rect.maxY - arm))
            ctx.stroke(p, with: bright, lineWidth: lw)
        }
    }

    // MARK: - Recent Scan Row

    @ViewBuilder
    private func recentScanRow(scan: ScanResult) -> some View {
        let isAssigned = scanStore.isAssigned(barcode: scan.value)
        Button {
            pendingScan = scan
        } label: {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(isAssigned ? Color.green.opacity(0.75) : Color.orange.opacity(0.75))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.value)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(scan.symbology.rawValue)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                Spacer()

                Text(isAssigned ? "ASSIGNED" : "UNASSIGNED")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(isAssigned ? .green.opacity(0.8) : .orange.opacity(0.8))
                    .tracking(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider().opacity(0.2).padding(.horizontal, 14)
    }

    // MARK: - Denied State

    private var deniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.5))
            Text("Camera access required")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .foregroundColor(.white)
        }
    }
}


