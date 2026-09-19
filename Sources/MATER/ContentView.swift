import AppKit
import SwiftUI

private enum AlignmentRefinementKind {
    case wiggle
    case caCoFold

    var savePanelTitle: String {
        switch self {
        case .wiggle: return "Save Wiggle-Refined Alignment"
        case .caCoFold: return "Save CaCoFold-Refined Alignment"
        }
    }

    var savePanelPrompt: String {
        switch self {
        case .wiggle: return "Wiggle-refine and Save"
        case .caCoFold: return "CaCoFold-refine and Save"
        }
    }

    var filenameStem: String {
        switch self {
        case .wiggle: return "MATER-wiggle-refined"
        case .caCoFold: return "MATER-CaCoFold-refined"
        }
    }
}

struct DocumentEditorView: View {
    @ObservedObject var document: StockholmDocument
    let sourceURL: URL?
    @StateObject private var state: EditorState
    @EnvironmentObject private var residuePalette: ResiduePaletteSettings
    @EnvironmentObject private var keyboardShortcuts: KeyboardShortcutSettings
    @State private var searchText = ""
    @State private var pendingExportFormat: AlignmentExportFormat?
    @State private var exportConfiguration = AlignmentExportConfiguration()
    @State private var suggestedEdits: [StemEditSuggestion] = []
    @State private var showingSuggestedEdits = false
    @State private var isWiggleRefining = false
    @State private var wiggleProgress: AlignmentRefinementProgress?
    @State private var wiggleTask: Task<Void, Never>?
    @State private var isCaCoFoldRefining = false
    @StateObject private var rScapeController = RScapeController()
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openDocument) private var openDocument

    init(document: StockholmDocument, sourceURL: URL?, initialSelectedColumn: Int? = nil) {
        self.document = document
        self.sourceURL = sourceURL

        let state = EditorState()
        if let initialSelectedColumn {
            state.select(row: 0, column: initialSelectedColumn)
        }
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if !validationErrors.isEmpty {
                validationSafetyBanner
                Divider()
            }
            if state.referenceSequenceName != nil {
                PinnedReferencePanel(document: document, state: state, residuePalette: residuePalette)
                Divider()
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    AlignmentCanvas(document: document, state: state, residuePalette: residuePalette)
                    if state.showMinimap {
                        Divider()
                        AlignmentMinimapView(document: document, state: state)
                    }
                }
                if state.showInspector {
                    Divider()
                    StructuralQualityInspector(document: document, state: state, suggestEdits: suggestAlignmentEdits)
                }
                if rScapeController.isPanelVisible {
                    Divider()
                    RScapeResultsPanel(
                        controller: rScapeController,
                        locateExecutable: locateRScape,
                        runAgain: startRScapeAnalysis
                    )
                }
            }
            Divider()
            legendAndStatus
        }
        .frame(
            minWidth: 900 + (state.showInspector ? 220 : 0) + (rScapeController.isPanelVisible ? 300 : 0),
            minHeight: 650
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .background(ShortcutMonitor(shortcuts: keyboardShortcuts, handler: handleShortcut))
        .onAppear {
            document.configureRecoverySourceURL(sourceURL)
        }
        .sheet(item: $pendingExportFormat) { format in
            ExportOptionsView(
                format: format,
                selectedRowCount: state.selectedRows.count,
                selectedColumnCount: state.selectedColumnSet.count,
                configuration: $exportConfiguration,
                cancel: { pendingExportFormat = nil },
                export: {
                    let configuration = exportConfiguration
                    pendingExportFormat = nil
                    DispatchQueue.main.async { exportAlignment(format, configuration: configuration) }
                }
            )
        }
        .sheet(isPresented: $showingSuggestedEdits) {
            SuggestedEditsView(
                suggestions: suggestedEdits,
                cancel: { showingSuggestedEdits = false },
                apply: applySuggestedEdit
            )
        }
        .onChange(of: document.integrityNotice) { notice in
            guard !notice.isEmpty else { return }
            state.statusMessage = notice
            NSSound.beep()
        }
        .onDisappear {
            wiggleTask?.cancel()
        }
    }

    private var controls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Picker("Color", selection: $state.colorMode) {
                    ForEach(AlignmentColorMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .frame(width: 540)
                .help("Switch among fine stems, continuous high-level helix elements, descriptive pair variation, nucleotide identity, non-dominant residues, and uncolored views.")

                Menu {
                    ColorPicker("Adenine (A)", selection: residuePalette.binding(for: "A"), supportsOpacity: false)
                    ColorPicker("Cytosine (C)", selection: residuePalette.binding(for: "C"), supportsOpacity: false)
                    ColorPicker("Guanine (G)", selection: residuePalette.binding(for: "G"), supportsOpacity: false)
                    ColorPicker("Uracil (U/T)", selection: residuePalette.binding(for: "U"), supportsOpacity: false)
                    Divider()
                    Button("Reset residue colors", action: residuePalette.reset)
                } label: {
                    Label("Base colors", systemImage: "paintpalette")
                }
                .help("Choose the colors used for A, C, G, and U/T in Residue mode.")

                Menu {
                    Button("No pinned reference") { state.referenceSequenceName = nil }
                    Divider()
                    ForEach(document.file.sequenceRows, id: \.recordIndex) { row in
                        if case .sequence(let name) = row.kind {
                            Button {
                                state.referenceSequenceName = name
                            } label: {
                                if state.referenceSequenceName == name {
                                    Label(name, systemImage: "checkmark")
                                } else {
                                    Text(name)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Reference", systemImage: "pin")
                }
                .help("Pin a reference sequence above the scrolling alignment.")

                Menu {
                    Button("Export colored alignment as PDF…") { beginExport(.pdf) }
                    Button("Export colored alignment as SVG…") { beginExport(.svg) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export the entire alignment as a vector PDF or SVG using the current colors and display options.")

                Button(action: toggleSequenceEditing) {
                    Label(
                        document.sequenceEditingUnlocked ? "Sequence editing" : "Alignment locked",
                        systemImage: document.sequenceEditingUnlocked ? "lock.open.fill" : "lock.fill"
                    )
                }
                .tint(document.sequenceEditingUnlocked ? .orange : .green)
                .help(document.sequenceEditingUnlocked
                    ? "Ungapped residue changes are allowed. Click to restore alignment-only protection."
                    : "Sequence integrity is protected: gap placement and annotations may change, but ungapped sequences may not.")

                Spacer()

                Menu {
                    Button("Insert empty gap column", action: insertGapColumn)
                    Button("Delete selected all-gap column", action: deleteGapColumn)
                    Button("Remove all empty columns", action: removeAllGapColumns)
                    Divider()
                    Toggle("Cell grid", isOn: $state.showGrid)
                    Toggle("Hide PP annotation rows", isOn: $state.hidePosteriorProbability)
                    Toggle("Show R2R consensus row", isOn: $state.showConsensus)
                    Toggle("Show entropy bar plot", isOn: $state.showEntropyPlot)
                    Toggle("Show gap-frequency plot", isOn: $state.showGapPlot)
                    Toggle("Highlight high-entropy/gap-rich columns", isOn: $state.highlightAnalysisColumns)
                    Divider()
                    Toggle("Structure and analysis overview", isOn: $state.showMinimap)
                    Toggle("Structural Quality Inspector", isOn: $state.showInspector)
                    HStack {
                        Text("Entropy ≥ \(state.entropyThreshold, specifier: "%.2f")")
                        Slider(value: $state.entropyThreshold, in: 0...2, step: 0.05)
                    }
                    HStack {
                        Text("Gaps ≥ \(state.gapThreshold * 100, specifier: "%.0f")%")
                        Slider(value: $state.gapThreshold, in: 0...1, step: 0.05)
                    }
                    HStack {
                        Text("Text size")
                        Slider(value: $state.fontSize, in: 11...23, step: 1)
                    }
                    Picker("Fixed-width font", selection: $state.fontName) {
                        ForEach(["System Monospaced", "Menlo", "Monaco", "Courier"], id: \.self) { Text($0) }
                    }
                    Toggle("Non-dominant coloring: current column only", isOn: $state.nonDominantCurrentColumnOnly)
                } label: {
                    Label("View & columns", systemImage: "slider.horizontal.3")
                }
            }

            HStack(spacing: 10) {
                Button(action: { shift(-1) }) { Label("Move selection left", systemImage: "arrow.left") }
                    .help("Move the selected block, or the complete fine stem arm under a single selected base, left into a gap.")
                Button(action: { shift(1) }) { Label("Move selection right", systemImage: "arrow.right") }
                    .help("Move the selected block, or the complete fine stem arm under a single selected base, right into a gap.")
                Toggle(isOn: $state.linkPairedStemShifts) {
                    Label("Link stem arms", systemImage: "link")
                }
                .toggleStyle(.button)
                .help("When shifting one stem arm, move its paired arm one column in the opposite direction to keep the helix in register.")
                Button(action: openGap) { Label("Open row gap", systemImage: "arrow.right.to.line") }
                    .help("Open a gap in only the selected sequence while consuming its next downstream gap.")
                Button(action: closeGap) { Label("Close row gap", systemImage: "arrow.left.to.line") }
                    .help("Close a gap in only the selected sequence and pull the following residue block left.")
                Button(action: insertGapColumn) { Label("Insert column", systemImage: "rectangle.split.1x2") }
                    .help("Insert an empty alignment column across every sequence and annotation row.")
                Button(action: jumpToPair) { Label("Jump pair", systemImage: "arrow.left.and.right") }
                    .help("Jump to the nucleotide paired with the selected column.")
                Button(action: selectStem) { Label("Select stem", systemImage: "point.3.connected.trianglepath.dotted") }
                    .help("Select both sides of the complete stem containing the cursor. Double-click selects one pair; triple-click selects its stem.")

                Divider().frame(height: 24)

                Menu {
                    Picker("Pairing layer", selection: $state.pairingLayer) {
                        ForEach(PairingLayer.allCases) { layer in Text(layer.title).tag(layer) }
                    }
                } label: {
                    Label(state.pairingLayer.title, systemImage: "link")
                }
                .help("Choose the SS_cons or pseudoknot layer to annotate.")

                Button("Set pair", action: setPair)
                    .disabled(state.selectedColumnSet.count < 2)
                    .help("Pair the first and last selected columns in the chosen structure layer.")
                Button("Unpair", action: clearPair)
                    .help("Remove structural pairs touching the selected columns.")
            }

            HStack(spacing: 10) {
                Button(action: suggestAlignmentEdits) {
                    Label("Suggest fixes", systemImage: "wand.and.stars")
                }
                .disabled(state.selectingConsensus || !document.analysis.rows.indices.contains(state.selectedRow) || !document.analysis.rows[state.selectedRow].kind.isSequence)
                .help("Preview gap-only shifts that improve the selected sequence's current stem.")
                Button(action: {
                    if isWiggleRefining {
                        wiggleTask?.cancel()
                    } else {
                        wiggleRefineAlignment()
                    }
                }) {
                    if isWiggleRefining {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            if let wiggleProgress {
                                Text("Cancel \(Int(wiggleProgress.fractionCompleted * 100))%")
                            } else {
                                Text("Cancel Wiggle")
                            }
                        }
                    } else {
                        Label("Wiggle-refine", systemImage: "sparkles")
                    }
                }
                .disabled(isCaCoFoldRefining || (!isWiggleRefining && document.analysis.structurePairs.isEmpty))
                .help(isWiggleRefining ? "Cancel Wiggle-refine without writing an output file." : "Create and open a new alignment after applying MATER's safe gap-only helix-window refinements to convergence. The current file is not changed.")
                Button(action: caCoFoldRefineStructure) {
                    if isCaCoFoldRefining {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("CaCoFold…")
                        }
                    } else {
                        Label("CaCoFold-refine", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    }
                }
                .disabled(isWiggleRefining || isCaCoFoldRefining || rScapeController.isRunning || document.analysis.structurePairs.isEmpty)
                .help("Use an installed R-scape to improve the given structure with CaCoFold, retain only a new Stockholm alignment, and open it in MATER. The current file is not changed.")
                Button(action: showOrRunRScape) {
                    if rScapeController.isRunning {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("R-scape…")
                        }
                    } else if rScapeController.result != nil {
                        Label("R-scape results", systemImage: "waveform.path.ecg")
                    } else {
                        Label("Run R-scape", systemImage: "waveform.path.ecg")
                    }
                }
                .disabled(isCaCoFoldRefining || document.analysis.structurePairs.isEmpty)
                .help("Evaluate the current given SS_cons structure with an installed R-scape `-s` test and show the R2R result in a closable panel.")
                Spacer()
                Text("Refinement creates a new alignment; the open file is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Menu {
                    Button("Focus search") { searchFieldFocused = true }
                        .keyboardShortcut("f", modifiers: .command)
                    Button("Find next", action: findNext)
                    Divider()
                    Button("Next problem", action: { navigateToProblem(nil) })
                    Button("Next noncanonical pair", action: { navigateToProblem(.noncanonical) })
                    Button("Next high-entropy column", action: { navigateToProblem(.highEntropy) })
                    Button("Next gap-rich column", action: { navigateToProblem(.gapRich) })
                    Button("Next validation problem", action: { navigateToProblem(.validation) })
                } label: {
                    Label("Navigate", systemImage: "scope")
                }

                Menu {
                    Button("Push selection fully left", action: { pushToEdge(-1) })
                    Button("Push selection fully right", action: { pushToEdge(1) })
                    Divider()
                    Button("Left-justify selected residues", action: { justifySelection(towardRight: false) })
                    Button("Right-justify selected residues", action: { justifySelection(towardRight: true) })
                    Button("Transpose with left gap", action: { transposeSelection(direction: -1) })
                    Button("Transpose with right gap", action: { transposeSelection(direction: 1) })
                    Divider()
                    Button("Write calculated consensus to #=GC cons", action: writeConsensus)
                    Button("Fold selected region as hairpin", action: foldHairpin)
                    Button("Permute alignment around cursor…", action: confirmPermute)
                    Divider()
                    Button("Detect inconsistent or identical sequences", action: showAlignmentAudit)
                    Button("Alignment statistics", action: showAlignmentStatistics)
                    Button("Delete sequences matching selected-column criteria…", action: deleteMatchingSequences)
                    Divider()
                    Button(state.columnBookmarks.contains(state.selectedColumn) ? "Remove column bookmark" : "Bookmark current column", action: toggleColumnBookmark)
                    Button("Next column bookmark", action: nextColumnBookmark)
                        .disabled(state.columnBookmarks.isEmpty)
                } label: {
                    Label("Alignment tools", systemImage: "wrench.and.screwdriver")
                }

                Menu {
                    Toggle("Highlight changes from opened file", isOn: $state.showChanges)
                    Button("Revert selected region", action: revertSelectedRegion)
                    Button("Revert selected rows", action: revertSelectedRows)
                    Divider()
                    Button("Create recovery snapshot", action: createRecoverySnapshot)
                    Button("Restore latest recovery snapshot", action: restoreRecoverySnapshot)
                        .disabled(document.recoverySnapshotCount == 0)
                    Button("Copy Diagnostics", action: copyDiagnostics)
                    Divider()
                    let summary = document.changeSummary
                    Text("\(summary.changedCells) changed cells in \(summary.changedRows) rows")
                    Text("Sequences: \(summary.changedSequenceCells) • annotations: \(summary.changedAnnotationCells)")
                    Text("Recovery snapshots: \(document.recoverySnapshotCount)")
                } label: {
                    Label("Changes", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    state.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }

                Button { MATERApplicationActions.openUserGuide() } label: {
                    Label("Guide", systemImage: "questionmark.circle")
                }

                Spacer()

                TextField("Name, motif, or col:123", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .focused($searchFieldFocused)
                    .onSubmit(findNext)

                Text("Drag a selection to move • ⌃, / ⌃. move • shortcuts in Settings")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
        }
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var validationErrors: [ValidationIssue] {
        document.analysis.validationIssues.filter { $0.severity == .error }
    }

    private var validationSafetyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: document.invalidSavingUnlocked ? "exclamationmark.triangle.fill" : "lock.trianglebadge.exclamationmark.fill")
                .foregroundStyle(document.invalidSavingUnlocked ? .orange : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.invalidSavingUnlocked
                    ? "Invalid-file saving is temporarily allowed for this document"
                    : "Save protection: \(validationErrors.count) Stockholm validation error\(validationErrors.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                Text(document.invalidSavingUnlocked
                    ? "Saving may preserve or create malformed Stockholm data. Correct the errors, or restore protection when you are done."
                    : "MATER will not overwrite this alignment until the errors are corrected or you explicitly allow an invalid save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Copy Diagnostics", action: copyDiagnostics)
            if document.invalidSavingUnlocked {
                Button("Restore Save Protection") {
                    document.invalidSavingUnlocked = false
                    state.statusMessage = "Invalid-file save protection restored."
                }
            } else {
                Button("Allow Invalid Save…", action: allowInvalidSave)
                    .tint(.red)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.07))
        .help(validationErrors.map(\.message).joined(separator: "\n"))
    }

    private var legendAndStatus: some View {
        HStack(spacing: 12) {
            switch state.colorMode {
            case .covariation:
                LegendSwatch(color: .green.opacity(0.70), label: "same pair")
                LegendSwatch(color: .cyan.opacity(0.75), label: "one-sided")
                LegendSwatch(color: .blue.opacity(0.85), label: "two-sided change")
                LegendSwatch(color: .red.opacity(0.85), label: "noncanonical")
                LegendSwatch(color: .gray.opacity(0.55), label: "gap")
            case .stem:
                Text("Canonical pairs are colored by insertion-tolerant stem; large loops and branches start a new stem.")
                    .foregroundStyle(.secondary)
            case .element:
                Text("Canonical pairs in each continuous helix element share a color across bulges and internal loops; branches start new elements.")
                    .foregroundStyle(.secondary)
            case .residue:
                LegendSwatch(color: Color(nsColor: residuePalette.adenine), label: "A")
                LegendSwatch(color: Color(nsColor: residuePalette.cytosine), label: "C")
                LegendSwatch(color: Color(nsColor: residuePalette.guanine), label: "G")
                LegendSwatch(color: Color(nsColor: residuePalette.uracil), label: "U/T")
            case .nonDominant:
                LegendSwatch(color: .orange.opacity(0.72), label: "differs from consensus")
                Text("Dominant residues remain uncolored.").foregroundStyle(.secondary)
            case .none:
                Text("Coloring disabled").foregroundStyle(.secondary)
            }

            Spacer()
            let integrity = document.integrityReport
            if document.sequenceEditingUnlocked {
                Label(
                    integrity.isIntact ? "Sequence editing unlocked" : "\(integrity.changedSequenceCount) sequence(s) changed",
                    systemImage: "lock.open.fill"
                )
                .foregroundStyle(.orange)
                .help(integrity.violations.map(\.message).joined(separator: "\n"))
            } else if integrity.isIntact {
                Label("Integrity verified", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .help(integrity.summary)
            } else {
                Label("Integrity check failed", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                    .help(integrity.violations.map(\.message).joined(separator: "\n"))
            }
            if let issue = document.analysis.validationIssues.first {
                Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                    .lineLimit(1)
                    .help(document.analysis.validationIssues.map(\.message).joined(separator: "\n"))
            } else {
                Label("Valid Stockholm alignment", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text("\(document.analysis.sequenceCount) sequences × \(document.analysis.alignmentLength) columns")
                .foregroundStyle(.secondary)
            Text("\(state.selectedRows.count)×\(state.selectedColumnSet.count) selected")
                .foregroundStyle(.secondary)
            Text(selectionInspectorText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(selectionInspectorText)
            if document.changeSummary.changedCells > 0 {
                Text("\(document.changeSummary.changedCells) changed")
                    .foregroundStyle(.orange)
            }
            Text(state.statusMessage)
                .lineLimit(1)
                .frame(minWidth: 180, alignment: .trailing)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func shift(_ direction: Int) {
        guard !state.selectingConsensus else {
            state.statusMessage = "The calculated R2R consensus row is read-only."
            NSSound.beep()
            return
        }
        if !AlignmentShiftController.shift(
            document: document,
            state: state,
            direction: direction,
            undoManager: undoManager
        ) {
            NSSound.beep()
        }
    }

    private func toggleSequenceEditing() {
        if document.sequenceEditingUnlocked {
            let report = document.integrityReport
            if !report.isIntact {
                let alert = NSAlert()
                alert.messageText = "Sequence data differs from the opened file"
                alert.informativeText = "Locking now will prevent further residue edits and saving will remain blocked until the changes are reverted or sequence editing is unlocked again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Lock Anyway")
                alert.addButton(withTitle: "Keep Unlocked")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            document.sequenceEditingUnlocked = false
            state.statusMessage = "Alignment Integrity mode enabled. Ungapped sequence data is protected."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Unlock biological sequence editing?"
        alert.informativeText = "Gap shifts and structural annotation do not require this. Unlock only when you intentionally need to add, delete, or replace residues; MATER will continue reporting differences from the opened file."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Unlock Sequence Editing")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        document.sequenceEditingUnlocked = true
        state.statusMessage = "Sequence editing unlocked. Ungapped residue changes are now allowed."
    }

    private func suggestAlignmentEdits() {
        suggestedEdits = StemEditSuggester.suggestions(
            in: document.file,
            modelRow: state.selectedRow,
            column: state.selectedColumn,
            preferLinked: state.linkPairedStemShifts
        )
        showingSuggestedEdits = true
        state.statusMessage = suggestedEdits.isEmpty
            ? "No improving adjacent gap shift was found for this sequence and stem."
            : "Found \(suggestedEdits.count) safe gap-shift suggestion\(suggestedEdits.count == 1 ? "" : "s")."
    }

    private func applySuggestedEdit(_ suggestion: StemEditSuggestion) {
        var applied = false
        document.mutate("Apply Suggested Stem Shift", undoManager: undoManager) { file in
            guard file.records.indices.contains(suggestion.recordIndex),
                  file.records[suggestion.recordIndex].aligned == suggestion.expectedAligned else { return }
            applied = file.replaceSequenceGapPlacement(
                recordIndex: suggestion.recordIndex,
                with: suggestion.proposedAligned
            )
        }
        guard applied else {
            state.statusMessage = "The alignment changed and this suggestion is no longer applicable."
            NSSound.beep()
            return
        }
        state.selectColumns(suggestion.primaryDestinationColumns, row: suggestion.modelRow)
        state.statusMessage = "Applied a gap-only stem improvement to \(suggestion.sequenceName). Undo is available."
        showingSuggestedEdits = false
    }

    private func wiggleRefineAlignment() {
        guard !isWiggleRefining, !isCaCoFoldRefining else { return }
        guard !document.analysis.structurePairs.isEmpty else {
            state.statusMessage = "Wiggle-refinement requires at least one recognized SS_cons pair."
            NSSound.beep()
            return
        }
        guard let outputURL = refinementOutputURL(kind: .wiggle) else { return }

        let source = document.file
        let preferLinked = state.linkPairedStemShifts
        isWiggleRefining = true
        wiggleProgress = nil
        state.statusMessage = "Wiggle-refining every sequence and annotated stem… The current alignment remains unchanged."

        wiggleTask = Task {
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try StemEditSuggester.refineEntireAlignmentCancellable(
                        in: source,
                        preferLinked: preferLinked,
                        maximumPasses: 100,
                        shouldCancel: {
                            withUnsafeCurrentTask { $0?.isCancelled ?? false }
                        },
                        progress: { progress in
                            Task { @MainActor in
                                wiggleProgress = progress
                                state.statusMessage = "Wiggle-refine pass \(progress.pass): \(progress.completedRows)/\(progress.totalRows) sequences, \(progress.editCount) accepted edits…"
                            }
                        }
                    )
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                try result.file.rendered.write(to: outputURL, atomically: true, encoding: .utf8)
                isWiggleRefining = false
                wiggleProgress = nil
                wiggleTask = nil
                let convergenceText = result.converged ? "converged" : "reached the 100-pass safety limit"
                state.statusMessage = "Created \(outputURL.lastPathComponent): \(result.editCount) gap edit\(result.editCount == 1 ? "" : "s") across \(result.changedSequenceCount) sequence\(result.changedSequenceCount == 1 ? "" : "s"); \(convergenceText)."
                await openGeneratedStockholm(outputURL)
            } catch is CancellationError {
                isWiggleRefining = false
                wiggleProgress = nil
                wiggleTask = nil
                state.statusMessage = "Wiggle-refine cancelled. The current alignment was not changed and no output was written."
            } catch {
                isWiggleRefining = false
                wiggleProgress = nil
                wiggleTask = nil
                state.statusMessage = "Could not write the refined alignment: \(error.localizedDescription)"
                presentAlert(
                    title: "Could not create the Wiggle-refined alignment",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func caCoFoldRefineStructure() {
        guard !isWiggleRefining, !isCaCoFoldRefining else { return }
        let errors = document.analysis.validationIssues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            let message = "Fix the Stockholm validation errors before running CaCoFold. "
                + errors.prefix(3).map(\.message).joined(separator: " ")
            state.statusMessage = "CaCoFold-refinement requires a valid Stockholm alignment."
            presentAlert(title: "Cannot run CaCoFold-refine", message: message)
            return
        }
        guard !document.analysis.structurePairs.isEmpty else {
            state.statusMessage = "CaCoFold-refinement requires at least one recognized SS_cons pair."
            NSSound.beep()
            return
        }

        let executableURL: URL
        if let located = RScapeExecutableLocator.locate() {
            executableURL = located
        } else {
            guard let selected = chooseRScapeExecutable(
                message: "CaCoFold-refine requires a separately installed R-scape. Select its executable, bin folder, or installation folder."
            ) else {
                state.statusMessage = "CaCoFold-refinement was not started because R-scape is not available."
                return
            }
            executableURL = selected
        }
        UserDefaults.standard.set(executableURL.path, forKey: RScapeExecutableLocator.savedPathKey)
        guard let outputURL = refinementOutputURL(kind: .caCoFold) else { return }

        let stockholmText = document.file.rendered
        isCaCoFoldRefining = true
        state.statusMessage = "R-scape and CaCoFold are improving the given structure… The current alignment remains unchanged."

        Task {
            do {
                let resultText = try await RScapeRunner.refineStructureWithCaCoFold(
                    executableURL: executableURL,
                    stockholmText: stockholmText,
                    processHandle: RScapeProcessHandle()
                )
                try resultText.write(to: outputURL, atomically: true, encoding: .utf8)
                isCaCoFoldRefining = false
                let resultFile = StockholmParser.parse(resultText)
                state.statusMessage = "Created \(outputURL.lastPathComponent) with \(resultFile.structureRows.count) structure layer\(resultFile.structureRows.count == 1 ? "" : "s"). R-scape intermediate files were discarded."
                await openGeneratedStockholm(outputURL)
            } catch {
                isCaCoFoldRefining = false
                state.statusMessage = "CaCoFold-refinement failed: \(error.localizedDescription)"
                presentAlert(
                    title: "CaCoFold-refinement failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func showOrRunRScape() {
        if rScapeController.hasPresentableState {
            rScapeController.isPanelVisible = true
            return
        }
        startRScapeAnalysis()
    }

    private func startRScapeAnalysis() {
        guard !rScapeController.isRunning else {
            rScapeController.isPanelVisible = true
            return
        }
        guard let executableURL = RScapeExecutableLocator.locate() else {
            rScapeController.presentMissingExecutable()
            state.statusMessage = "R-scape was not found in PATH. Use Locate R-scape in the results panel."
            return
        }
        UserDefaults.standard.set(executableURL.path, forKey: RScapeExecutableLocator.savedPathKey)
        startRScapeAnalysis(using: executableURL)
    }

    private func startRScapeAnalysis(using executableURL: URL) {
        let errors = document.analysis.validationIssues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            let message = "Fix the Stockholm validation errors before running R-scape. "
                + errors.prefix(3).map(\.message).joined(separator: " ")
            rScapeController.presentError(NSError(
                domain: "MATER.RScape",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
            state.statusMessage = "R-scape requires a valid Stockholm alignment."
            return
        }
        guard !document.analysis.structurePairs.isEmpty else {
            rScapeController.presentError(NSError(
                domain: "MATER.RScape",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "R-scape’s given-structure test requires at least one recognized SS_cons pair."]
            ))
            return
        }
        guard let outputDirectory = rScapeOutputDirectory() else { return }

        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "MATER-alignment"
        rScapeController.run(
            executableURL: executableURL,
            stockholmText: document.file.rendered,
            outputDirectory: outputDirectory,
            outputName: "\(baseName)-R-scape"
        )
        state.statusMessage = "R-scape is evaluating a snapshot of the given structure."
    }

    private func locateRScape() {
        guard let executableURL = chooseRScapeExecutable(
            message: "Select the R-scape executable, its bin folder, or the R-scape installation folder. MATER will prefer the installed bin copy containing R2R."
        ) else { return }
        startRScapeAnalysis(using: executableURL)
    }

    private func chooseRScapeExecutable(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Locate R-scape"
        panel.message = message
        panel.prompt = "Use R-scape"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if let savedPath = UserDefaults.standard.string(forKey: RScapeExecutableLocator.savedPathKey) {
            panel.directoryURL = URL(fileURLWithPath: savedPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let selectionURL = panel.url else { return nil }
        guard let executableURL = RScapeExecutableLocator.resolveSelection(selectionURL) else {
            presentAlert(
                title: "R-scape is not usable",
                message: RScapeRunError.invalidExecutable(selectionURL.path).localizedDescription
            )
            NSSound.beep()
            return nil
        }
        UserDefaults.standard.set(executableURL.path, forKey: RScapeExecutableLocator.savedPathKey)
        return executableURL
    }

    private func rScapeOutputDirectory() -> URL? {
        let parentDirectory: URL
        let baseName: String
        if let sourceURL {
            parentDirectory = sourceURL.deletingLastPathComponent()
            baseName = sourceURL.deletingPathExtension().lastPathComponent
        } else {
            let panel = NSOpenPanel()
            panel.title = "Choose R-scape Results Location"
            panel.message = "MATER will create a new results folder in the selected directory."
            panel.prompt = "Choose"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let selectedDirectory = panel.url else { return nil }
            parentDirectory = selectedDirectory
            baseName = "MATER-alignment"
        }

        let fileManager = FileManager.default
        var suffix = ""
        var counter = 2
        while true {
            let candidate = parentDirectory.appendingPathComponent(
                "\(baseName)-MATER-R-scape\(suffix)",
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            suffix = "-\(counter)"
            counter += 1
        }
    }

    private func refinementOutputURL(kind: AlignmentRefinementKind) -> URL? {
        guard let sourceURL else {
            let panel = NSSavePanel()
            panel.title = kind.savePanelTitle
            panel.prompt = kind.savePanelPrompt
            panel.allowedContentTypes = [.stockholmAlignment]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(kind.filenameStem).sto"
            return panel.runModal() == .OK ? panel.url : nil
        }

        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let sourceExtension = sourceURL.pathExtension.isEmpty ? "sto" : sourceURL.pathExtension
        var suffix = ""
        var counter = 2
        while true {
            let filename = "\(baseName)-\(kind.filenameStem)\(suffix).\(sourceExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            suffix = "-\(counter)"
            counter += 1
        }
    }

    private func openGeneratedStockholm(_ url: URL) async {
        do {
            try await openDocument(at: url)
        } catch {
            state.statusMessage += " The file was saved, but MATER could not open it automatically."
            presentAlert(
                title: "The refined alignment was saved",
                message: "MATER could not open \(url.lastPathComponent) automatically. Open it with File → Open.\n\n\(error.localizedDescription)"
            )
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func allowInvalidSave() {
        let alert = NSAlert()
        alert.messageText = "Allow saving an invalid Stockholm alignment?"
        alert.informativeText = "The file currently has \(validationErrors.count) validation error\(validationErrors.count == 1 ? "" : "s"). Saving it may make downstream RNA tools reject it or interpret it incorrectly. Prefer correcting the errors or saving a separate copy."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Allow Invalid Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        document.invalidSavingUnlocked = true
        state.statusMessage = "Invalid-file saving allowed for this document. Restore protection from the warning banner when finished."
    }

    private func copyDiagnostics() {
        let diagnostics = MATERDiagnostics.report(document: document, sourceURL: sourceURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        state.statusMessage = "Copied privacy-safe MATER diagnostics; no sequence or annotation contents were included."
    }

    private var selectionInspectorText: String {
        if state.selectingConsensus {
            let columns = state.orderedSelectedColumns
            let columnText = columns.count == 1
                ? "col \((columns.first ?? 0) + 1)"
                : "cols \((columns.first ?? 0) + 1)–\((columns.last ?? 0) + 1)"
            return "R2R consensus • \(columnText)"
        }
        let rowLabels = state.selectedRows.compactMap { document.analysis.rows.indices.contains($0) ? document.analysis.rows[$0].label : nil }
        let rowText = rowLabels.count <= 1 ? (rowLabels.first ?? "row") : "\(rowLabels.first ?? "row")…\(rowLabels.last ?? "row")"
        let columns = state.orderedSelectedColumns
        let columnText: String
        if columns.count == 1 {
            columnText = "col \((columns.first ?? 0) + 1)"
        } else if state.specialColumns.isEmpty {
            columnText = "cols \((columns.first ?? 0) + 1)–\((columns.last ?? 0) + 1)"
        } else {
            columnText = "\(columns.count) paired/stem cols (\((columns.first ?? 0) + 1)–\((columns.last ?? 0) + 1))"
        }
        var pieces = [rowText, columnText]
        if let pair = document.analysis.structurePairs.first(where: { $0.left == state.selectedColumn || $0.right == state.selectedColumn }) {
            let partner = pair.left == state.selectedColumn ? pair.right : pair.left
            pieces.append("pair \(partner + 1)")
        }
        let column = state.selectedColumn
        let entropy = document.analysis.entropyByColumn
        if entropy.indices.contains(column) { pieces.append(String(format: "H %.2f", entropy[column])) }
        let gaps = document.analysis.gapFrequencyByColumn
        if gaps.indices.contains(column) { pieces.append(String(format: "gaps %.0f%%", gaps[column] * 100)) }
        return pieces.joined(separator: " • ")
    }

    private func jumpToPair() {
        guard let pair = document.analysis.structurePairs.first(where: { $0.left == state.selectedColumn || $0.right == state.selectedColumn }) else {
            state.statusMessage = "The selected column is not paired in any SS_cons layer."
            NSSound.beep()
            return
        }
        let destination = pair.left == state.selectedColumn ? pair.right : pair.left
        select(row: state.selectedRow, column: destination)
        state.statusMessage = "Jumped to column \(destination + 1) in \(pair.structureTag)."
    }

    private func handleShortcut(_ action: EditorShortcutAction) {
        switch action {
        case .moveLeft: shift(-1)
        case .moveRight: shift(1)
        case .pushLeft: pushToEdge(-1)
        case .pushRight: pushToEdge(1)
        case .insertColumn: insertGapColumn()
        case .deleteColumn: deleteGapColumn()
        case .removeAllGapColumns: removeAllGapColumns()
        case .openRowGap: openGap()
        case .closeRowGap: closeGap()
        case .jumpPair: jumpToPair()
        case .clearCells: clearSelectedCells()
        case .fastLeft: moveSelection(rowDelta: 0, columnDelta: -10)
        case .fastRight: moveSelection(rowDelta: 0, columnDelta: 10)
        case .fastUp: moveSelection(rowDelta: -10, columnDelta: 0)
        case .fastDown: moveSelection(rowDelta: 10, columnDelta: 0)
        case .findForward:
            if searchText.isEmpty { searchFieldFocused = true } else { findNext() }
        case .findReverse:
            if searchText.isEmpty { searchFieldFocused = true } else { findPrevious() }
        case .gotoRow: promptForLocation(isRow: true)
        case .gotoColumn: promptForLocation(isRow: false)
        case .justifyLeft: justifySelection(towardRight: false)
        case .justifyRight: justifySelection(towardRight: true)
        case .transpose: transposeSelection(direction: 1)
        case .structureColors: state.colorMode = .stem
        case .pairVariationColors: state.colorMode = .covariation
        case .residueColors: state.colorMode = .residue
        case .fontIncrease: state.fontSize = min(23, state.fontSize + 1)
        case .fontDecrease: state.fontSize = max(11, state.fontSize - 1)
        case .copy: copySelectedCells()
        case .paste: pasteSelectedCells()
        case .selectAll: selectAllAlignment()
        case .undo: undoManager?.undo()
        case .redo: undoManager?.redo()
        case .alignmentStatistics: showAlignmentStatistics()
        case .detectProblems: showAlignmentAudit()
        case .permuteColumns: confirmPermute()
        case .foldHairpin: foldHairpin()
        case .writeConsensus: writeConsensus()
        }
    }

    private func moveSelection(rowDelta: Int, columnDelta: Int) {
        let row = max(0, min(state.selectedRow + rowDelta, max(0, document.analysis.rows.count - 1)))
        let column = max(0, min(state.selectedColumn + columnDelta, max(0, document.file.alignmentLength - 1)))
        select(row: row, column: column)
        state.statusMessage = "Row \(row + 1), column \(column + 1)."
    }

    private func pushToEdge(_ direction: Int) {
        if AlignmentShiftController.shiftToEdge(document: document, state: state, direction: direction, undoManager: undoManager) == 0 {
            NSSound.beep()
        }
    }

    private func justifySelection(towardRight: Bool) {
        let rows = Set(state.selectedRows.filter {
            document.analysis.rows.indices.contains($0) && document.analysis.rows[$0].kind.isSequence
        })
        var changed = false
        document.mutate(towardRight ? "Right-justify Residues" : "Left-justify Residues", undoManager: undoManager) { file in
            changed = file.justify(rows: rows, columns: state.selectedColumnBounds, towardRight: towardRight)
        }
        state.statusMessage = changed
            ? "\(towardRight ? "Right" : "Left")-justified residues in the selected window."
            : "Nothing moved; select sequence rows and a window containing both residues and gaps."
        if !changed { NSSound.beep() }
    }

    private func transposeSelection(direction: Int) {
        var changed = false
        document.mutate("Transpose Residue and Gap", undoManager: undoManager) { file in
            changed = file.transposeGap(row: state.selectedRow, column: state.selectedColumn, direction: direction)
        }
        if changed {
            state.select(row: state.selectedRow, column: state.selectedColumn + direction)
            state.statusMessage = "Transposed the residue with its neighboring gap."
        } else {
            state.statusMessage = "Transpose requires one residue and one adjacent gap."
            NSSound.beep()
        }
    }

    private func clearSelectedCells() {
        guard !state.selectingConsensus else { NSSound.beep(); return }
        let rows = state.selectedRows.filter { document.analysis.rows.indices.contains($0) }
        let columns = state.selectedColumnSet
        let deletesResidue = rows.contains { row in
            document.analysis.rows[row].kind.isSequence && columns.contains { column in
                document.file.character(row: row, column: column).map { !AlignmentSymbol.isSequenceGap($0) } ?? false
            }
        }
        guard !deletesResidue || document.sequenceEditingUnlocked else {
            state.statusMessage = "Alignment Integrity mode blocked residue deletion. Move residues with gaps, or unlock sequence editing."
            NSSound.beep()
            return
        }
        document.mutate("Clear Selected Cells", undoManager: undoManager) { file in
            for row in rows {
                let kind = document.analysis.rows[row].kind
                if kind.isStructure { file.clearPairs(touching: columns, recordIndex: document.analysis.rows[row].recordIndex) }
                let fill: Character = kind.isSequence ? "-" : "."
                for column in columns { file.replaceCharacter(row: row, column: column, with: fill) }
            }
        }
        state.statusMessage = "Cleared the selected cells."
    }

    private func selectAllAlignment() {
        let sequenceRows = document.analysis.rows.indices.filter { document.analysis.rows[$0].kind.isSequence }
        guard let first = sequenceRows.first, let last = sequenceRows.last else { return }
        state.anchorRow = first
        state.selectedRow = last
        state.anchorColumn = 0
        state.selectedColumn = max(0, document.file.alignmentLength - 1)
        state.specialColumns = []
        state.statusMessage = "Selected the complete sequence alignment."
    }

    private func copySelectedCells() {
        let columns = state.orderedSelectedColumns
        let rows = state.selectedRows.filter { document.analysis.rows.indices.contains($0) }
        let text = rows.map { row -> String in
            let characters = Array(document.file.records[document.analysis.rows[row].recordIndex].aligned)
            return String(columns.compactMap { characters.indices.contains($0) ? characters[$0] : nil })
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.statusMessage = "Copied \(rows.count) row(s) × \(columns.count) column(s)."
    }

    private func pasteSelectedCells() {
        guard let source = NSPasteboard.general.string(forType: .string) else { NSSound.beep(); return }
        let lines = source.components(separatedBy: .newlines).map { $0.filter { !$0.isWhitespace } }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        let rows = Array(state.selectedRows.filter { document.analysis.rows.indices.contains($0) })
        var candidate = document.file
        for (offset, line) in lines.enumerated() {
            let row = lines.count == 1 ? state.selectedRow : (rows.indices.contains(offset) ? rows[offset] : -1)
            guard document.analysis.rows.indices.contains(row) else { continue }
            candidate.replaceCharacters(row: row, startingAt: state.selectedColumnBounds.lowerBound, with: line)
        }
        if rows.contains(where: { document.analysis.rows[$0].kind.isStructure }),
           StructureParser.validationIssues(in: candidate).contains(where: { $0.severity == .error }) {
            state.statusMessage = "Paste blocked: structure text must contain complete, balanced WUSS pairs."
            NSSound.beep()
            return
        }
        document.mutate("Paste", undoManager: undoManager) { $0 = candidate }
        state.statusMessage = "Pasted alignment cells."
    }

    private func selectStem() {
        guard let pair = document.analysis.structurePairs.first(where: { $0.left == state.selectedColumn || $0.right == state.selectedColumn }) else {
            state.statusMessage = "The selected column is not part of a defined stem."
            NSSound.beep()
            return
        }
        let columns = Set(document.analysis.structurePairs.filter { $0.stem == pair.stem }.flatMap { [$0.left, $0.right] })
        state.selectColumns(columns, row: state.selectedRow)
        state.statusMessage = "Selected stem \(pair.stem + 1): \(columns.count) paired columns."
    }

    private func setPair() {
        guard let left = state.selectedColumnSet.min(), let right = state.selectedColumnSet.max(), left < right else { return }
        document.mutate("Set Structural Pair", undoManager: undoManager) { file in
            file.setPair(left: left, right: right, layer: state.pairingLayer)
        }
        state.statusMessage = "Paired columns \(left + 1) and \(right + 1) in \(state.pairingLayer.tag)."
    }

    private func clearPair() {
        let selected = state.selectedColumnSet
        document.mutate("Remove Structural Pair", undoManager: undoManager) { file in
            file.clearPairs(touching: selected)
        }
        state.statusMessage = "Removed structural pairs touching the selection."
    }

    private func insertGapColumn() {
        let column = state.selectedColumnBounds.lowerBound
        document.mutate("Insert Gap Column", undoManager: undoManager) { file in
            file.insertColumn(at: column)
        }
        state.statusMessage = "Inserted a gap column before column \(column + 1)."
    }

    private func deleteGapColumn() {
        let column = state.selectedColumn
        var deleted = false
        document.mutate("Delete Gap Column", undoManager: undoManager) { file in
            deleted = file.deleteColumn(at: column)
        }
        if deleted {
            state.clamp(rowCount: document.analysis.rows.count, alignmentLength: document.analysis.alignmentLength)
            state.statusMessage = "Deleted all-gap column \(column + 1)."
        } else {
            state.statusMessage = "Column \(column + 1) contains sequence residues and was not deleted."
            NSSound.beep()
        }
    }

    private func removeAllGapColumns() {
        let priorColumn = state.selectedColumn
        var removedColumns: [Int] = []
        document.mutate("Remove All Empty Columns", undoManager: undoManager) { file in
            removedColumns = file.removeAllGapColumns()
        }
        guard !removedColumns.isEmpty else {
            state.statusMessage = "No all-gap columns were found."
            return
        }

        let columnsBeforeSelection = removedColumns.lazy.filter { $0 < priorColumn }.count
        select(row: state.selectedRow, column: max(0, priorColumn - columnsBeforeSelection))
        state.clamp(rowCount: document.analysis.rows.count, alignmentLength: document.analysis.alignmentLength)
        state.statusMessage = "Removed \(removedColumns.count) all-gap column\(removedColumns.count == 1 ? "" : "s")."
    }

    private func openGap() {
        guard !state.selectingConsensus else {
            state.statusMessage = "The calculated R2R consensus row is read-only."
            NSSound.beep()
            return
        }
        var changed = false
        document.mutate("Open Gap", undoManager: undoManager) { file in
            changed = file.openGap(row: state.selectedRow, at: state.selectedColumn)
        }
        state.statusMessage = changed ? "Opened a gap before column \(state.selectedColumn + 1)." : "A downstream gap is required to open space here."
        if !changed { NSSound.beep() }
    }

    private func closeGap() {
        guard !state.selectingConsensus else {
            state.statusMessage = "The calculated R2R consensus row is read-only."
            NSSound.beep()
            return
        }
        var changed = false
        document.mutate("Close Gap", undoManager: undoManager) { file in
            changed = file.closeGap(row: state.selectedRow, at: state.selectedColumn)
        }
        state.statusMessage = changed ? "Closed the selected gap." : "Select a gap that has residues to its right."
        if !changed { NSSound.beep() }
    }

    private func findNext() {
        guard let match = AlignmentSearch.find(searchText, in: document.file, afterRow: state.selectedRow, afterColumn: state.selectedColumn) else {
            state.statusMessage = "No match for “\(searchText)”."
            NSSound.beep()
            return
        }
        select(row: match.row, column: match.column)
        state.statusMessage = "Found \(match.message)."
    }

    private func findPrevious() {
        guard let match = AlignmentSearch.findBackward(
            searchText,
            in: document.file,
            beforeRow: state.selectedRow,
            beforeColumn: state.selectedColumn
        ) else {
            state.statusMessage = "No previous match for “\(searchText)”."
            NSSound.beep()
            return
        }
        select(row: match.row, column: match.column)
        state.statusMessage = "Found \(match.message)."
    }

    private func promptForLocation(isRow: Bool) {
        let maximum = isRow ? document.analysis.rows.count : document.file.alignmentLength
        let alert = NSAlert()
        alert.messageText = isRow ? "Go to alignment row" : "Go to alignment column"
        alert.informativeText = "Enter a 1-based number from 1 to \(max(1, maximum))."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: String((isRow ? state.selectedRow : state.selectedColumn) + 1))
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let value = Int(field.stringValue), value >= 1, value <= maximum else { return }
        select(
            row: isRow ? value - 1 : state.selectedRow,
            column: isRow ? state.selectedColumn : value - 1
        )
    }

    private func writeConsensus() {
        let replacement = ConsensusAnalyzer.consensus(in: document.file)
        if let existing = document.file.records.first(where: {
            if case .columnAnnotation(let tag) = $0.kind { return tag.caseInsensitiveCompare("cons") == .orderedSame }
            return false
        }), existing.aligned != replacement {
            let alert = NSAlert()
            alert.messageText = "Replace the existing #=GC cons row?"
            alert.informativeText = "MATER will replace it with the calculated GSC/R2R consensus. Undo remains available."
            alert.addButton(withTitle: "Replace Consensus")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        document.mutate("Write R2R Consensus", undoManager: undoManager) { $0.writeConsensusAnnotation() }
        state.statusMessage = "Wrote the calculated GSC/R2R consensus to #=GC cons."
    }

    private func foldHairpin() {
        let columns = state.selectedColumnBounds
        let replacedPairCount = document.analysis.structurePairs.filter {
            $0.structureTag == state.pairingLayer.tag && (columns.contains($0.left) || columns.contains($0.right))
        }.count
        if replacedPairCount > 0 {
            let alert = NSAlert()
            alert.messageText = "Replace \(replacedPairCount) existing pair\(replacedPairCount == 1 ? "" : "s") in this layer?"
            alert.informativeText = "The selected interval will become a nested hairpin in \(state.pairingLayer.tag). Other structure layers are unchanged. Undo remains available."
            alert.addButton(withTitle: "Fold Hairpin")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        var count = 0
        document.mutate("Fold Selection as Hairpin", undoManager: undoManager) { file in
            count = file.foldHairpin(columns: columns, layer: state.pairingLayer)
        }
        state.statusMessage = count > 0
            ? "Annotated a \(count)-pair hairpin in \(state.pairingLayer.tag)."
            : "Select at least four columns to fold a hairpin."
        if count == 0 { NSSound.beep() }
    }

    private func confirmPermute() {
        guard state.selectedColumn > 0 else {
            state.statusMessage = "Choose a column after column 1 as the new alignment start."
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Permute alignment around column \(state.selectedColumn + 1)?"
        alert.informativeText = "Every sequence and annotation row will rotate together. The edit is rejected if a structure pair would cross the new boundary. Undo remains available."
        alert.addButton(withTitle: "Permute")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let column = state.selectedColumn
        var changed = false
        document.mutate("Permute Alignment", undoManager: undoManager) { file in
            changed = file.permuteColumns(around: column)
        }
        if changed {
            state.select(row: state.selectedRow, column: 0)
            state.statusMessage = "Permuted the alignment; former column \(column + 1) is now column 1."
        } else {
            state.statusMessage = "Permutation blocked because it would split a structure pair across the alignment boundary."
            NSSound.beep()
        }
    }

    private func showAlignmentStatistics() {
        let file = document.file
        let sequenceCount = file.sequenceRows.count
        let length = file.alignmentLength
        let gaps = GapAnalyzer.columnGapFrequencies(in: file)
        let entropy = EntropyAnalyzer.columnEntropies(in: file)
        let meanGap = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count)
        let meanEntropy = entropy.isEmpty ? 0 : entropy.reduce(0, +) / Double(entropy.count)
        let residues = file.sequenceRows.reduce(0) { partial, row in
            partial + file.records[row.recordIndex].aligned.filter { !AlignmentSymbol.isSequenceGap($0) }.count
        }
        let alert = NSAlert()
        alert.messageText = "Alignment statistics"
        alert.informativeText = """
        Sequences: \(sequenceCount)
        Alignment columns: \(length)
        Ungapped residues: \(residues)
        Defined base pairs: \(document.analysis.structurePairs.count)
        Mean gap frequency: \(String(format: "%.1f%%", meanGap * 100))
        Mean sequence entropy: \(String(format: "%.3f bits", meanEntropy))
        Validation issues: \(document.analysis.validationIssues.count)
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showAlignmentAudit() {
        let file = document.file
        let grouped = Dictionary(grouping: file.sequenceRows) { file.records[$0.recordIndex].aligned.uppercased() }
        let duplicateGroups = grouped.values.filter { $0.count > 1 }
        let duplicateNames = duplicateGroups.map { group in group.map(\.label).joined(separator: ", ") }
        let errors = file.validationIssues.filter { $0.severity == .error }.map(\.message)
        let body: String
        if duplicateNames.isEmpty && errors.isEmpty {
            body = "No identical aligned sequences or Stockholm consistency errors were found."
        } else {
            let duplicates = duplicateNames.isEmpty ? "No identical aligned sequences." : "Identical aligned sequences:\n• " + duplicateNames.joined(separator: "\n• ")
            let inconsistencies = errors.isEmpty ? "No consistency errors." : "Consistency errors:\n• " + errors.joined(separator: "\n• ")
            body = duplicates + "\n\n" + inconsistencies
        }
        let alert = NSAlert()
        alert.messageText = "Alignment integrity report"
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func deleteMatchingSequences() {
        guard document.sequenceEditingUnlocked else {
            state.statusMessage = "Sequence deletion requires explicitly unlocking Alignment Integrity mode."
            NSSound.beep()
            return
        }
        let columns = state.selectedColumnSet
        let rowsByRecord = Dictionary(uniqueKeysWithValues: document.analysis.rows.enumerated().map { ($0.element.recordIndex, $0.offset) })
        let matches = Set(document.file.sequenceRows.compactMap { row -> Int? in
            let characters = Array(document.file.records[row.recordIndex].aligned)
            let matched = columns.contains { column in
                guard characters.indices.contains(column) else { return true }
                let character = Character(String(characters[column]).uppercased())
                return AlignmentSymbol.isSequenceGap(character) || !"ACGUT".contains(character)
            }
            return matched ? rowsByRecord[row.recordIndex] : nil
        })
        guard !matches.isEmpty, matches.count < document.file.sequenceRows.count else {
            state.statusMessage = matches.isEmpty
                ? "No sequence has a gap or ambiguity in the selected columns."
                : "Deletion blocked because it would remove every sequence."
            NSSound.beep()
            return
        }
        let names = matches.sorted().map { document.analysis.rows[$0].label }
        let preview = names.prefix(12).joined(separator: "\n") + (names.count > 12 ? "\n…and \(names.count - 12) more" : "")
        let alert = NSAlert()
        alert.messageText = "Delete \(names.count) matching sequence\(names.count == 1 ? "" : "s")?"
        alert.informativeText = "The following sequences contain a gap or ambiguity in at least one selected column:\n\n\(preview)\n\nAttached #=GR rows will be removed too. Undo remains available."
        alert.addButton(withTitle: "Delete Sequences")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var removed: [String] = []
        document.mutate("Delete Matching Sequences", undoManager: undoManager) { file in
            removed = file.removeSequences(modelRows: matches)
        }
        state.clamp(to: document.file)
        state.statusMessage = "Deleted \(removed.count) sequence\(removed.count == 1 ? "" : "s") and attached annotations."
    }

    private func toggleColumnBookmark() {
        let column = state.selectedColumn
        if state.columnBookmarks.contains(column) {
            state.columnBookmarks.remove(column)
            state.statusMessage = "Removed bookmark at column \(column + 1)."
        } else {
            state.columnBookmarks.insert(column)
            state.statusMessage = "Bookmarked column \(column + 1) for this editing session."
        }
    }

    private func nextColumnBookmark() {
        let sorted = state.columnBookmarks.sorted()
        guard let next = sorted.first(where: { $0 > state.selectedColumn }) ?? sorted.first else { return }
        select(row: state.selectedRow, column: next)
        state.statusMessage = "Jumped to bookmarked column \(next + 1)."
    }

    private func navigateToProblem(_ kind: AlignmentProblemKind?) {
        guard let problem = AlignmentProblemAnalyzer.next(
            kind: kind,
            in: document.file,
            afterRow: state.selectedRow,
            afterColumn: state.selectedColumn,
            entropyThreshold: state.entropyThreshold,
            gapThreshold: state.gapThreshold
        ) else {
            state.statusMessage = kind.map { "No \($0.rawValue.lowercased()) problems found." } ?? "No analysis problems found."
            NSSound.beep()
            return
        }
        select(row: problem.row, column: problem.column)
        state.statusMessage = problem.message
    }

    private func select(row: Int, column: Int) {
        let wholeColumn = document.analysis.rows.indices.contains(row)
            && document.analysis.rows[row].kind.selectsWholeColumn
        state.select(row: row, column: column, wholeColumn: wholeColumn)
    }

    private func revertSelectedRegion() {
        let count = document.restoreBaselineSelection(
            rows: Set(state.selectedRows),
            columns: state.selectedColumnSet,
            undoManager: undoManager
        )
        state.statusMessage = count > 0 ? "Reverted \(count) selected cells to the opened file." : "No matching baseline cells could be restored."
        if count == 0 { NSSound.beep() }
    }

    private func revertSelectedRows() {
        let count = document.restoreBaselineRows(Set(state.selectedRows), undoManager: undoManager)
        state.statusMessage = count > 0 ? "Reverted \(count) row\(count == 1 ? "" : "s") to the opened file." : "Rows can only be restored when their original width matches the current alignment."
        if count == 0 { NSSound.beep() }
    }

    private func createRecoverySnapshot() {
        if let url = document.createRecoverySnapshot() {
            state.statusMessage = "Created recovery snapshot \(url.lastPathComponent)."
        } else {
            state.statusMessage = "Could not create a recovery snapshot."
            NSSound.beep()
        }
    }

    private func restoreRecoverySnapshot() {
        if document.restoreLatestRecovery(undoManager: undoManager) {
            state.clamp(to: document.file)
            state.statusMessage = "Restored the latest recovery snapshot. Undo is available."
        } else {
            state.statusMessage = "No different recovery snapshot is available."
            NSSound.beep()
        }
    }

    private func beginExport(_ format: AlignmentExportFormat) {
        exportConfiguration = AlignmentExportConfiguration()
        pendingExportFormat = format
    }

    private func exportAlignment(_ format: AlignmentExportFormat, configuration: AlignmentExportConfiguration) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "MATER-alignment.\(format.pathExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = "Exports the full alignment using the current colors and display options."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let residueColors = AlignmentResidueColors(
                adenine: residuePalette.adenine,
                cytosine: residuePalette.cytosine,
                guanine: residuePalette.guanine,
                uracil: residuePalette.uracil
            )
            var options = AlignmentExportOptions(
                title: configuration.title,
                includeLegend: configuration.includeLegend,
                numberingInterval: configuration.numberingInterval,
                labelWidth: configuration.labelWidth,
                tiledPDF: format == .pdf && configuration.tiledPDF
            )
            if configuration.selectedRowsOnly { options.selectedRows = Set(state.selectedRows) }
            if configuration.selectedColumnsOnly { options.selectedColumns = state.selectedColumnBounds }
            let exportData = AlignmentExporter.data(
                format: format,
                file: document.file,
                colorMode: state.colorMode,
                residueColors: residueColors,
                hidePosteriorProbability: state.hidePosteriorProbability,
                showEntropy: state.showEntropyPlot,
                showGap: state.showGapPlot,
                showConsensus: state.showConsensus,
                showGrid: state.showGrid,
                fontSize: state.fontSize,
                options: options
            )
            do {
                try exportData.write(to: url, options: .atomic)
                state.statusMessage = "Exported \(url.lastPathComponent)."
            } catch {
                state.statusMessage = "Export failed: \(error.localizedDescription)"
                NSAlert(error: error).runModal()
            }
        }
    }
}

private struct LegendSwatch: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
