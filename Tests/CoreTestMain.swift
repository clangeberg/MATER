import Foundation

@main
struct CoreTestMain {
    private static var failures = 0

    static func main() async {
        roundTripPreservesStockholmText()
        joinsInterleavedStockholmBlocks()
        parsesCrossingPseudoknotLayers()
        groupsBulgedStemsAndMajorElements()
        recognizesCanonicalBasePairs()
        covariationClassification()
        calculatesColumnEntropy()
        calculatesR2RConsensusAndGapFrequency()
        verifiesSequenceIntegrity()
        calculatesStructuralQuality()
        suggestsSafeStemImprovements()
        optimizesCompleteHelixWindows()
        leavesUnoccupiedStructuralVariantsAlone()
        parsesRScapeOutputsAndHandlesMissingExecutable()
        await runsCaCoFoldRefinementAndDiscardsTemporaryArtifacts()
        await runsRScapeIntegrationWhenRequested()
        refinesEntireAlignmentWithoutChangingSequences()
        alignmentEditingKeepsRowsSynchronized()
        advancedGapAndRectangularEditing()
        stemAwareAndLinkedArmShifting()
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
            if file.normalizedInterleavedSegmentCount == 0 {
                expect(file.rendered == source, "round-trip changed \(path)")
            } else {
                let reparsed = StockholmParser.parse(file.rendered)
                expect(reparsed.rendered == file.rendered, "interleaved normalization was not idempotent for \(path)")
                expect(reparsed.normalizedInterleavedSegmentCount == 0, "normalized output remained interleaved for \(path)")
            }
            let errors = file.validationIssues.filter { $0.severity == .error }
            expect(errors.isEmpty, "\(path): \(errors.map(\.message).joined(separator: "; "))")
            print("Audited \(URL(fileURLWithPath: path).lastPathComponent): \(file.sequenceRows.count) sequences × \(file.alignmentLength) columns, \(file.structureRows.count) structure layer(s)")
            if ProcessInfo.processInfo.environment["MATER_REFINE_AUDIT"] == "1" {
                let started = Date()
                let result = StemEditSuggester.refineEntireAlignment(in: file, preferLinked: true)
                expect(SequenceIntegrityAnalyzer.preservesSequences(from: file, to: result.file), "auto-refinement changed ungapped sequences in \(path)")
                expect(result.after.canonical >= result.before.canonical, "auto-refinement reduced canonical support in \(path)")
                expect(result.after.noncanonical <= result.before.noncanonical, "auto-refinement increased violations in \(path)")
                print("Auto-refined \(URL(fileURLWithPath: path).lastPathComponent): \(result.editCount) edits across \(result.changedSequenceCount) sequences in \(result.passes) passes and \(String(format: "%.2f", Date().timeIntervalSince(started))) s; converged=\(result.converged)")
            }
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
        expect(file.rows.contains { $0.kind.selectsWholeColumn && $0.label == "#=GC SS_cons" }, "SS_cons whole-column selection marker")
        expect(file.rows.contains { $0.kind.selectsWholeColumn && $0.label == "#=GC RF" }, "RF whole-column selection marker")
        expect(AlignmentRowKind.columnAnnotation(tag: "cons").selectsWholeColumn, "cons whole-column selection marker")
        expect(file.validationIssues.isEmpty, "valid fixture reported issues")
    }

    private static func joinsInterleavedStockholmBlocks() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        #=GF ID wrapped
        seq1          GCAU
        seq2          GU-U
        #=GR seq1 PP  9988
        #=GC SS_cons  <<>>

        # a preserved block comment
        seq1          AACG
        seq2          AA-G
        #=GR seq1 PP  7766
        #=GC SS_cons  (())
        //
        """)
        expect(file.sequenceRows.count == 2, "interleaved sequences were not collapsed into logical rows")
        expect(file.alignmentLength == 8, "interleaved segment widths were not concatenated")
        expect(file.records[file.sequenceRows[0].recordIndex].aligned == "GCAUAACG", "first wrapped sequence was not joined")
        expect(file.records[file.sequenceRows[1].recordIndex].aligned == "GU-UAA-G", "second wrapped sequence was not joined")
        let structureRows = file.structureRows
        expect(structureRows.count == 1, "wrapped SS_cons rows were not joined")
        if let structureRow = structureRows.first {
            expect(file.records[structureRow.recordIndex].aligned == "<<>>(())", "wrapped SS_cons content was not joined")
        }
        let ppRows = file.rows.filter(\.kind.isPosteriorProbability)
        expect(ppRows.count == 1, "wrapped #=GR rows were not joined")
        if let ppRow = ppRows.first {
            expect(file.records[ppRow.recordIndex].aligned == "99887766", "wrapped #=GR content was not joined")
        }
        expect(file.normalizedInterleavedSegmentCount == 4, "interleaved normalization count")
        expect(file.rendered.contains("# a preserved block comment"), "interleaved raw comments were not preserved")
        expect(file.validationIssues.allSatisfy { $0.severity != .error }, "normalized interleaved file has validation errors")
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

    private static func groupsBulgedStemsAndMajorElements() {
        func file(with structure: String) -> StockholmFile {
            StockholmParser.parse("""
            # STOCKHOLM 1.0
            one             \(String(repeating: "A", count: structure.count))
            #=GC SS_cons    \(structure)
            //
            """)
        }

        let bulgedPairs = StructureParser.pairs(in: file(with: "(((.....)).)"))
        expect(bulgedPairs.count == 3, "bulged stem pair count")
        expect(Set(bulgedPairs.map(\.stem)).count == 1, "a one-column arm bulge split one helix into multiple stems")

        let continuous = StructureParser.pairs(in: file(with: "((..(.(....(((.....)).)))....)..)"))
        expect(Set(continuous.map(\.element)).count == 1, "a continuous nested helix was split across large internal loops")

        let disjoint = StructureParser.pairs(in: file(with: "((...))((..))"))
        expect(Set(disjoint.map(\.element)).count == 2, "two disjoint helices were merged into one element")

        let branched = StructureParser.pairs(in: file(with: "((((((...)))(((...))))))"))
        expect(Set(branched.map(\.element)).count == 3, "an outer helix with two child branches did not produce three elements")

        let explicit = StructureParser.pairs(in: file(with: "((((([[[[[.....]]]]]...{{{{{.....}}}}})))))"))
        let ordinary = StructureParser.pairs(in: file(with: "((((((((((.....)))))...(((((.....))))))))))"))
        expect(Set(explicit.map(\.stem)).count == 3, "explicit nested WUSS classes did not produce three stacks")
        expect(Set(ordinary.map(\.stem)).count == 3, "ordinary dot-bracket topology did not preserve three stacks")
        expect(Set(explicit.map(\.element)).count == 3, "explicit WUSS classes did not retain three high-level elements")
        expect(Set(ordinary.map(\.element)).count == 3, "ordinary dot-bracket branching did not produce three high-level elements")

        let knotPairs = StructureParser.pairs(in: file(with: "AA..BB..CC..aa..bb..cc"))
        expect(Set(knotPairs.map(\.stem)).count == 3, "crossing K/L/M-style classes were not retained as separate stems")
        expect(Set(knotPairs.map(\.element)).count == 3, "crossing pseudoknot classes did not retain distinct elements")
        expect(knotPairs.allSatisfy(\.isPseudoknot), "lettered pseudoknot pairs lost their pseudoknot identity")
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

    private static func calculatesR2RConsensusAndGapFrequency() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one AC-U
        two AT-G
        three AG-G
        #=GC SS_cons ....
        //
        """)
        expect(ConsensusAnalyzer.consensus(in: file) == "An-n", "GSC-weighted RNA consensus calculation")
        let gaps = GapAnalyzer.columnGapFrequencies(in: file)
        expect(abs(gaps[2] - 1.0) < 0.000_001, "gap-frequency calculation")

        // This is the official R2R 1.0.7 demo alignment and its generated
        // sequence consensus, providing an end-to-end compatibility fixture.
        let r2rDemo = StockholmParser.parse("""
        # STOCKHOLM 1.0
        human   ACACGCGAAA.GCGCAA.CAAACGUGCACGG
        chimp   GAAUGUGAAAAACACCA.CUCUUGAGGACCU
        bigfoot UUGAG.UUCG..CUCGUUUUCUCGAGUACAC
        //
        """)
        expect(
            ConsensusAnalyzer.consensus(in: r2rDemo) == "nnRnGnnnnR-nCnCnn-YnnnYGnGnACnn",
            "consensus differs from the official R2R 1.0.7 demo output"
        )

        let ambiguous = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one A
        two N
        three R
        //
        """)
        expect(ConsensusAnalyzer.consensus(in: ambiguous) == "A", "ambiguous input residues should be omitted from R2R counts")

        let fragmentary = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one -A-
        two GCG
        //
        """)
        expect(ConsensusAnalyzer.consensus(in: fragmentary) == "GnG", "terminal fragment gaps should be excluded from R2R counts")

        expect(ConsensusAnalyzer.symbol(for: [0.75, 0, 0.25, 0, 0]) == "A", "75% identity threshold")
        expect(ConsensusAnalyzer.symbol(for: [0.74, 0, 0.26, 0, 0]) == "R", "purine ambiguity threshold")
        expect(ConsensusAnalyzer.symbol(for: [0, 0.50, 0, 0.50, 0]) == "Y", "pyrimidine ambiguity threshold")
        expect(ConsensusAnalyzer.symbol(for: [0.40, 0.20, 0.20, 0.10, 0.10]) == "n", "R2R nucleotide-presence symbol")
        expect(ConsensusAnalyzer.symbol(for: [0.20, 0, 0, 0, 0.80]) == "-", "R2R low-presence symbol")
    }

    private static func verifiesSequenceIntegrity() {
        let baseline = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one A-CG
        two AU-G
        //
        """)
        var gapOnlyEdit = baseline
        expect(gapOnlyEdit.shift(row: 0, selection: 2...2, direction: -1), "integrity gap-shift fixture failed")
        expect(
            SequenceIntegrityAnalyzer.preservesSequences(from: baseline, to: gapOnlyEdit),
            "gap-only alignment edit changed sequence integrity"
        )
        var residueEdit = baseline
        residueEdit.replaceCharacter(row: 0, column: 0, with: "U")
        let report = SequenceIntegrityAnalyzer.report(current: residueEdit, baseline: baseline)
        expect(!report.isIntact && report.changedSequenceCount == 1, "residue change was not reported by the integrity analyzer")
    }

    private static func calculatesStructuralQuality() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        reference GC
        canonical AU
        invalid GG
        gapped G-
        ambiguous GN
        #=GC SS_cons <>
        //
        """)
        guard let quality = StructuralQualityAnalyzer.stem(containing: 0, in: file) else {
            expect(false, "structural quality was not calculated")
            return
        }
        expect(quality.canonical == 2, "structural canonical count")
        expect(quality.noncanonical == 1, "structural noncanonical count")
        expect(quality.gaps == 1, "structural gap count")
        expect(quality.ambiguous == 1, "structural ambiguity count")
        expect(quality.issues.count == 3, "structural issue list")
        expect(quality.problemRecordIndices.count == 1, "only definite pair violations should enter the problem filter")
        expect(abs(quality.canonicalFraction - (2.0 / 3.0)) < 0.000_001, "canonical support should use occupied, evaluable pairs")
        expect(abs(quality.noncanonicalFraction - (1.0 / 3.0)) < 0.000_001, "violation rate should use occupied, evaluable pairs")
        let problemFractions = StructuralQualityAnalyzer.problemFractionsByColumn(in: file)
        expect(problemFractions.count == 2, "pair-violation heatmap width")
        expect(abs(problemFractions[0] - (1.0 / 3.0)) < 0.000_001, "gaps and ambiguity should not inflate pair violations")
        expect(abs(problemFractions[1] - (1.0 / 3.0)) < 0.000_001, "paired columns should share the violation fraction")
    }

    private static func suggestsSafeStemImprovements() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        needs_shift -A--U-
        aligned     A---U-
        #=GC SS_cons <...>.
        //
        """)
        let suggestions = StemEditSuggester.suggestions(in: file, modelRow: 0, column: 0, preferLinked: true)
        expect(!suggestions.isEmpty, "no gap-only stem improvement was suggested")
        guard let suggestion = suggestions.first(where: { $0.proposedAligned == "A---U-" }) else {
            expect(false, "expected close-gap stem improvement was not suggested")
            return
        }
        expect(suggestion.after.canonical > suggestion.before.canonical, "suggestion did not improve canonical support")
        var proposed = file
        proposed.records[suggestion.recordIndex].aligned = suggestion.proposedAligned
        expect(SequenceIntegrityAnalyzer.preservesSequences(from: file, to: proposed), "suggestion changed the ungapped sequence")
    }

    private static func optimizesCompleteHelixWindows() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        needs_window -AU----AU---
        aligned      --AU----AU--
        #=GC SS_cons ..<<....>>..
        //
        """)
        let suggestions = StemEditSuggester.suggestions(in: file, modelRow: 0, column: 2, preferLinked: true)
        guard let suggestion = suggestions.first(where: {
            $0.operationTitle.contains("Optimize helix") && $0.proposedAligned == "--AU----AU--"
        }) else {
            expect(false, "complete helix-window optimization was not suggested")
            return
        }
        expect(suggestion.after.canonical == 2, "helix-window optimization did not recover both pairs")
        expect(suggestion.after.noncanonical == 0, "helix-window optimization retained a definite violation")
        expect(suggestion.residueDisplacement >= 2, "helix-window optimization did not report its multi-residue move")
        var proposed = file
        proposed.records[suggestion.recordIndex].aligned = suggestion.proposedAligned
        expect(SequenceIntegrityAnalyzer.preservesSequences(from: file, to: proposed), "helix-window optimization changed ungapped residues")
    }

    private static func leavesUnoccupiedStructuralVariantsAlone() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        subtype --AU--------
        aligned --AU----AU--
        #=GC SS_cons ..<<....>>..
        //
        """)
        let suggestions = StemEditSuggester.suggestions(in: file, modelRow: 0, column: 2, preferLinked: true)
        expect(
            !suggestions.contains(where: { $0.operationTitle.contains("Optimize helix") }),
            "an unoccupied helix arm should be treated as a possible structural variant"
        )
    }

    private static func parsesRScapeOutputsAndHandlesMissingExecutable() {
        let covariance = """
        # Method Target_E-val
        *  2  20  45.0  0.001
           4  18  39.0  0.020
        """
        let power = """
        # BPAIRS 12
        # BPAIRS expected to covary 4.7 +/- 1.2
        # BPAIRS observed to covary 1
        """
        let process = """
        # R-scape :: RNA Structural Covariation Above Phylogenetic Expectation
        # R-scape 2.6.16 (August 2026)
        """
        let summary = RScapeOutputParser.summary(
            covarianceText: covariance,
            powerText: power,
            processText: process
        )
        expect(summary.version == "2.6.16", "R-scape version parsing")
        expect(summary.significantPairs == 2, "R-scape significant-pair parsing")
        expect(summary.significantAnnotatedPairs == 1, "R-scape annotated-pair parsing")
        expect(summary.annotatedBasePairs == 12, "R-scape proposed-pair parsing")
        expect(abs((summary.expectedCovaryingPairs ?? 0) - 4.7) < 0.000_001, "R-scape expected-covariation parsing")
        expect(summary.observedCovaryingPairs == 1, "R-scape observed-covariation parsing")
        expect(
            RScapeExecutableLocator.resolveSelection(URL(fileURLWithPath: "/definitely/missing/R-scape")) == nil,
            "a missing R-scape executable should be a normal nil result"
        )

        let installation = FileManager.default.temporaryDirectory
            .appendingPathComponent("MATER-RScape-locator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: installation) }
        do {
            let sourceDirectory = installation.appendingPathComponent("src", isDirectory: true)
            let binDirectory = installation.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
            let sourceExecutable = sourceDirectory.appendingPathComponent("R-scape")
            let binExecutable = binDirectory.appendingPathComponent("R-scape")
            let r2rExecutable = binDirectory.appendingPathComponent("R2R")
            for url in [sourceExecutable, binExecutable, r2rExecutable] {
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            expect(
                RScapeExecutableLocator.resolveSelection(sourceExecutable)?.path == binExecutable.path,
                "selecting src/R-scape did not prefer the installed bin/R-scape with R2R"
            )
            expect(
                RScapeExecutableLocator.resolveSelection(installation)?.path == binExecutable.path,
                "selecting an R-scape installation folder did not resolve bin/R-scape"
            )
        } catch {
            expect(false, "could not construct R-scape locator fixture: \(error.localizedDescription)")
        }
    }

    private static func runsRScapeIntegrationWhenRequested() async {
        let environment = ProcessInfo.processInfo.environment
        guard let executablePath = environment["MATER_RSCAPE_EXECUTABLE"],
              let inputPath = environment["MATER_RSCAPE_INPUT"] else { return }

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MATER-RScape-integration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        do {
            let source = try String(contentsOfFile: inputPath, encoding: .utf8)
            let result = try await RScapeRunner.run(
                executableURL: URL(fileURLWithPath: executablePath),
                stockholmText: source,
                outputDirectory: outputDirectory,
                outputName: "integration-test",
                processHandle: RScapeProcessHandle()
            )
            expect(FileManager.default.fileExists(atPath: result.covarianceTableURL.path), "R-scape integration .cov output")
            expect(FileManager.default.fileExists(atPath: result.r2rPDFURL.path), "R-scape integration R2R PDF output")
            expect(result.inputSnapshotURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } == source, "R-scape integration input snapshot")
            expect((result.summary.annotatedBasePairs ?? 0) > 0, "R-scape integration power summary")
            let caCoFoldText = try await RScapeRunner.refineStructureWithCaCoFold(
                executableURL: URL(fileURLWithPath: executablePath),
                stockholmText: source,
                processHandle: RScapeProcessHandle()
            )
            let caCoFoldFile = StockholmParser.parse(caCoFoldText)
            expect(!caCoFoldFile.sequenceRows.isEmpty, "CaCoFold integration sequence rows")
            expect(!caCoFoldFile.structureRows.isEmpty, "CaCoFold integration structure rows")
            expect(
                caCoFoldFile.validationIssues.allSatisfy { $0.severity != .error },
                "CaCoFold integration produced an invalid Stockholm alignment"
            )
            let annotated = result.summary.annotatedBasePairs.map(String.init) ?? "unknown"
            print("R-scape and CaCoFold integration passed with \(result.summary.significantPairs) significant pair(s) across \(annotated) annotated pair(s).")
        } catch {
            expect(false, "R-scape integration failed: \(error.localizedDescription)")
        }
    }

    private static func runsCaCoFoldRefinementAndDiscardsTemporaryArtifacts() async {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MATER-CaCoFold-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        do {
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            let executableURL = fixtureDirectory.appendingPathComponent("R-scape")
            let executable = """
            #!/bin/sh
            saw_structure=0
            saw_cacofold=0
            saw_nofigures=0
            saw_onemsa=0
            outdir=""
            outname=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                -s) saw_structure=1 ;;
                --cacofold) saw_cacofold=1 ;;
                --nofigures) saw_nofigures=1 ;;
                --onemsa) saw_onemsa=1 ;;
                --outdir) shift; outdir="$1" ;;
                --outname) shift; outname="$1" ;;
              esac
              shift
            done
            if [ "$saw_structure$saw_cacofold$saw_nofigures$saw_onemsa" != "1111" ]; then exit 42; fi
            printf '# STOCKHOLM 1.0\n#=GF CC TEMP_DIR=%s\nseq ACGU\n#=GC SS_cons <..>\n//\n' "$outdir" > "$outdir/$outname.cacofold.sto"
            touch "$outdir/$outname.cacofold.power"
            exit 0
            """
            try executable.write(to: executableURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

            let resultText = try await RScapeRunner.refineStructureWithCaCoFold(
                executableURL: executableURL,
                stockholmText: "# STOCKHOLM 1.0\nseq ACGU\n#=GC SS_cons <..>\n//\n",
                processHandle: RScapeProcessHandle()
            )
            let parsed = StockholmParser.parse(resultText)
            expect(parsed.sequenceRows.count == 1, "CaCoFold runner returned its Stockholm alignment")
            let temporaryPath = resultText.split(whereSeparator: \.isNewline)
                .first(where: { $0.hasPrefix("#=GF CC TEMP_DIR=") })
                .map { String($0.dropFirst("#=GF CC TEMP_DIR=".count)) }
            expect(temporaryPath != nil, "CaCoFold fixture recorded its working directory")
            if let temporaryPath {
                expect(
                    !FileManager.default.fileExists(atPath: temporaryPath),
                    "CaCoFold temporary output directory was retained"
                )
            }
        } catch {
            expect(false, "CaCoFold runner fixture failed: \(error.localizedDescription)")
        }
    }

    private static func refinesEntireAlignmentWithoutChangingSequences() {
        let file = StockholmParser.parse("""
        # STOCKHOLM 1.0
        needs_au -A--U-
        needs_gc -G--C-
        aligned  A---U-
        #=GC SS_cons <...>.
        //
        """)
        let result = StemEditSuggester.refineEntireAlignment(in: file, preferLinked: true)
        expect(result.converged, "whole-alignment refinement did not converge")
        expect(result.editCount == 2, "whole-alignment refinement should apply two gap-only improvements")
        expect(result.changedSequenceCount == 2, "whole-alignment changed-sequence count")
        expect(result.before.canonical == 1 && result.after.canonical == 3, "whole-alignment canonical gain")
        expect(result.after.noncanonical <= result.before.noncanonical, "whole-alignment refinement introduced pairing violations")
        expect(SequenceIntegrityAnalyzer.preservesSequences(from: file, to: result.file), "whole-alignment refinement changed ungapped sequences")
        expect(result.file.records[result.file.sequenceRows[0].recordIndex].aligned == "A---U-", "AU row was not refined")
        expect(result.file.records[result.file.sequenceRows[1].recordIndex].aligned == "G---C-", "GC row was not refined")
        expect(file.records[file.sequenceRows[0].recordIndex].aligned == "-A--U-", "source alignment was mutated")

        let secondPass = StemEditSuggester.refineEntireAlignment(in: result.file, preferLinked: true)
        expect(secondPass.converged && secondPass.editCount == 0, "refined alignment should be a local fixed point")
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

    private static func stemAwareAndLinkedArmShifting() {
        let text = """
        # STOCKHOLM 1.0
        one -ACG----CGU-
        #=GC SS_cons .<<<....>>>.
        //
        """

        var oneArmFile = StockholmParser.parse(text)
        guard let oneArmPlan = StructureParser.stemArmShiftPlan(
            selectedColumns: [1],
            cursorColumn: 1,
            direction: 1,
            linkPairedArm: false,
            in: oneArmFile
        ) else {
            expect(false, "single-base stem-arm plan was not created")
            return
        }
        expect(oneArmPlan.primaryColumns == [1, 2, 3], "single-base selection did not expand to the complete arm")
        expect(oneArmPlan.pairedColumns.isEmpty, "unlinked shift unexpectedly included the paired arm")
        expect(oneArmFile.shift(rows: [0], moves: oneArmPlan.moves), "complete stem-arm shift failed")
        expect(oneArmFile.records[oneArmFile.sequenceRows[0].recordIndex].aligned == "--ACG---CGU-", "complete stem-arm shift output")

        var linkedFile = StockholmParser.parse(text)
        guard let linkedPlan = StructureParser.stemArmShiftPlan(
            selectedColumns: [10],
            cursorColumn: 10,
            direction: -1,
            linkPairedArm: true,
            in: linkedFile
        ) else {
            expect(false, "linked stem-arm plan was not created")
            return
        }
        expect(linkedPlan.primaryColumns == [8, 9, 10], "right stem arm was not detected")
        expect(linkedPlan.pairedColumns == [1, 2, 3], "paired stem arm was not detected")
        expect(linkedFile.shift(rows: [0], moves: linkedPlan.moves), "linked stem-arm shift failed")
        expect(linkedFile.records[linkedFile.sequenceRows[0].recordIndex].aligned == "--ACG--CGU--", "linked stem-arm shift output")

        let repeatedPlan = StemArmShiftPlan(
            stem: linkedPlan.stem,
            primaryColumns: linkedPlan.primaryDestinationColumns,
            counterpartColumns: linkedPlan.counterpartDestinationColumns,
            direction: -1,
            linkPairedArm: true
        )
        expect(linkedFile.shift(rows: [0], moves: repeatedPlan.moves), "repeated linked stem-arm shift failed")
        expect(linkedFile.records[linkedFile.sequenceRows[0].recordIndex].aligned == "---ACGCGU---", "repeated linked stem-arm shift output")

        var blockedFile = StockholmParser.parse("""
        # STOCKHOLM 1.0
        one AACG----CGU-
        #=GC SS_cons .<<<....>>>.
        //
        """)
        let original = blockedFile.rendered
        let blockedPlan = StructureParser.stemArmShiftPlan(
            selectedColumns: [1],
            cursorColumn: 1,
            direction: -1,
            linkPairedArm: false,
            in: blockedFile
        )!
        expect(!blockedFile.shift(rows: [0], moves: blockedPlan.moves), "blocked stem-arm shift should fail")
        expect(blockedFile.rendered == original, "blocked stem-arm shift was not atomic")
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
