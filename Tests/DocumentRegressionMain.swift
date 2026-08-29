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

        print("MATER document recovery and comparison regression tests passed.")
    }
}
