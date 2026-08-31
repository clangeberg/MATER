import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum AlignmentExportFormat: String, Identifiable {
    case pdf
    case svg

    var pathExtension: String { rawValue }
    var id: String { rawValue }
    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .svg: return .svg
        }
    }
}

struct AlignmentExportOptions {
    var title = ""
    var includeLegend = true
    var numberingInterval = 10
    var labelWidth: CGFloat? = nil
    var selectedRows: Set<Int>? = nil
    var selectedColumns: ClosedRange<Int>? = nil
    var tiledPDF = false

    func preparedFile(from file: StockholmFile) -> StockholmFile {
        // Keep every row available for structure/covariation analysis. The
        // snapshot filters visible rows afterward so selected-row exports use
        // exactly the same classifications as the full alignment.
        let records = file.rows.map { row -> StockholmRecord in
            var record = file.records[row.recordIndex]
            if let selectedColumns {
                let characters = Array(record.aligned)
                let lower = max(0, selectedColumns.lowerBound)
                let upper = min(characters.count - 1, selectedColumns.upperBound)
                record.aligned = lower <= upper ? String(characters[lower...upper]) : ""
            }
            return record
        }
        return StockholmFile(records: records, lineEnding: file.lineEnding, hasFinalNewline: false)
    }
}

struct AlignmentResidueColors {
    let adenine: NSColor
    let cytosine: NSColor
    let guanine: NSColor
    let uracil: NSColor

    func color(for residue: Character) -> NSColor? {
        switch Character(String(residue).uppercased()) {
        case "A": return adenine
        case "C": return cytosine
        case "G": return guanine
        case "U", "T": return uracil
        default: return nil
        }
    }
}

@MainActor
enum AlignmentExporter {
    static func data(
        format: AlignmentExportFormat,
        file: StockholmFile,
        colorMode: AlignmentColorMode,
        residueColors: AlignmentResidueColors,
        hidePosteriorProbability: Bool,
        showEntropy: Bool,
        showGap: Bool = false,
        showConsensus: Bool = false,
        showGrid: Bool,
        fontSize: Double,
        options: AlignmentExportOptions = AlignmentExportOptions()
    ) -> Data {
        var consensusCharacters = showConsensus ? Array(ConsensusAnalyzer.consensus(in: file)) : []
        if let selectedColumns = options.selectedColumns, !consensusCharacters.isEmpty {
            let lower = max(0, selectedColumns.lowerBound)
            let upper = min(consensusCharacters.count - 1, selectedColumns.upperBound)
            consensusCharacters = lower <= upper ? Array(consensusCharacters[lower...upper]) : []
        }
        let preparedFile = options.preparedFile(from: file)
        let snapshot = AlignmentExportSnapshot(
            file: preparedFile,
            colorMode: colorMode,
            residueColors: residueColors,
            hidePosteriorProbability: hidePosteriorProbability,
            showEntropy: showEntropy,
            showGap: showGap,
            consensusCharacters: consensusCharacters,
            showGrid: showGrid,
            fontSize: fontSize,
            options: options
        )
        switch format {
        case .pdf:
            if options.tiledPDF { return snapshot.tiledPDFData }
            let view = AlignmentPDFView(snapshot: snapshot)
            return view.dataWithPDF(inside: view.bounds)
        case .svg:
            return snapshot.svgData
        }
    }
}

@MainActor
private struct AlignmentExportSnapshot {
    struct Row {
        let label: String
        let kind: AlignmentRowKind
        let recordIndex: Int
        let characters: [Character]
    }

    struct CellStyle {
        let background: NSColor?
        let foreground: NSColor
    }

    let rows: [Row]
    let alignmentLength: Int
    let colorMode: AlignmentColorMode
    let residueColors: AlignmentResidueColors
    let showEntropy: Bool
    let showGap: Bool
    let consensusCharacters: [Character]
    let showGrid: Bool
    let stemByColumn: [Int: Int]
    let stemPairByColumn: [Int: BasePair]
    let canonicalStemColumnsByRecord: [Int: Set<Int>]
    let covariance: [Int: [Int: CovariationClass]]
    let entropyByColumn: [Double]
    let gapFrequencyByColumn: [Double]
    let font: NSFont
    let boldFont: NSFont
    let cellWidth: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    let labelWidth: CGFloat
    let entropyHeight: CGFloat
    let title: String
    let includeLegend: Bool
    let numberingInterval: Int
    let columnNumberOffset: Int
    let titleHeight: CGFloat
    let legendHeight: CGFloat
    let padding: CGFloat = 16

    var gridOriginX: CGFloat { padding + labelWidth }
    var gridHeaderOriginY: CGFloat { padding + titleHeight + legendHeight }
    var rowsOriginY: CGFloat { gridHeaderOriginY + headerHeight }
    var consensusOriginY: CGFloat { rowsOriginY + CGFloat(rows.count) * rowHeight }
    var consensusHeight: CGFloat { consensusCharacters.isEmpty ? 0 : rowHeight }
    var entropyOriginY: CGFloat { consensusOriginY + consensusHeight }
    var size: NSSize {
        NSSize(
            width: padding * 2 + labelWidth + CGFloat(alignmentLength) * cellWidth,
            height: padding * 2 + titleHeight + legendHeight + headerHeight + CGFloat(rows.count) * rowHeight + consensusHeight + entropyHeight
        )
    }

    init(
        file: StockholmFile,
        colorMode: AlignmentColorMode,
        residueColors: AlignmentResidueColors,
        hidePosteriorProbability: Bool,
        showEntropy: Bool,
        showGap: Bool,
        consensusCharacters: [Character],
        showGrid: Bool,
        fontSize: Double,
        options: AlignmentExportOptions
    ) {
        alignmentLength = file.alignmentLength
        self.colorMode = colorMode
        self.residueColors = residueColors
        self.showEntropy = showEntropy
        self.showGap = showGap
        self.consensusCharacters = consensusCharacters
        self.showGrid = showGrid
        title = options.title.trimmingCharacters(in: .whitespacesAndNewlines)
        includeLegend = options.includeLegend
        numberingInterval = max(1, options.numberingInterval)
        columnNumberOffset = options.selectedColumns?.lowerBound ?? 0

        let exportRows = file.rows.enumerated().compactMap { modelIndex, row -> AlignmentRow? in
            guard options.selectedRows?.contains(modelIndex) ?? true else { return nil }
            guard !hidePosteriorProbability || !row.kind.isPosteriorProbability else { return nil }
            return row
        }
        rows = exportRows.map { row in
            Row(
                label: row.label,
                kind: row.kind,
                recordIndex: row.recordIndex,
                characters: Array(file.records[row.recordIndex].aligned)
            )
        }

        let pairs = StructureParser.pairs(in: file)
        var stems: [Int: Int] = [:]
        var stemPairs: [Int: BasePair] = [:]
        for pair in pairs {
            if stems[pair.left] == nil {
                stems[pair.left] = pair.stem
                stemPairs[pair.left] = pair
            }
            if stems[pair.right] == nil {
                stems[pair.right] = pair.stem
                stemPairs[pair.right] = pair
            }
        }
        stemByColumn = stems
        stemPairByColumn = stemPairs

        var canonicalColumnsByRecord: [Int: Set<Int>] = [:]
        for row in file.sequenceRows {
            let characters = Array(file.records[row.recordIndex].aligned)
            var columns: Set<Int> = []
            for (column, pair) in stemPairs {
                guard characters.indices.contains(pair.left), characters.indices.contains(pair.right) else { continue }
                if BasePairRules.isCanonical(characters[pair.left], characters[pair.right]) {
                    columns.insert(column)
                }
            }
            canonicalColumnsByRecord[row.recordIndex] = columns
        }
        canonicalStemColumnsByRecord = canonicalColumnsByRecord
        covariance = colorMode == .covariation
            ? CovariationAnalyzer.classifications(in: file, pairs: pairs)
            : [:]
        entropyByColumn = showEntropy ? EntropyAnalyzer.columnEntropies(in: file) : []
        gapFrequencyByColumn = showGap ? GapAnalyzer.columnGapFrequencies(in: file) : []

        let exportFontSize = CGFloat(max(8, min(22, fontSize)))
        let resolvedFont = NSFont.monospacedSystemFont(ofSize: exportFontSize, weight: .regular)
        let resolvedCellWidth = ceil(resolvedFont.maximumAdvancement.width) + 2
        font = resolvedFont
        boldFont = NSFont.monospacedSystemFont(ofSize: exportFontSize, weight: .semibold)
        cellWidth = resolvedCellWidth
        rowHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading) + 6
        headerHeight = rowHeight * 1.55
        titleHeight = title.isEmpty ? 0 : rowHeight * 1.45
        legendHeight = includeLegend ? rowHeight * 1.35 : 0
        var labelTexts = exportRows.map(\.label) + ["Alignment rows"]
        if showEntropy { labelTexts.append("Entropy (0–2 bits)") }
        if showGap { labelTexts.append("Gap frequency (0–100%)") }
        if !consensusCharacters.isEmpty { labelTexts.append("R2R consensus") }
        let widest = labelTexts.map {
            ($0 as NSString).size(withAttributes: [.font: resolvedFont]).width
        }.max() ?? 0
        labelWidth = options.labelWidth.map { max(120, min(520, $0)) } ?? max(180, widest + 28)
        entropyHeight = CGFloat((showEntropy ? 1 : 0) + (showGap ? 1 : 0)) * max(50, rowHeight * 2.25)
    }

    func style(for row: Row, column: Int, character: Character) -> CellStyle {
        var background: NSColor?
        var foreground = NSColor.black
        switch colorMode {
        case .stem:
            if let stem = stemByColumn[column] {
                if !row.kind.isSequence || canonicalStemColumnsByRecord[row.recordIndex]?.contains(column) == true {
                    background = AlignmentPalette.stemColor(for: stem)
                }
            }
        case .element:
            if let pair = stemPairByColumn[column] {
                if !row.kind.isSequence || canonicalStemColumnsByRecord[row.recordIndex]?.contains(column) == true {
                    background = AlignmentPalette.stemColor(for: pair.element)
                }
            }
        case .covariation:
            if row.kind.isSequence, let classification = covariance[row.recordIndex]?[column] {
                background = AlignmentPalette.covariation[classification]
                foreground = classification == .compensatory || classification == .noncanonical ? .white : .black
            } else if row.kind.isStructure, let stem = stemByColumn[column] {
                background = AlignmentPalette.stemColor(for: stem)
            }
        case .residue:
            if row.kind.isSequence { background = residueColors.color(for: character) }
        case .none:
            break
        }
        return CellStyle(background: background, foreground: foreground)
    }

    func consensusStyle(column: Int, character: Character) -> CellStyle {
        var background: NSColor?
        switch colorMode {
        case .stem:
            if let pair = stemPairByColumn[column],
               consensusCharacters.indices.contains(pair.left), consensusCharacters.indices.contains(pair.right),
               BasePairRules.isCanonical(consensusCharacters[pair.left], consensusCharacters[pair.right]) {
                background = AlignmentPalette.stemColor(for: pair.stem)
            }
        case .element:
            if let pair = stemPairByColumn[column],
               consensusCharacters.indices.contains(pair.left), consensusCharacters.indices.contains(pair.right),
               BasePairRules.isCanonical(consensusCharacters[pair.left], consensusCharacters[pair.right]) {
                background = AlignmentPalette.stemColor(for: pair.element)
            }
        case .residue:
            background = residueColors.color(for: character)
        case .covariation, .none:
            break
        }
        return CellStyle(background: background, foreground: .black)
    }

    func drawAppKit(in bounds: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        if !title.isEmpty {
            (title as NSString).draw(
                in: NSRect(x: padding, y: padding + 1, width: size.width - padding * 2, height: titleHeight),
                withAttributes: [.font: NSFont.systemFont(ofSize: font.pointSize * 1.25, weight: .bold), .foregroundColor: NSColor.black]
            )
        }
        if includeLegend { drawLegendAppKit(y: padding + titleHeight) }

        let contentHeight = headerHeight + CGFloat(rows.count) * rowHeight + consensusHeight + entropyHeight
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: padding, y: gridHeaderOriginY, width: labelWidth, height: contentHeight).fill()
        NSRect(x: gridOriginX, y: gridHeaderOriginY, width: CGFloat(alignmentLength) * cellWidth, height: headerHeight).fill()

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        for column in 0..<alignmentLength where (column + columnNumberOffset + 1).isMultiple(of: numberingInterval) {
            ("\(column + columnNumberOffset + 1)" as NSString).draw(
                in: NSRect(x: gridOriginX + CGFloat(column - 2) * cellWidth, y: gridHeaderOriginY + 3, width: cellWidth * 5, height: rowHeight),
                withAttributes: [.font: font, .foregroundColor: NSColor.darkGray, .paragraphStyle: centered]
            )
            NSColor(calibratedWhite: 0.76, alpha: 0.65).setStroke()
            let line = NSBezierPath()
            let x = gridOriginX + CGFloat(column) * cellWidth + cellWidth / 2
            line.move(to: NSPoint(x: x, y: gridHeaderOriginY + headerHeight - 5))
            line.line(to: NSPoint(x: x, y: gridHeaderOriginY + contentHeight))
            line.stroke()
        }
        ("Alignment rows" as NSString).draw(
            in: NSRect(x: padding + 10, y: gridHeaderOriginY + 5, width: labelWidth - 18, height: rowHeight),
            withAttributes: [.font: boldFont, .foregroundColor: NSColor.darkGray]
        )

        for (rowIndex, row) in rows.enumerated() {
            let y = rowsOriginY + CGFloat(rowIndex) * rowHeight
            if rowIndex.isMultiple(of: 2) {
                NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
                NSRect(x: padding, y: y, width: labelWidth + CGFloat(alignmentLength) * cellWidth, height: rowHeight).fill()
            }
            (row.label as NSString).draw(
                in: NSRect(x: padding + 10, y: y + 3, width: labelWidth - 18, height: rowHeight - 4),
                withAttributes: [.font: row.kind.isStructure ? boldFont : font, .foregroundColor: row.kind.isStructure ? NSColor.systemPurple : NSColor.black]
            )
            for column in 0..<min(alignmentLength, row.characters.count) {
                let character = row.characters[column]
                let cell = NSRect(x: gridOriginX + CGFloat(column) * cellWidth, y: y, width: cellWidth, height: rowHeight)
                let cellStyle = style(for: row, column: column, character: character)
                if let background = cellStyle.background {
                    background.setFill()
                    cell.fill()
                }
                if showGrid {
                    NSColor(calibratedWhite: 0.78, alpha: 0.55).setStroke()
                    let grid = NSBezierPath(rect: cell.insetBy(dx: 0.25, dy: 0.25))
                    grid.lineWidth = 0.5
                    grid.stroke()
                }
                (String(character) as NSString).draw(
                    in: NSRect(x: cell.minX, y: cell.minY + 2, width: cell.width, height: cell.height - 2),
                    withAttributes: [.font: row.kind.isStructure ? boldFont : font, .foregroundColor: cellStyle.foreground, .paragraphStyle: centered]
                )
            }
        }

        if !consensusCharacters.isEmpty {
            drawConsensusAppKit()
        }

        guard showEntropy || showGap else { return }
        var trackY = entropyOriginY
        if showEntropy {
            drawAnalysisTrackAppKit(
                title: "Entropy (0–2 bits)",
                values: entropyByColumn.map { $0 / 2.0 },
                color: .systemIndigo,
                y: trackY
            )
            trackY += analysisTrackHeight
        }
        if showGap {
            drawAnalysisTrackAppKit(
                title: "Gap frequency (0–100%)",
                values: gapFrequencyByColumn,
                color: .systemTeal,
                y: trackY
            )
        }
    }

    private func drawConsensusAppKit() {
        let y = consensusOriginY
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: padding, y: y, width: labelWidth, height: rowHeight).fill()
        NSColor(calibratedWhite: 0.76, alpha: 1).setStroke()
        let top = NSBezierPath()
        top.move(to: NSPoint(x: padding, y: y + 0.5))
        top.line(to: NSPoint(x: size.width - padding, y: y + 0.5))
        top.stroke()
        ("R2R consensus" as NSString).draw(
            in: NSRect(x: padding + 10, y: y + 3, width: labelWidth - 18, height: rowHeight - 4),
            withAttributes: [.font: boldFont, .foregroundColor: NSColor.systemPurple]
        )
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        for column in 0..<min(alignmentLength, consensusCharacters.count) {
            let character = consensusCharacters[column]
            let cell = NSRect(x: gridOriginX + CGFloat(column) * cellWidth, y: y, width: cellWidth, height: rowHeight)
            let cellStyle = consensusStyle(column: column, character: character)
            if let background = cellStyle.background {
                background.setFill()
                cell.fill()
            }
            if showGrid {
                NSColor(calibratedWhite: 0.78, alpha: 0.55).setStroke()
                let grid = NSBezierPath(rect: cell.insetBy(dx: 0.25, dy: 0.25))
                grid.lineWidth = 0.5
                grid.stroke()
            }
            (String(character) as NSString).draw(
                in: NSRect(x: cell.minX, y: cell.minY + 2, width: cell.width, height: cell.height - 2),
                withAttributes: [.font: font, .foregroundColor: cellStyle.foreground, .paragraphStyle: centered]
            )
        }
    }

    private var analysisTrackHeight: CGFloat { max(50, rowHeight * 2.25) }

    private func drawAnalysisTrackAppKit(title: String, values: [Double], color: NSColor, y: CGFloat) {
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: padding, y: y, width: labelWidth, height: analysisTrackHeight).fill()
        NSColor(calibratedWhite: 0.76, alpha: 1).setStroke()
        let top = NSBezierPath()
        top.move(to: NSPoint(x: padding, y: y + 0.5))
        top.line(to: NSPoint(x: size.width - padding, y: y + 0.5))
        top.stroke()
        (title as NSString).draw(
            in: NSRect(x: padding + 10, y: y + 7, width: labelWidth - 18, height: rowHeight),
            withAttributes: [.font: font, .foregroundColor: NSColor.darkGray]
        )
        let baseline = y + analysisTrackHeight - 7
        let maximumBarHeight = max(1, analysisTrackHeight - 16)
        for column in 0..<min(alignmentLength, values.count) {
            let fraction = max(0, min(1, values[column]))
            let barHeight = CGFloat(fraction) * maximumBarHeight
            guard barHeight > 0 else { continue }
            color.withAlphaComponent(0.78).setFill()
            NSRect(
                x: gridOriginX + CGFloat(column) * cellWidth + 1,
                y: baseline - barHeight,
                width: max(1, cellWidth - 2),
                height: barHeight
            ).fill()
        }
    }

    private var legendItems: [(String, NSColor)] {
        switch colorMode {
        case .stem:
            return [("canonical stem", AlignmentPalette.stemColor(for: 0)), ("pair violation", .white)]
        case .element:
            return [("canonical structural element", AlignmentPalette.stemColor(for: 0)), ("pair violation", .white)]
        case .covariation:
            return [
                ("same pair", AlignmentPalette.covariation[.conserved]!),
                ("one-sided change", AlignmentPalette.covariation[.consistent]!),
                ("two-sided change", AlignmentPalette.covariation[.compensatory]!),
                ("noncanonical", AlignmentPalette.covariation[.noncanonical]!),
                ("gap", AlignmentPalette.covariation[.gap]!)
            ]
        case .residue:
            return [("A", residueColors.adenine), ("C", residueColors.cytosine), ("G", residueColors.guanine), ("U/T", residueColors.uracil)]
        case .none:
            return []
        }
    }

    private func drawLegendAppKit(y: CGFloat) {
        var x = padding
        for (label, color) in legendItems {
            color.setFill()
            let swatch = NSRect(x: x, y: y + 4, width: 14, height: 12)
            swatch.fill()
            NSColor(calibratedWhite: 0.7, alpha: 1).setStroke()
            NSBezierPath(rect: swatch).stroke()
            (label as NSString).draw(
                at: NSPoint(x: x + 19, y: y + 2),
                withAttributes: [.font: NSFont.systemFont(ofSize: max(8, font.pointSize - 2)), .foregroundColor: NSColor.darkGray]
            )
            x += 25 + (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: max(8, font.pointSize - 2))]).width
        }
    }

    var svgData: Data {
        var svg: [String] = []
        svg.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        svg.append(#"<svg xmlns="http://www.w3.org/2000/svg" width="\#(n(size.width))" height="\#(n(size.height))" viewBox="0 0 \#(n(size.width)) \#(n(size.height))">"#)
        svg.append(##"<rect width="100%" height="100%" fill="#ffffff"/>"##)
        if !title.isEmpty {
            svg.append(text(title, x: padding, y: padding + titleHeight / 2, size: font.pointSize * 1.25, color: .black, anchor: "start", weight: "700"))
        }
        if includeLegend {
            var legendX = padding
            let legendY = padding + titleHeight + legendHeight / 2
            for (label, color) in legendItems {
                svg.append(rect(x: legendX, y: legendY - 6, width: 14, height: 12, color: color))
                svg.append(text(label, x: legendX + 19, y: legendY, size: max(8, font.pointSize - 2), color: .darkGray, anchor: "start"))
                legendX += 25 + (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: max(8, font.pointSize - 2))]).width
            }
        }
        let contentHeight = headerHeight + CGFloat(rows.count) * rowHeight + consensusHeight + entropyHeight
        svg.append(rect(x: padding, y: gridHeaderOriginY, width: labelWidth, height: contentHeight, color: NSColor(calibratedWhite: 0.96, alpha: 1)))
        svg.append(rect(x: gridOriginX, y: gridHeaderOriginY, width: CGFloat(alignmentLength) * cellWidth, height: headerHeight, color: NSColor(calibratedWhite: 0.96, alpha: 1)))

        for column in 0..<alignmentLength where (column + columnNumberOffset + 1).isMultiple(of: numberingInterval) {
            let x = gridOriginX + CGFloat(column) * cellWidth + cellWidth / 2
            svg.append(##"<line x1="\##(n(x))" y1="\##(n(gridHeaderOriginY + headerHeight - 5))" x2="\##(n(x))" y2="\##(n(gridHeaderOriginY + contentHeight))" stroke="#b8b8bd" stroke-opacity="0.65"/>"##)
            svg.append(text("\(column + columnNumberOffset + 1)", x: gridOriginX + CGFloat(column) * cellWidth + cellWidth / 2, y: gridHeaderOriginY + rowHeight / 2, size: font.pointSize, color: .darkGray, anchor: "middle"))
        }
        svg.append(text("Alignment rows", x: padding + 10, y: gridHeaderOriginY + rowHeight / 2, size: boldFont.pointSize, color: .darkGray, anchor: "start", weight: "600"))

        for (rowIndex, row) in rows.enumerated() {
            let y = rowsOriginY + CGFloat(rowIndex) * rowHeight
            if rowIndex.isMultiple(of: 2) {
                svg.append(rect(x: padding, y: y, width: labelWidth + CGFloat(alignmentLength) * cellWidth, height: rowHeight, color: NSColor(calibratedWhite: 0.965, alpha: 1)))
            }
            svg.append(text(row.label, x: padding + 10, y: y + rowHeight / 2, size: font.pointSize, color: row.kind.isStructure ? .systemPurple : .black, anchor: "start", weight: row.kind.isStructure ? "600" : "400"))
            for column in 0..<min(alignmentLength, row.characters.count) {
                let character = row.characters[column]
                let x = gridOriginX + CGFloat(column) * cellWidth
                let cellStyle = style(for: row, column: column, character: character)
                if let background = cellStyle.background {
                    svg.append(rect(x: x, y: y, width: cellWidth, height: rowHeight, color: background))
                }
                if showGrid {
                    svg.append(##"<rect x="\##(n(x + 0.25))" y="\##(n(y + 0.25))" width="\##(n(cellWidth - 0.5))" height="\##(n(rowHeight - 0.5))" fill="none" stroke="#c7c7cc" stroke-opacity="0.55" stroke-width="0.5"/>"##)
                }
                svg.append(text(String(character), x: x + cellWidth / 2, y: y + rowHeight / 2, size: font.pointSize, color: cellStyle.foreground, anchor: "middle", weight: row.kind.isStructure ? "600" : "400"))
            }
        }

        if !consensusCharacters.isEmpty {
            let y = consensusOriginY
            svg.append(rect(x: padding, y: y, width: labelWidth, height: rowHeight, color: NSColor(calibratedWhite: 0.96, alpha: 1)))
            svg.append(##"<line x1="\##(n(padding))" y1="\##(n(y + 0.5))" x2="\##(n(size.width - padding))" y2="\##(n(y + 0.5))" stroke="#b8b8bd"/>"##)
            svg.append(text("R2R consensus", x: padding + 10, y: y + rowHeight / 2, size: boldFont.pointSize, color: .systemPurple, anchor: "start", weight: "600"))
            for column in 0..<min(alignmentLength, consensusCharacters.count) {
                let character = consensusCharacters[column]
                let x = gridOriginX + CGFloat(column) * cellWidth
                let cellStyle = consensusStyle(column: column, character: character)
                if let background = cellStyle.background {
                    svg.append(rect(x: x, y: y, width: cellWidth, height: rowHeight, color: background))
                }
                if showGrid {
                    svg.append(##"<rect x="\##(n(x + 0.25))" y="\##(n(y + 0.25))" width="\##(n(cellWidth - 0.5))" height="\##(n(rowHeight - 0.5))" fill="none" stroke="#c7c7cc" stroke-opacity="0.55" stroke-width="0.5"/>"##)
                }
                svg.append(text(String(character), x: x + cellWidth / 2, y: y + rowHeight / 2, size: font.pointSize, color: cellStyle.foreground, anchor: "middle"))
            }
        }

        if showEntropy || showGap {
            var trackY = entropyOriginY
            let tracks: [(String, [Double], NSColor)] = [
                showEntropy ? ("Entropy (0–2 bits)", entropyByColumn.map { $0 / 2.0 }, .systemIndigo) : nil,
                showGap ? ("Gap frequency (0–100%)", gapFrequencyByColumn, .systemTeal) : nil
            ].compactMap { $0 }
            for (title, values, color) in tracks {
                svg.append(rect(x: padding, y: trackY, width: labelWidth, height: analysisTrackHeight, color: NSColor(calibratedWhite: 0.96, alpha: 1)))
                svg.append(##"<line x1="\##(n(padding))" y1="\##(n(trackY + 0.5))" x2="\##(n(size.width - padding))" y2="\##(n(trackY + 0.5))" stroke="#b8b8bd"/>"##)
                svg.append(text(title, x: padding + 10, y: trackY + rowHeight / 2, size: font.pointSize, color: .darkGray, anchor: "start"))
                let baseline = trackY + analysisTrackHeight - 7
                let maximumBarHeight = max(1, analysisTrackHeight - 16)
                for column in 0..<min(alignmentLength, values.count) {
                    let fraction = max(0, min(1, values[column]))
                let barHeight = CGFloat(fraction) * maximumBarHeight
                guard barHeight > 0 else { continue }
                svg.append(rect(
                    x: gridOriginX + CGFloat(column) * cellWidth + 1,
                    y: baseline - barHeight,
                    width: max(1, cellWidth - 2),
                    height: barHeight,
                        color: color.withAlphaComponent(0.78)
                ))
                }
                trackY += analysisTrackHeight
            }
        }

        svg.append("</svg>")
        return Data(svg.joined(separator: "\n").utf8)
    }

    var tiledPDFData: Data {
        let pageSize = NSSize(width: 792, height: 612) // US Letter, landscape
        let horizontalPages = max(1, Int(ceil(size.width / pageSize.width)))
        let verticalPages = max(1, Int(ceil(size.height / pageSize.height)))
        let document = PDFDocument()
        var pageIndex = 0
        for verticalPage in 0..<verticalPages {
            for horizontalPage in 0..<horizontalPages {
                let origin = NSPoint(
                    x: CGFloat(horizontalPage) * pageSize.width,
                    y: CGFloat(verticalPage) * pageSize.height
                )
                let view = AlignmentPDFTileView(snapshot: self, tileOrigin: origin, pageSize: pageSize)
                let data = view.dataWithPDF(inside: view.bounds)
                if let tileDocument = PDFDocument(data: data), let page = tileDocument.page(at: 0) {
                    document.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            }
        }
        return document.dataRepresentation() ?? Data()
    }

    private func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) -> String {
        #"<rect x="\#(n(x))" y="\#(n(y))" width="\#(n(width))" height="\#(n(height))" \#(fill(color))/>"#
    }

    private func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, anchor: String, weight: String = "400") -> String {
        #"<text x="\#(n(x))" y="\#(n(y))" text-anchor="\#(anchor)" dominant-baseline="middle" font-family="Menlo, SFMono-Regular, monospace" font-size="\#(n(size))" font-weight="\#(weight)" \#(fill(color))>\#(xmlEscaped(value))</text>"#
    }

    private func fill(_ color: NSColor) -> String {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        let hex = String(format: "#%02X%02X%02X", red, green, blue)
        return String(format: "fill=\"%@\" fill-opacity=\"%.3f\"", hex, converted.alphaComponent)
    }

    private func n(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

@MainActor
private final class AlignmentPDFView: NSView {
    private let snapshot: AlignmentExportSnapshot

    init(snapshot: AlignmentExportSnapshot) {
        self.snapshot = snapshot
        super.init(frame: NSRect(origin: .zero, size: snapshot.size))
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        snapshot.drawAppKit(in: bounds)
    }
}

@MainActor
private final class AlignmentPDFTileView: NSView {
    private let snapshot: AlignmentExportSnapshot
    private let tileOrigin: NSPoint

    init(snapshot: AlignmentExportSnapshot, tileOrigin: NSPoint, pageSize: NSSize) {
        self.snapshot = snapshot
        self.tileOrigin = tileOrigin
        super.init(frame: NSRect(origin: .zero, size: pageSize))
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: -tileOrigin.x, y: -tileOrigin.y)
        snapshot.drawAppKit(in: NSRect(origin: .zero, size: snapshot.size))
        NSGraphicsContext.restoreGraphicsState()
    }
}
