import SwiftUI

// MARK: - Top Panel — Calculator

struct TopPanelView: View {
    let safeArea: EdgeInsets

    @State private var display: String = "0"
    @State private var operand: Double = 0
    @State private var pendingOp: CalcOp? = nil
    @State private var freshEntry: Bool = true   // next digit starts a new number

    // Button grid layout
    private let rows: [[CalcKey]] = [
        [.clear, .sign,  .percent, .op(.divide)],
        [.digit(7), .digit(8), .digit(9), .op(.multiply)],
        [.digit(4), .digit(5), .digit(6), .op(.subtract)],
        [.digit(1), .digit(2), .digit(3), .op(.add)],
        [.digit(0), .decimal, .equals]
    ]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ────────────────────────────────────────────────────
                Text("CALCULATOR")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .tracking(4)
                    .padding(.top, safeArea.top + 16)
                    .padding(.bottom, 8)

                // ── Display + Button grid anchored to bottom ──────────────────
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
        }
    }

    // MARK: - Formatted Display

    private var formattedDisplay: String {
        guard let d = Double(display) else { return display }
        if display.hasSuffix(".") { return display }
        // Show integer if no fractional part, else show decimal
        if d == d.rounded() && !display.contains(".") {
            let formatted = String(format: "%.0f", d)
            return formatted.count > 9 ? String(d) : formatted
        }
        return display.count > 10 ? String(format: "%.6g", d) : display
    }

    // MARK: - Button View

    @ViewBuilder
    private func calcButton(key: CalcKey, width: CGFloat, height: CGFloat) -> some View {
        let (label, fg, bg) = appearance(for: key)

        Button {
            handle(key)
        } label: {
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
        case .clear:
            return (display == "0" && !freshEntry ? "AC" : "C",
                    .black, Color(white: 0.75))
        case .sign:   return ("+/−", .black, Color(white: 0.75))
        case .percent: return ("%",  .black, Color(white: 0.75))
        case .op(let o): return (o.symbol, .white, .orange)
        case .digit(let d): return ("\(d)", .white, Color(white: 0.22))
        case .decimal: return (".", .white, Color(white: 0.22))
        case .equals: return ("=",  .white, .orange)
        }
    }

    private func operatorForKey(_ key: CalcKey) -> CalcOp? {
        if case .op(let o) = key { return o }
        return nil
    }

    // MARK: - Logic

    private func handle(_ key: CalcKey) {
        switch key {

        case .digit(let d):
            if freshEntry {
                display = d == 0 ? "0" : "\(d)"
                freshEntry = false
            } else {
                if display == "0" { display = "\(d)" }
                else if display.count < 10 { display += "\(d)" }
            }

        case .decimal:
            if freshEntry { display = "0."; freshEntry = false }
            else if !display.contains(".") { display += "." }

        case .clear:
            display = "0"
            if !freshEntry { freshEntry = true }
            else { operand = 0; pendingOp = nil }

        case .sign:
            if let v = Double(display) {
                display = format(-v)
            }

        case .percent:
            if let v = Double(display) {
                display = format(v / 100)
            }

        case .op(let o):
            commit()
            operand = Double(display) ?? 0
            pendingOp = o
            freshEntry = true

        case .equals:
            commit()
            pendingOp = nil
            freshEntry = true
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
        display = format(result)
        operand = result
    }

    private func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "Error" }
        let r = v == v.rounded() ? String(format: "%.0f", v) : String(v)
        return r.count > 10 ? String(format: "%.6g", v) : r
    }
}

// MARK: - Supporting Types

enum CalcOp: Equatable {
    case add, subtract, multiply, divide
    var symbol: String {
        switch self {
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
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
