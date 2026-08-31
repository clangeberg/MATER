import Foundation

struct SequenceIntegrityEntry: Equatable, Sendable {
    let key: String
    let name: String
    let residues: String
}

struct SequenceIntegrityViolation: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case missing = "missing"
        case added = "added"
        case changed = "changed"
        case reordered = "reordered"
    }

    let id: String
    let kind: Kind
    let sequenceName: String
    let message: String
}

struct SequenceIntegrityReport: Equatable, Sendable {
    let sequenceCount: Int
    let violations: [SequenceIntegrityViolation]

    var isIntact: Bool { violations.isEmpty }
    var changedSequenceCount: Int {
        Set(violations.filter { $0.kind != .reordered }.map(\.sequenceName)).count
    }

    var summary: String {
        if isIntact { return "Integrity verified: \(sequenceCount) ungapped sequence\(sequenceCount == 1 ? "" : "s") unchanged." }
        return "Sequence integrity differs in \(changedSequenceCount) sequence\(changedSequenceCount == 1 ? "" : "s")."
    }
}

enum SequenceIntegrityAnalyzer {
    static func entries(in file: StockholmFile) -> [SequenceIntegrityEntry] {
        var occurrences: [String: Int] = [:]
        return file.sequenceRows.compactMap { row in
            guard case .sequence(let name) = row.kind else { return nil }
            let occurrence = occurrences[name, default: 0]
            occurrences[name] = occurrence + 1
            let residues = file.records[row.recordIndex].aligned.filter { !isAlignmentGap($0) }
            return SequenceIntegrityEntry(
                key: "\(name)#\(occurrence)",
                name: name,
                residues: String(residues)
            )
        }
    }

    static func preservesSequences(from before: StockholmFile, to after: StockholmFile) -> Bool {
        entries(in: before) == entries(in: after)
    }

    static func report(current: StockholmFile, baseline: StockholmFile) -> SequenceIntegrityReport {
        let original = entries(in: baseline)
        let edited = entries(in: current)
        let originalByKey = Dictionary(uniqueKeysWithValues: original.map { ($0.key, $0) })
        let editedByKey = Dictionary(uniqueKeysWithValues: edited.map { ($0.key, $0) })
        var violations: [SequenceIntegrityViolation] = []

        for entry in original {
            guard let currentEntry = editedByKey[entry.key] else {
                violations.append(.init(
                    id: "missing:\(entry.key)",
                    kind: .missing,
                    sequenceName: entry.name,
                    message: "\(entry.name) is missing."
                ))
                continue
            }
            if entry.residues != currentEntry.residues {
                violations.append(.init(
                    id: "changed:\(entry.key)",
                    kind: .changed,
                    sequenceName: entry.name,
                    message: "\(entry.name) has a changed ungapped residue sequence."
                ))
            }
        }
        for entry in edited where originalByKey[entry.key] == nil {
            violations.append(.init(
                id: "added:\(entry.key)",
                kind: .added,
                sequenceName: entry.name,
                message: "\(entry.name) was added."
            ))
        }

        let originalOrder = original.map(\.key)
        let editedOrder = edited.map(\.key)
        if originalOrder != editedOrder, Set(originalOrder) == Set(editedOrder) {
            violations.append(.init(
                id: "reordered",
                kind: .reordered,
                sequenceName: "Alignment",
                message: "Sequence rows were reordered."
            ))
        }
        return SequenceIntegrityReport(sequenceCount: original.count, violations: violations)
    }

    static func differenceScore(current: StockholmFile, baseline: StockholmFile) -> Int {
        let original = entries(in: baseline)
        let edited = entries(in: current)
        let originalByKey = Dictionary(uniqueKeysWithValues: original.map { ($0.key, $0) })
        let editedByKey = Dictionary(uniqueKeysWithValues: edited.map { ($0.key, $0) })
        var score = 0

        for entry in original {
            guard let currentEntry = editedByKey[entry.key] else {
                score += max(1, entry.residues.count)
                continue
            }
            let originalResidues = Array(entry.residues)
            let currentResidues = Array(currentEntry.residues)
            score += abs(originalResidues.count - currentResidues.count)
            score += zip(originalResidues, currentResidues).filter { $0 != $1 }.count
        }
        for entry in edited where originalByKey[entry.key] == nil {
            score += max(1, entry.residues.count)
        }
        if original.map(\.key) != edited.map(\.key) {
            score += 1
        }
        return score
    }

    private static func isAlignmentGap(_ character: Character) -> Bool {
        StockholmFile.isGap(character) || character == "_" || character == " "
    }
}

struct SequenceStructureStatus: Equatable, Sendable {
    var canonical = 0
    var noncanonical = 0
    var gaps = 0
    var ambiguous = 0

    /// Definite pairing violations only. Gaps can represent genuine structural
    /// subtypes, and ambiguity codes are not evaluable observations.
    var problemCount: Int { noncanonical }
}

struct SequencePairIssue: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case noncanonical = "noncanonical"
        case gap = "gap"
        case ambiguous = "ambiguous"
    }

    let id: String
    let modelRow: Int
    let recordIndex: Int
    let sequenceName: String
    let pair: BasePair
    let observedPair: String
    let kind: Kind
}

struct PairQuality: Identifiable, Equatable, Sendable {
    let pair: BasePair
    let canonical: Int
    let noncanonical: Int
    let gaps: Int
    let ambiguous: Int

    var id: String { pair.id }
    var total: Int { canonical + noncanonical + gaps + ambiguous }
    var evaluable: Int { canonical + noncanonical }
    var canonicalFraction: Double { evaluable == 0 ? 0 : Double(canonical) / Double(evaluable) }
}

struct StemQuality: Identifiable, Equatable, Sendable {
    let stem: Int
    let structureTag: String
    let pairs: [BasePair]
    let canonical: Int
    let noncanonical: Int
    let gaps: Int
    let ambiguous: Int
    let pairTypeCounts: [String: Int]
    let pairQualities: [PairQuality]
    let issues: [SequencePairIssue]
    let statusByRecordIndex: [Int: SequenceStructureStatus]

    var id: Int { stem }
    var total: Int { canonical + noncanonical + gaps + ambiguous }
    var evaluable: Int { canonical + noncanonical }
    var canonicalFraction: Double { evaluable == 0 ? 0 : Double(canonical) / Double(evaluable) }
    var noncanonicalFraction: Double { evaluable == 0 ? 0 : Double(noncanonical) / Double(evaluable) }
    var gapFraction: Double { total == 0 ? 0 : Double(gaps) / Double(total) }
    var ambiguousFraction: Double { total == 0 ? 0 : Double(ambiguous) / Double(total) }
    var problemRecordIndices: Set<Int> {
        Set(statusByRecordIndex.compactMap { $0.value.problemCount > 0 ? $0.key : nil })
    }
}

enum StructuralQualityAnalyzer {
    static func stem(containing column: Int, in file: StockholmFile) -> StemQuality? {
        let pairs = StructureParser.pairs(in: file)
        guard let selectedPair = pairs.first(where: { $0.left == column || $0.right == column }) else { return nil }
        return quality(stem: selectedPair.stem, pairs: pairs, in: file)
    }

    static func quality(stem: Int, in file: StockholmFile) -> StemQuality? {
        quality(stem: stem, pairs: StructureParser.pairs(in: file), in: file)
    }

    static func quality(stem: Int, pairs: [BasePair], in file: StockholmFile) -> StemQuality? {
        let stemPairs = pairs.filter { $0.stem == stem }.sorted { $0.left < $1.left }
        guard let firstPair = stemPairs.first else { return nil }
        let modelRowByRecord = Dictionary(uniqueKeysWithValues: file.rows.enumerated().map { ($0.element.recordIndex, $0.offset) })
        var canonical = 0
        var noncanonical = 0
        var gaps = 0
        var ambiguous = 0
        var pairTypes: [String: Int] = [:]
        var perPair: [String: SequenceStructureStatus] = [:]
        var issues: [SequencePairIssue] = []
        var statusByRecord: [Int: SequenceStructureStatus] = [:]

        for row in file.sequenceRows {
            let characters = Array(file.records[row.recordIndex].aligned)
            guard case .sequence(let sequenceName) = row.kind, let modelRow = modelRowByRecord[row.recordIndex] else { continue }
            for pair in stemPairs {
                let key = pair.id
                var pairStatus = perPair[key, default: SequenceStructureStatus()]
                var sequenceStatus = statusByRecord[row.recordIndex, default: SequenceStructureStatus()]
                let left = characters.indices.contains(pair.left) ? characters[pair.left] : "-"
                let right = characters.indices.contains(pair.right) ? characters[pair.right] : "-"
                let normalizedLeft = normalize(left)
                let normalizedRight = normalize(right)
                let pairText = "\(normalizedLeft)–\(normalizedRight)"
                let issueKind: SequencePairIssue.Kind?

                if StockholmFile.isGap(left) || StockholmFile.isGap(right) || left == "_" || right == "_" {
                    gaps += 1
                    pairStatus.gaps += 1
                    sequenceStatus.gaps += 1
                    issueKind = .gap
                } else if !isCanonicalResidue(normalizedLeft) || !isCanonicalResidue(normalizedRight) {
                    ambiguous += 1
                    pairStatus.ambiguous += 1
                    sequenceStatus.ambiguous += 1
                    issueKind = .ambiguous
                } else if BasePairRules.isCanonical(normalizedLeft, normalizedRight) {
                    canonical += 1
                    pairStatus.canonical += 1
                    sequenceStatus.canonical += 1
                    pairTypes[pairText, default: 0] += 1
                    issueKind = nil
                } else {
                    noncanonical += 1
                    pairStatus.noncanonical += 1
                    sequenceStatus.noncanonical += 1
                    pairTypes[pairText, default: 0] += 1
                    issueKind = .noncanonical
                }

                perPair[key] = pairStatus
                statusByRecord[row.recordIndex] = sequenceStatus
                if let issueKind {
                    issues.append(.init(
                        id: "\(row.recordIndex):\(pair.id):\(issueKind.rawValue)",
                        modelRow: modelRow,
                        recordIndex: row.recordIndex,
                        sequenceName: sequenceName,
                        pair: pair,
                        observedPair: pairText,
                        kind: issueKind
                    ))
                }
            }
        }

        let pairQualities = stemPairs.map { pair -> PairQuality in
            let status = perPair[pair.id, default: SequenceStructureStatus()]
            return PairQuality(
                pair: pair,
                canonical: status.canonical,
                noncanonical: status.noncanonical,
                gaps: status.gaps,
                ambiguous: status.ambiguous
            )
        }
        return StemQuality(
            stem: stem,
            structureTag: firstPair.structureTag,
            pairs: stemPairs,
            canonical: canonical,
            noncanonical: noncanonical,
            gaps: gaps,
            ambiguous: ambiguous,
            pairTypeCounts: pairTypes,
            pairQualities: pairQualities,
            issues: issues,
            statusByRecordIndex: statusByRecord
        )
    }

    static func wholeAlignmentGapFraction(recordIndex: Int, in file: StockholmFile) -> Double {
        let characters = Array(file.records[recordIndex].aligned)
        guard !characters.isEmpty else { return 0 }
        let count = characters.filter { StockholmFile.isGap($0) || $0 == "_" }.count
        return Double(count) / Double(characters.count)
    }

    static func problemFractionsByColumn(in file: StockholmFile) -> [Double] {
        problemFractionsByColumn(in: file, pairs: StructureParser.pairs(in: file))
    }

    static func problemFractionsByColumn(in file: StockholmFile, pairs: [BasePair]) -> [Double] {
        let length = file.alignmentLength
        guard length > 0 else { return [] }
        var problemCounts = Array(repeating: 0, count: length)
        var observationCounts = Array(repeating: 0, count: length)
        let sequences = file.sequenceRows.map { Array(file.records[$0.recordIndex].aligned) }
        for pair in pairs {
            for characters in sequences {
                guard characters.indices.contains(pair.left), characters.indices.contains(pair.right) else { continue }
                let left = characters[pair.left]
                let right = characters[pair.right]
                guard !StockholmFile.isGap(left), !StockholmFile.isGap(right), left != "_", right != "_" else {
                    continue
                }
                let normalizedLeft = normalize(left)
                let normalizedRight = normalize(right)
                guard isCanonicalResidue(normalizedLeft), isCanonicalResidue(normalizedRight) else {
                    continue
                }
                let isProblem = !BasePairRules.isCanonical(normalizedLeft, normalizedRight)
                for column in [pair.left, pair.right] {
                    observationCounts[column] += 1
                    if isProblem { problemCounts[column] += 1 }
                }
            }
        }
        return zip(problemCounts, observationCounts).map { problems, observations in
            observations == 0 ? 0 : Double(problems) / Double(observations)
        }
    }

    private static func normalize(_ character: Character) -> Character {
        let upper = Character(String(character).uppercased())
        return upper == "T" ? "U" : upper
    }

    private static func isCanonicalResidue(_ character: Character) -> Bool {
        character == "A" || character == "C" || character == "G" || character == "U"
    }
}

struct RowStemMetrics: Equatable, Sendable {
    let canonical: Int
    let noncanonical: Int
    let gaps: Int
    let ambiguous: Int
}

struct StemEditSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let modelRow: Int
    let sequenceName: String
    let recordIndex: Int
    let stem: Int
    let operationTitle: String
    let direction: Int
    let linked: Bool
    let moves: [Int: Int]
    let primaryDestinationColumns: Set<Int>
    let expectedAligned: String
    let proposedAligned: String
    let before: RowStemMetrics
    let after: RowStemMetrics
    let globalCanonicalBefore: Int
    let globalCanonicalAfter: Int
    let leftBefore: String
    let leftAfter: String
    let rightBefore: String
    let rightAfter: String

    var canonicalGain: Int { after.canonical - before.canonical }
    var globalCanonicalGain: Int { globalCanonicalAfter - globalCanonicalBefore }
    var directionTitle: String { operationTitle }
}

struct AlignmentRefinementScore: Equatable, Sendable {
    let canonical: Int
    let noncanonical: Int
    let gaps: Int
    let ambiguous: Int

    /// Automatic refinement uses a Pareto-style safety rule: canonical support
    /// may not decrease and definite noncanonical observations may not increase.
    /// Gap and ambiguity counts are descriptive tie-breakers only because either
    /// can represent a legitimate structural subtype or incomplete sequence.
    func isSafeImprovement(over other: AlignmentRefinementScore) -> Bool {
        canonical >= other.canonical
            && noncanonical <= other.noncanonical
            && (canonical > other.canonical || noncanonical < other.noncanonical)
    }

    func isPreferred(over other: AlignmentRefinementScore) -> Bool {
        if canonical != other.canonical { return canonical > other.canonical }
        if noncanonical != other.noncanonical { return noncanonical < other.noncanonical }
        if gaps != other.gaps { return gaps < other.gaps }
        return ambiguous < other.ambiguous
    }
}

struct AlignmentRefinementResult: Equatable, Sendable {
    let file: StockholmFile
    let before: AlignmentRefinementScore
    let after: AlignmentRefinementScore
    let editCount: Int
    let changedSequenceCount: Int
    let passes: Int
    let converged: Bool
}

enum StemEditSuggester {
    static func suggestions(
        in file: StockholmFile,
        modelRow: Int,
        column: Int,
        preferLinked: Bool
    ) -> [StemEditSuggestion] {
        let allPairs = StructureParser.pairs(in: file)
        let rows = file.rows
        guard rows.indices.contains(modelRow), rows[modelRow].kind.isSequence,
              let cursorPair = allPairs.first(where: { $0.left == column || $0.right == column }) else { return [] }
        return suggestions(
            in: file,
            modelRow: modelRow,
            cursorPair: cursorPair,
            stemPairs: allPairs.filter { $0.stem == cursorPair.stem }.sorted { $0.left < $1.left },
            cursorIsLeft: cursorPair.left == column,
            preferLinked: preferLinked,
            allPairs: allPairs,
            globalCanonicalBeforeOverride: nil
        )
    }

    private static func suggestions(
        in file: StockholmFile,
        modelRow: Int,
        cursorPair: BasePair,
        stemPairs: [BasePair],
        cursorIsLeft: Bool,
        preferLinked: Bool,
        allPairs: [BasePair],
        globalCanonicalBeforeOverride: Int?
    ) -> [StemEditSuggestion] {
        let rows = file.rows
        guard rows.indices.contains(modelRow), rows[modelRow].kind.isSequence,
              case .sequence(let sequenceName) = rows[modelRow].kind else { return [] }
        let primaryColumns = Set(stemPairs.map { cursorIsLeft ? $0.left : $0.right })
        let counterpartColumns = Set(stemPairs.map { cursorIsLeft ? $0.right : $0.left })
        let recordIndex = rows[modelRow].recordIndex
        let originalCharacters = Array(file.records[recordIndex].aligned)
        let originalAligned = file.records[recordIndex].aligned
        let beforeMetrics = rowMetrics(characters: originalCharacters, pairs: stemPairs)
        let globalBefore = globalCanonicalBeforeOverride
            ?? StructuralQualityAnalyzer.quality(stem: cursorPair.stem, pairs: allPairs, in: file)?.canonical
            ?? 0
        let linkOrder = preferLinked ? [true, false] : [false, true]
        var results: [StemEditSuggestion] = []
        var seenAlignments: Set<String> = []

        func appendCandidate(
            _ candidateAligned: String,
            identifier: String,
            title: String,
            direction: Int,
            linked: Bool,
            moves: [Int: Int],
            destinationColumns: Set<Int>
        ) {
            guard seenAlignments.insert(candidateAligned).inserted,
                  ungappedResidues(in: candidateAligned) == ungappedResidues(in: originalAligned) else { return }
            let candidateCharacters = Array(candidateAligned)
            let afterMetrics = rowMetrics(characters: candidateCharacters, pairs: stemPairs)
            let globalAfter = globalBefore - beforeMetrics.canonical + afterMetrics.canonical
            let improvement = afterMetrics.canonical > beforeMetrics.canonical
                || (afterMetrics.canonical == beforeMetrics.canonical && afterMetrics.noncanonical < beforeMetrics.noncanonical)
                || (afterMetrics.canonical == beforeMetrics.canonical && afterMetrics.gaps < beforeMetrics.gaps)
            guard improvement else { return }

            let leftColumns = stemPairs.map(\.left).sorted()
            let rightColumns = stemPairs.map(\.right).sorted()
            results.append(StemEditSuggestion(
                id: identifier,
                modelRow: modelRow,
                sequenceName: sequenceName,
                recordIndex: recordIndex,
                stem: cursorPair.stem,
                operationTitle: title,
                direction: direction,
                linked: linked,
                moves: moves,
                primaryDestinationColumns: destinationColumns,
                expectedAligned: originalAligned,
                proposedAligned: candidateAligned,
                before: beforeMetrics,
                after: afterMetrics,
                globalCanonicalBefore: globalBefore,
                globalCanonicalAfter: globalAfter,
                leftBefore: string(at: leftColumns, in: originalCharacters),
                leftAfter: string(at: leftColumns, in: candidateCharacters),
                rightBefore: string(at: rightColumns, in: originalCharacters),
                rightAfter: string(at: rightColumns, in: candidateCharacters)
            ))
        }

        for linked in linkOrder {
            for direction in [-1, 1] {
                let plan = StemArmShiftPlan(
                    stem: cursorPair.stem,
                    primaryColumns: primaryColumns,
                    counterpartColumns: counterpartColumns,
                    direction: direction,
                    linkPairedArm: linked
                )
                guard let candidateAligned = shifted(originalAligned, moves: plan.moves) else { continue }
                appendCandidate(
                    candidateAligned,
                    identifier: "stem:\(modelRow):\(cursorPair.stem):\(direction):\(linked)",
                    title: direction < 0 ? "Shift selected stem arm left" : "Shift selected stem arm right",
                    direction: direction,
                    linked: linked,
                    moves: plan.moves,
                    destinationColumns: plan.primaryDestinationColumns
                )
            }
        }

        // Also test width-preserving gap transfers near either arm. This can
        // pull a residue that is just outside an SS_cons column into register,
        // which moving the already-aligned stem columns cannot do.
        let endpoints = Set(stemPairs.flatMap { [$0.left, $0.right] })
        let candidateColumns = Set(endpoints.flatMap { endpoint in
            [endpoint - 1, endpoint, endpoint + 1].filter { $0 >= 0 && $0 < file.alignmentLength }
        })
        for candidateColumn in candidateColumns.sorted() {
            if let opened = openingGap(in: originalAligned, at: candidateColumn) {
                appendCandidate(
                    opened,
                    identifier: "open:\(modelRow):\(candidateColumn)",
                    title: "Open a gap before column \(candidateColumn + 1)",
                    direction: 1,
                    linked: false,
                    moves: [:],
                    destinationColumns: endpoints
                )
            }
            if let closed = closingGap(in: originalAligned, at: candidateColumn) {
                appendCandidate(
                    closed,
                    identifier: "close:\(modelRow):\(candidateColumn)",
                    title: "Close the gap at column \(candidateColumn + 1)",
                    direction: -1,
                    linked: false,
                    moves: [:],
                    destinationColumns: endpoints
                )
            }
        }

        return results.sorted {
            if $0.canonicalGain != $1.canonicalGain { return $0.canonicalGain > $1.canonicalGain }
            if $0.globalCanonicalGain != $1.globalCanonicalGain { return $0.globalCanonicalGain > $1.globalCanonicalGain }
            if $0.after.noncanonical != $1.after.noncanonical { return $0.after.noncanonical < $1.after.noncanonical }
            if $0.after.gaps != $1.after.gaps { return $0.after.gaps < $1.after.gaps }
            if $0.linked != $1.linked { return $0.linked && !$1.linked }
            return $0.id < $1.id
        }
    }

    /// Iteratively applies the strongest structural improvement available for
    /// each sequence. Every accepted edit preserves ungapped residues, never
    /// reduces the alignment-wide canonical count, and never increases the
    /// definite noncanonical count. Successive passes build on prior edits
    /// until no supported one-column move can safely improve those metrics.
    static func refineEntireAlignment(
        in source: StockholmFile,
        preferLinked: Bool,
        maximumPasses: Int = 50
    ) -> AlignmentRefinementResult {
        let allPairs = StructureParser.pairs(in: source)
        let beforeScore = alignmentScore(in: source, pairs: allPairs)
        guard !allPairs.isEmpty, maximumPasses > 0 else {
            return AlignmentRefinementResult(
                file: source,
                before: beforeScore,
                after: beforeScore,
                editCount: 0,
                changedSequenceCount: 0,
                passes: 0,
                converged: true
            )
        }

        let stems = Dictionary(grouping: allPairs, by: \.stem)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.left < $1.left } }
        var refined = source
        var score = beforeScore
        var editCount = 0
        var changedRecordIndices: Set<Int> = []
        var passes = 0
        var converged = false

        while passes < maximumPasses {
            passes += 1
            var changedInPass = false
            let rows = refined.rows

            for modelRow in rows.indices where rows[modelRow].kind.isSequence {
                let recordIndex = rows[modelRow].recordIndex
                let currentAligned = refined.records[recordIndex].aligned
                let currentRowScore = refinementScore(
                    rowMetrics(characters: Array(currentAligned), pairs: allPairs)
                )
                var bestSuggestion: StemEditSuggestion?
                var bestScore: AlignmentRefinementScore?
                var seenAlignments: Set<String> = []

                for stemPairs in stems {
                    guard let cursorPair = stemPairs.first else { continue }
                    for cursorIsLeft in [true, false] {
                        let candidates = suggestions(
                            in: refined,
                            modelRow: modelRow,
                            cursorPair: cursorPair,
                            stemPairs: stemPairs,
                            cursorIsLeft: cursorIsLeft,
                            preferLinked: preferLinked,
                            allPairs: allPairs,
                            globalCanonicalBeforeOverride: 0
                        )
                        for candidate in candidates where seenAlignments.insert(candidate.proposedAligned).inserted {
                            let candidateRowScore = refinementScore(
                                rowMetrics(characters: Array(candidate.proposedAligned), pairs: allPairs)
                            )
                            let candidateScore = replacing(
                                score,
                                rowScore: currentRowScore,
                                with: candidateRowScore
                            )
                            guard candidateScore.isSafeImprovement(over: score) else { continue }
                            if let existingScore = bestScore {
                                if candidateScore.isPreferred(over: existingScore)
                                    || (candidateScore == existingScore
                                        && bestSuggestion.map { isPreferred(candidate, over: $0) } == true) {
                                    bestSuggestion = candidate
                                    bestScore = candidateScore
                                }
                            } else {
                                bestSuggestion = candidate
                                bestScore = candidateScore
                            }
                        }
                    }
                }

                guard let bestSuggestion, let bestScore,
                      refined.records[recordIndex].aligned == bestSuggestion.expectedAligned else { continue }
                refined.records[recordIndex].aligned = bestSuggestion.proposedAligned
                score = bestScore
                editCount += 1
                changedRecordIndices.insert(recordIndex)
                changedInPass = true
            }

            if !changedInPass {
                converged = true
                break
            }
        }

        guard SequenceIntegrityAnalyzer.preservesSequences(from: source, to: refined) else {
            return AlignmentRefinementResult(
                file: source,
                before: beforeScore,
                after: beforeScore,
                editCount: 0,
                changedSequenceCount: 0,
                passes: passes,
                converged: false
            )
        }
        return AlignmentRefinementResult(
            file: refined,
            before: beforeScore,
            after: score,
            editCount: editCount,
            changedSequenceCount: changedRecordIndices.count,
            passes: passes,
            converged: converged
        )
    }

    private static func alignmentScore(in file: StockholmFile, pairs: [BasePair]) -> AlignmentRefinementScore {
        file.sequenceRows.reduce(
            AlignmentRefinementScore(canonical: 0, noncanonical: 0, gaps: 0, ambiguous: 0)
        ) { total, row in
            let rowScore = refinementScore(
                rowMetrics(characters: Array(file.records[row.recordIndex].aligned), pairs: pairs)
            )
            return AlignmentRefinementScore(
                canonical: total.canonical + rowScore.canonical,
                noncanonical: total.noncanonical + rowScore.noncanonical,
                gaps: total.gaps + rowScore.gaps,
                ambiguous: total.ambiguous + rowScore.ambiguous
            )
        }
    }

    private static func refinementScore(_ metrics: RowStemMetrics) -> AlignmentRefinementScore {
        AlignmentRefinementScore(
            canonical: metrics.canonical,
            noncanonical: metrics.noncanonical,
            gaps: metrics.gaps,
            ambiguous: metrics.ambiguous
        )
    }

    private static func replacing(
        _ total: AlignmentRefinementScore,
        rowScore old: AlignmentRefinementScore,
        with new: AlignmentRefinementScore
    ) -> AlignmentRefinementScore {
        AlignmentRefinementScore(
            canonical: total.canonical - old.canonical + new.canonical,
            noncanonical: total.noncanonical - old.noncanonical + new.noncanonical,
            gaps: total.gaps - old.gaps + new.gaps,
            ambiguous: total.ambiguous - old.ambiguous + new.ambiguous
        )
    }

    private static func isPreferred(_ lhs: StemEditSuggestion, over rhs: StemEditSuggestion) -> Bool {
        if lhs.canonicalGain != rhs.canonicalGain { return lhs.canonicalGain > rhs.canonicalGain }
        if lhs.after.noncanonical != rhs.after.noncanonical { return lhs.after.noncanonical < rhs.after.noncanonical }
        if lhs.after.gaps != rhs.after.gaps { return lhs.after.gaps < rhs.after.gaps }
        if lhs.linked != rhs.linked { return lhs.linked && !rhs.linked }
        return lhs.id < rhs.id
    }

    private static func rowMetrics(characters: [Character], pairs: [BasePair]) -> RowStemMetrics {
        var canonical = 0
        var noncanonical = 0
        var gaps = 0
        var ambiguous = 0
        for pair in pairs {
            let left = characters.indices.contains(pair.left) ? characters[pair.left] : "-"
            let right = characters.indices.contains(pair.right) ? characters[pair.right] : "-"
            if StockholmFile.isGap(left) || StockholmFile.isGap(right) || left == "_" || right == "_" {
                gaps += 1
            } else {
                let normalizedLeft = Character(String(left).uppercased()) == "T" ? "U" : Character(String(left).uppercased())
                let normalizedRight = Character(String(right).uppercased()) == "T" ? "U" : Character(String(right).uppercased())
                let canonicalAlphabet = Set("ACGU")
                if !canonicalAlphabet.contains(normalizedLeft) || !canonicalAlphabet.contains(normalizedRight) {
                    ambiguous += 1
                } else if BasePairRules.isCanonical(normalizedLeft, normalizedRight) {
                    canonical += 1
                } else {
                    noncanonical += 1
                }
            }
        }
        return RowStemMetrics(canonical: canonical, noncanonical: noncanonical, gaps: gaps, ambiguous: ambiguous)
    }

    private static func string(at columns: [Int], in characters: [Character]) -> String {
        String(columns.map { characters.indices.contains($0) ? characters[$0] : " " })
    }

    private static func shifted(_ aligned: String, moves: [Int: Int]) -> String? {
        guard !moves.isEmpty else { return nil }
        let characters = Array(aligned)
        let sources = Set(moves.keys)
        let destinations = Array(moves.values)
        guard Set(destinations).count == destinations.count,
              sources.allSatisfy({ characters.indices.contains($0) }),
              destinations.allSatisfy({ characters.indices.contains($0) }),
              Set(destinations).subtracting(sources).allSatisfy({ StockholmFile.isGap(characters[$0]) }) else { return nil }
        var result = characters
        for source in sources { result[source] = "-" }
        for (source, destination) in moves { result[destination] = characters[source] }
        let candidate = String(result)
        return candidate == aligned ? nil : candidate
    }

    private static func openingGap(in aligned: String, at column: Int) -> String? {
        var characters = Array(aligned)
        guard characters.indices.contains(column),
              let downstreamGap = ((column + 1)..<characters.count).first(where: { StockholmFile.isGap(characters[$0]) }) else { return nil }
        characters.remove(at: downstreamGap)
        characters.insert("-", at: column)
        let candidate = String(characters)
        return candidate == aligned ? nil : candidate
    }

    private static func closingGap(in aligned: String, at column: Int) -> String? {
        var characters = Array(aligned)
        guard characters.indices.contains(column), StockholmFile.isGap(characters[column]) else { return nil }
        let downstreamGap = ((column + 1)..<characters.count).first(where: { StockholmFile.isGap(characters[$0]) }) ?? characters.count
        characters.remove(at: column)
        characters.insert("-", at: min(downstreamGap, characters.count))
        let candidate = String(characters)
        return candidate == aligned ? nil : candidate
    }

    private static func ungappedResidues(in aligned: String) -> String {
        String(aligned.filter { !(StockholmFile.isGap($0) || $0 == "_" || $0 == " ") })
    }
}
