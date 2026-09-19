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
        let movementColumns = stemPlan == nil
            ? document.file.expandedColumnsForDirectionalPush(
                rows: rows,
                columns: selectedColumns,
                direction: direction
            ) ?? selectedColumns
            : selectedColumns
        let extendedThroughOccupiedRun = stemPlan == nil && movementColumns.count > selectedColumns.count

        var shifted = false
        document.mutate(direction < 0 ? "Move Selection Left" : "Move Selection Right", undoManager: undoManager) { file in
            if let stemPlan {
                shifted = file.shift(rows: rows, moves: stemPlan.moves)
            } else {
                shifted = file.shift(rows: rows, columns: movementColumns, direction: direction)
            }
        }

        guard shifted else {
            let edge = direction < 0 ? "left" : "right"
            if let stemPlan {
                state.statusMessage = stemPlan.isLinked
                    ? "Blocked: both linked stem arms need an available gap in their move directions."
                    : "Blocked: the complete stem arm has no gap on its \(edge) edge."
            } else {
                state.statusMessage = "Blocked: every selected row needs a gap on the \(edge) edge of the moved block."
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
            if extendedThroughOccupiedRun {
                state.selectColumns(Set(movementColumns.map { $0 + direction }))
                state.statusMessage = "Shifted the contiguous occupied block \(directionName) to the next gap."
            } else {
                state.translateSelectedColumns(by: direction)
                state.statusMessage = "Shifted selection \(directionName)."
            }
        }
        return true
    }

    /// Repeats the normal gap-safe move to the furthest valid position and
    /// groups all steps into one Undo command.
    @discardableResult
    static func shiftToEdge(
        document: StockholmDocument,
        state: EditorState,
        direction: Int,
        undoManager: UndoManager?
    ) -> Int {
        undoManager?.beginUndoGrouping()
        defer {
            undoManager?.endUndoGrouping()
            undoManager?.setActionName(direction < 0 ? "Push Selection Left" : "Push Selection Right")
        }
        var count = 0
        let limit = max(1, document.file.alignmentLength)
        while count < limit, shift(document: document, state: state, direction: direction, undoManager: undoManager) {
            count += 1
        }
        if count > 0 {
            let plural = count == 1 ? "" : "s"
            let side = direction < 0 ? "left" : "right"
            state.statusMessage = "Moved \(count) column\(plural) to the \(side)most valid position."
        }
        return count
    }
}
