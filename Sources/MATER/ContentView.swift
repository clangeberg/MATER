import AppKit
import SwiftUI

struct DocumentEditorView: View {
    @ObservedObject var document: StockholmDocument
    let sourceURL: URL?
    @StateObject private var state = EditorState()
    @StateObject private var residuePalette = ResiduePaletteSettings()
    @State private var searchText = ""
    @State private var pendingExportFormat: AlignmentExportFormat?
    @State private var exportConfiguration = AlignmentExportConfiguration()
    @State private var suggestedEdits: [StemEditSuggestion] = []
    @State private var showingSuggestedEdits = false
    @State private var isAutoRefining = false
    @StateObject private var rScapeController = RScapeController()
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
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
    }

    private var controls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Picker("Color", selection: $state.colorMode) {
                    ForEach(AlignmentColorMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .frame(width: 445)
                .help("Switch among individual stems, topology-derived major elements, descriptive pair variation, nucleotide identity, and uncolored views.")

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
                } label: {
                    Label("View & columns", systemImage: "slider.horizontal.3")
                }
            }

            HStack(spacing: 10) {
                Button(action: { shift(-1) }) { Label("Shift left", systemImage: "arrow.left") }
                    .help("Shift the selected block left into an adjacent gap (Option–Left Arrow).")
                Button(action: { shift(1) }) { Label("Shift right", systemImage: "arrow.right") }
                    .help("Shift the selected block right into an adjacent gap (Option–Right Arrow).")
                Toggle(isOn: $state.linkPairedStemShifts) {
                    Label("Link stem arms", systemImage: "link")
                }
                .toggleStyle(.button)
                .help("When shifting one stem arm, move its paired arm one column in the opposite direction to keep the helix in register.")
                Button(action: openGap) { Label("Open gap", systemImage: "arrow.right.to.line") }
                    .help("Open a gap before the cursor while consuming the next gap (Control–G).")
                Button(action: closeGap) { Label("Close gap", systemImage: "arrow.left.to.line") }
                    .help("Close the selected gap and pull the following block left (Control–Shift–G).")
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
                Button(action: suggestAlignmentEdits) {
                    Label("Suggest fixes", systemImage: "wand.and.stars")
                }
                .disabled(state.selectingConsensus || !document.analysis.rows.indices.contains(state.selectedRow) || !document.analysis.rows[state.selectedRow].kind.isSequence)
                .help("Preview gap-only shifts that improve the selected sequence's current stem.")
                Button(action: autoRefineAlignmentCopy) {
                    if isAutoRefining {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("Refining…")
                        }
                    } else {
                        Label("Auto-refine copy", systemImage: "sparkles")
                    }
                }
                .disabled(isAutoRefining || document.analysis.structurePairs.isEmpty)
                .help("Create and open a new alignment after automatically applying safe helix-window and neighboring gap refinements to convergence. The current file is not changed.")
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
                .disabled(document.analysis.structurePairs.isEmpty)
                .help("Evaluate the current given SS_cons structure with an installed R-scape `-s` test and show the R2R result in a closable panel.")
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
                    Toggle("Highlight changes from opened file", isOn: $state.showChanges)
                    Button("Revert selected region", action: revertSelectedRegion)
                    Button("Revert selected rows", action: revertSelectedRows)
                    Divider()
                    Button("Create recovery snapshot", action: createRecoverySnapshot)
                    Button("Restore latest recovery snapshot", action: restoreRecoverySnapshot)
                        .disabled(document.recoverySnapshotCount == 0)
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

                Spacer()

                TextField("Name, motif, or col:123", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .focused($searchFieldFocused)
                    .onSubmit(findNext)

                Text("Shift–arrows select rectangle • Option–←/→ shifts • ⌃G opens gap")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
                Text("Canonical pairs in nested or crossing stems are colored together as topology-derived major elements.")
                    .foregroundStyle(.secondary)
            case .residue:
                LegendSwatch(color: Color(nsColor: residuePalette.adenine), label: "A")
                LegendSwatch(color: Color(nsColor: residuePalette.cytosine), label: "C")
                LegendSwatch(color: Color(nsColor: residuePalette.guanine), label: "G")
                LegendSwatch(color: Color(nsColor: residuePalette.uracil), label: "U/T")
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
            file.records[suggestion.recordIndex].aligned = suggestion.proposedAligned
            applied = true
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

    private func autoRefineAlignmentCopy() {
        guard !isAutoRefining else { return }
        guard !document.analysis.structurePairs.isEmpty else {
            state.statusMessage = "Auto-refinement requires at least one recognized SS_cons pair."
            NSSound.beep()
            return
        }
        guard let outputURL = autoRefinementOutputURL() else { return }

        let source = document.file
        let preferLinked = state.linkPairedStemShifts
        isAutoRefining = true
        state.statusMessage = "Auto-refining every sequence and annotated stem… The current alignment remains unchanged."

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                StemEditSuggester.refineEntireAlignment(
                    in: source,
                    preferLinked: preferLinked,
                    maximumPasses: 100
                )
            }.value

            do {
                try result.file.rendered.write(to: outputURL, atomically: true, encoding: .utf8)
                isAutoRefining = false
                let convergenceText = result.converged ? "converged" : "reached the 100-pass safety limit"
                state.statusMessage = "Created \(outputURL.lastPathComponent): \(result.editCount) gap edit\(result.editCount == 1 ? "" : "s") across \(result.changedSequenceCount) sequence\(result.changedSequenceCount == 1 ? "" : "s"); \(convergenceText)."
                NSWorkspace.shared.open(outputURL)
            } catch {
                isAutoRefining = false
                state.statusMessage = "Could not write the refined alignment: \(error.localizedDescription)"
                let alert = NSAlert()
                alert.messageText = "Could not create the refined alignment"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
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
        let panel = NSOpenPanel()
        panel.title = "Locate R-scape"
        panel.message = "Select the R-scape executable, its bin folder, or the R-scape installation folder. MATER will prefer the installed bin copy containing R2R."
        panel.prompt = "Use R-scape"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if let savedPath = UserDefaults.standard.string(forKey: RScapeExecutableLocator.savedPathKey) {
            panel.directoryURL = URL(fileURLWithPath: savedPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let selectionURL = panel.url else { return }
        guard let executableURL = RScapeExecutableLocator.resolveSelection(selectionURL) else {
            rScapeController.presentError(RScapeRunError.invalidExecutable(selectionURL.path))
            NSSound.beep()
            return
        }
        UserDefaults.standard.set(executableURL.path, forKey: RScapeExecutableLocator.savedPathKey)
        startRScapeAnalysis(using: executableURL)
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

    private func autoRefinementOutputURL() -> URL? {
        guard let sourceURL else {
            let panel = NSSavePanel()
            panel.title = "Save Auto-Refined Alignment"
            panel.prompt = "Refine and Save"
            panel.allowedContentTypes = [.stockholmAlignment]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "MATER-refined.sto"
            return panel.runModal() == .OK ? panel.url : nil
        }

        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let sourceExtension = sourceURL.pathExtension.isEmpty ? "sto" : sourceURL.pathExtension
        var suffix = ""
        var counter = 2
        while true {
            let filename = "\(baseName)-MATER-refined\(suffix).\(sourceExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            suffix = "-\(counter)"
            counter += 1
        }
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
        if let pair = StructureParser.pair(at: state.selectedColumn, in: document.file) {
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
        guard let pair = StructureParser.pair(at: state.selectedColumn, in: document.file) else {
            state.statusMessage = "The selected column is not paired in any SS_cons layer."
            NSSound.beep()
            return
        }
        let destination = pair.left == state.selectedColumn ? pair.right : pair.left
        select(row: state.selectedRow, column: destination)
        state.statusMessage = "Jumped to column \(destination + 1) in \(pair.structureTag)."
    }

    private func selectStem() {
        guard let pair = StructureParser.pair(at: state.selectedColumn, in: document.file) else {
            state.statusMessage = "The selected column is not part of a defined stem."
            NSSound.beep()
            return
        }
        let columns = Set(StructureParser.pairs(in: document.file).filter { $0.stem == pair.stem }.flatMap { [$0.left, $0.right] })
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
