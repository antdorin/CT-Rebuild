import SwiftUI
import Speech
import AVFoundation

// MARK: - Top Panel

struct TopPanelView: View {
    let safeArea: EdgeInsets

    @State private var selectedTab: Int? = 1

    // Read directly from UIKit — reliable even when parent ignores safe area
    private var topInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.top ?? 50
    }

    var body: some View {
        ZStack {
            if selectedTab != nil {
                Rectangle()
                    .fill(.ultraThinMaterial)
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
                            NotesContentView(safeArea: safeArea)
                        } else {
                            Spacer()
                        }
                    }
                    .transition(.opacity)
                } else {
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
    }
}

// MARK: - Tab Bar

private struct TopTabBar: View {
    @Binding var selected: Int?

    private let labels = ["CALC", "NOTES", "—"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(labels.indices, id: \.self) { i in
                Button { selected = i } label: {
                    Text(labels[i])
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(selected == i ? .black : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule().fill(selected == i ? Color.orange : Color(white: 0.2))
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

// MARK: - Notes Content

private struct NotesContentView: View {
    let safeArea: EdgeInsets

    @AppStorage("topPanelNotes") private var notes: String = ""
    @StateObject private var speech = SpeechManager()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    if speech.isRecording {
                        speech.stopRecording { appended in
                            notes += (notes.isEmpty ? "" : " ") + appended
                        }
                    } else {
                        speech.startRecording { appended in
                            notes += (notes.isEmpty ? "" : " ") + appended
                        }
                    }
                } label: {
                    Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundColor(speech.isRecording ? .red : .secondary)
                        .padding(10)
                }
                .buttonStyle(.plain)
                .disabled(!speech.isAvailable)
            }
            .padding(.horizontal, 12)

            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundColor(.primary)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .padding(.bottom, safeArea.bottom + 16)
        }
        .onAppear { speech.requestPermission() }
    }
}

// MARK: - Speech Manager

private class SpeechManager: ObservableObject {
    @Published var isRecording = false
    @Published var isAvailable = false

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tapInstalled = false
    private var livePending = ""
    private var onCommit: ((String) -> Void)?

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.isAvailable = (status == .authorized) }
        }
    }

    func startRecording(onCommit: @escaping (String) -> Void) {
        guard !tapInstalled, let rec = recognizer, rec.isAvailable else { return }
        self.onCommit = onCommit
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            request = SFSpeechAudioBufferRecognitionRequest()
            request?.shouldReportPartialResults = true

            task = rec.recognitionTask(with: request!) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    DispatchQueue.main.async {
                        self.livePending = text
                        if isFinal { self.flush(); self.stopEngine() }
                    }
                }
                if error != nil { DispatchQueue.main.async { self.stopEngine() } }
            }

            let node = engine.inputNode
            let fmt = node.inputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                self?.request?.append(buf)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            stopEngine()
        }
    }

    func stopRecording(_ completing: ((String) -> Void)? = nil) {
        if let c = completing { onCommit = c }
        flush()
        stopEngine()
    }

    private func flush() {
        guard !livePending.isEmpty else { return }
        onCommit?(livePending)
        livePending = ""
    }

    private func stopEngine() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        onCommit = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
