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
        state.select(row: 1, column: 3, extending: true)
        precondition(state.selectedRows == 0...1, "Shift-selection should extend across rows.")
        precondition(state.selection == 0...3, "Shift-selection should extend across columns.")

        state.selectColumns([0, 3], row: 0)
        precondition(state.selectedColumnSet == [0, 3], "Discontinuous pair/stem selection was lost.")
        precondition(state.selectedColumnRanges == [0...0, 3...3])
        state.translateSelectedColumns(by: 1)
        precondition(state.selectedColumnSet == [1, 4])
        state.clamp(rowCount: 2, alignmentLength: 4)
        precondition(state.selectedColumnSet == [1], "Clamping should discard out-of-range special columns.")

        withExtendedLifetime(observation) {}
        print("MATER editor-state regression test passed.")
    }
}
