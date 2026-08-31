import Foundation

struct StemShiftContinuation: Equatable {
    let stem: Int
    let primaryColumns: Set<Int>
    let counterpartColumns: Set<Int>
}

enum AlignmentColorMode: String, CaseIterable, Identifiable {
    case stem
    case element
    case covariation
    case residue
    case none

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stem: return "Stem"
        case .element: return "Element"
        case .covariation: return "Pair variation"
        case .residue: return "Residue"
        case .none: return "None"
        }
    }
}

enum SequenceFilterMode: String, CaseIterable, Identifiable {
    case all
    case structuralProblems
    case noncanonical
    case gaps

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All sequences"
        case .structuralProblems: return "Pair violations"
        case .noncanonical: return "Noncanonical only"
        case .gaps: return "Gaps in stem"
        }
    }
}

enum SequenceSortMode: String, CaseIterable, Identifiable {
    case fileOrder
    case name
    case mostProblems
    case gapFraction

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fileOrder: return "File order"
        case .name: return "Sequence name"
        case .mostProblems: return "Most pair violations"
        case .gapFraction: return "Highest gap fraction"
        }
    }
}

@MainActor
final class EditorState: ObservableObject {
    @Published var selectedRow = 0
    @Published var anchorRow = 0
    @Published var anchorColumn = 0
    @Published var selectedColumn = 0
    @Published var specialColumns: Set<Int> = []
    @Published var colorMode: AlignmentColorMode = .stem
    @Published var pairingLayer: PairingLayer = .primary
    @Published var fontSize: Double = 15
    @Published var showGrid = true
    @Published var hidePosteriorProbability = true
    @Published var showEntropyPlot = true
    @Published var showGapPlot = true
    @Published var highlightAnalysisColumns = true
    @Published var entropyThreshold = 1.25
    @Published var gapThreshold = 0.50
    @Published var showConsensus = true
    @Published var highlightWholeColumn = false
    @Published var selectingConsensus = false
    @Published var referenceSequenceName: String?
    @Published var showChanges = false
    @Published var showInspector = true
    @Published var showMinimap = true
    @Published var sequenceFilterMode: SequenceFilterMode = .all
    @Published var sequenceSortMode: SequenceSortMode = .fileOrder
    @Published var linkPairedStemShifts = true
    @Published var stemShiftContinuation: StemShiftContinuation?
    @Published var statusMessage = "Ready"

    var selection: ClosedRange<Int> {
        min(anchorColumn, selectedColumn)...max(anchorColumn, selectedColumn)
    }

    var selectedRows: ClosedRange<Int> {
        min(anchorRow, selectedRow)...max(anchorRow, selectedRow)
    }

    var selectedColumnSet: Set<Int> {
        specialColumns.isEmpty ? Set(selection) : specialColumns
    }

    var orderedSelectedColumns: [Int] { selectedColumnSet.sorted() }

    var selectedColumnRanges: [ClosedRange<Int>] {
        let columns = orderedSelectedColumns
        guard var start = columns.first else { return [] }
        var prior = start
        var ranges: [ClosedRange<Int>] = []
        for column in columns.dropFirst() {
            if column != prior + 1 {
                ranges.append(start...prior)
                start = column
            }
            prior = column
        }
        ranges.append(start...prior)
        return ranges
    }

    var selectedColumnBounds: ClosedRange<Int> {
        let columns = orderedSelectedColumns
        return (columns.first ?? selectedColumn)...(columns.last ?? selectedColumn)
    }

    var selectedCellCount: Int { selectedRows.count * selectedColumnSet.count }

    func select(
        row: Int,
        column: Int,
        extending: Bool = false,
        wholeColumn: Bool = false,
        consensus: Bool = false
    ) {
        let targetRow = max(0, row)
        let targetColumn = max(0, column)
        if selectedRow != targetRow { selectedRow = targetRow }
        if selectedColumn != targetColumn { selectedColumn = targetColumn }
        if !extending {
            if anchorRow != targetRow { anchorRow = targetRow }
            if anchorColumn != targetColumn { anchorColumn = targetColumn }
        } else if consensus, anchorRow != targetRow {
            // The calculated row has no model-row range of its own; Shift
            // extends columns only.
            anchorRow = targetRow
        }
        if !specialColumns.isEmpty { specialColumns = [] }
        if highlightWholeColumn != wholeColumn { highlightWholeColumn = wholeColumn }
        if selectingConsensus != consensus { selectingConsensus = consensus }
        if stemShiftContinuation != nil { stemShiftContinuation = nil }
    }

    func selectColumns(_ columns: Set<Int>, row: Int? = nil) {
        guard let first = columns.min(), let last = columns.max() else { return }
        if let row {
            let target = max(0, row)
            if selectedRow != target { selectedRow = target }
            if anchorRow != target { anchorRow = target }
        }
        if anchorColumn != first { anchorColumn = first }
        if selectedColumn != last { selectedColumn = last }
        if specialColumns != columns { specialColumns = columns }
        if highlightWholeColumn { highlightWholeColumn = false }
        if selectingConsensus { selectingConsensus = false }
        if stemShiftContinuation != nil { stemShiftContinuation = nil }
    }

    func translateSelectedColumns(by offset: Int) {
        guard offset != 0 else { return }
        if specialColumns.isEmpty {
            anchorColumn += offset
            selectedColumn += offset
        } else {
            specialColumns = Set(specialColumns.map { $0 + offset })
            anchorColumn += offset
            selectedColumn += offset
        }
        if stemShiftContinuation != nil { stemShiftContinuation = nil }
        if highlightWholeColumn { highlightWholeColumn = false }
        if selectingConsensus { selectingConsensus = false }
    }

    func clamp(to file: StockholmFile) {
        clamp(rowCount: file.rows.count, alignmentLength: file.alignmentLength)
    }

    func clamp(rowCount: Int, alignmentLength: Int) {
        let clampedRow = max(0, min(selectedRow, max(0, rowCount - 1)))
        let clampedAnchorRow = max(0, min(anchorRow, max(0, rowCount - 1)))
        let clampedAnchor = max(0, min(anchorColumn, max(0, alignmentLength - 1)))
        let clampedColumn = max(0, min(selectedColumn, max(0, alignmentLength - 1)))

        // @Published emits even when a value is assigned to itself. Avoiding
        // no-op assignments prevents NSViewRepresentable updates from feeding
        // back into another SwiftUI refresh indefinitely.
        if selectedRow != clampedRow { selectedRow = clampedRow }
        if anchorRow != clampedAnchorRow { anchorRow = clampedAnchorRow }
        if anchorColumn != clampedAnchor { anchorColumn = clampedAnchor }
        if selectedColumn != clampedColumn { selectedColumn = clampedColumn }
        let validSpecialColumns = specialColumns.filter { $0 >= 0 && $0 < alignmentLength }
        if specialColumns != validSpecialColumns { specialColumns = validSpecialColumns }
        if let continuation = stemShiftContinuation {
            let valid = continuation.primaryColumns.allSatisfy { $0 >= 0 && $0 < alignmentLength }
                && continuation.counterpartColumns.allSatisfy { $0 >= 0 && $0 < alignmentLength }
            if !valid { stemShiftContinuation = nil }
        }
    }
}
