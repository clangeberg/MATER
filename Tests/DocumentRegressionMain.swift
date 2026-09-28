import AppKit
import Foundation

@main
struct DocumentRegressionMain {
    @MainActor
    static func main() {
        precondition(StockholmDocument.clearAllRecoveryData(), "Could not clear the isolated recovery-test directory.")
        let firstPathDocument = StockholmDocument()
        let secondPathDocument = StockholmDocument()
        firstPathDocument.configureRecoverySourceURL(URL(fileURLWithPath: "/tmp/mater-first/same.sto"))
        secondPathDocument.configureRecoverySourceURL(URL(fileURLWithPath: "/tmp/mater-second/same.sto"))
        precondition(firstPathDocument.createRecoverySnapshot() != nil)
        precondition(firstPathDocument.recoverySnapshotCount == 1)
        precondition(secondPathDocument.recoverySnapshotCount == 0, "Identical files at different paths shared recovery data.")

        exerciseRandomizedUndoRedo()

        let document = StockholmDocument()
        precondition(document.changeSummary.changedCells == 0)
        precondition(!document.sequenceEditingUnlocked, "Alignment Integrity mode should be enabled by default.")
        precondition(document.integrityReport.isIntact)

        document.mutate("Blocked residue edit", undoManager: nil) { file in
            file.replaceCharacter(row: 0, column: 0, with: "A")
        }
        precondition(document.file.character(row: 0, column: 0) == "G", "Integrity lock allowed a residue replacement.")
        precondition(!document.integrityNotice.isEmpty, "Blocked integrity edit was not reported.")

        document.sequenceEditingUnlocked = true

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
        document.sequenceEditingUnlocked = false
        do {
            _ = try document.snapshot(contentType: .stockholmAlignment)
            preconditionFailure("Saving a sequence-altered document while integrity-locked should fail.")
        } catch is AlignmentIntegrityError {
            // Expected: the explicit unlock is required to save residue changes.
        } catch {
            preconditionFailure("Unexpected integrity-save error: \(error)")
        }
        let repairedCells = document.restoreBaselineSelection(rows: [0], columns: [0], undoManager: nil)
        precondition(repairedCells == 1, "Integrity mode did not permit a baseline repair.")
        precondition(document.integrityReport.isIntact, "Baseline repair did not restore sequence integrity.")
        do {
            _ = try document.snapshot(contentType: .stockholmAlignment)
        } catch {
            preconditionFailure("An integrity-repaired document should save while locked: \(error)")
        }

        let invalidDocument = StockholmDocument(previewFile: StockholmParser.parse("""
        # STOCKHOLM 1.0
        one ACGU
        two ACG
        //
        """))
        precondition(invalidDocument.analysis.validationIssues.contains { $0.severity == .error })
        do {
            _ = try invalidDocument.snapshot(contentType: .stockholmAlignment)
            preconditionFailure("Saving an invalid Stockholm alignment should require explicit permission.")
        } catch is StockholmValidationSaveError {
            // Expected.
        } catch {
            preconditionFailure("Unexpected validation-save error: \(error)")
        }
        invalidDocument.invalidSavingUnlocked = true
        do {
            _ = try invalidDocument.snapshot(contentType: .stockholmAlignment)
        } catch {
            preconditionFailure("Explicitly permitted invalid Stockholm content should save: \(error)")
        }
        let diagnostics = MATERDiagnostics.report(document: invalidDocument, sourceURL: URL(fileURLWithPath: "/private/example.sto"))
        precondition(diagnostics.contains("example.sto"))
        precondition(diagnostics.contains("2 sequences"))
        precondition(!diagnostics.contains("one ACGU"), "Diagnostics leaked sequence contents.")

        let shiftDocument = StockholmDocument()
        shiftDocument.sequenceEditingUnlocked = true
        shiftDocument.mutate("Prepare stem shift", undoManager: nil) { file in
            for row in file.sequenceRows {
                file.records[row.recordIndex].aligned = "-ACG----CGU-"
            }
            if let structureRow = file.structureRows.first {
                file.records[structureRow.recordIndex].aligned = ".<<<....>>>."
            }
        }
        shiftDocument.sequenceEditingUnlocked = false
        let state = EditorState()
        state.linkPairedStemShifts = true
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

        let flankingResidueDocument = StockholmDocument(previewFile: StockholmParser.parse("""
        # STOCKHOLM 1.0
        outside -CGGGUUU.
        #=GR outside PP .1234567.
        #=GC SS_cons ..<<<>>>.
        //
        """))
        let flankingState = EditorState()
        flankingState.select(row: 0, column: 1)
        precondition(
            AlignmentShiftController.shift(
                document: flankingResidueDocument,
                state: flankingState,
                direction: 1,
                undoManager: nil
            ),
            "An unpaired flanking residue could not push its adjacent occupied stack."
        )
        let flankingRecord = flankingResidueDocument.file.sequenceRows[0].recordIndex
        precondition(
            flankingResidueDocument.file.records[flankingRecord].aligned == "-.CGGGUUU",
            "Directional occupied-stack expansion produced the wrong sequence placement."
        )
        let flankingAnnotation = flankingResidueDocument.file.records.first {
            if case .residueAnnotation("outside", "PP") = $0.kind { return true }
            return false
        }
        precondition(
            flankingAnnotation?.aligned == "..1234567",
            "Directional occupied-stack expansion did not keep the #=GR annotation registered."
        )
        precondition(
            flankingState.selectedColumnSet == Set(2...8),
            "The expanded destination block did not remain selected."
        )

        let deletionDocument = StockholmDocument(previewFile: StockholmParser.parse("""
        # STOCKHOLM 1.0
        one ACGU
        two ACGU
        three ACGU
        #=GR one PP 9876
        #=GR two PP 8765
        #=GC SS_cons <..>
        //
        """))
        deletionDocument.sequenceEditingUnlocked = true
        let deletionBefore = deletionDocument.file
        let deletionUndoManager = UndoManager()
        deletionUndoManager.groupsByEvent = false
        deletionUndoManager.beginUndoGrouping()
        deletionDocument.mutate("Delete Selected Sequences", undoManager: deletionUndoManager) { file in
            let removed = file.removeSequences(modelRows: [0, 1])
            precondition(removed == ["one", "two"], "Multi-row sequence deletion removed the wrong rows.")
        }
        deletionUndoManager.endUndoGrouping()
        let deletionAfter = deletionDocument.file
        precondition(deletionAfter.sequenceRows.map(\.label) == ["three"], "Selected sequences were not removed.")
        precondition(
            !deletionAfter.rows.contains { if case .residueAnnotation = $0.kind { return true }; return false },
            "Attached #=GR rows survived sequence deletion."
        )
        deletionUndoManager.undo()
        precondition(deletionDocument.file == deletionBefore, "Undo did not restore deleted sequence rows.")
        deletionUndoManager.redo()
        precondition(deletionDocument.file == deletionAfter, "Redo did not restore direct sequence deletion.")

        print("MATER document recovery and comparison regression tests passed.")
    }

    @MainActor
    private static func exerciseRandomizedUndoRedo() {
        let fixtures: [(String, (inout StockholmFile) -> Void)] = [
            ("""
            # STOCKHOLM 1.0
            one .A-C.
            #=GR one PP .9.8.
            #=GC SS_cons <...>
            //
            """, { _ = $0.shift(row: 0, selection: 1...1, direction: -1) }),
            ("""
            # STOCKHOLM 1.0
            one ACG.U
            #=GR one PP 987.6
            #=GC SS_cons .....
            //
            """, { _ = $0.openGap(row: 0, at: 1) }),
            ("""
            # STOCKHOLM 1.0
            one A.CGU
            #=GR one PP 9.876
            #=GC SS_cons .....
            //
            """, { _ = $0.closeGap(row: 0, at: 1) }),
            ("""
            # STOCKHOLM 1.0
            one -A--U-
            #=GR one PP .9..8.
            #=GC SS_cons <...>.
            //
            """, {
                let index = $0.sequenceRows[0].recordIndex
                _ = $0.replaceSequenceGapPlacement(recordIndex: index, with: "A---U-")
            })
        ]

        for iteration in 0..<200 {
            let fixture = fixtures[(iteration &* 73) % fixtures.count]
            let document = StockholmDocument(previewFile: StockholmParser.parse(fixture.0))
            let before = document.file
            let undoManager = UndoManager()
            undoManager.groupsByEvent = false
            undoManager.beginUndoGrouping()
            document.mutate("Randomized undo property", undoManager: undoManager, fixture.1)
            undoManager.endUndoGrouping()
            let after = document.file
            precondition(after != before, "Randomized undo fixture made no change.")
            precondition(ResidueAnnotationIntegrityAnalyzer.preservesAttachmentsForMovedSequences(from: before, to: after))

            undoManager.undo()
            precondition(document.file == before, "Undo did not restore exact Stockholm state at iteration \(iteration).")
            undoManager.redo()
            precondition(document.file == after, "Redo did not restore exact edited Stockholm state at iteration \(iteration).")
        }
    }
}
