import Foundation

@main
struct CoreTestMain {
    private static var failures = 0

    static func main() {
        roundTripPreservesStockholmText()
        parsesCrossingPseudoknotLayers()
        recognizesCanonicalBasePairs()
        covariationClassification()
        calculatesColumnEntropy()
        calculatesConsensusAndGapFrequency()
        alignmentEditingKeepsRowsSynchronized()
        advancedGapAndRectangularEditing()
        searchesAndNavigatesProblems()
        removesEveryAllGapColumnSafely()
        canCreateAndRemovePseudoknotPair()
        if CommandLine.arguments.count > 1 {
            for path in CommandLine.arguments.dropFirst() { audit(path: path) }
        }
        guard failures == 0 else {
            fputs("\(failures) core test(s) failed.\n", stderr)
            exit(1)
        }
        print("All MATER core tests passed.")
    }

    private static func audit(path: String) {
        do {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let file = StockholmParser.parse(source)
            expect(file.rendered == source, "round-trip changed \(path)")
            let errors = file.validationIssues.filter { $0.severity == .error }
            expect(errors.isEmpty, "\(path): \(errors.map(\.message).joined(separator: "; "))")
            print("Audited \(URL(fileURLWithPath: path).lastPathComponent): \(file.sequenceRows.count) sequences × \(file.alignmentLength) columns, \(file.structureRows.count) structure layer(s)")
        } catch {
            expect(false, "could not read \(path): \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
        if !condition() {
            failures += 1
            fputs("FAIL line \(line): \(message)\n", stderr)
        }
    }

    private static func roundTripPreservesStockholmText() {
        let text = """
        # STOCKHOLM 1.0
        #=GF ID example
        seq/1-8      GCAU--GC
        seq2         GUAU--AC
        #=GR seq2 PP 9999..88
        #=GC SS_cons <<....>>
        #=GC RF      xxxxxx..
        //
        """
        let file = StockholmParser.parse(text)
        expect(file.rendered == text, "round-trip changed the source text")
        expect(file.sequenceRows.count == 2, "sequence row count")
        expect(file.alignmentLength == 8, "alignment length")
        expect(file.structureRows.count == 1, "structure row count")
        expect(file.validationIssues.isEmpty, "valid fixture reported issues")
    }

    private static func parsesCrossingPseudoknotLayers() {
        let text = """
        # STOCKHOLM 1.0
        one GCGAAACGCUUCGG
        two GUGAAACGCAACGG
        #=GC SS_cons <<....>>......
        #=GC SS_cons_2 ..((....))....
        //
        """
        let file = StockholmParser.parse(text)
        let pairs = StructureParser.pairs(in: file)
        expect(pairs.count == 4, "pair count")
        expect(pairs.contains { $0.left == 0 && $0.right == 7 }, "primary pair missing")
        expect(pairs.contains { $0.left == 2 && $0.right == 9 && $0.isPseudoknot }, "crossing pseudoknot missing")
        expect(Set(pairs.map(\.stem)).count == 2, "stacked pairs were not grouped into two stems")
        expect(file.validationIssues.isEmpty, "pseudoknot fixture reported issues")
    }

    private static func covariationClassification() {
        let text = """
        # STOCKHOLM 1.0
        reference_1 GC
        reference_2 GC
        compensatory AU
        one_sided GU
        invalid GG
        gapped G-
        #=GC SS_cons <>
        //
        """
        let file = StockholmParser.parse(text)
        let classes = CovariationAnalyzer.classifications(in: file)
        let rows = Dictionary(uniqueKeysWithValues: file.sequenceRows.compactMap { row -> (String, Int)? in
            guard case .sequence(let name) = row.kind else { return nil }
            return (name, row.recordIndex)
        })
        expect(classes[rows["reference_1"]!]?[0] == .conserved, "conserved classification")
        expect(classes[rows["compensatory"]!]?[0] == .compensatory, "compensatory classification")
        expect(classes[rows["one_sided"]!]?[0] == .consistent, "one-sided classification")
        expect(classes[rows["invalid"]!]?[0] == .noncanonical, "noncanonical classification")
        expect(classes[rows["gapped"]!]?[0] == .gap, "gap classification")
    }

    private static func recognizesCanonicalBasePairs() {
        for pair in ["AU", "UA", "GC", "CG", "GU", "UG", "AT", "TA"] {
            expect(BasePairRules.isCanonical(pair.first!, pair.last!), "canonical pair \(pair)")
        }
        for pair in ["AA", "AC", "GG", "UU", "G-", "NN"] {
            expect(!BasePairRules.isCanonical(pair.first!, pair.last!), "noncanonical pair \(pair)")
        }
    }

    private static func calculatesColumnEntropy() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one AA-
        two AC-
        three AG-
        four AT-
        #=GC SS_cons ...
        //
        """)
        let entropy = EntropyAnalyzer.columnEntropies(in: file)
        expect(entropy.count == 3, "entropy column count")
        expect(abs(entropy[0]) < 0.000_001, "conserved-column entropy")
        expect(abs(entropy[1] - 2.0) < 0.000_001, "maximal RNA entropy")
        expect(abs(entropy[2]) < 0.000_001, "gap-only entropy")
    }

    private static func calculatesConsensusAndGapFrequency() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one AC-U
        two AT-G
        three AG-G
        #=GC SS_cons ....
        //
        """)
        expect(ConsensusAnalyzer.consensus(in: file) == "AC-G", "RNA consensus calculation")
        let gaps = GapAnalyzer.columnGapFrequencies(in: file)
        expect(abs(gaps[2] - 1.0) < 0.000_001, "gap-frequency calculation")
    }

    private static func alignmentEditingKeepsRowsSynchronized() {
        var file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one A-CG
        two A-GG
        #=GC SS_cons <..>
        //
        """)
        expect(file.shift(row: 0, selection: 2...2, direction: -1), "shift failed")
        expect(file.records[file.sequenceRows[0].recordIndex].aligned == "AC-G", "shift output")
        file.insertColumn(at: 2)
        expect(file.alignmentLength == 5, "insert column length")
        expect(Set(file.rows.map { file.records[$0.recordIndex].aligned.count }) == [5], "rows became unsynchronized")
        expect(file.deleteColumn(at: 2), "all-gap column delete")
        expect(file.alignmentLength == 4, "delete column length")
    }

    private static func advancedGapAndRectangularEditing() {
        var file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one -A-C-
        two -G-U-
        #=GC SS_cons .....
        //
        """)
        expect(file.shift(rows: [0, 1], columns: [1, 3], direction: -1), "rectangular discontinuous shift failed")
        expect(file.records[file.sequenceRows[0].recordIndex].aligned == "A-C--", "first discontinuous-shift row")
        expect(file.records[file.sequenceRows[1].recordIndex].aligned == "G-U--", "second discontinuous-shift row")

        var gapFile = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one ACG-U
        #=GC SS_cons .....
        //
        """)
        expect(gapFile.openGap(row: 0, at: 1), "open-gap command failed")
        expect(gapFile.records[gapFile.sequenceRows[0].recordIndex].aligned == "A-CGU", "open-gap output")
        expect(gapFile.closeGap(row: 0, at: 1), "close-gap command failed")
        expect(gapFile.records[gapFile.sequenceRows[0].recordIndex].aligned == "ACGU-", "close-gap output")
    }

    private static func searchesAndNavigatesProblems() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        alpha GC
        beta  GG
        #=GC SS_cons <>
        //
        """)
        let motif = AlignmentSearch.find("GG", in: file, afterRow: 0, afterColumn: 0)
        expect(motif?.row == 1 && motif?.column == 0, "motif search")
        let column = AlignmentSearch.find("col:2", in: file, afterRow: 0, afterColumn: 0)
        expect(column?.column == 1, "column search")
        let problem = AlignmentProblemAnalyzer.next(
            kind: .noncanonical,
            in: file,
            afterRow: 0,
            afterColumn: 0,
            entropyThreshold: 1.0,
            gapThreshold: 0.5
        )
        expect(problem?.row == 1 && problem?.column == 0, "noncanonical navigation")
    }

    private static func removesEveryAllGapColumnSafely() {
        var file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one -A--C
        two .U--G
        #=GR one PP .9..9
        #=GC SS_cons <...>
        //
        """)
        let ppRows = file.rows.filter(\.kind.isPosteriorProbability)
        expect(ppRows.count == 1, "PP annotation detection")

        let removed = file.removeAllGapColumns()
        expect(removed == [0, 2, 3], "all-gap column indices")
        expect(file.alignmentLength == 2, "bulk gap removal length")
        expect(Set(file.rows.map { file.records[$0.recordIndex].aligned.count }) == [2], "bulk removal desynchronized rows")
        expect(StructureParser.pairs(in: file).isEmpty, "orphaned structural pair was not cleared")
        expect(file.validationIssues.filter { $0.severity == .error }.isEmpty, "bulk removal produced invalid Stockholm")
    }

    private static func canCreateAndRemovePseudoknotPair() {
        var file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one ACGUAC
        two ACGUAC
        #=GC SS_cons ......
        //
        """)
        file.setPair(left: 1, right: 4, layer: .pseudoknot1)
        expect(file.structureRows.count == 2, "pseudoknot row was not created")
        expect(StructureParser.pairs(in: file).contains { $0.left == 1 && $0.right == 4 && $0.structureTag == "SS_cons_2" }, "pseudoknot pair was not created")
        file.clearPairs(touching: 1...1)
        expect(!StructureParser.pairs(in: file).contains { $0.left == 1 || $0.right == 1 }, "pseudoknot pair was not removed")
    }
}
