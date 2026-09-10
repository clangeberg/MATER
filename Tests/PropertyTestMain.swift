import Foundation

@main
struct PropertyTestMain {
    private static var failures = 0

    static func main() {
        let scenarioCount = Int(ProcessInfo.processInfo.environment["MATER_PROPERTY_SCENARIOS"] ?? "250") ?? 250
        let editsPerScenario = Int(ProcessInfo.processInfo.environment["MATER_PROPERTY_EDITS"] ?? "40") ?? 40
        let seed = UInt64(ProcessInfo.processInfo.environment["MATER_PROPERTY_SEED"] ?? "1296127058") ?? 1_296_127_058
        var random = SplitMix64(seed: seed)

        for scenario in 0..<scenarioCount {
            exerciseValidAlignment(scenario: scenario, edits: editsPerScenario, random: &random)
        }
        exerciseMalformedInputs(count: max(500, scenarioCount * 4), random: &random)

        guard failures == 0 else {
            fputs("\(failures) randomized property test(s) failed; seed=\(seed).\n", stderr)
            exit(1)
        }
        print("MATER randomized properties passed: \(scenarioCount) alignments × \(editsPerScenario) edits plus malformed-input fuzz; seed=\(seed).")
    }

    private static func exerciseValidAlignment(
        scenario: Int,
        edits: Int,
        random: inout SplitMix64
    ) {
        var file = StockholmParser.parse(makeAlignment(scenario: scenario, random: &random))
        verify(file, context: "scenario \(scenario) initial")

        for edit in 0..<edits {
            let before = file
            switch random.int(upperBound: 6) {
            case 0: randomSingleCellShift(&file, random: &random)
            case 1: randomGapOpen(&file, random: &random)
            case 2: randomGapClose(&file, random: &random)
            case 3: randomGapRedistribution(&file, random: &random)
            case 4:
                let column = random.int(upperBound: max(1, file.alignmentLength + 1))
                file.insertColumn(at: column)
                expect(file.deleteColumn(at: column), "inserted all-gap column could not be deleted", context: "scenario \(scenario) edit \(edit)")
            default:
                if file.alignmentLength > 12, random.bool() {
                    _ = file.removeAllGapColumns()
                } else {
                    randomRectangularShift(&file, random: &random)
                }
            }

            expect(
                SequenceIntegrityAnalyzer.preservesSequences(from: before, to: file),
                "a gap-only operation changed an ungapped sequence",
                context: "scenario \(scenario) edit \(edit)"
            )
            expect(
                ResidueAnnotationIntegrityAnalyzer.preservesAttachmentsForMovedSequences(from: before, to: file),
                "a #=GR character detached from its residue",
                context: "scenario \(scenario) edit \(edit)"
            )
            verify(file, context: "scenario \(scenario) edit \(edit)")
        }
    }

    private static func verify(_ file: StockholmFile, context: String) {
        let widths = Set(file.rows.map { file.records[$0.recordIndex].aligned.count })
        expect(widths.count <= 1, "aligned row widths diverged: \(widths)", context: context)
        expect(
            file.validationIssues.filter { $0.severity == .error }.isEmpty,
            "valid generated file has errors: \(file.validationIssues.map(\.message))",
            context: context
        )
        expect(file.validationIssues == file.validationIssues, "validation issue identity is unstable", context: context)
        let reparsed = StockholmParser.parse(file.rendered)
        expect(reparsed.rendered == file.rendered, "save/reopen changed normalized text", context: context)
        expect(
            SequenceIntegrityAnalyzer.preservesSequences(from: file, to: reparsed),
            "save/reopen changed ungapped sequences",
            context: context
        )
        expect(
            ResidueAnnotationIntegrityAnalyzer.preservesAttachmentsForMovedSequences(from: file, to: reparsed),
            "save/reopen changed #=GR attachment",
            context: context
        )
        expect(StructureParser.validationIssues(in: reparsed).isEmpty, "save/reopen produced invalid WUSS", context: context)
    }

    private static func randomSingleCellShift(_ file: inout StockholmFile, random: inout SplitMix64) {
        let rows = file.sequenceRows
        guard !rows.isEmpty else { return }
        let sequenceRow = rows[random.int(upperBound: rows.count)]
        guard let modelRow = file.rows.firstIndex(where: { $0.recordIndex == sequenceRow.recordIndex }) else { return }
        let characters = Array(file.records[sequenceRow.recordIndex].aligned)
        var candidates: [(Int, Int)] = []
        for column in characters.indices where !AlignmentSymbol.isSequenceGap(characters[column]) {
            if column > 0, AlignmentSymbol.isSequenceGap(characters[column - 1]) { candidates.append((column, -1)) }
            if column + 1 < characters.count, AlignmentSymbol.isSequenceGap(characters[column + 1]) { candidates.append((column, 1)) }
        }
        guard let candidate = random.element(in: candidates) else { return }
        _ = file.shift(row: modelRow, selection: candidate.0...candidate.0, direction: candidate.1)
    }

    private static func randomRectangularShift(_ file: inout StockholmFile, random: inout SplitMix64) {
        let rows = file.sequenceRows
        guard rows.count >= 2, file.alignmentLength > 1 else { return }
        let modelRows = rows.compactMap { sequenceRow in
            file.rows.firstIndex(where: { $0.recordIndex == sequenceRow.recordIndex })
        }
        let selectedRows: Set<Int> = [
            modelRows[random.int(upperBound: modelRows.count)],
            modelRows[random.int(upperBound: modelRows.count)]
        ]
        let direction = random.bool() ? 1 : -1
        let destination = direction > 0 ? random.int(upperBound: file.alignmentLength - 1) + 1 : random.int(upperBound: file.alignmentLength - 1)
        let source = destination - direction
        _ = file.shift(rows: selectedRows, columns: [source], direction: direction)
    }

    private static func randomGapOpen(_ file: inout StockholmFile, random: inout SplitMix64) {
        let rows = file.sequenceRows
        guard !rows.isEmpty, file.alignmentLength > 1 else { return }
        let sequenceRow = rows[random.int(upperBound: rows.count)]
        guard let modelRow = file.rows.firstIndex(where: { $0.recordIndex == sequenceRow.recordIndex }) else { return }
        let characters = Array(file.records[sequenceRow.recordIndex].aligned)
        let candidates = characters.indices.filter { column in
            column + 1 < characters.count
                && ((column + 1)..<characters.count).contains { AlignmentSymbol.isStockholmGap(characters[$0]) }
        }
        guard let column = random.element(in: candidates) else { return }
        _ = file.openGap(row: modelRow, at: column)
    }

    private static func randomGapClose(_ file: inout StockholmFile, random: inout SplitMix64) {
        let rows = file.sequenceRows
        guard !rows.isEmpty else { return }
        let sequenceRow = rows[random.int(upperBound: rows.count)]
        guard let modelRow = file.rows.firstIndex(where: { $0.recordIndex == sequenceRow.recordIndex }) else { return }
        let characters = Array(file.records[sequenceRow.recordIndex].aligned)
        let candidates = characters.indices.filter { AlignmentSymbol.isStockholmGap(characters[$0]) }
        guard let column = random.element(in: candidates) else { return }
        _ = file.closeGap(row: modelRow, at: column)
    }

    private static func randomGapRedistribution(_ file: inout StockholmFile, random: inout SplitMix64) {
        let rows = file.sequenceRows
        guard !rows.isEmpty else { return }
        let row = rows[random.int(upperBound: rows.count)]
        let original = Array(file.records[row.recordIndex].aligned)
        let residues = original.filter { !AlignmentSymbol.isSequenceGap($0) }
        let gaps = original.filter(AlignmentSymbol.isSequenceGap)
        guard !residues.isEmpty, !gaps.isEmpty else { return }

        var slots = Array(original.indices)
        random.shuffle(&slots)
        let residueSlots = Set(slots.prefix(residues.count))
        var residueIndex = 0
        var gapIndex = 0
        let replacement = original.indices.map { column -> Character in
            if residueSlots.contains(column) {
                defer { residueIndex += 1 }
                return residues[residueIndex]
            }
            defer { gapIndex += 1 }
            return gaps[gapIndex]
        }
        _ = file.replaceSequenceGapPlacement(recordIndex: row.recordIndex, with: String(replacement))
    }

    private static func makeAlignment(scenario: Int, random: inout SplitMix64) -> String {
        let width = 30 + random.int(upperBound: 91)
        let rowCount = 2 + random.int(upperBound: 11)
        var lines = ["# STOCKHOLM 1.0", "#=GF ID property_\(scenario)", "#=GF CC randomized-safe-edit-fixture"]
        let structure = makeStructure(width: width, includePseudoknot: scenario.isMultiple(of: 3))
        for row in 0..<rowCount {
            let name = "seq_\(scenario)_\(row)/1-\(width)"
            var sequence: [Character] = []
            var pp: [Character] = []
            var residueSS: [Character] = []
            for column in 0..<width {
                if random.int(upperBound: 100) < 28 {
                    let gap: Character = random.bool() ? "-" : "."
                    sequence.append(gap)
                    pp.append(gap == "." ? "." : "-")
                    residueSS.append(".")
                } else {
                    sequence.append(["A", "C", "G", "U", "N"][random.int(upperBound: 5)])
                    pp.append(Character(String(random.int(upperBound: 10))))
                    residueSS.append(column.isMultiple(of: 7) ? "x" : ".")
                }
            }
            lines.append("\(name)    \(String(sequence))")
            lines.append("#=GR \(name) PP    \(String(pp))")
            lines.append("#=GR \(name) SS    \(String(residueSS))")
        }
        lines.append("#=GC SS_cons    \(structure)")
        lines.append("#=GC RF         \(String(repeating: "x", count: width))")
        lines.append("//")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func makeStructure(width: Int, includePseudoknot: Bool) -> String {
        var structure = Array(repeating: Character("."), count: width)
        structure[1] = "<"
        structure[2] = "<"
        structure[width / 2] = ">"
        structure[width / 2 - 1] = ">"
        if includePseudoknot {
            structure[width / 3] = "A"
            structure[width / 3 + 1] = "A"
            structure[width - 3] = "a"
            structure[width - 4] = "a"
        }
        return String(structure)
    }

    private static func exerciseMalformedInputs(count: Int, random: inout SplitMix64) {
        let alphabet = Array("#=GRGC /_-~.<>[]{}AaACGUNxyz0123456789\t")
        for index in 0..<count {
            var lines: [String] = []
            for _ in 0..<(1 + random.int(upperBound: 20)) {
                let length = random.int(upperBound: 100)
                lines.append(String((0..<length).map { _ in alphabet[random.int(upperBound: alphabet.count)] }))
            }
            let source = lines.joined(separator: random.bool() ? "\n" : "\r\n")
            let parsed = StockholmParser.parse(source)
            _ = parsed.validationIssues
            _ = StructureParser.pairs(in: parsed)
            _ = StockholmParser.parse(parsed.rendered).validationIssues
            if index.isMultiple(of: 100) { _ = parsed.rendered }
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String, context: String) {
        if !condition() {
            failures += 1
            fputs("FAIL [\(context)]: \(message)\n", stderr)
        }
    }
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func int(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    mutating func bool() -> Bool { next() & 1 == 0 }

    mutating func element<T>(in values: [T]) -> T? {
        values.isEmpty ? nil : values[int(upperBound: values.count)]
    }

    mutating func shuffle<T>(_ values: inout [T]) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            values.swapAt(index, int(upperBound: index + 1))
        }
    }
}
