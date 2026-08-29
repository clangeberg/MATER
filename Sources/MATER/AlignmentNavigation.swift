import Foundation

struct AlignmentLocation {
    let row: Int
    let column: Int
    let message: String
}

enum AlignmentSearch {
    static func find(_ rawQuery: String, in file: StockholmFile, afterRow: Int, afterColumn: Int) -> AlignmentLocation? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let rows = file.rows
        let lowered = query.lowercased()

        let columnText = lowered.hasPrefix("col:") ? String(lowered.dropFirst(4)) : lowered
        if let requested = Int(columnText), requested > 0, requested <= file.alignmentLength {
            return AlignmentLocation(row: afterRow, column: requested - 1, message: "Column \(requested)")
        }

        let orderedRows = Array(rows.indices.filter { $0 > afterRow }) + Array(rows.indices.filter { $0 <= afterRow })
        if let row = orderedRows.first(where: { rows[$0].label.localizedCaseInsensitiveContains(query) }) {
            return AlignmentLocation(row: row, column: min(afterColumn, max(0, file.alignmentLength - 1)), message: rows[row].label)
        }

        let motif = query.uppercased().replacingOccurrences(of: "T", with: "U")
        for rowIndex in orderedRows where rows[rowIndex].kind.isSequence {
            let aligned = file.records[rows[rowIndex].recordIndex].aligned.uppercased().replacingOccurrences(of: "T", with: "U")
            let searchStarts = rowIndex == afterRow ? [min(aligned.count, afterColumn + 1), 0] : [0]
            for start in searchStarts {
                guard start < aligned.count else { continue }
                let startIndex = aligned.index(aligned.startIndex, offsetBy: start)
                if let range = aligned.range(of: motif, range: startIndex..<aligned.endIndex) {
                    let column = aligned.distance(from: aligned.startIndex, to: range.lowerBound)
                    return AlignmentLocation(row: rowIndex, column: column, message: "\(rows[rowIndex].label), motif \(query)")
                }
            }
        }
        return nil
    }
}

enum AlignmentProblemKind: String, CaseIterable {
    case noncanonical = "Noncanonical pair"
    case highEntropy = "High entropy"
    case gapRich = "Gap-rich column"
    case validation = "Validation problem"
}

struct AlignmentProblem {
    let kind: AlignmentProblemKind
    let row: Int
    let column: Int
    let message: String
}

enum AlignmentProblemAnalyzer {
    static func problems(in file: StockholmFile, entropyThreshold: Double, gapThreshold: Double) -> [AlignmentProblem] {
        let rows = file.rows
        let modelIndexByRecord = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.recordIndex, $0.offset) })
        var problems: [AlignmentProblem] = []
        let pairs = StructureParser.pairs(in: file)

        for sequence in file.sequenceRows {
            let characters = Array(file.records[sequence.recordIndex].aligned)
            guard let row = modelIndexByRecord[sequence.recordIndex] else { continue }
            for pair in pairs where characters.indices.contains(pair.left) && characters.indices.contains(pair.right) {
                let left = characters[pair.left]
                let right = characters[pair.right]
                guard !StockholmFile.isGap(left), !StockholmFile.isGap(right), !BasePairRules.isCanonical(left, right) else { continue }
                problems.append(AlignmentProblem(
                    kind: .noncanonical,
                    row: row,
                    column: pair.left,
                    message: "\(sequence.label): \(left)–\(right) violates pair columns \(pair.left + 1)/\(pair.right + 1)"
                ))
            }
        }

        let fallbackRow = rows.firstIndex(where: { $0.kind.isSequence }) ?? 0
        for (column, entropy) in EntropyAnalyzer.columnEntropies(in: file).enumerated() where entropy >= entropyThreshold {
            problems.append(AlignmentProblem(kind: .highEntropy, row: fallbackRow, column: column, message: String(format: "Column %d entropy %.2f bits", column + 1, entropy)))
        }
        for (column, frequency) in GapAnalyzer.columnGapFrequencies(in: file).enumerated() where frequency >= gapThreshold {
            problems.append(AlignmentProblem(kind: .gapRich, row: fallbackRow, column: column, message: String(format: "Column %d gaps %.0f%%", column + 1, frequency * 100)))
        }

        for (row, alignmentRow) in rows.enumerated() {
            let length = file.records[alignmentRow.recordIndex].aligned.count
            if length != file.alignmentLength {
                problems.append(AlignmentProblem(
                    kind: .validation,
                    row: row,
                    column: min(length, max(0, file.alignmentLength - 1)),
                    message: "\(alignmentRow.label) has \(length) columns; expected \(file.alignmentLength)"
                ))
            }
        }
        if !StructureParser.validationIssues(in: file).isEmpty {
            for structureRow in file.structureRows {
                guard let row = modelIndexByRecord[structureRow.recordIndex] else { continue }
                problems.append(AlignmentProblem(kind: .validation, row: row, column: 0, message: "Check unmatched symbols in \(structureRow.label)"))
            }
        }

        return problems.sorted {
            if $0.row != $1.row { return $0.row < $1.row }
            if $0.column != $1.column { return $0.column < $1.column }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    static func next(
        kind: AlignmentProblemKind?,
        in file: StockholmFile,
        afterRow: Int,
        afterColumn: Int,
        entropyThreshold: Double,
        gapThreshold: Double
    ) -> AlignmentProblem? {
        let matching = problems(in: file, entropyThreshold: entropyThreshold, gapThreshold: gapThreshold)
            .filter { kind == nil || $0.kind == kind }
        return matching.first { $0.row > afterRow || ($0.row == afterRow && $0.column > afterColumn) } ?? matching.first
    }
}
