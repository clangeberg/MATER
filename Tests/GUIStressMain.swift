import AppKit
import Darwin
import Foundation
import SwiftUI

@main
struct GUIStressMain {
    private struct StressCase {
        let rows: Int
        let columns: Int
    }

    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let quick = ProcessInfo.processInfo.environment["MATER_STRESS_QUICK"] == "1"
        let cases = quick
            ? [StressCase(rows: 100, columns: 1_000), StressCase(rows: 500, columns: 1_000)]
            : [
                StressCase(rows: 100, columns: 1_000),
                StressCase(rows: 1_000, columns: 1_000),
                StressCase(rows: 5_000, columns: 1_000),
                StressCase(rows: 200, columns: 10_000)
            ]

        for stressCase in cases {
            print("Starting GUI stress case \(stressCase.rows)×\(stressCase.columns)…")
            fflush(stdout)
            autoreleasepool {
                exercise(stressCase)
            }
        }
        print("MATER \(quick ? "quick" : "full") GUI stress matrix passed (\(cases.count) alignment sizes).")
    }

    @MainActor
    private static func exercise(_ stressCase: StressCase) {
        let label = "\(stressCase.rows)×\(stressCase.columns)"
        let source = makeAlignment(rows: stressCase.rows, columns: stressCase.columns)
        let creation = measure {
            StockholmDocument(previewFile: StockholmParser.parse(source))
        }
        let document = creation.value
        precondition(document.analysis.validationIssues.filter { $0.severity == .error }.isEmpty, "\(label) validation failed")
        precondition(document.analysis.sequenceCount == stressCase.rows)
        precondition(document.analysis.alignmentLength == stressCase.columns)

        let palette = ResiduePaletteSettings()
        let state = EditorState()
        state.showInspector = false
        state.showMinimap = true
        let canvas = AlignmentCanvasView()

        let firstRender = measure {
            state.colorMode = .stem
            canvas.configure(document: document, state: state, residuePalette: palette)
            render(canvas, rect: viewport(in: canvas.bounds, horizontalFraction: 0, verticalFraction: 0))
        }
        let distantRender = measure {
            state.select(row: max(0, stressCase.rows - 1), column: max(0, stressCase.columns - 1))
            state.colorMode = .residue
            canvas.configure(document: document, state: state, residuePalette: palette)
            render(canvas, rect: viewport(in: canvas.bounds, horizontalFraction: 1, verticalFraction: 1))
        }
        let covarianceRender = measure {
            state.colorMode = .covariation
            canvas.configure(document: document, state: state, residuePalette: palette)
            render(canvas, rect: viewport(in: canvas.bounds, horizontalFraction: 0.5, verticalFraction: 0.5))
        }

        let before = document.file
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        var shifted = false
        let edit = measure {
            document.mutate("Stress linked-safe shift", undoManager: undoManager) { file in
                shifted = file.shift(row: 0, selection: 1...1, direction: -1)
            }
        }
        undoManager.endUndoGrouping()
        precondition(shifted, "\(label) protected shift failed")
        let after = document.file
        precondition(SequenceIntegrityAnalyzer.preservesSequences(from: before, to: after))
        precondition(ResidueAnnotationIntegrityAnalyzer.preservesAttachmentsForMovedSequences(from: before, to: after))
        undoManager.undo()
        precondition(document.file == before, "\(label) undo failed")
        undoManager.redo()
        precondition(document.file == after, "\(label) redo failed")

        let reopen = measure {
            let parsed = StockholmParser.parse(document.file.rendered)
            precondition(parsed.validationIssues.filter { $0.severity == .error }.isEmpty)
            precondition(SequenceIntegrityAnalyzer.preservesSequences(from: document.file, to: parsed))
        }

        let exportRows = Set(0..<min(30, document.analysis.rows.count))
        let exportColumns = 0...min(999, stressCase.columns - 1)
        var options = AlignmentExportOptions()
        options.title = "MATER stress \(label)"
        options.selectedRows = exportRows
        options.selectedColumns = exportColumns
        options.tiledPDF = true
        let colors = AlignmentResidueColors(
            adenine: palette.adenine,
            cytosine: palette.cytosine,
            guanine: palette.guanine,
            uracil: palette.uracil
        )
        let export = measure {
            let pdf = AlignmentExporter.data(
                format: .pdf,
                file: document.file,
                colorMode: .stem,
                residueColors: colors,
                hidePosteriorProbability: true,
                showEntropy: true,
                showGap: true,
                showConsensus: true,
                showGrid: true,
                fontSize: 12,
                options: options
            )
            let svg = AlignmentExporter.data(
                format: .svg,
                file: document.file,
                colorMode: .residue,
                residueColors: colors,
                hidePosteriorProbability: true,
                showEntropy: true,
                showGap: true,
                showConsensus: true,
                showGrid: false,
                fontSize: 12,
                options: options
            )
            precondition(String(decoding: pdf.prefix(4), as: UTF8.self) == "%PDF")
            precondition(String(decoding: svg.prefix(64), as: UTF8.self).contains("<svg"))
        }

        print(String(
            format: "%@ create/analyze %.2fs | first %.2fs | distant %.2fs | pair variation %.2fs | edit %.2fs | reopen %.2fs | bounded PDF+SVG %.2fs | peak %.0f MB",
            label,
            creation.seconds,
            firstRender.seconds,
            distantRender.seconds,
            covarianceRender.seconds,
            edit.seconds,
            reopen.seconds,
            export.seconds,
            peakResidentMegabytes()
        ))
        fflush(stdout)
    }

    @MainActor
    private static func render(_ view: NSView, rect: NSRect) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else {
            preconditionFailure("could not allocate offscreen GUI bitmap")
        }
        view.cacheDisplay(in: rect, to: bitmap)
        precondition(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
    }

    private static func viewport(
        in bounds: NSRect,
        horizontalFraction: CGFloat,
        verticalFraction: CGFloat
    ) -> NSRect {
        let width = min(1_440, bounds.width)
        let height = min(900, bounds.height)
        return NSRect(
            x: max(0, bounds.width - width) * horizontalFraction,
            y: max(0, bounds.height - height) * verticalFraction,
            width: width,
            height: height
        )
    }

    private static func makeAlignment(rows: Int, columns: Int) -> String {
        precondition(columns >= 50)
        var template = Array(repeating: Character("A"), count: columns)
        for column in template.indices {
            switch column % 17 {
            case 0: template[column] = "-"
            case 5: template[column] = "."
            case 1, 7, 11: template[column] = "G"
            case 2, 8, 12: template[column] = "C"
            case 3, 9, 13: template[column] = "U"
            default: template[column] = "A"
            }
        }
        template[0] = "-"
        template[1] = "G"
        var structure = Array(repeating: Character("."), count: columns)
        for offset in 0..<10 {
            structure[10 + offset] = "<"
            structure[columns - 11 - offset] = ">"
            structure[40 + offset] = "A"
            structure[columns - 41 - offset] = "a"
        }

        var source = "# STOCKHOLM 1.0\n#=GF ID stress_\(rows)x\(columns)\n"
        source.reserveCapacity(rows * (columns + 32))
        for row in 0..<rows {
            var sequence = template
            for offset in 0..<10 {
                sequence[10 + offset] = row.isMultiple(of: 3) ? "G" : "A"
                sequence[columns - 11 - offset] = row.isMultiple(of: 3) ? "C" : "U"
                sequence[40 + offset] = "G"
                sequence[columns - 41 - offset] = "C"
            }
            // Keep the matrix deep and somewhat diverse without turning the
            // exact GSC guide-tree check into the sole purpose of this GUI
            // stress test. Repeated patterns also exercise duplicate collapse.
            let pattern = row % 128
            for bit in 0..<7 {
                let column = 100 + bit * 13
                sequence[column] = (pattern & (1 << bit)) == 0 ? "A" : "U"
            }
            let name = "stress_\(row)"
            source += "\(name) \(String(sequence))\n"
            if row.isMultiple(of: 25) {
                let pp = sequence.map { AlignmentSymbol.isSequenceGap($0) ? $0 : "9" }
                source += "#=GR \(name) PP \(String(pp))\n"
            }
        }
        source += "#=GC SS_cons \(String(structure))\n//\n"
        return source
    }

    private static func measure<T>(_ operation: () -> T) -> (value: T, seconds: TimeInterval) {
        let start = ContinuousClock.now
        let value = operation()
        let duration = start.duration(to: .now).components
        return (value, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }

    private static func peakResidentMegabytes() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576
    }
}
