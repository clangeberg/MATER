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

    var selectsWholeColumn: Bool {
        guard case .columnAnnotation(let tag) = self else { return false }
        return tag.hasPrefix("SS_cons")
            || tag.caseInsensitiveCompare("RF") == .orderedSame
            || tag.caseInsensitiveCompare("cons") == .orderedSame
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
    let id: String
    let severity: Severity
    let message: String

    init(id: String? = nil, severity: Severity, message: String) {
        self.id = id ?? "\(severity.rawValue):\(message)"
        self.severity = severity
        self.message = message
    }
}

/// Centralized gap semantics. MATER preserves the user's `.`/`-` notation
/// while treating the accepted Stockholm symbols consistently everywhere.
enum AlignmentSymbol {
    static func isStockholmGap(_ character: Character) -> Bool {
        character == "-" || character == "." || character == "~"
    }

    static func isSequenceGap(_ character: Character) -> Bool {
        isStockholmGap(character) || character == "_" || character == " "
    }
}

struct StockholmFile: Equatable, Sendable {
    var records: [StockholmRecord]
    var lineEnding: String
    var hasFinalNewline: Bool
    var normalizedInterleavedSegmentCount: Int
    var parseValidationIssues: [ValidationIssue]

    init(
        records: [StockholmRecord],
        lineEnding: String = "\n",
        hasFinalNewline: Bool = true,
        normalizedInterleavedSegmentCount: Int = 0,
        parseValidationIssues: [ValidationIssue] = []
    ) {
        self.records = records
        self.lineEnding = lineEnding
        self.hasFinalNewline = hasFinalNewline
        self.normalizedInterleavedSegmentCount = normalizedInterleavedSegmentCount
        self.parseValidationIssues = parseValidationIssues
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
        var issues = parseValidationIssues
        if normalizedInterleavedSegmentCount > 0 {
            issues.append(.init(
                severity: .warning,
                message: "Opened an interleaved Stockholm alignment and joined \(normalizedInterleavedSegmentCount) wrapped row segment\(normalizedInterleavedSegmentCount == 1 ? "" : "s") into complete rows. Saving writes the normalized single-block form."
            ))
        }
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
        let sequenceNameCounts = Dictionary(grouping: sequenceRows.compactMap { row -> String? in
            if case .sequence(let name) = row.kind { return name }
            return nil
        }, by: { $0 }).mapValues(\.count)
        for row in rows {
            guard case .residueAnnotation(let sequence, let tag) = row.kind else { continue }
            if sequenceNameCounts[sequence] == nil {
                issues.append(.init(
                    id: "orphan-gr:\(sequence):\(tag):\(row.recordIndex)",
                    severity: .error,
                    message: "#=GR \(sequence) \(tag) has no matching sequence row."
                ))
            } else if sequenceNameCounts[sequence] != 1 {
                issues.append(.init(
                    id: "ambiguous-gr:\(sequence):\(tag):\(row.recordIndex)",
                    severity: .error,
                    message: "#=GR \(sequence) \(tag) cannot be associated because sequence name '\(sequence)' is duplicated."
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
        let alignmentRows = rows
        guard alignmentRows.indices.contains(row) else { return }
        let recordIndex = alignmentRows[row].recordIndex
        var characters = Array(records[recordIndex].aligned)
        var changed = false
        for (offset, character) in text.enumerated() where characters.indices.contains(column + offset) {
            characters[column + offset] = character
            changed = true
        }
        guard changed else { return }
        let replacement = String(characters)
        if alignmentRows[row].kind.isSequence,
           Self.ungappedResidues(in: replacement) == Self.ungappedResidues(in: records[recordIndex].aligned) {
            _ = replaceSequenceGapPlacement(recordIndex: recordIndex, with: replacement)
        } else {
            records[recordIndex].aligned = replacement
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
        guard direction == -1 || direction == 1 else { return false }
        return shift(
            rows: selectedRows,
            moves: Dictionary(uniqueKeysWithValues: columns.map { ($0, $0 + direction) })
        )
    }

    /// Applies an atomic set of source-to-destination moves to every requested
    /// sequence row. This supports linked stem arms moving in opposite
    /// directions while retaining the same gap-safety rules as a normal shift.
    @discardableResult
    mutating func shift(rows selectedRows: Set<Int>, moves: [Int: Int]) -> Bool {
        let alignmentRows = rows
        guard !selectedRows.isEmpty, !moves.isEmpty else { return false }
        let modelRows = selectedRows.sorted()
        guard modelRows.allSatisfy({ alignmentRows.indices.contains($0) && alignmentRows[$0].kind.isSequence }) else { return false }

        let sources = Set(moves.keys)
        let destinations = Array(moves.values)
        guard Set(destinations).count == destinations.count else { return false }

        var replacements: [Int: String] = [:]
        for row in modelRows {
            let recordIndex = alignmentRows[row].recordIndex
            let characters = Array(records[recordIndex].aligned)
            guard sources.allSatisfy({ characters.indices.contains($0) }) else { return false }
            guard destinations.allSatisfy({ characters.indices.contains($0) }) else { return false }
            guard Set(destinations).subtracting(sources).allSatisfy({ Self.isGap(characters[$0]) }) else { return false }

            guard let shifted = Self.movedCharactersPreservingGaps(characters, moves: moves) else { return false }
            replacements[recordIndex] = String(shifted)
        }
        var replacementFile = self
        for (recordIndex, replacement) in replacements {
            guard replacementFile.replaceSequenceGapPlacement(recordIndex: recordIndex, with: replacement) else { return false }
        }
        self = replacementFile
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
        let displacedGap = characters.remove(at: downstreamGap)
        characters.insert(displacedGap, at: column)
        return replaceSequenceGapPlacement(recordIndex: recordIndex, with: String(characters))
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
        let displacedGap = characters.remove(at: column)
        characters.insert(displacedGap, at: min(downstreamGap, characters.count))
        let replacement = String(characters)
        guard replacement != records[recordIndex].aligned else { return false }
        return replaceSequenceGapPlacement(recordIndex: recordIndex, with: replacement)
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
        AlignmentSymbol.isStockholmGap(character)
    }

    static func ungappedResidues(in aligned: String) -> String {
        String(aligned.filter { !AlignmentSymbol.isSequenceGap($0) })
    }

    /// Applies a gap-only placement change to a sequence and every matching
    /// per-residue annotation using the identical full-column permutation.
    @discardableResult
    mutating func replaceSequenceGapPlacement(recordIndex: Int, with replacement: String) -> Bool {
        guard records.indices.contains(recordIndex),
              case .sequence(let name) = records[recordIndex].kind else { return false }
        let original = records[recordIndex].aligned
        guard original.count == replacement.count,
              Self.ungappedResidues(in: original) == Self.ungappedResidues(in: replacement),
              let permutation = Self.gapOnlyColumnPermutation(from: original, to: replacement) else { return false }

        let matchingSequences = sequenceRows.filter {
            if case .sequence(let candidate) = $0.kind { return candidate == name }
            return false
        }
        guard matchingSequences.count == 1 else { return false }

        let annotationIndices = records.indices.filter {
            if case .residueAnnotation(let sequence, _) = records[$0].kind { return sequence == name }
            return false
        }
        guard annotationIndices.allSatisfy({ records[$0].aligned.count == original.count }) else { return false }

        var annotationReplacements: [Int: String] = [:]
        for annotationIndex in annotationIndices {
            let source = Array(records[annotationIndex].aligned)
            var target = source
            for oldColumn in source.indices { target[permutation[oldColumn]] = source[oldColumn] }
            annotationReplacements[annotationIndex] = String(target)
        }
        records[recordIndex].aligned = replacement
        for (annotationIndex, aligned) in annotationReplacements {
            records[annotationIndex].aligned = aligned
        }
        return true
    }

    static func gapOnlyColumnPermutation(from original: String, to replacement: String) -> [Int]? {
        let old = Array(original)
        let new = Array(replacement)
        guard old.count == new.count else { return nil }
        let oldResidues = old.indices.filter { !AlignmentSymbol.isSequenceGap(old[$0]) }
        let newResidues = new.indices.filter { !AlignmentSymbol.isSequenceGap(new[$0]) }
        guard oldResidues.map({ old[$0] }) == newResidues.map({ new[$0] }) else { return nil }
        let oldGaps = old.indices.filter { AlignmentSymbol.isSequenceGap(old[$0]) }
        let newGaps = new.indices.filter { AlignmentSymbol.isSequenceGap(new[$0]) }
        guard oldGaps.count == newGaps.count else { return nil }
        var destinationByOld = Array(repeating: 0, count: old.count)
        for (source, destination) in zip(oldResidues, newResidues) { destinationByOld[source] = destination }
        for (source, destination) in zip(oldGaps, newGaps) { destinationByOld[source] = destination }
        return destinationByOld
    }

    /// Defensive repair for bulk UI mutations (notably paste and baseline
    /// restore). If a closure moved only gaps in a sequence but left its GR
    /// rows untouched, apply the missing permutation before committing.
    mutating func synchronizeResidueAnnotationsAfterGapMoves(from original: StockholmFile) {
        let originalSequences = Dictionary(
            grouping: original.sequenceRows.compactMap { row -> (String, Int)? in
                guard case .sequence(let name) = row.kind else { return nil }
                return (name, row.recordIndex)
            },
            by: { $0.0 }
        )
        let currentSequences = Dictionary(
            grouping: sequenceRows.compactMap { row -> (String, Int)? in
                guard case .sequence(let name) = row.kind else { return nil }
                return (name, row.recordIndex)
            },
            by: { $0.0 }
        )

        for (name, currentEntries) in currentSequences where currentEntries.count == 1 {
            guard let originalEntries = originalSequences[name], originalEntries.count == 1 else { continue }
            let oldAligned = original.records[originalEntries[0].1].aligned
            let newAligned = records[currentEntries[0].1].aligned
            guard oldAligned != newAligned,
                  let permutation = Self.gapOnlyColumnPermutation(from: oldAligned, to: newAligned) else { continue }

            let oldAnnotations = Dictionary(original.records.enumerated().compactMap { index, record -> (String, (Int, String))? in
                guard case .residueAnnotation(let sequence, let tag) = record.kind, sequence == name else { return nil }
                return (tag, (index, record.aligned))
            }, uniquingKeysWith: { first, _ in first })
            for index in records.indices {
                guard case .residueAnnotation(let sequence, let tag) = records[index].kind,
                      sequence == name,
                      let (_, oldAnnotation) = oldAnnotations[tag],
                      records[index].aligned == oldAnnotation,
                      oldAnnotation.count == permutation.count else { continue }
                let source = Array(oldAnnotation)
                var target = source
                for oldColumn in source.indices { target[permutation[oldColumn]] = source[oldColumn] }
                records[index].aligned = String(target)
            }
        }
    }

    /// Vacated source cells receive the gap symbol displaced at the end of the
    /// move chain, preserving mixed `.` and `-` alignments.
    static func movedCharactersPreservingGaps(_ characters: [Character], moves: [Int: Int]) -> [Character]? {
        guard !moves.isEmpty else { return nil }
        let sources = Set(moves.keys)
        let destinations = Array(moves.values)
        guard Set(destinations).count == destinations.count,
              sources.allSatisfy(characters.indices.contains),
              destinations.allSatisfy(characters.indices.contains),
              Set(destinations).subtracting(sources).allSatisfy({ AlignmentSymbol.isSequenceGap(characters[$0]) }) else {
            return nil
        }

        var result = characters
        for (source, destination) in moves { result[destination] = characters[source] }
        for root in sources.subtracting(Set(destinations)) {
            var terminal = root
            var visited: Set<Int> = []
            while let destination = moves[terminal], sources.contains(destination), visited.insert(terminal).inserted {
                terminal = destination
            }
            guard let gapColumn = moves[terminal], AlignmentSymbol.isSequenceGap(characters[gapColumn]) else { return nil }
            result[root] = characters[gapColumn]
        }
        return result == characters ? nil : result
    }
}

enum StockholmParser {
    private enum AlignedRecordKey: Hashable {
        case sequence(String)
        case columnAnnotation(String)
        case residueAnnotation(sequence: String, tag: String)
    }

    static func parse(_ text: String) -> StockholmFile {
        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let hasFinalNewline = normalizedText.hasSuffix("\n")
        var lines = normalizedText.components(separatedBy: "\n")
        if hasFinalNewline, lines.last == "" { lines.removeLast() }
        let parsedRecords = lines.map(parseLine)
        let joined = joiningInterleavedSegments(in: parsedRecords)
        return StockholmFile(
            records: joined.records,
            lineEnding: lineEnding,
            hasFinalNewline: hasFinalNewline,
            normalizedInterleavedSegmentCount: joined.joinedSegmentCount,
            parseValidationIssues: joined.validationIssues
        )
    }

    /// Stockholm permits an alignment to be wrapped into repeated blocks. The
    /// editor uses one complete string per logical row, so join later segments
    /// by their sequence name or annotation identity while retaining raw
    /// metadata/comments and the first row's formatting.
    private static func joiningInterleavedSegments(
        in parsedRecords: [StockholmRecord]
    ) -> (records: [StockholmRecord], joinedSegmentCount: Int, validationIssues: [ValidationIssue]) {
        struct OccurrenceKey: Hashable {
            let key: AlignedRecordKey
            let occurrence: Int
        }

        var result: [StockholmRecord] = []
        var resultIndexByKey: [OccurrenceKey: Int] = [:]
        var currentBlockKeys: [AlignedRecordKey] = []
        var occurrenceByKey: [AlignedRecordKey: Int] = [:]
        var blockIndex = 0
        var joinedSegmentCount = 0
        var validationIssues: [ValidationIssue] = []

        func duplicateDescription(_ key: AlignedRecordKey) -> String {
            switch key {
            case .sequence(let name):
                return "Duplicate sequence name '\(name)' appears within one Stockholm block. Sequence names must be unique."
            case .columnAnnotation(let tag):
                return "Duplicate #=GC tag '\(tag)' appears within one Stockholm block."
            case .residueAnnotation(let sequence, let tag):
                return "Duplicate #=GR row for '\(sequence) \(tag)' appears within one Stockholm block."
            }
        }

        func startNextBlock() {
            guard !currentBlockKeys.isEmpty else { return }
            blockIndex += 1
            currentBlockKeys.removeAll(keepingCapacity: true)
            occurrenceByKey.removeAll(keepingCapacity: true)
        }

        for record in parsedRecords {
            guard let key = alignedRecordKey(for: record) else {
                result.append(record)
                if record.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    startNextBlock()
                }
                if record.raw.trimmingCharacters(in: .whitespaces) == "//" {
                    resultIndexByKey.removeAll()
                    currentBlockKeys.removeAll()
                    occurrenceByKey.removeAll()
                    blockIndex = 0
                }
                continue
            }

            if blockIndex == 0, currentBlockKeys.count > 1, key == currentBlockKeys.first {
                startNextBlock()
            }

            let occurrence = occurrenceByKey[key, default: 0]
            occurrenceByKey[key] = occurrence + 1
            currentBlockKeys.append(key)
            let occurrenceKey = OccurrenceKey(key: key, occurrence: occurrence)

            if blockIndex == 0 {
                if occurrence > 0 {
                    validationIssues.append(.init(
                        id: "duplicate:\(String(describing: key)):\(occurrence)",
                        severity: .error,
                        message: duplicateDescription(key)
                    ))
                }
                resultIndexByKey[occurrenceKey] = result.count
                result.append(record)
                continue
            }
            if let existingIndex = resultIndexByKey[occurrenceKey] {
                result[existingIndex].aligned += record.aligned
                joinedSegmentCount += 1
            } else {
                validationIssues.append(.init(
                    id: "wrapped-mismatch:\(blockIndex):\(String(describing: key)):\(occurrence)",
                    severity: .error,
                    message: "Wrapped Stockholm block \(blockIndex + 1) contains a row not present in the first block: \(record.kind?.label ?? "unknown row")."
                ))
                resultIndexByKey[occurrenceKey] = result.count
                result.append(record)
            }
        }
        return (result, joinedSegmentCount, validationIssues)
    }

    private static func alignedRecordKey(for record: StockholmRecord) -> AlignedRecordKey? {
        switch record.kind {
        case .sequence(let name):
            return .sequence(name)
        case .columnAnnotation(let tag):
            return .columnAnnotation(tag)
        case .residueAnnotation(let sequence, let tag):
            return .residueAnnotation(sequence: sequence, tag: tag)
        case nil:
            return nil
        }
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
    private struct TreeNode {
        let left: Int
        let right: Int
        let leftBranchLength: Float
        let rightBranchLength: Float
        let descendantCount: Int
    }

    private static let identityThresholds: [Double] = [0.97, 0.90, 0.75]
    private static let presenceThresholds: [Double] = [0.97, 0.90, 0.75, 0.50]

    /// Reproduces R2R's standard GSC-weighted sequence consensus. Its output
    /// alphabet is deliberately limited to A, C, G, U, R, Y, n, and -.
    static func consensus(in file: StockholmFile) -> String {
        let length = file.alignmentLength
        guard length > 0 else { return "" }
        let sequences = file.sequenceRows.map { Array(file.records[$0.recordIndex].aligned) }
        guard !sequences.isEmpty else { return String(repeating: "-", count: length) }

        let weights = gscWeights(for: sequences)
        let validRegions = sequences.map { sequence -> Range<Int> in
            let first = sequence.firstIndex(where: isAlphabetic) ?? sequence.count
            let last = sequence.lastIndex(where: isAlphabetic).map { $0 + 1 } ?? first
            return first..<last
        }

        var result = String()
        result.reserveCapacity(length)
        for column in 0..<length {
            // R2R count order: A, C, G, U, gap.
            var counts = Array(repeating: 0.0, count: 5)
            for sequenceIndex in sequences.indices {
                let sequence = sequences[sequenceIndex]
                guard sequence.indices.contains(column), validRegions[sequenceIndex].contains(column) else { continue }
                let residue = sequence[column]
                if let nucleotide = canonicalNucleotideIndex(residue) {
                    counts[nucleotide] += Double(weights[sequenceIndex])
                } else if !isAlphabetic(residue) {
                    counts[4] += Double(weights[sequenceIndex])
                }
                // Alphabetic ambiguity symbols are intentionally omitted.
            }
            result.append(symbol(for: counts))
        }
        return result
    }

    /// Internal for threshold-focused regression tests. Values may be raw
    /// weighted counts or normalized frequencies.
    static func symbol(for rawCounts: [Double]) -> Character {
        guard rawCounts.count == 5 else { return "-" }
        let total = rawCounts.reduce(0, +)
        guard total > 0 else { return "-" }
        let counts = rawCounts.map { $0 / total }
        let nucleotides: [Character] = ["A", "C", "G", "U"]

        for threshold in identityThresholds {
            for nucleotide in 0..<4 where counts[nucleotide] >= threshold {
                return nucleotides[nucleotide]
            }
        }
        for threshold in identityThresholds {
            if counts[0] + counts[2] >= threshold { return "R" }
            if counts[1] + counts[3] >= threshold { return "Y" }
        }
        for threshold in presenceThresholds where 1.0 - counts[4] >= threshold {
            return "n"
        }
        return "-"
    }

    private static func canonicalNucleotideIndex(_ character: Character) -> Int? {
        switch character {
        case "A", "a": return 0
        case "C", "c": return 1
        case "G", "g": return 2
        case "U", "u", "T", "t": return 3
        default: return nil
        }
    }

    private static func isAlphabetic(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isGSCGap(_ character: Character) -> Bool {
        AlignmentSymbol.isSequenceGap(character)
    }

    private static func pairwiseIdentity(_ first: [Character], _ second: [Character]) -> Float {
        var identities = 0
        var firstLength = 0
        var secondLength = 0
        for (lhs, rhs) in zip(first, second) {
            if !isGSCGap(lhs) {
                firstLength += 1
                if lhs == rhs { identities += 1 }
            }
            if !isGSCGap(rhs) { secondLength += 1 }
        }
        let denominator = min(firstLength, secondLength)
        return denominator == 0 ? 0 : Float(identities) / Float(denominator)
    }

    /// Exposed within the module so alignment refinement can compare nearby
    /// unpaired residues against the same GSC-weighted sequence evidence used
    /// by the displayed R2R consensus.
    static func gscWeights(for sequences: [[Character]]) -> [Float] {
        let count = sequences.count
        guard count > 1 else { return count == 1 ? [1] : [] }

        var matrix = Array(repeating: Array(repeating: Float(0), count: count), count: count)
        for first in 0..<count {
            for second in (first + 1)..<count {
                let distance = 1 - pairwiseIdentity(sequences[first], sequences[second])
                matrix[first][second] = distance
                matrix[second][first] = distance
            }
        }

        var coordinates = Array(0..<count)
        var nodes = Array<TreeNode?>(repeating: nil, count: count - 1)
        var nodeDistances = Array(repeating: Float(0), count: count - 1)

        for activeCount in stride(from: count, through: 2, by: -1) {
            var minimum = Float.greatestFiniteMagnitude
            var first = 0
            var second = 1
            for row in 0..<activeCount {
                guard row + 1 < activeCount else { continue }
                for column in (row + 1)..<activeCount where matrix[row][column] < minimum {
                    minimum = matrix[row][column]
                    first = row
                    second = column
                }
            }

            let left = coordinates[first]
            let right = coordinates[second]
            let nodeIndex = activeCount - 2
            let leftDistance = left >= count ? nodeDistances[left - count] : 0
            let rightDistance = right >= count ? nodeDistances[right - count] : 0
            let leftCount = left >= count ? nodes[left - count]?.descendantCount ?? 0 : 1
            let rightCount = right >= count ? nodes[right - count]?.descendantCount ?? 0 : 1
            nodes[nodeIndex] = TreeNode(
                left: left,
                right: right,
                leftBranchLength: minimum - leftDistance,
                rightBranchLength: minimum - rightDistance,
                descendantCount: leftCount + rightCount
            )
            nodeDistances[nodeIndex] = minimum

            if first == activeCount - 1 || second == activeCount - 2 {
                swap(&first, &second)
            }
            swapRowsAndColumns(&matrix, first, activeCount - 2, activeCount: activeCount)
            coordinates.swapAt(first, activeCount - 2)
            swapRowsAndColumns(&matrix, second, activeCount - 1, activeCount: activeCount)
            coordinates.swapAt(second, activeCount - 1)

            let merged = activeCount - 2
            let removed = activeCount - 1
            for column in 0..<activeCount {
                matrix[merged][column] = min(matrix[merged][column], matrix[removed][column])
            }
            for row in 0..<activeCount { matrix[row][merged] = matrix[merged][row] }
            coordinates[merged] = count + nodeIndex
        }

        var leftWeights = Array(repeating: Float(0), count: count * 2 - 1)
        var rightWeights = Array(repeating: Float(0), count: count * 2 - 1)
        var finalWeights = Array(repeating: Float(0), count: count * 2 - 1)

        func accumulate(_ identifier: Int) {
            guard identifier >= count, let node = nodes[identifier - count] else { return }
            accumulate(node.left)
            accumulate(node.right)
            leftWeights[identifier] = leftWeights[node.left] + rightWeights[node.left] + node.leftBranchLength
            rightWeights[identifier] = leftWeights[node.right] + rightWeights[node.right] + node.rightBranchLength
        }

        func distribute(_ identifier: Int) {
            guard identifier >= count, let node = nodes[identifier - count] else { return }
            let totalBranchWeight = leftWeights[identifier] + rightWeights[identifier]
            if totalBranchWeight > 0 {
                finalWeights[node.left] = finalWeights[identifier] * leftWeights[identifier] / totalBranchWeight
                finalWeights[node.right] = finalWeights[identifier] * rightWeights[identifier] / totalBranchWeight
            } else {
                let leftCount = node.left >= count ? nodes[node.left - count]?.descendantCount ?? 1 : 1
                let rightCount = node.right >= count ? nodes[node.right - count]?.descendantCount ?? 1 : 1
                let descendantTotal = Float(leftCount + rightCount)
                finalWeights[node.left] = finalWeights[identifier] * Float(leftCount) / descendantTotal
                finalWeights[node.right] = finalWeights[identifier] * Float(rightCount) / descendantTotal
            }
            distribute(node.left)
            distribute(node.right)
        }

        let root = count
        accumulate(root)
        finalWeights[root] = Float(count)
        distribute(root)
        return Array(finalWeights.prefix(count))
    }

    private static func swapRowsAndColumns(_ matrix: inout [[Float]], _ first: Int, _ second: Int, activeCount: Int) {
        guard first != second else { return }
        matrix.swapAt(first, second)
        for row in 0..<activeCount { matrix[row].swapAt(first, second) }
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
