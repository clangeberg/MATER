import Combine
import Foundation

@main
struct EditorStateRegressionMain {
    @MainActor
    static func main() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        sequence_1 ACGU
        #=GC SS_cons <..>
        //
        """)
        let state = EditorState()
        precondition(state.hidePosteriorProbability, "PP annotation rows should be hidden by default.")
        precondition(state.showEntropyPlot, "The entropy plot should be shown by default.")
        precondition(state.showGapPlot, "The gap-frequency plot should be shown by default.")
        precondition(state.linkPairedStemShifts, "Paired stem-arm shifting should be enabled by default.")
        precondition(state.showConsensus, "The R2R consensus row should be shown by default.")
        var notifications = 0
        let observation = state.objectWillChange.sink { notifications += 1 }

        state.clamp(to: file)
        precondition(notifications == 0, "Clamping valid state must not trigger a refresh.")

        state.selectedRow = 99
        notifications = 0
        state.clamp(to: file)
        precondition(notifications == 1, "Only the out-of-range coordinate should be published.")
        precondition(state.selectedRow == 1)

        state.select(row: 0, column: 0)
        state.select(row: 1, column: 1, wholeColumn: true)
        precondition(state.highlightWholeColumn, "Annotation selection should support a whole-column highlight.")
        state.select(row: 1, column: 1, wholeColumn: true, consensus: true)
        precondition(state.selectingConsensus, "Calculated consensus selection state was not retained.")
        state.select(row: 0, column: 0)
        precondition(!state.highlightWholeColumn, "Ordinary cell selection should clear the whole-column highlight.")
        precondition(!state.selectingConsensus, "Ordinary cell selection should leave the calculated consensus row.")
        state.select(row: 1, column: 3, extending: true)
        precondition(state.selectedRows == 0...1, "Shift-selection should extend across rows.")
        precondition(state.selection == 0...3, "Shift-selection should extend across columns.")

        state.selectColumns([0, 3], row: 0)
        precondition(!state.highlightWholeColumn, "Pair/stem selection should not retain a whole-column highlight.")
        precondition(state.selectedColumnSet == [0, 3], "Discontinuous pair/stem selection was lost.")
        precondition(state.selectedColumnRanges == [0...0, 3...3])
        state.translateSelectedColumns(by: 1)
        precondition(state.selectedColumnSet == [1, 4])
        state.clamp(rowCount: 2, alignmentLength: 4)
        precondition(state.selectedColumnSet == [1], "Clamping should discard out-of-range special columns.")

        state.stemShiftContinuation = StemShiftContinuation(stem: 0, primaryColumns: [1], counterpartColumns: [2])
        state.select(row: 0, column: 1)
        precondition(state.stemShiftContinuation == nil, "A new cell selection should end a stem-shift continuation.")

        withExtendedLifetime(observation) {}
        print("MATER editor-state regression test passed.")
    }
}
