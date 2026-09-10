import Foundation

@main
struct RfamCorpusAuditMain {
    private static var failures = 0

    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: mater-rfam-corpus-audit RFAM_SEED [SAMPLE_COUNT]\n", stderr)
            exit(2)
        }
        let path = CommandLine.arguments[1]
        let requested = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 250 : 250
        guard let data = FileManager.default.contents(atPath: path),
              let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            fputs("could not read decompressed Rfam SEED corpus at \(path)\n", stderr)
            exit(2)
        }

        let families = splitAlignments(source)
        guard !families.isEmpty else {
            fputs("no Stockholm alignments found in Rfam corpus\n", stderr)
            exit(2)
        }
        let selected = evenlySpacedSample(families, count: min(max(1, requested), families.count))
        var withResidueAnnotations = 0
        var withPseudoknots = 0
        var normalizedWrapping = 0
        var totalSequences = 0
        var totalColumns = 0
        var largest = (accession: "", cells: 0, rows: 0, columns: 0)

        for (sampleIndex, familyText) in selected.enumerated() {
            let file = StockholmParser.parse(familyText)
            let accession = familyText.split(whereSeparator: \.isNewline)
                .first(where: { $0.hasPrefix("#=GF AC") })?
                .split(whereSeparator: \.isWhitespace).last.map(String.init)
                ?? "sample-\(sampleIndex + 1)"
            let errors = file.validationIssues.filter { $0.severity == .error }
            expect(errors.isEmpty, "\(accession): \(errors.map(\.message).joined(separator: "; "))")
            expect(!file.sequenceRows.isEmpty, "\(accession): no sequence rows")

            if file.normalizedInterleavedSegmentCount == 0 {
                expect(file.rendered == familyText, "\(accession): no-op round trip changed source")
            } else {
                normalizedWrapping += 1
                let reparsed = StockholmParser.parse(file.rendered)
                expect(reparsed.rendered == file.rendered, "\(accession): normalized wrapping is not idempotent")
                expect(reparsed.normalizedInterleavedSegmentCount == 0, "\(accession): wrapping remained after normalization")
            }

            let pairs = StructureParser.pairs(in: file)
            _ = EntropyAnalyzer.columnEntropies(in: file)
            _ = GapAnalyzer.columnGapFrequencies(in: file)
            _ = ConsensusAnalyzer.consensus(in: file)
            _ = StructuralQualityAnalyzer.problemFractionsByColumn(in: file, pairs: pairs)
            if file.rows.contains(where: {
                if case .residueAnnotation = $0.kind { return true }
                return false
            }) { withResidueAnnotations += 1 }
            if pairs.contains(where: \.isPseudoknot) { withPseudoknots += 1 }

            exerciseOneSafeMove(file, accession: accession)
            totalSequences += file.sequenceRows.count
            totalColumns += file.alignmentLength
            let cells = file.sequenceRows.count * file.alignmentLength
            if cells > largest.cells {
                largest = (accession, cells, file.sequenceRows.count, file.alignmentLength)
            }
        }

        guard failures == 0 else {
            fputs("\(failures) Rfam corpus audit failure(s).\n", stderr)
            exit(1)
        }
        print("MATER Rfam corpus audit passed: \(selected.count)/\(families.count) SEED alignments, \(totalSequences) sequences, \(totalColumns) family-columns.")
        print("Coverage: \(withResidueAnnotations) with #=GR, \(withPseudoknots) with pseudoknots, \(normalizedWrapping) wrapped/interleaved.")
        print("Largest sampled alignment: \(largest.accession) — \(largest.rows) × \(largest.columns) (\(largest.cells) cells).")
    }

    private static func exerciseOneSafeMove(_ source: StockholmFile, accession: String) {
        for sequenceRow in source.sequenceRows {
            let characters = Array(source.records[sequenceRow.recordIndex].aligned)
            for column in characters.indices where !AlignmentSymbol.isSequenceGap(characters[column]) {
                for direction in [-1, 1] {
                    let destination = column + direction
                    guard characters.indices.contains(destination),
                          AlignmentSymbol.isStockholmGap(characters[destination]),
                          let modelRow = source.rows.firstIndex(where: { $0.recordIndex == sequenceRow.recordIndex }) else { continue }
                    var edited = source
                    guard edited.shift(row: modelRow, selection: column...column, direction: direction) else { continue }
                    expect(SequenceIntegrityAnalyzer.preservesSequences(from: source, to: edited), "\(accession): safe move changed sequence")
                    expect(
                        ResidueAnnotationIntegrityAnalyzer.preservesAttachmentsForMovedSequences(from: source, to: edited),
                        "\(accession): safe move detached #=GR annotation"
                    )
                    let reopened = StockholmParser.parse(edited.rendered)
                    expect(reopened.validationIssues.filter { $0.severity == .error }.isEmpty, "\(accession): edited save/reopen is invalid")
                    return
                }
            }
        }
    }

    private static func splitAlignments(_ source: String) -> [String] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [String] = []
        var current: [Substring] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            current.append(line)
            if line.trimmingCharacters(in: .whitespaces) == "//" {
                result.append(current.joined(separator: "\n") + "\n")
                current.removeAll(keepingCapacity: true)
            }
        }
        return result
    }

    private static func evenlySpacedSample(_ values: [String], count: Int) -> [String] {
        guard count < values.count else { return values }
        return (0..<count).map { index in
            let offset = Int((Double(index) + 0.5) * Double(values.count) / Double(count))
            return values[min(values.count - 1, offset)]
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }
    }
}
