import AppKit
import SwiftUI

struct AlignmentCanvas: NSViewRepresentable {
    @ObservedObject var document: StockholmDocument
    @ObservedObject var state: EditorState
    @ObservedObject var residuePalette: ResiduePaletteSettings

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        let canvas = AlignmentCanvasView()
        scrollView.documentView = canvas
        canvas.configure(document: document, state: state, residuePalette: residuePalette)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let canvas = scrollView.documentView as? AlignmentCanvasView else { return }
        state.clamp(rowCount: document.analysis.rows.count, alignmentLength: document.analysis.alignmentLength)
        canvas.configure(document: document, state: state, residuePalette: residuePalette)
    }
}

@MainActor
final class AlignmentCanvasView: NSView {
    private struct DisplayRow {
        let modelIndex: Int
        let row: AlignmentRow
        let characters: [Character]
    }

    private weak var document: StockholmDocument?
    private weak var state: EditorState?
    private weak var residuePalette: ResiduePaletteSettings?
    private var dragging = false

    private var font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
    private var cellWidth: CGFloat = 11
    private var rowHeight: CGFloat = 24
    private var headerHeight: CGFloat = 37
    private var labelWidth: CGFloat = 220
    private var alignmentLength = 0
    private var displayRows: [DisplayRow] = []
    private var displayIndexByModelRow: [Int: Int] = [:]
    private var pairs: [BasePair] = []
    private var partnersByColumn: [Int: [Int]] = [:]
    private var stemByColumn: [Int: Int] = [:]
    private var stemPairByColumn: [Int: BasePair] = [:]
    private var canonicalStemColumnsByRecord: [Int: Set<Int>] = [:]
    private var covariance: [Int: [Int: CovariationClass]]?
    private var entropyByColumn: [Double] = []
    private var gapFrequencyByColumn: [Double] = []
    private var changedColumnsByRecordIndex: [Int: Set<Int>] = [:]
    private var showEntropyPlot = false
    private var showGapPlot = false
    private var cachedRevision: UInt64?
    private var cachedHidePosteriorProbability: Bool?
    private var cachedShowEntropyPlot: Bool?
    private var cachedShowGapPlot: Bool?
    private var cachedFontSize: Double?
    private let centeredParagraph: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return paragraph
    }()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func configure(document: StockholmDocument, state: EditorState, residuePalette: ResiduePaletteSettings) {
        self.document = document
        self.state = state
        self.residuePalette = residuePalette

        let fontChanged = cachedFontSize != state.fontSize
        if fontChanged {
            font = NSFont.monospacedSystemFont(ofSize: CGFloat(state.fontSize), weight: .regular)
            boldFont = NSFont.monospacedSystemFont(ofSize: CGFloat(state.fontSize), weight: .semibold)
            cellWidth = ceil(font.maximumAdvancement.width) + 2
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 6
            headerHeight = rowHeight * 1.55
            cachedFontSize = state.fontSize
        }

        let alignmentChanged = cachedRevision != document.revision
            || cachedHidePosteriorProbability != state.hidePosteriorProbability
        let analysisVisibilityChanged = cachedShowEntropyPlot != state.showEntropyPlot
            || cachedShowGapPlot != state.showGapPlot
        if alignmentChanged {
            rebuildCache(document: document, hidePosteriorProbability: state.hidePosteriorProbability)
        }
        if alignmentChanged || fontChanged {
            let widest = displayRows.map { CGFloat($0.row.label.count) * cellWidth }.max() ?? 0
            labelWidth = min(360, max(180, widest + 28))
        }
        if state.colorMode == .covariation, covariance == nil {
            covariance = CovariationAnalyzer.classifications(in: document.file, pairs: pairs)
        }
        if state.showEntropyPlot, alignmentChanged || analysisVisibilityChanged || entropyByColumn.count != alignmentLength {
            entropyByColumn = document.analysis.entropyByColumn
        }
        if state.showGapPlot || state.highlightAnalysisColumns,
           alignmentChanged || analysisVisibilityChanged || gapFrequencyByColumn.count != alignmentLength {
            gapFrequencyByColumn = document.analysis.gapFrequencyByColumn
        }
        if alignmentChanged || state.showChanges { changedColumnsByRecordIndex = document.changedColumnsByRecordIndex }
        showEntropyPlot = state.showEntropyPlot
        showGapPlot = state.showGapPlot
        cachedShowEntropyPlot = state.showEntropyPlot
        cachedShowGapPlot = state.showGapPlot

        if displayIndexByModelRow[state.selectedRow] == nil, let nearest = displayRows.min(by: {
            abs($0.modelIndex - state.selectedRow) < abs($1.modelIndex - state.selectedRow)
        }) {
            state.select(row: nearest.modelIndex, column: state.selectedColumn)
        }

        let width = labelWidth + CGFloat(alignmentLength) * cellWidth + 36
        let height = headerHeight + CGFloat(displayRows.count) * rowHeight + analysisAreaHeight + 20
        let desiredSize = NSSize(width: max(width, 600), height: max(height, 300))
        if frame.size != desiredSize { frame.size = desiredSize }
        needsDisplay = true
        let selected = cellRect(row: state.selectedRow, column: state.selectedColumn)
        if !selected.isEmpty, !visibleRect.intersects(selected) {
            scrollToVisible(selected.insetBy(dx: -cellWidth * 3, dy: -rowHeight * 2))
        }
    }

    private func rebuildCache(document: StockholmDocument, hidePosteriorProbability: Bool) {
        let file = document.file
        alignmentLength = document.analysis.alignmentLength
        displayRows = document.analysis.rows.enumerated().compactMap { modelIndex, row in
            guard !hidePosteriorProbability || !row.kind.isPosteriorProbability else { return nil }
            return DisplayRow(
                modelIndex: modelIndex,
                row: row,
                characters: Array(file.records[row.recordIndex].aligned)
            )
        }
        displayIndexByModelRow = Dictionary(uniqueKeysWithValues: displayRows.enumerated().map { ($0.element.modelIndex, $0.offset) })
        pairs = StructureParser.pairs(in: file)
        partnersByColumn = [:]
        stemByColumn = [:]
        stemPairByColumn = [:]
        for pair in pairs {
            partnersByColumn[pair.left, default: []].append(pair.right)
            partnersByColumn[pair.right, default: []].append(pair.left)
            if stemByColumn[pair.left] == nil {
                stemByColumn[pair.left] = pair.stem
                stemPairByColumn[pair.left] = pair
            }
            if stemByColumn[pair.right] == nil {
                stemByColumn[pair.right] = pair.stem
                stemPairByColumn[pair.right] = pair
            }
        }
        for column in partnersByColumn.keys {
            partnersByColumn[column] = Array(Set(partnersByColumn[column] ?? [])).sorted()
        }
        canonicalStemColumnsByRecord = [:]
        for row in file.sequenceRows {
            let characters = Array(file.records[row.recordIndex].aligned)
            var canonicalColumns: Set<Int> = []
            for (column, pair) in stemPairByColumn {
                guard characters.indices.contains(pair.left), characters.indices.contains(pair.right) else { continue }
                if BasePairRules.isCanonical(characters[pair.left], characters[pair.right]) {
                    canonicalColumns.insert(column)
                }
            }
            canonicalStemColumnsByRecord[row.recordIndex] = canonicalColumns
        }
        covariance = nil
        entropyByColumn = []
        gapFrequencyByColumn = []
        changedColumnsByRecordIndex = document.changedColumnsByRecordIndex
        cachedRevision = document.revision
        cachedHidePosteriorProbability = hidePosteriorProbability
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let state else { return }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let labelRect = NSRect(x: 0, y: dirtyRect.minY, width: labelWidth, height: dirtyRect.height)
        NSColor.controlBackgroundColor.setFill()
        labelRect.fill()

        let startColumn = max(0, Int((dirtyRect.minX - labelWidth) / cellWidth) - 1)
        let endColumn = min(alignmentLength - 1, Int((dirtyRect.maxX - labelWidth) / cellWidth) + 1)
        drawColumnHeader(length: alignmentLength, startColumn: startColumn, endColumn: endColumn)
        let startRow = max(0, Int((dirtyRect.minY - headerHeight) / rowHeight))
        let endRow = min(displayRows.count - 1, Int((dirtyRect.maxY - headerHeight) / rowHeight) + 1)

        if state.highlightAnalysisColumns, endColumn >= startColumn {
            let rowArea = NSRect(x: labelWidth, y: headerHeight, width: CGFloat(alignmentLength) * cellWidth, height: CGFloat(displayRows.count) * rowHeight)
            for column in startColumn...endColumn {
                let highEntropy = entropyByColumn.indices.contains(column) && entropyByColumn[column] >= state.entropyThreshold
                let highGap = gapFrequencyByColumn.indices.contains(column) && gapFrequencyByColumn[column] >= state.gapThreshold
                guard highEntropy || highGap else { continue }
                (highEntropy ? NSColor.systemIndigo : NSColor.systemTeal).withAlphaComponent(0.055).setFill()
                NSRect(x: labelWidth + CGFloat(column) * cellWidth, y: rowArea.minY, width: cellWidth, height: rowArea.height).fill()
            }
        }

        if endRow >= startRow {
            for displayIndex in startRow...endRow {
                let displayed = displayRows[displayIndex]
                let row = displayed.row
                let y = headerHeight + CGFloat(displayIndex) * rowHeight
                if displayIndex.isMultiple(of: 2) {
                    NSColor.alternatingContentBackgroundColors.first?.withAlphaComponent(0.32).setFill()
                    NSRect(x: 0, y: y, width: bounds.width, height: rowHeight).fill()
                }
                drawLabel(row.label, y: y, isStructure: row.kind.isStructure)
                let rowEndColumn = min(displayed.characters.count - 1, endColumn)
                if rowEndColumn >= startColumn {
                    for column in startColumn...rowEndColumn {
                        let rect = cellRect(displayIndex: displayIndex, column: column)
                        drawCell(
                            character: displayed.characters[column],
                            rect: rect,
                            row: row,
                            column: column
                        )
                    }
                }
                if state.selectedRows.count == 1, displayed.modelIndex == state.selectedRow, state.selectedColumnSet.count == 1 {
                        drawPartnerHighlights(displayIndex: displayIndex, selectedColumn: state.selectedColumn)
                }
                for selection in state.selectedColumnRanges {
                    let selectionRect = NSRect(
                        x: labelWidth + CGFloat(selection.lowerBound) * cellWidth,
                        y: y,
                        width: CGFloat(selection.count) * cellWidth,
                        height: rowHeight
                    )
                    let rowSelected = state.selectedRows.contains(displayed.modelIndex)
                    NSColor.selectedContentBackgroundColor.withAlphaComponent(rowSelected ? 0.20 : 0.045).setFill()
                    selectionRect.fill()
                    if rowSelected {
                        NSColor.selectedContentBackgroundColor.setStroke()
                        let outline = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
                        outline.lineWidth = 1.5
                        outline.stroke()
                        if state.selectedColumnSet.count > 8 {
                            NSColor.selectedContentBackgroundColor.setFill()
                            NSBezierPath(ovalIn: NSRect(x: selectionRect.minX + 1, y: selectionRect.midY - 2, width: 4, height: 4)).fill()
                            NSBezierPath(ovalIn: NSRect(x: selectionRect.maxX - 5, y: selectionRect.midY - 2, width: 4, height: 4)).fill()
                        }
                    }
                }
            }
        }

        if showEntropyPlot || showGapPlot {
            drawAnalysisPlots(dirtyRect: dirtyRect, startColumn: startColumn, endColumn: endColumn)
        }

        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: labelWidth - 0.5, y: 0))
        separator.line(to: NSPoint(x: labelWidth - 0.5, y: bounds.height))
        separator.stroke()
    }

    private func drawColumnHeader(length: Int, startColumn: Int, endColumn: Int) {
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight).fill()
        guard length > 0, endColumn >= startColumn else { return }
        var column = startColumn
        let remainder = (column + 1) % 10
        if remainder != 0 { column += 10 - remainder }
        while column <= endColumn {
            let text = "\(column + 1)" as NSString
            let rect = NSRect(x: labelWidth + CGFloat(column - 2) * cellWidth, y: 3, width: cellWidth * 5, height: rowHeight)
            text.draw(in: rect, withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centeredParagraph])
            NSColor.gridColor.withAlphaComponent(0.45).setStroke()
            let line = NSBezierPath()
            let x = labelWidth + CGFloat(column) * cellWidth + cellWidth / 2
            line.move(to: NSPoint(x: x, y: headerHeight - 5))
            line.line(to: NSPoint(x: x, y: bounds.height))
            line.stroke()
            column += 10
        }
        ("Alignment rows" as NSString).draw(
            in: NSRect(x: 12, y: 5, width: labelWidth - 20, height: rowHeight),
            withAttributes: [.font: boldFont, .foregroundColor: NSColor.secondaryLabelColor]
        )
    }

    private func drawLabel(_ label: String, y: CGFloat, isStructure: Bool) {
        let color = isStructure ? NSColor.systemPurple : NSColor.labelColor
        (label as NSString).draw(
            in: NSRect(x: 10, y: y + 3, width: labelWidth - 18, height: rowHeight - 4),
            withAttributes: [.font: isStructure ? boldFont : font, .foregroundColor: color]
        )
    }

    private func drawCell(character: Character, rect: NSRect, row: AlignmentRow, column: Int) {
        guard let state else { return }
        var background: NSColor?
        var foreground = NSColor.labelColor
        switch state.colorMode {
        case .stem:
            if let stem = stemByColumn[column] {
                if row.kind.isSequence, canonicalStemColumnsByRecord[row.recordIndex]?.contains(column) != true {
                    break
                }
                background = AlignmentPalette.stemColor(for: stem)
                foreground = .black
            }
        case .covariation:
            if row.kind.isSequence, let classification = covariance?[row.recordIndex]?[column] {
                background = AlignmentPalette.covariation[classification]
                foreground = classification == .compensatory || classification == .noncanonical ? .white : .black
            } else if let stem = stemByColumn[column], row.kind.isStructure {
                background = AlignmentPalette.stemColor(for: stem)
                foreground = .black
            }
        case .residue:
            if row.kind.isSequence {
                background = residuePalette?.color(for: character)
                foreground = .black
            }
        case .none:
            break
        }
        if let background {
            background.setFill()
            rect.fill()
        }
        if state.showGrid {
            NSColor.gridColor.withAlphaComponent(0.20).setStroke()
            let grid = NSBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25))
            grid.lineWidth = 0.5
            grid.stroke()
        }
        if state.showChanges, changedColumnsByRecordIndex[row.recordIndex]?.contains(column) == true {
            NSColor.systemOrange.setFill()
            let marker = NSBezierPath()
            marker.move(to: NSPoint(x: rect.maxX - 5, y: rect.minY))
            marker.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            marker.line(to: NSPoint(x: rect.maxX, y: rect.minY + 5))
            marker.close()
            marker.fill()
        }
        (String(character) as NSString).draw(
            in: NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: rect.height - 2),
            withAttributes: [.font: row.kind.isStructure ? boldFont : font, .foregroundColor: foreground, .paragraphStyle: centeredParagraph]
        )
    }

    private func drawPartnerHighlights(displayIndex: Int, selectedColumn: Int) {
        for partner in partnersByColumn[selectedColumn] ?? [] {
            let rect = cellRect(displayIndex: displayIndex, column: partner)
            NSColor.systemOrange.withAlphaComponent(0.18).setFill()
            rect.fill()
            NSColor.systemOrange.setStroke()
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 1.25, dy: 1.25), xRadius: 2, yRadius: 2)
            outline.lineWidth = 2.25
            outline.stroke()
        }
    }

    private var analysisTrackHeight: CGFloat { max(50, rowHeight * 2.25) }
    private var analysisAreaHeight: CGFloat {
        CGFloat((showEntropyPlot ? 1 : 0) + (showGapPlot ? 1 : 0)) * analysisTrackHeight
    }

    private func drawAnalysisPlots(dirtyRect: NSRect, startColumn: Int, endColumn: Int) {
        var y = headerHeight + CGFloat(displayRows.count) * rowHeight
        if showEntropyPlot {
            drawAnalysisTrack(
                title: "Entropy (0–2 bits)",
                values: entropyByColumn.map { $0 / 2.0 },
                color: .systemIndigo,
                y: y,
                dirtyRect: dirtyRect,
                startColumn: startColumn,
                endColumn: endColumn
            )
            y += analysisTrackHeight
        }
        if showGapPlot {
            drawAnalysisTrack(
                title: "Gap frequency (0–100%)",
                values: gapFrequencyByColumn,
                color: .systemTeal,
                y: y,
                dirtyRect: dirtyRect,
                startColumn: startColumn,
                endColumn: endColumn
            )
        }
    }

    private func drawAnalysisTrack(title: String, values: [Double], color: NSColor, y: CGFloat, dirtyRect: NSRect, startColumn: Int, endColumn: Int) {
        let area = NSRect(x: 0, y: y, width: bounds.width, height: analysisTrackHeight)
        guard dirtyRect.intersects(area) else { return }

        NSColor.windowBackgroundColor.setFill()
        area.fill()
        NSColor.controlBackgroundColor.setFill()
        NSRect(x: 0, y: y, width: labelWidth, height: analysisTrackHeight).fill()
        NSColor.separatorColor.setStroke()
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: 0, y: y + 0.5))
        separator.line(to: NSPoint(x: bounds.width, y: y + 0.5))
        separator.stroke()

        (title as NSString).draw(
            in: NSRect(x: 10, y: y + 7, width: labelWidth - 18, height: rowHeight),
            withAttributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        )

        guard endColumn >= startColumn else { return }
        let baseline = area.maxY - 7
        let maximumBarHeight = max(1, analysisTrackHeight - 16)
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        let baselinePath = NSBezierPath()
        baselinePath.move(to: NSPoint(x: labelWidth, y: baseline + 0.5))
        baselinePath.line(to: NSPoint(x: bounds.width, y: baseline + 0.5))
        baselinePath.stroke()

        for column in startColumn...endColumn where values.indices.contains(column) {
            let fraction = max(0, min(1, values[column]))
            let barHeight = CGFloat(fraction) * maximumBarHeight
            guard barHeight > 0 else { continue }
            color.withAlphaComponent(0.78).setFill()
            NSRect(
                x: labelWidth + CGFloat(column) * cellWidth + 1,
                y: baseline - barHeight,
                width: max(1, cellWidth - 2),
                height: barHeight
            ).fill()
        }
    }

    private func cellRect(row: Int, column: Int) -> NSRect {
        guard let displayIndex = displayIndexByModelRow[row] else { return .zero }
        return cellRect(displayIndex: displayIndex, column: column)
    }

    private func cellRect(displayIndex: Int, column: Int) -> NSRect {
        NSRect(
            x: labelWidth + CGFloat(column) * cellWidth,
            y: headerHeight + CGFloat(displayIndex) * rowHeight,
            width: cellWidth,
            height: rowHeight
        )
    }

    private func location(for event: NSEvent) -> (row: Int, column: Int)? {
        let point = convert(event.locationInWindow, from: nil)
        guard point.y >= headerHeight else { return nil }
        let displayIndex = Int((point.y - headerHeight) / rowHeight)
        let column = Int((point.x - labelWidth) / cellWidth)
        guard displayRows.indices.contains(displayIndex), column >= 0, column < alignmentLength else { return nil }
        return (displayRows[displayIndex].modelIndex, column)
    }

    private func analysisColumn(for event: NSEvent) -> Int? {
        guard analysisAreaHeight > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let analysisY = headerHeight + CGFloat(displayRows.count) * rowHeight
        guard point.y >= analysisY, point.y < analysisY + analysisAreaHeight else { return nil }
        let column = Int((point.x - labelWidth) / cellWidth)
        return column >= 0 && column < alignmentLength ? column : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let state else { return }
        if let column = analysisColumn(for: event) {
            state.select(row: state.selectedRow, column: column)
            updateStatus()
            needsDisplay = true
            return
        }
        guard let location = location(for: event) else { return }
        dragging = true
        if event.clickCount >= 3, let stem = stemByColumn[location.column] {
            let columns = Set(pairs.filter { $0.stem == stem }.flatMap { [$0.left, $0.right] })
            state.selectColumns(columns, row: location.row)
            state.statusMessage = "Selected stem \(stem + 1) (\(columns.count) paired columns)."
            needsDisplay = true
            return
        }
        if event.clickCount == 2, let partners = partnersByColumn[location.column], !partners.isEmpty {
            state.selectColumns(Set(partners + [location.column]), row: location.row)
            state.statusMessage = "Selected both base-pair partners."
            needsDisplay = true
            return
        }
        state.select(row: location.row, column: location.column, extending: event.modifierFlags.contains(.shift))
        updateStatus()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, let location = location(for: event), let state else { return }
        state.select(row: location.row, column: location.column, extending: true)
        updateStatus()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) { dragging = false }

    override func keyDown(with event: NSEvent) {
        guard let document, let state else { return }
        let command = event.modifierFlags.contains(.command)
        let control = event.modifierFlags.contains(.control)
        let shift = event.modifierFlags.contains(.shift)
        if control, event.charactersIgnoringModifiers?.lowercased() == "g" {
            if shift { closeGapAtCursor() } else { openGapAtCursor() }
            updateStatus()
            needsDisplay = true
            return
        }
        if command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "c" { copySelection(); return }
            if key == "v" { pasteSelection(); return }
            if key == "a" {
                let sequenceModelRows = document.analysis.rows.indices.filter { document.analysis.rows[$0].kind.isSequence }
                if let firstRow = sequenceModelRows.first, let lastRow = sequenceModelRows.last {
                    state.anchorRow = firstRow
                    state.selectedRow = lastRow
                }
                state.anchorColumn = 0
                state.selectedColumn = max(0, document.file.alignmentLength - 1)
                state.specialColumns = []
                needsDisplay = true
                return
            }
        }
        let option = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 123:
            if option { shiftSelection(direction: -1) } else { move(rowDelta: 0, columnDelta: -1, extending: shift) }
        case 124:
            if option { shiftSelection(direction: 1) } else { move(rowDelta: 0, columnDelta: 1, extending: shift) }
        case 125: move(rowDelta: 1, columnDelta: 0, extending: shift)
        case 126: move(rowDelta: -1, columnDelta: 0, extending: shift)
        case 51, 117: replaceSelectionWithGap()
        case 115:
            state.select(row: state.selectedRow, column: 0, extending: shift)
        case 119:
            state.select(row: state.selectedRow, column: max(0, document.file.alignmentLength - 1), extending: shift)
        default:
            guard !command, !control, let characters = event.charactersIgnoringModifiers, characters.count == 1, let character = characters.first else {
                super.keyDown(with: event); return
            }
            type(character)
        }
        updateStatus()
        needsDisplay = true
    }

    private func move(rowDelta: Int, columnDelta: Int, extending: Bool) {
        guard let state, !displayRows.isEmpty else { return }
        let currentDisplayIndex = displayIndexByModelRow[state.selectedRow] ?? 0
        let targetDisplayIndex = max(0, min(currentDisplayIndex + rowDelta, displayRows.count - 1))
        let row = displayRows[targetDisplayIndex].modelIndex
        let column = max(0, min(state.selectedColumn + columnDelta, alignmentLength - 1))
        state.select(row: row, column: column, extending: extending)
        scrollToVisible(cellRect(row: row, column: column).insetBy(dx: -cellWidth * 2, dy: -rowHeight))
    }

    private func type(_ input: Character) {
        guard let document, let state, document.analysis.rows.indices.contains(state.selectedRow) else { return }
        let modelRows = state.selectedRows.filter { document.analysis.rows.indices.contains($0) }
        let sequenceRows = modelRows.filter { document.analysis.rows[$0].kind.isSequence }
        let targetRows = modelRows.count > 1 ? sequenceRows : modelRows
        guard !targetRows.isEmpty else { NSSound.beep(); return }
        let isSequenceEdit = targetRows.allSatisfy { document.analysis.rows[$0].kind.isSequence }
        let character: Character
        if isSequenceEdit {
            let upper = Character(String(input).uppercased())
            let allowed = Set("ACGUTNRYSWKMBDHVX-.~")
            guard allowed.contains(upper) else { NSSound.beep(); return }
            character = upper
        } else {
            guard !input.isWhitespace else { return }
            character = input
        }
        let columns = state.selectedColumnSet
        document.mutate("Type", undoManager: window?.undoManager) { file in
            for row in targetRows {
                for column in columns { file.replaceCharacter(row: row, column: column, with: character) }
            }
        }
        let next = min(document.file.alignmentLength - 1, (columns.max() ?? state.selectedColumn) + 1)
        state.select(row: state.selectedRow, column: next)
    }

    private func replaceSelectionWithGap() {
        guard let document, let state, document.analysis.rows.indices.contains(state.selectedRow) else { return }
        let rows = state.selectedRows.filter { document.analysis.rows.indices.contains($0) }
        let columns = state.selectedColumnSet
        document.mutate("Clear Cells", undoManager: window?.undoManager) { file in
            for row in rows {
                let fill: Character = document.analysis.rows[row].kind.isSequence ? "-" : "."
                for column in columns { file.replaceCharacter(row: row, column: column, with: fill) }
            }
        }
    }

    private func shiftSelection(direction: Int) {
        guard let document, let state else { return }
        let rows = Set(state.selectedRows.filter {
            document.analysis.rows.indices.contains($0) && document.analysis.rows[$0].kind.isSequence
        })
        var shifted = false
        document.mutate(direction < 0 ? "Shift Left" : "Shift Right", undoManager: window?.undoManager) { file in
            shifted = file.shift(rows: rows, columns: state.selectedColumnSet, direction: direction)
        }
        if shifted {
            state.translateSelectedColumns(by: direction)
        } else {
            NSSound.beep()
            state.statusMessage = "A gap is required beside the selected block."
        }
    }

    private func copySelection() {
        guard let document, let state, document.analysis.rows.indices.contains(state.selectedRow) else { return }
        let columns = state.orderedSelectedColumns
        let selectedRows = state.selectedRows.filter { document.analysis.rows.indices.contains($0) }
        let lines = selectedRows.map { modelRow -> String in
            let row = document.analysis.rows[modelRow]
            let characters = Array(document.file.records[row.recordIndex].aligned)
            return String(columns.compactMap { characters.indices.contains($0) ? characters[$0] : nil })
        }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        state.statusMessage = "Copied \(state.selectedCellCount) alignment cells."
    }

    private func pasteSelection() {
        guard let document, let state, let source = NSPasteboard.general.string(forType: .string) else { return }
        let lines = source.components(separatedBy: .newlines).map { $0.filter { !$0.isWhitespace } }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        let targetRows = state.selectedRows.filter { document.analysis.rows.indices.contains($0) }
        let columns = state.orderedSelectedColumns
        let startColumn = columns.first ?? state.selectedColumn
        document.mutate("Paste", undoManager: window?.undoManager) { file in
            for (offset, line) in lines.enumerated() {
                let targetRow = lines.count == 1 ? state.selectedRow : (targetRows.indices.contains(offset) ? targetRows[offset] : -1)
                guard document.analysis.rows.indices.contains(targetRow) else { continue }
                if !state.specialColumns.isEmpty, line.count <= columns.count {
                    for (character, column) in zip(line, columns) { file.replaceCharacter(row: targetRow, column: column, with: character) }
                } else {
                    file.replaceCharacters(row: targetRow, startingAt: startColumn, with: String(line.prefix(max(0, file.alignmentLength - startColumn))))
                }
            }
        }
        let final = min(document.file.alignmentLength - 1, startColumn + (lines.map(\.count).max() ?? 1) - 1)
        state.anchorColumn = startColumn
        state.selectedColumn = final
        state.specialColumns = []
    }

    private func openGapAtCursor() {
        guard let document, let state else { return }
        var changed = false
        document.mutate("Open Gap", undoManager: window?.undoManager) { file in
            changed = file.openGap(row: state.selectedRow, at: state.selectedColumn)
        }
        state.statusMessage = changed ? "Opened a gap before column \(state.selectedColumn + 1)." : "A downstream gap is required to open space here."
        if !changed { NSSound.beep() }
    }

    private func closeGapAtCursor() {
        guard let document, let state else { return }
        var changed = false
        document.mutate("Close Gap", undoManager: window?.undoManager) { file in
            changed = file.closeGap(row: state.selectedRow, at: state.selectedColumn)
        }
        state.statusMessage = changed ? "Closed the selected gap." : "Select a gap that has residues to its right."
        if !changed { NSSound.beep() }
    }

    private func updateStatus() {
        guard let document, let state, document.analysis.rows.indices.contains(state.selectedRow) else { return }
        let row = document.analysis.rows[state.selectedRow]
        var message = "\(row.label) • column \(state.selectedColumn + 1)"
        if state.selectedCellCount > 1 { message += " • \(state.selectedRows.count) row(s) × \(state.selectedColumnSet.count) column(s)" }
        if let pair = pairs.first(where: { $0.left == state.selectedColumn || $0.right == state.selectedColumn }) {
            message += " • paired with \((pair.left == state.selectedColumn ? pair.right : pair.left) + 1) in \(pair.structureTag)"
        }
        if state.showEntropyPlot, entropyByColumn.indices.contains(state.selectedColumn) {
            message += String(format: " • entropy %.2f bits", entropyByColumn[state.selectedColumn])
        }
        if state.showGapPlot, gapFrequencyByColumn.indices.contains(state.selectedColumn) {
            message += String(format: " • gaps %.0f%%", gapFrequencyByColumn[state.selectedColumn] * 100)
        }
        state.statusMessage = message
    }
}

private extension String {
    func character(at offset: Int) -> Character? {
        guard offset >= 0, let index = index(startIndex, offsetBy: offset, limitedBy: endIndex), index < endIndex else { return nil }
        return self[index]
    }

    func substring(_ range: ClosedRange<Int>) -> String {
        guard !isEmpty else { return "" }
        let lower = index(startIndex, offsetBy: max(0, range.lowerBound), limitedBy: endIndex) ?? endIndex
        let upperOffset = min(count, range.upperBound + 1)
        let upper = index(startIndex, offsetBy: upperOffset, limitedBy: endIndex) ?? endIndex
        return String(self[lower..<upper])
    }
}
