import AppKit
import Foundation
import PDFKit

@main
struct ExportRegressionMain {
    @MainActor
    static func main() throws {
        let uniqueStemColors = Set((0..<256).map { stem -> String in
            let color = AlignmentPalette.stemColor(for: stem).usingColorSpace(.deviceRGB)!
            return String(format: "%.8f,%.8f,%.8f", color.redComponent, color.greenComponent, color.blueComponent)
        })
        precondition(uniqueStemColors.count == 256, "Stem colors repeated within the first 256 stems.")

        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        alpha GCAU
        beta  GUAC
        #=GR alpha PP 9988
        #=GC SS_cons <..>
        //
        """)
        let colors = AlignmentResidueColors(
            adenine: .systemGreen,
            cytosine: .systemBlue,
            guanine: .systemOrange,
            uracil: .systemRed
        )
        let arguments: (AlignmentExportFormat) -> Data = { format in
            AlignmentExporter.data(
                format: format,
                file: file,
                colorMode: .stem,
                residueColors: colors,
                hidePosteriorProbability: true,
                showEntropy: true,
                showGap: true,
                showConsensus: true,
                showGrid: true,
                fontSize: 15
            )
        }

        let svg = arguments(.svg)
        let pdf = arguments(.pdf)
        let svgText = String(decoding: svg, as: UTF8.self)
        precondition(svgText.contains("<svg"), "SVG root element is missing.")
        precondition(svgText.contains("Entropy (0–2 bits)"), "SVG entropy plot is missing.")
        precondition(svgText.contains("Gap frequency (0–100%)"), "SVG gap plot is missing.")
        precondition(svgText.contains("R2R consensus"), "SVG R2R consensus row is missing.")
        precondition(svgText.contains("&lt;"), "SVG structure symbols were not XML-escaped.")
        precondition(!svgText.contains("#=GR alpha PP"), "Hidden PP rows leaked into the SVG.")
        precondition(String(decoding: pdf.prefix(4), as: UTF8.self) == "%PDF", "PDF header is missing.")
        precondition(pdf.count > 1_000, "PDF export is unexpectedly small.")

        let selectedSVG = AlignmentExporter.data(
            format: .svg,
            file: file,
            colorMode: .residue,
            residueColors: colors,
            hidePosteriorProbability: true,
            showEntropy: false,
            showGrid: true,
            fontSize: 15,
            options: AlignmentExportOptions(
                title: "Selected & colored",
                includeLegend: true,
                numberingInterval: 2,
                labelWidth: 160,
                selectedRows: [0],
                selectedColumns: 1...2
            )
        )
        let selectedText = String(decoding: selectedSVG, as: UTF8.self)
        precondition(selectedText.contains("Selected &amp; colored"), "Export title was not escaped.")
        precondition(selectedText.contains(">C</text>") && selectedText.contains(">A</text>"), "Selected columns were not cropped correctly.")
        precondition(!selectedText.contains("beta"), "Selected rows were not cropped correctly.")

        let longSequence = String(repeating: "ACGU", count: 70)
        let longFile = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one \(longSequence)
        two \(longSequence)
        #=GC SS_cons \(String(repeating: ".", count: longSequence.count))
        //
        """)
        let tiledPDF = AlignmentExporter.data(
            format: .pdf,
            file: longFile,
            colorMode: .residue,
            residueColors: colors,
            hidePosteriorProbability: true,
            showEntropy: true,
            showGap: true,
            showGrid: true,
            fontSize: 15,
            options: AlignmentExportOptions(title: "Tiled", tiledPDF: true)
        )
        precondition((PDFDocument(data: tiledPDF)?.pageCount ?? 0) > 1, "Tiled PDF did not create multiple pages.")

        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let svgURL = outputDirectory.appendingPathComponent("MATER-export-test.svg")
        let pdfURL = outputDirectory.appendingPathComponent("MATER-export-test.pdf")
        try svg.write(to: svgURL, options: .atomic)
        try pdf.write(to: pdfURL, options: .atomic)
        print("MATER vector-export regression tests passed.")
        print("Wrote \(svgURL.path) and \(pdfURL.path)")
    }
}
