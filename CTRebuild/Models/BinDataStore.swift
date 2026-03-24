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

    /// group.id → per-page extracted data for that group
    private var groupData: [String: [String: Int]] = [:]

    // MARK: - Public API

    /// Called when a PDF group is toggled active.
    /// Extracts bin locations + committed numbers from the merged document.
    func activate(groupId: String, document: PDFDocument) {
        var perGroup: [String: Int] = [:]
        for i in 0..<document.pageCount {
            guard let text = document.page(at: i)?.string else { continue }
            let pairs = extractBinCommitted(from: text)
            for (bin, qty) in pairs {
                perGroup[bin, default: 0] += qty
            }
        }
        groupData[groupId] = perGroup
        recalculate()
    }

    /// Called when a PDF group is toggled inactive.
    func deactivate(groupId: String) {
        groupData.removeValue(forKey: groupId)
        recalculate()
    }

    /// Whether a group is currently active.
    func isActive(groupId: String) -> Bool {
        groupData[groupId] != nil
    }

    // MARK: - Extraction

    // Regex for bin location: digit + letter + dash + digit + letter
    // e.g. "1A-1A", "2B-3C", "3A-4F"
    private static let binRegex = try! NSRegularExpression(
        pattern: #"\b(\d[A-Fa-f]-\d[A-Fa-f])\b"#
    )

    // Regex for committed number — looks for "Committed" header/label
    // followed by a number (possibly on the next line).
    private static let committedRegex = try! NSRegularExpression(
        pattern: #"[Cc]ommitted[\s:]*(\d+)"#
    )

    /// Extracts (binCode, committedQty) pairs from a single PDF page's text.
    /// Each bin code is paired with the nearest committed quantity that follows it.
    /// If no committed number appears after a bin, that bin is skipped.
    private func extractBinCommitted(from text: String) -> [(String, Int)] {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Find all bin codes with their positions
        let binMatches = Self.binRegex.matches(in: text, range: fullRange)
        // Find all committed quantities with their positions
        let commitMatches = Self.committedRegex.matches(in: text, range: fullRange)

        guard !binMatches.isEmpty, !commitMatches.isEmpty else { return [] }

        var results: [(String, Int)] = []

        for binMatch in binMatches {
            let binCode = ns.substring(with: binMatch.range(at: 1)).uppercased()
            let binPos = binMatch.range.location

            // Find the closest committed qty by absolute distance to this bin
            var bestQty: Int? = nil
            var bestDist = Int.max

            for cm in commitMatches {
                guard let qty = Int(ns.substring(with: cm.range(at: 1))) else { continue }
                let cmPos = cm.range.location
                let dist = abs(cmPos - binPos)
                if dist < bestDist {
                    bestDist = dist
                    bestQty = qty
                }
            }

            if let qty = bestQty, qty > 0 {
                results.append((binCode, qty))
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
    }
}
