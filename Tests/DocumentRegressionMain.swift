import AppKit
import Foundation

@main
struct DocumentRegressionMain {
    @MainActor
    static func main() {
        let document = StockholmDocument()
        precondition(document.changeSummary.changedCells == 0)

        document.mutate("Test edit", undoManager: nil) { file in
            file.replaceCharacter(row: 0, column: 0, with: "A")
        }
        precondition(document.changeSummary.changedCells == 1, "Change comparison did not detect an edited cell.")
        precondition(document.changedColumnsByRecordIndex.values.contains { $0.contains(0) }, "Changed-cell highlighting data is missing.")

        let restoredCells = document.restoreBaselineSelection(rows: [0], columns: [0], undoManager: nil)
        precondition(restoredCells == 1)
        precondition(document.changeSummary.changedCells == 0, "Regional baseline revert failed.")

        document.mutate("Recovery source", undoManager: nil) { file in
            file.replaceCharacter(row: 0, column: 0, with: "C")
        }
        precondition(document.createRecoverySnapshot() != nil, "Could not write a recovery snapshot.")
        document.mutate("Later edit", undoManager: nil) { file in
            file.replaceCharacter(row: 0, column: 0, with: "U")
        }
        precondition(document.restoreLatestRecovery(undoManager: nil), "Could not restore the latest recovery snapshot.")
        precondition(document.file.character(row: 0, column: 0) == "C", "Recovery restored the wrong document state.")
        precondition(document.recoverySnapshotCount > 0)

        let shiftDocument = StockholmDocument()
        shiftDocument.mutate("Prepare stem shift", undoManager: nil) { file in
            for row in file.sequenceRows {
                file.records[row.recordIndex].aligned = "-ACG----CGU-"
            }
            if let structureRow = file.structureRows.first {
                file.records[structureRow.recordIndex].aligned = ".<<<....>>>."
            }
        }
        let state = EditorState()
        state.select(row: 0, column: 10)
        precondition(
            AlignmentShiftController.shift(document: shiftDocument, state: state, direction: -1, undoManager: nil),
            "The controller did not perform a linked stem-arm shift."
        )
        let shiftedRecord = shiftDocument.file.sequenceRows[0].recordIndex
        precondition(shiftDocument.file.records[shiftedRecord].aligned == "--ACG--CGU--", "The controller linked shift output is wrong.")
        precondition(state.stemShiftContinuation != nil, "The controller did not preserve repeated linked shifting.")
        precondition(
            AlignmentShiftController.shift(document: shiftDocument, state: state, direction: -1, undoManager: nil),
            "The controller did not repeat a linked stem-arm shift."
        )
        precondition(shiftDocument.file.records[shiftedRecord].aligned == "---ACGCGU---", "The repeated controller shift output is wrong.")

        print("MATER document recovery and comparison regression tests passed.")
    }
}
