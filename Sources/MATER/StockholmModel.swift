import Foundation

enum AlignmentRowKind: Equatable, Sendable {
    case sequence(name: String)
    case columnAnnotation(tag: String)
    case residueAnnotation(sequence: String, tag: String)

    var isSequence: Bool {
        if case .sequence = self { return true }
        return false
    }

    var isStructure: Bool {
        if case .columnAnnotation(let tag) = self {
            return tag.hasPrefix("SS_cons")
        }
        return false
    }

    var isPosteriorProbability: Bool {
        switch self {
        case .columnAnnotation(let tag):
            return tag.caseInsensitiveCompare("PP_cons") == .orderedSame
        case .residueAnnotation(_, let tag):
            return tag.caseInsensitiveCompare("PP") == .orderedSame
        case .sequence:
            return false
        }
    }

    var label: String {
        switch self {
        case .sequence(let name): return name
        case .columnAnnotation(let tag): return "#=GC \(tag)"
        case .residueAnnotation(let sequence, let tag): return "#=GR \(sequence) \(tag)"
        }
    }
}

struct StockholmRecord: Equatable, Sendable {
    var raw: String
    var kind: AlignmentRowKind?
    var prefix: String
    var separator: String
    var aligned: String
    var suffix: String

    static func raw(_ line: String) -> StockholmRecord {
        StockholmRecord(raw: line, kind: nil, prefix: "", separator: "", aligned: "", suffix: "")
    }

    var rendered: String {
        guard kind != nil else { return raw }
        return prefix + separator + aligned + suffix
    }
}

struct AlignmentRow: Identifiable, Equatable, Sendable {
    let recordIndex: Int
    let kind: AlignmentRowKind
    var id: Int { recordIndex }
    var label: String { kind.label }
}

struct ValidationIssue: Identifiable, Equatable, Sendable {
    enum Severity: String, Sendable { case warning, error }
    let id = UUID()
    let severity: Severity
    let message: String
}

struct StockholmFile: Equatable, Sendable {
    var records: [StockholmRecord]
    var lineEnding: String
    var hasFinalNewline: Bool

    init(records: [StockholmRecord], lineEnding: String = "\n", hasFinalNewline: Bool = true) {
        self.records = records
        self.lineEnding = lineEnding
        self.hasFinalNewline = hasFinalNewline
    }

    var rows: [AlignmentRow] {
        records.enumerated().compactMap { index, record in
            record.kind.map { AlignmentRow(recordIndex: index, kind: $0) }
        }
    }

    var sequenceRows: [AlignmentRow] { rows.filter(\.kind.isSequence) }
    var structureRows: [AlignmentRow] { rows.filter(\.kind.isStructure) }

    var alignmentLength: Int {
        let lengths = sequenceRows.map { records[$0.recordIndex].aligned.count }
        guard !lengths.isEmpty else {
            return rows.map { records[$0.recordIndex].aligned.count }.max() ?? 0
        }
        let counts = Dictionary(grouping: lengths, by: { $0 }).mapValues(\.count)
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key ?? 0
    }

    var rendered: String {
        let body = records.map(\.rendered).joined(separator: lineEnding)
        return body + (hasFinalNewline ? lineEnding : "")
    }

    var validationIssues: [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let length = alignmentLength
        if sequenceRows.isEmpty {
            issues.append(.init(severity: .error, message: "No sequence rows were found."))
        }
        if !records.contains(where: { $0.rendered.trimmingCharacters(in: .whitespaces) == "# STOCKHOLM 1.0" }) {
            issues.append(.init(severity: .warning, message: "Missing '# STOCKHOLM 1.0' header."))
        }
        if !records.contains(where: { $0.rendered.trimmingCharacters(in: .whitespaces) == "//" }) {
            issues.append(.init(severity: .warning, message: "Missing Stockholm terminator '//'."))
        }
        for row in rows {
            let rowLength = records[row.recordIndex].aligned.count
            if rowLength != length {
                issues.append(.init(
                    severity: .error,
                    message: "\(row.label) has \(rowLength) columns; expected \(length)."
                ))
            }
        }
        if structureRows.isEmpty {
            issues.append(.init(severity: .warning, message: "No #=GC SS_cons structure row was found."))
        }
        issues.append(contentsOf: StructureParser.validationIssues(in: self))
        return issues
    }

    func character(row: Int, column: Int) -> Character? {
        let alignmentRows = rows
        guard alignmentRows.indices.contains(row) else { return nil }
        return records[alignmentRows[row].recordIndex].aligned.character(at: column)
    }

    mutating func replaceCharacter(row: Int, column: Int, with character: Character) {
        let alignmentRows = rows
        guard alignmentRows.indices.contains(row) else { return }
        let recordIndex = alignmentRows[row].recordIndex
        records[recordIndex].aligned.replaceCharacter(at: column, with: character)
    }

    mutating func replaceCharacters(row: Int, startingAt column: Int, with text: String) {
        for (offset, character) in text.enumerated() {
            replaceCharacter(row: row, column: column + offset, with: character)
        }
    }

    mutating func insertColumn(at column: Int) {
        let length = alignmentLength
        let target = max(0, min(column, length))
        for row in rows where records[row.recordIndex].aligned.count == length {
            let fill: Character = row.kind.isSequence ? "-" : "."
            records[row.recordIndex].aligned.insertCharacter(fill, at: target)
        }
    }

    @discardableResult
    mutating func deleteColumn(at column: Int, requireAllSequenceGaps: Bool = true) -> Bool {
        let length = alignmentLength
        guard column >= 0, column < length else { return false }
        if requireAllSequenceGaps {
            let canDelete = sequenceRows.allSatisfy {
                records[$0.recordIndex].aligned.character(at: column).map(Self.isGap) ?? false
            }
            guard canDelete else { return false }
        }
        removeColumns([column], alignmentLength: length)
        return true
    }

    /// Removes every column containing gaps in all sequence rows. Column
    /// annotations are removed in lockstep, and any structural pair left with
    /// only one endpoint is cleared so the resulting WUSS annotation is valid.
    @discardableResult
    mutating func removeAllGapColumns() -> [Int] {
        let length = alignmentLength
        let sequenceCharacters = sequenceRows.map { Array(records[$0.recordIndex].aligned) }
        guard length > 0, !sequenceCharacters.isEmpty else { return [] }

        let columns = (0..<length).filter { column in
            sequenceCharacters.allSatisfy { characters in
                characters.indices.contains(column) && Self.isGap(characters[column])
            }
        }
        guard !columns.isEmpty else { return [] }
        removeColumns(Set(columns), alignmentLength: length)
        return columns
    }

    @discardableResult
    mutating func shift(row: Int, selection: ClosedRange<Int>, direction: Int) -> Bool {
        shift(rows: [row], columns: Set(selection), direction: direction)
    }

    /// Moves a continuous or discontinuous set of selected cells together.
    /// Every destination must be either selected or a gap, and every requested
    /// row must be able to move so rectangular edits remain atomic.
    @discardableResult
    mutating func shift(rows selectedRows: Set<Int>, columns: Set<Int>, direction: Int) -> Bool {
        let alignmentRows = rows
        guard !selectedRows.isEmpty, !columns.isEmpty, direction == -1 || direction == 1 else { return false }
        let modelRows = selectedRows.sorted()
        guard modelRows.allSatisfy({ alignmentRows.indices.contains($0) && alignmentRows[$0].kind.isSequence }) else { return false }

        var replacements: [Int: String] = [:]
        for row in modelRows {
            let recordIndex = alignmentRows[row].recordIndex
            let characters = Array(records[recordIndex].aligned)
            guard columns.allSatisfy({ characters.indices.contains($0) }) else { return false }
            let destinations = Set(columns.map { $0 + direction })
            guard destinations.allSatisfy({ characters.indices.contains($0) }) else { return false }
            guard destinations.subtracting(columns).allSatisfy({ Self.isGap(characters[$0]) }) else { return false }

            var shifted = characters
            for column in columns { shifted[column] = "-" }
            let ordered = direction < 0 ? columns.sorted() : columns.sorted(by: >)
            for column in ordered {
                shifted[column + direction] = characters[column]
            }
            replacements[recordIndex] = String(shifted)
        }
        for (recordIndex, replacement) in replacements { records[recordIndex].aligned = replacement }
        return true
    }

    /// Inserts a gap before the cursor while consuming the nearest downstream
    /// gap, keeping the Stockholm alignment width unchanged.
    @discardableResult
    mutating func openGap(row: Int, at column: Int) -> Bool {
        let alignmentRows = rows
        guard alignmentRows.indices.contains(row), alignmentRows[row].kind.isSequence else { return false }
        let recordIndex = alignmentRows[row].recordIndex
        var characters = Array(records[recordIndex].aligned)
        guard characters.indices.contains(column),
              let downstreamGap = ((column + 1)..<characters.count).first(where: { Self.isGap(characters[$0]) }) else { return false }
        characters.remove(at: downstreamGap)
        characters.insert("-", at: column)
        records[recordIndex].aligned = String(characters)
        return true
    }

    /// Removes the gap at the cursor and pulls the following residue block left;
    /// the gap is moved to the far edge of that block.
    @discardableResult
    mutating func closeGap(row: Int, at column: Int) -> Bool {
        let alignmentRows = rows
        guard alignmentRows.indices.contains(row), alignmentRows[row].kind.isSequence else { return false }
        let recordIndex = alignmentRows[row].recordIndex
        var characters = Array(records[recordIndex].aligned)
        guard characters.indices.contains(column), Self.isGap(characters[column]) else { return false }
        let downstreamGap = ((column + 1)..<characters.count).first(where: { Self.isGap(characters[$0]) }) ?? characters.count
        characters.remove(at: column)
        characters.insert("-", at: min(downstreamGap, characters.count))
        let replacement = String(characters)
        guard replacement != records[recordIndex].aligned else { return false }
        records[recordIndex].aligned = replacement
        return true
    }

    mutating func setPair(left: Int, right: Int, layer: PairingLayer) {
        let length = alignmentLength
        guard left >= 0, right < length, left < right else { return }
        let recordIndex = ensureStructureRow(tag: layer.tag)
        clearPair(at: left, recordIndex: recordIndex)
        clearPair(at: right, recordIndex: recordIndex)
        records[recordIndex].aligned.replaceCharacter(at: left, with: layer.open)
        records[recordIndex].aligned.replaceCharacter(at: right, with: layer.close)
    }

    mutating func clearPairs(touching columns: ClosedRange<Int>) {
        clearPairs(touching: Set(columns))
    }

    mutating func clearPairs(touching columns: Set<Int>) {
        let currentPairs = StructureParser.pairs(in: self)
        for pair in currentPairs where columns.contains(pair.left) || columns.contains(pair.right) {
            records[pair.recordIndex].aligned.replaceCharacter(at: pair.left, with: ".")
            records[pair.recordIndex].aligned.replaceCharacter(at: pair.right, with: ".")
        }
    }

    private mutating func clearPair(at column: Int, recordIndex: Int) {
        let pairs = StructureParser.pairs(in: self)
        for pair in pairs where pair.recordIndex == recordIndex && (pair.left == column || pair.right == column) {
            records[recordIndex].aligned.replaceCharacter(at: pair.left, with: ".")
            records[recordIndex].aligned.replaceCharacter(at: pair.right, with: ".")
        }
    }

    private mutating func removeColumns(_ columns: Set<Int>, alignmentLength length: Int) {
        let currentPairs = StructureParser.pairs(in: self)
        for pair in currentPairs where columns.contains(pair.left) || columns.contains(pair.right) {
            if !columns.contains(pair.left) {
                records[pair.recordIndex].aligned.replaceCharacter(at: pair.left, with: ".")
            }
            if !columns.contains(pair.right) {
                records[pair.recordIndex].aligned.replaceCharacter(at: pair.right, with: ".")
            }
        }

        let descendingColumns = columns.sorted(by: >)
        for row in rows where records[row.recordIndex].aligned.count == length {
            var characters = Array(records[row.recordIndex].aligned)
            for column in descendingColumns where characters.indices.contains(column) {
                characters.remove(at: column)
            }
            records[row.recordIndex].aligned = String(characters)
        }
    }

    private mutating func ensureStructureRow(tag: String) -> Int {
        if let existing = records.firstIndex(where: {
            if case .columnAnnotation(let candidate) = $0.kind { return candidate == tag }
            return false
        }) {
            return existing
        }
        let insertion = records.firstIndex(where: { $0.raw.trimmingCharacters(in: .whitespaces) == "//" }) ?? records.endIndex
        let prefix = "#=GC \(tag)"
        let record = StockholmRecord(
            raw: "",
            kind: .columnAnnotation(tag: tag),
            prefix: prefix,
            separator: "    ",
            aligned: String(repeating: ".", count: alignmentLength),
            suffix: ""
        )
        records.insert(record, at: insertion)
        return insertion
    }

    static func isGap(_ character: Character) -> Bool {
        character == "-" || character == "." || character == "~"
    }
}

enum StockholmParser {
    static func parse(_ text: String) -> StockholmFile {
        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let hasFinalNewline = normalized.hasSuffix("\n")
        var lines = normalized.components(separatedBy: "\n")
        if hasFinalNewline, lines.last == "" { lines.removeLast() }
        let records = lines.map(parseLine)
        return StockholmFile(records: records, lineEnding: lineEnding, hasFinalNewline: hasFinalNewline)
    }

    private static func parseLine(_ line: String) -> StockholmRecord {
        if line.hasPrefix("#=GC") {
            guard let pieces = splitAlignmentLine(line, metadataTokenCount: 2) else { return .raw(line) }
            let tag = tokenArray(in: pieces.prefix).dropFirst().first ?? ""
            return StockholmRecord(raw: line, kind: .columnAnnotation(tag: tag), prefix: pieces.prefix, separator: pieces.separator, aligned: pieces.value, suffix: pieces.suffix)
        }
        if line.hasPrefix("#=GR") {
            guard let pieces = splitAlignmentLine(line, metadataTokenCount: 3) else { return .raw(line) }
            let tokens = tokenArray(in: pieces.prefix)
            let sequence = tokens.count > 1 ? tokens[1] : ""
            let tag = tokens.count > 2 ? tokens[2] : ""
            return StockholmRecord(raw: line, kind: .residueAnnotation(sequence: sequence, tag: tag), prefix: pieces.prefix, separator: pieces.separator, aligned: pieces.value, suffix: pieces.suffix)
        }
        if line.isEmpty || line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces) == "//" {
            return .raw(line)
        }
        guard let pieces = splitAlignmentLine(line, metadataTokenCount: 1) else { return .raw(line) }
        let name = tokenArray(in: pieces.prefix).first ?? pieces.prefix
        return StockholmRecord(raw: line, kind: .sequence(name: name), prefix: pieces.prefix, separator: pieces.separator, aligned: pieces.value, suffix: pieces.suffix)
    }

    private static func tokenArray(in string: String) -> [String] {
        string.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func splitAlignmentLine(_ line: String, metadataTokenCount: Int) -> (prefix: String, separator: String, value: String, suffix: String)? {
        let characters = Array(line)
        var index = 0
        var tokens = 0
        while index < characters.count, tokens < metadataTokenCount {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count else { return nil }
            while index < characters.count, !characters[index].isWhitespace { index += 1 }
            tokens += 1
        }
        let prefixEnd = index
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index > prefixEnd, index < characters.count else { return nil }
        let valueStart = index
        while index < characters.count, !characters[index].isWhitespace { index += 1 }
        let valueEnd = index
        let prefix = String(characters[0..<prefixEnd])
        let separator = String(characters[prefixEnd..<valueStart])
        let value = String(characters[valueStart..<valueEnd])
        let suffix = String(characters[valueEnd..<characters.count])
        return (prefix, separator, value, suffix)
    }
}

enum EntropyAnalyzer {
    /// Shannon entropy for canonical RNA residues, in bits. Gaps and ambiguous
    /// symbols are excluded, and DNA thymine is counted as uracil.
    static func columnEntropies(in file: StockholmFile) -> [Double] {
        let length = file.alignmentLength
        guard length > 0 else { return [] }
        var counts = Array(repeating: Array(repeating: 0, count: 4), count: length)

        for row in file.sequenceRows {
            for (column, residue) in file.records[row.recordIndex].aligned.uppercased().enumerated() where column < length {
                let index: Int?
                switch residue {
                case "A": index = 0
                case "C": index = 1
                case "G": index = 2
                case "U", "T": index = 3
                default: index = nil
                }
                if let index { counts[column][index] += 1 }
            }
        }

        return counts.map { columnCounts in
            let total = columnCounts.reduce(0, +)
            guard total > 0 else { return 0 }
            return columnCounts.reduce(0.0) { entropy, count in
                guard count > 0 else { return entropy }
                let probability = Double(count) / Double(total)
                return entropy - probability * log2(probability)
            }
        }
    }
}

enum GapAnalyzer {
    static func columnGapFrequencies(in file: StockholmFile) -> [Double] {
        let length = file.alignmentLength
        let sequences = file.sequenceRows
        guard length > 0, !sequences.isEmpty else { return [] }
        var gaps = Array(repeating: 0, count: length)
        for row in sequences {
            for (column, character) in file.records[row.recordIndex].aligned.enumerated() where column < length {
                if StockholmFile.isGap(character) { gaps[column] += 1 }
            }
        }
        return gaps.map { Double($0) / Double(sequences.count) }
    }
}

enum ConsensusAnalyzer {
    static func consensus(in file: StockholmFile) -> String {
        let length = file.alignmentLength
        guard length > 0 else { return "" }
        var counts = Array(repeating: [Character: Int](), count: length)
        for row in file.sequenceRows {
            for (column, residue) in file.records[row.recordIndex].aligned.uppercased().enumerated() where column < length {
                let normalized: Character
                switch residue {
                case "A", "C", "G", "U": normalized = residue
                case "T": normalized = "U"
                default: continue
                }
                counts[column][normalized, default: 0] += 1
            }
        }
        return String(counts.map { column in
            column.max { lhs, rhs in
                lhs.value == rhs.value ? String(lhs.key) > String(rhs.key) : lhs.value < rhs.value
            }?.key ?? "-"
        })
    }
}

enum PairingLayer: String, CaseIterable, Identifiable, Sendable {
    case primary
    case pseudoknot1
    case pseudoknot2
    case pseudoknot3
    case pseudoknot4

    var id: String { rawValue }
    var title: String {
        switch self {
        case .primary: return "Primary  < >"
        case .pseudoknot1: return "Pseudoknot 1  ( )"
        case .pseudoknot2: return "Pseudoknot 2  [ ]"
        case .pseudoknot3: return "Pseudoknot 3  { }"
        case .pseudoknot4: return "Pseudoknot 4  A a"
        }
    }
    var tag: String {
        switch self {
        case .primary: return "SS_cons"
        case .pseudoknot1: return "SS_cons_2"
        case .pseudoknot2: return "SS_cons_3"
        case .pseudoknot3: return "SS_cons_4"
        case .pseudoknot4: return "SS_cons_5"
        }
    }
    var open: Character {
        switch self {
        case .primary: return "<"
        case .pseudoknot1: return "("
        case .pseudoknot2: return "["
        case .pseudoknot3: return "{"
        case .pseudoknot4: return "A"
        }
    }
    var close: Character {
        switch self {
        case .primary: return ">"
        case .pseudoknot1: return ")"
        case .pseudoknot2: return "]"
        case .pseudoknot3: return "}"
        case .pseudoknot4: return "a"
        }
    }
}

private extension String {
    func character(at offset: Int) -> Character? {
        guard offset >= 0, let index = index(startIndex, offsetBy: offset, limitedBy: endIndex), index < endIndex else { return nil }
        return self[index]
    }

    mutating func replaceCharacter(at offset: Int, with character: Character) {
        guard offset >= 0, let index = index(startIndex, offsetBy: offset, limitedBy: endIndex), index < endIndex else { return }
        replaceSubrange(index...index, with: String(character))
    }

    mutating func insertCharacter(_ character: Character, at offset: Int) {
        guard offset >= 0, let index = index(startIndex, offsetBy: offset, limitedBy: endIndex) else { return }
        insert(character, at: index)
    }

    mutating func removeCharacter(at offset: Int) {
        guard offset >= 0, let index = index(startIndex, offsetBy: offset, limitedBy: endIndex), index < endIndex else { return }
        remove(at: index)
    }
}
