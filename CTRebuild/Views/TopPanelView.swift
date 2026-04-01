import SwiftUI

// MARK: - Top Panel

struct TopPanelView: View {
    let safeArea: EdgeInsets

    @AppStorage("panel_selectedTab") private var selectedTabRaw: Int = 1
    @State private var selectedTab: Int? = nil
    @AppStorage("panel_showMaterial")  private var showMaterial    = true
    @AppStorage("panel_materialStyle") private var materialStyleRaw = "ultraThin"
    @AppStorage("panel_tintTopR")      private var panelTintR: Double = 0
    @AppStorage("panel_tintTopG")      private var panelTintG: Double = 0
    @AppStorage("panel_tintTopB")      private var panelTintB: Double = 0
    @AppStorage("panel_tintTopA")      private var panelTintA: Double = 0

    // Read directly from UIKit — reliable even when parent ignores safe area
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.top ?? 50
    }

    var body: some View {
        ZStack {
            if selectedTab != nil && showMaterial {
                (PanelMaterialStyle(rawValue: materialStyleRaw) ?? .ultraThin).background()
                    .transition(.opacity)
            }
            if selectedTab != nil && panelTintA > 0.001 {
                Rectangle()
                    .fill(Color(red: panelTintR, green: panelTintG, blue: panelTintB, opacity: panelTintA))
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                Spacer().frame(height: topInset + 16)

                TopTabBar(selected: $selectedTab)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                if let tab = selectedTab {
                    Group {
                        if tab == 0 {
                            CalculatorContentView(safeArea: safeArea)
                        } else if tab == 1 {
                            TasksContentView(safeArea: safeArea)
                        } else if tab == 2 {
                            NotesContentView(safeArea: safeArea)                        } else {
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
        .onAppear {
            if selectedTab == nil {
                selectedTab = selectedTabRaw
            }
        }
        .onChange(of: selectedTab) { newVal in
            if let v = newVal { selectedTabRaw = v }
        }
    }
}

// MARK: - Tab Bar

private struct TopTabBar: View {
    @Binding var selected: Int?

    private let labels = ["CALC", "TASKS", "NOTES"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(labels.indices, id: \.self) { i in
                Button { selected = i } label: {
                    Text(labels[i])
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .foregroundColor(selected == i ? .black : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule().fill(selected == i ? Color.orange : Color.black)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Calculator Content

private struct CalculatorContentView: View {
    let safeArea: EdgeInsets

    @State private var display: String = "0"
    @State private var operand: Double = 0
    @State private var pendingOp: CalcOp? = nil
    @State private var freshEntry: Bool = true

    private let rows: [[CalcKey]] = [
        [.clear, .sign,  .percent, .op(.divide)],
        [.digit(7), .digit(8), .digit(9), .op(.multiply)],
        [.digit(4), .digit(5), .digit(6), .op(.subtract)],
        [.digit(1), .digit(2), .digit(3), .op(.add)],
        [.digit(0), .decimal, .equals]
    ]

    var body: some View {
        GeometryReader { geo in
            let hPad: CGFloat = 16
            let spacing: CGFloat = 10
            let cols: CGFloat = 4
            let btnW = (geo.size.width - hPad * 2 - spacing * (cols - 1)) / cols
            let btnH = btnW * 0.82

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Text(formattedDisplay)
                    .font(.system(size: 48, weight: .thin, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, hPad)
                    .padding(.bottom, 12)

                VStack(spacing: spacing) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: spacing) {
                            ForEach(rows[r].indices, id: \.self) { c in
                                let key = rows[r][c]
                                calcButton(key: key,
                                           width: key == .digit(0) ? btnW * 2 + spacing : btnW,
                                           height: btnH)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, hPad)
                    }
                }
                .padding(.bottom, safeArea.bottom + 16)
            }
        }
    }

    private var formattedDisplay: String {
        guard let d = Double(display) else { return display }
        if display.hasSuffix(".") { return display }
        if d == d.rounded() && !display.contains(".") {
            let formatted = String(format: "%.0f", d)
            return formatted.count > 9 ? String(d) : formatted
        }
        return display.count > 10 ? String(format: "%.6g", d) : display
    }

    @ViewBuilder
    private func calcButton(key: CalcKey, width: CGFloat, height: CGFloat) -> some View {
        let (label, fg, bg) = appearance(for: key)
        Button { handle(key) } label: {
            Text(label)
                .font(.system(size: height * 0.38, weight: .regular, design: .rounded))
                .foregroundColor(fg)
                .frame(width: width, height: height)
                .background(bg, in: RoundedRectangle(cornerRadius: height * 0.28))
        }
        .buttonStyle(.plain)
    }

    private func appearance(for key: CalcKey) -> (String, Color, Color) {
        switch key {
        case .clear:        return (display == "0" && !freshEntry ? "AC" : "C", .black, Color(white: 0.75))
        case .sign:         return ("+/−", .black, Color(white: 0.75))
        case .percent:      return ("%",   .black, Color(white: 0.75))
        case .op(let o):    return (o.symbol, .white, .orange)
        case .digit(let d): return ("\(d)", .white, Color(white: 0.22))
        case .decimal:      return (".", .white, Color(white: 0.22))
        case .equals:       return ("=",  .white, .orange)
        }
    }

    private func handle(_ key: CalcKey) {
        switch key {
        case .digit(let d):
            if freshEntry { display = d == 0 ? "0" : "\(d)"; freshEntry = false }
            else { if display == "0" { display = "\(d)" } else if display.count < 10 { display += "\(d)" } }
        case .decimal:
            if freshEntry { display = "0."; freshEntry = false }
            else if !display.contains(".") { display += "." }
        case .clear:
            display = "0"
            if !freshEntry { freshEntry = true } else { operand = 0; pendingOp = nil }
        case .sign:
            if let v = Double(display) { display = format(-v) }
        case .percent:
            if let v = Double(display) { display = format(v / 100) }
        case .op(let o):
            commit(); operand = Double(display) ?? 0; pendingOp = o; freshEntry = true
        case .equals:
            commit(); pendingOp = nil; freshEntry = true
        }
    }

    private func commit() {
        guard let op = pendingOp, let current = Double(display) else { return }
        let result: Double
        switch op {
        case .add:      result = operand + current
        case .subtract: result = operand - current
        case .multiply: result = operand * current
        case .divide:   result = current == 0 ? 0 : operand / current
        }
        display = format(result); operand = result
    }

    private func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "Error" }
        let r = v == v.rounded() ? String(format: "%.0f", v) : String(v)
        return r.count > 10 ? String(format: "%.6g", v) : r
    }
}

// MARK: - Tasks Content

private struct TasksContentView: View {
    let safeArea: EdgeInsets
    @AppStorage("tasks_selectedSubTab") private var selectedSubTab: Int = 0

    private let subLabels = ["PDF BROWSER", "PDF READER"]

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            Picker("", selection: $selectedSubTab) {
                ForEach(subLabels.indices, id: \.self) { i in
                    Text(subLabels[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Group {
                if selectedSubTab == 0 {
                    PdfBrowserView(safeArea: safeArea)
                } else {
                    WebReaderView(safeArea: safeArea)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Notes Content

private struct NotesContentView: View {
    let safeArea: EdgeInsets
    @AppStorage("topPanelNotes") private var notes: String = ""
    @StateObject private var speech = SpeechManager()
    @FocusState private var notesFocused: Bool

    // Show live transcription while recording, saved text otherwise
    private var liveText: String {
        guard speech.isRecording else { return notes }
        if speech.partial.isEmpty { return speech.baseText }
        let sep = speech.baseText.isEmpty ? "" : "\n"
        return speech.baseText + sep + speech.partial
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { liveText },
            set: { if !speech.isRecording { notes = $0 } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: textBinding)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundColor(speech.isRecording ? .primary.opacity(0.6) : .primary)
                .font(.system(size: 15))
                .disabled(speech.isRecording)
                .focused($notesFocused)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .onTapGesture {
                    guard !speech.isRecording else { return }
                    notesFocused.toggle()
                }

            HStack {
                Spacer()
                Button {
                    if speech.isRecording {
                        // Commit live transcription before stopping
                        if !speech.partial.isEmpty {
                            let sep = speech.baseText.isEmpty ? "" : "\n"
                            notes = speech.baseText + sep + speech.partial
                        }
                        speech.stop()
                    } else {
                        speech.start(baseText: notes)
                    }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(speech.isRecording ? .red : .secondary)
                        .modifier(PulseModifier(active: speech.isRecording))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.bottom, safeArea.bottom + 12)
            }
        }
        .onDisappear { speech.stop() }
        .alert("Permission Required", isPresented: $speech.permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Microphone and speech recognition access are required for dictation.")
        }
    }
}

// MARK: - Pulse Modifier (iOS 16 compatible, no symbolEffect)

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (dim ? 0.35 : 1.0) : 1.0)
            .animation(
                active ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default,
                value: dim
            )
            .onChange(of: active) { on in dim = on }
            .onAppear { dim = active }
    }
}

// MARK: - Supporting Types

enum CalcOp: Equatable {
    case add, subtract, multiply, divide
    var symbol: String {
        switch self {
        case .add:      return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide:   return "÷"
        }
    }
}

enum CalcKey: Equatable {
    case digit(Int)
    case decimal
    case clear
    case sign
    case percent
    case equals
    case op(CalcOp)
}
