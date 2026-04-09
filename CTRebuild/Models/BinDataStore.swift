import Foundation
import PDFKit
import Combine

// MARK: - Bin Data Store
//
// Shared store that maps bin location codes (e.g. "1A-1A") to committed
// quantities extracted from active PDF groups. The left-panel bin grid
// observes this to display numbers on corresponding cells.

final class BinDataStore: ObservableObject {
    static let shared = BinDataStore()
    private init() {}

    /// bin code → total committed qty (summed across all active groups / pages)
    @Published private(set) var binQuantities: [String: Int] = [:]

    /// Ordered list of active groups for display (e.g. in the camera overlay)
    @Published private(set) var activeEntries: [(id: String, label: String, doc: PDFDocument)] = []

    /// group.id → per-page extracted data for that group
    private var groupData: [String: [String: Int]] = [:]

    /// group.id → (display label, merged PDFDocument)
    private var activeMeta: [String: (label: String, doc: PDFDocument)] = [:]

    // MARK: - Public API

    /// Called when a PDF group is toggled active.
    /// Extracts bin locations + committed numbers from the merged document.
    func activate(groupId: String, label: String = "", document: PDFDocument) {
        var perGroup: [String: Int] = [:]
        for i in 0..<document.pageCount {
            guard let text = document.page(at: i)?.string else { continue }
            let pairs = extractBinCommitted(from: text)
            for (bin, qty) in pairs {
                perGroup[bin, default: 0] += qty
            }
        }
        groupData[groupId] = perGroup
        activeMeta[groupId] = (label: label.isEmpty ? groupId : label, doc: document)
        recalculate()
    }

    /// Called when a PDF group is toggled inactive.
    func deactivate(groupId: String) {
        groupData.removeValue(forKey: groupId)
        activeMeta.removeValue(forKey: groupId)
        recalculate()
    }

    /// Whether a group is currently active.
    func isActive(groupId: String) -> Bool {
        groupData[groupId] != nil
    }

    // MARK: - Extraction

    // Matches picking-ticket bin codes: "1-A-4D", "2-B-1E", "10-A-3F"
    private static let binRegex = try! NSRegularExpression(
        pattern: #"\b(\d+-[A-F]-\d+[A-F])\b"#,
        options: .caseInsensitive
    )

    // Matches the Committed column: <qty> <units-abbrev> <committed>
    // e.g. "1 PR 2", "10 EA 5", "3 PC 3"
    // Captures the committed value (last number after the units abbreviation).
    private static let committedRegex = try! NSRegularExpression(
        pattern: #"\b\d+\s+[A-Z]{1,8}\s+(\d+)\b"#
    )

    /// Keeps PDF format "1-A-4D" as-is (grid now matches PDF format)
    private func toGridCode(_ raw: String) -> String {
        raw.uppercased()
    }

    /// Extracts (gridCode, committedQty) pairs from a single PDF page's text.
    /// Finds the Committed column value by matching the pattern: <qty> <units> <committed>
    /// e.g. a row "1-B-1B  CT-11RDC1-BK  1  PR  2" → bin "1B-1B", committed = 2
    private func extractBinCommitted(from text: String) -> [(String, Int)] {
        var results: [(String, Int)] = []

        // ── Primary: line-by-line ────────────────────────────────────────────
        for line in text.components(separatedBy: .newlines) {
            let ns = line as NSString
            let lineRange = NSRange(location: 0, length: ns.length)
            let binMatches = Self.binRegex.matches(in: line, range: lineRange)
            guard !binMatches.isEmpty else { continue }

            // Look for <qty> <units-abbrev> <committed> pattern — committed is the captured group.
            // This correctly identifies the Committed column regardless of Quantity value.
            let commitMatches = Self.committedRegex.matches(in: line, range: lineRange)
            if let last = commitMatches.last,
               let committed = Int(ns.substring(with: last.range(at: 1))), committed > 0 {
                for bm in binMatches {
                    results.append((toGridCode(ns.substring(with: bm.range(at: 1))), committed))
                }
            } else {
                // Fallback: last plain integer on the line
                let nums = line.components(separatedBy: .whitespaces).compactMap { Int($0) }.filter { $0 > 0 }
                guard let qty = nums.last else { continue }
                for bm in binMatches {
                    results.append((toGridCode(ns.substring(with: bm.range(at: 1))), qty))
                }
            }
        }

        // ── Fallback: proximity scan (when PDF has no line breaks) ───────────
        if results.isEmpty {
            let ns = text as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let binMatches = Self.binRegex.matches(in: text, range: fullRange)

            for bm in binMatches {
                let binEnd = bm.range.location + bm.range.length
                let remaining = ns.substring(from: binEnd)
                let remNS = remaining as NSString
                let remRange = NSRange(location: 0, length: remNS.length)
                // Use committed pattern first, fallback to first integer
                if let cm = Self.committedRegex.matches(in: remaining, range: remRange).first,
                   let committed = Int(remNS.substring(with: cm.range(at: 1))), committed > 0 {
                    results.append((toGridCode(ns.substring(with: bm.range(at: 1))), committed))
                } else {
                    let numRegex = try! NSRegularExpression(pattern: #"\b(\d+)\b"#)
                    if let nm = numRegex.firstMatch(in: remaining, range: remRange),
                       let qty = Int(remNS.substring(with: nm.range(at: 1))), qty > 0 {
                        results.append((toGridCode(ns.substring(with: bm.range(at: 1))), qty))
                    }
                }
            }
        }

        return results
    }

    // MARK: - Recalculation

    private func recalculate() {
        var merged: [String: Int] = [:]
        for (_, perGroup) in groupData {
            for (bin, qty) in perGroup {
                merged[bin, default: 0] += qty
            }
        }
        binQuantities = merged
        activeEntries = activeMeta
            .map { (id: $0.key, label: $0.value.label, doc: $0.value.doc) }
            .sorted { $0.id < $1.id }
    }
}
