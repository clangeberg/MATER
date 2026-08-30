import Foundation

@MainActor
enum AlignmentShiftController {
    @discardableResult
    static func shift(
        document: StockholmDocument,
        state: EditorState,
        direction: Int,
        undoManager: UndoManager?
    ) -> Bool {
        let rows = Set(state.selectedRows.filter {
            document.analysis.rows.indices.contains($0) && document.analysis.rows[$0].kind.isSequence
        })
        let selectedColumns = state.selectedColumnSet
        let stemPlan: StemArmShiftPlan?
        if let continuation = state.stemShiftContinuation,
           continuation.primaryColumns == selectedColumns {
            stemPlan = StemArmShiftPlan(
                stem: continuation.stem,
                primaryColumns: continuation.primaryColumns,
                counterpartColumns: continuation.counterpartColumns,
                direction: direction,
                linkPairedArm: state.linkPairedStemShifts
            )
        } else {
            stemPlan = StructureParser.stemArmShiftPlan(
                selectedColumns: selectedColumns,
                cursorColumn: state.selectedColumn,
                direction: direction,
                linkPairedArm: state.linkPairedStemShifts,
                in: document.file
            )
        }

        var shifted = false
        document.mutate(direction < 0 ? "Shift Left" : "Shift Right", undoManager: undoManager) { file in
            if let stemPlan {
                shifted = file.shift(rows: rows, moves: stemPlan.moves)
            } else {
                shifted = file.shift(rows: rows, columns: selectedColumns, direction: direction)
            }
        }

        guard shifted else {
            if let stemPlan {
                state.statusMessage = stemPlan.isLinked
                    ? "A gap is required beside both linked stem arms."
                    : "A gap is required beside the complete stem arm."
            } else {
                state.statusMessage = "A gap is required beside the selected block."
            }
            return false
        }

        let directionName = direction < 0 ? "left" : "right"
        if let stemPlan {
            state.selectColumns(stemPlan.primaryDestinationColumns)
            state.stemShiftContinuation = StemShiftContinuation(
                stem: stemPlan.stem,
                primaryColumns: stemPlan.primaryDestinationColumns,
                counterpartColumns: stemPlan.counterpartDestinationColumns
            )
            if stemPlan.isLinked {
                let pairedDirectionName = direction < 0 ? "right" : "left"
                state.statusMessage = "Shifted stem arm \(directionName) and paired arm \(pairedDirectionName)."
            } else {
                state.statusMessage = "Shifted complete stem arm \(directionName)."
            }
        } else {
            state.translateSelectedColumns(by: direction)
            state.statusMessage = "Shifted selection \(directionName)."
        }
        return true
    }
}
