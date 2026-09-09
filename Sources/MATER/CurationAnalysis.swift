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
        AlignmentSymbol.isSequenceGap(character)
    }
}

enum ResidueAnnotationIntegrityAnalyzer {
    /// Verifies that #=GR characters remain attached to the same residue
    /// ordinals for every sequence whose gap placement changed. Standalone
    /// annotation editing remains allowed because no sequence moved.
    static func preservesAttachmentsForMovedSequences(
        from before: StockholmFile,
        to after: StockholmFile
    ) -> Bool {
        let beforeSequences = uniqueSequences(in: before)
        let afterSequences = uniqueSequences(in: after)
        for (name, beforeIndex) in beforeSequences {
            guard let afterIndex = afterSequences[name] else { continue }
            let oldAligned = before.records[beforeIndex].aligned
            let newAligned = after.records[afterIndex].aligned
            guard oldAligned != newAligned,
                  StockholmFile.ungappedResidues(in: oldAligned) == StockholmFile.ungappedResidues(in: newAligned) else { continue }
            if residueAnnotationSignatures(sequence: name, in: before)
                != residueAnnotationSignatures(sequence: name, in: after) {
                return false
            }
        }
        return true
    }

    private static func uniqueSequences(in file: StockholmFile) -> [String: Int] {
        let grouped = Dictionary(grouping: file.sequenceRows.compactMap { row -> (String, Int)? in
            guard case .sequence(let name) = row.kind else { return nil }
            return (name, row.recordIndex)
        }, by: { $0.0 })
        return grouped.compactMapValues { $0.count == 1 ? $0[0].1 : nil }
    }

    private static func residueAnnotationSignatures(sequence name: String, in file: StockholmFile) -> [String: String] {
        guard let sequenceRow = file.sequenceRows.first(where: {
            if case .sequence(let candidate) = $0.kind { return candidate == name }
            return false
        }) else { return [:] }
        let sequence = Array(file.records[sequenceRow.recordIndex].aligned)
        var result: [String: String] = [:]
        for record in file.records {
            guard case .residueAnnotation(let sequenceName, let tag) = record.kind,
                  sequenceName == name else { continue }
            let annotation = Array(record.aligned)
            guard annotation.count == sequence.count else {
                result[tag] = "<invalid-width>"
                continue
            }
            result[tag] = String(sequence.indices.compactMap {
                AlignmentSymbol.isSequenceGap(sequence[$0]) ? nil : annotation[$0]
            })
        }
        return result
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

                if AlignmentSymbol.isSequenceGap(left) || AlignmentSymbol.isSequenceGap(right) {
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
        let count = characters.filter(AlignmentSymbol.isSequenceGap).count
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
    let neighborhoodProfileBefore: Double
    let neighborhoodProfileAfter: Double
    let residueDisplacement: Int
    let leftBefore: String
    let leftAfter: String
    let rightBefore: String
    let rightAfter: String

    var canonicalGain: Int { after.canonical - before.canonical }
    var globalCanonicalGain: Int { globalCanonicalAfter - globalCanonicalBefore }
    var neighborhoodProfileGain: Double { neighborhoodProfileAfter - neighborhoodProfileBefore }
    var directionTitle: String { operationTitle }
}

struct AlignmentRefinementScore: Equatable, Sendable {
    let canonical: Int
    let noncanonical: Int
    let gaps: Int
    let ambiguous: Int

    /// Automatic refinement uses a Pareto-style safety rule: canonical support
    /// may not decrease and definite noncanonical observations may not increase.
    /// Gap and ambiguity counts are descriptive only because either can
    /// represent a legitimate structural subtype or incomplete sequence.
    func isSafeChange(over other: AlignmentRefinementScore) -> Bool {
        canonical >= other.canonical && noncanonical <= other.noncanonical
    }

    func isSafeImprovement(over other: AlignmentRefinementScore) -> Bool {
        isSafeChange(over: other)
            && (canonical > other.canonical || noncanonical < other.noncanonical)
    }

    func isPreferred(over other: AlignmentRefinementScore) -> Bool {
        if canonical != other.canonical { return canonical > other.canonical }
        if noncanonical != other.noncanonical { return noncanonical < other.noncanonical }
        return false
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

struct AlignmentRefinementProgress: Equatable, Sendable {
    let pass: Int
    let completedRows: Int
    let totalRows: Int
    let editCount: Int

    var fractionCompleted: Double {
        totalRows == 0 ? 0 : Double(completedRows) / Double(totalRows)
    }
}

private struct RefinementColumnProfile: Sendable {
    let weightedCounts: [Int: [Character: Double]]
    let totals: [Int: Double]
    let excludedWeight: Double
    let excludedSymbols: [Int: Character]

    func logProbability(of character: Character, at column: Int) -> Double {
        guard let symbol = StemEditSuggester.profileSymbol(character) else { return 0 }
        let excludedSymbol = excludedSymbols[column]
        let total = (totals[column] ?? 0) - (excludedSymbol == nil ? 0 : excludedWeight)
        guard total > 0 else { return 0 }
        let alphabetSize = 5.0
        let pseudocount = 0.25
        let count = (weightedCounts[column]?[symbol] ?? 0)
            - (excludedSymbol == symbol ? excludedWeight : 0)
        return log((count + pseudocount) / (total + alphabetSize * pseudocount))
    }
}

private struct WeightedAlignmentColumnProfile: Sendable {
    let weightedCounts: [Int: [Character: Double]]
    let totals: [Int: Double]
    let weightByRecordIndex: [Int: Double]

    func excluding(recordIndex: Int, characters: [Character]) -> RefinementColumnProfile {
        let symbols = Dictionary(uniqueKeysWithValues: characters.enumerated().compactMap { column, character in
            StemEditSuggester.profileSymbol(character).map { (column, $0) }
        })
        return RefinementColumnProfile(
            weightedCounts: weightedCounts,
            totals: totals,
            excludedWeight: weightByRecordIndex[recordIndex] ?? 0,
            excludedSymbols: symbols
        )
    }
}

private struct HelixWindowPlacement: Sendable {
    let characters: [Character]
    let displacement: Int
    let profileScore: Double
    let structuralProxyScore: Double
}

private struct HelixPlacementState {
    var characters: [Character]
    var residueIndex: Int
    var gapIndex: Int
    var displacement: Int
    var profileScore: Double
    var structuralProxyScore: Double

    var rankingScore: Double {
        profileScore + structuralProxyScore * 2.0 - Double(displacement) * 0.025
    }
}

enum StemEditSuggester {
    private static let neighborhoodFlank = 3
    private static let maximumResidueDisplacement = 3
    private static let placementBeamWidth = 256
    private static let placementsPerWindow = 24
    private static let minimumProfileGain = 0.20

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
        let sequenceWeights = ConsensusAnalyzer.gscWeights(for: file.sequenceRows.map {
            Array(file.records[$0.recordIndex].aligned)
        })
        let alignmentProfile = weightedAlignmentProfile(in: file, sequenceWeights: sequenceWeights)
        return suggestions(
            in: file,
            modelRow: modelRow,
            cursorPair: cursorPair,
            stemPairs: allPairs.filter { $0.stem == cursorPair.stem }.sorted { $0.left < $1.left },
            cursorIsLeft: cursorPair.left == column,
            preferLinked: preferLinked,
            allPairs: allPairs,
            globalCanonicalBeforeOverride: nil,
            alignmentProfile: alignmentProfile,
            includeHelixWindow: true,
            includeRedistributionWindow: true,
            maximumUniformShift: maximumResidueDisplacement,
            allowProfileOnly: true
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
        globalCanonicalBeforeOverride: Int?,
        alignmentProfile: WeightedAlignmentColumnProfile,
        includeHelixWindow: Bool,
        includeRedistributionWindow: Bool,
        maximumUniformShift: Int,
        allowProfileOnly: Bool
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
        let allPairsBeforeMetrics = rowMetrics(characters: originalCharacters, pairs: allPairs)
        let globalBefore = globalCanonicalBeforeOverride
            ?? StructuralQualityAnalyzer.quality(stem: cursorPair.stem, pairs: allPairs, in: file)?.canonical
            ?? 0
        let endpoints = Set(stemPairs.flatMap { [$0.left, $0.right] })
        let armWindows = refinementArmWindows(
            stemPairs: stemPairs,
            allPairs: allPairs,
            alignmentLength: file.alignmentLength,
            flank: neighborhoodFlank
        )
        let refinementWindows = mergedRanges(armWindows)
        let editableColumns = Set(refinementWindows.flatMap { Array($0) })
        let unpairedNeighborhoodColumns = editableColumns.subtracting(endpoints)
        let profile = alignmentProfile.excluding(
            recordIndex: recordIndex,
            characters: originalCharacters
        )
        let profileBefore = profileScore(
            characters: originalCharacters,
            columns: unpairedNeighborhoodColumns,
            profile: profile
        )
        let helixPresent = hasTwoArmOccupancy(
            characters: originalCharacters,
            armWindows: armWindows,
            pairCount: stemPairs.count
        )
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
            destinationColumns: Set<Int>,
            residueDisplacement: Int
        ) {
            guard seenAlignments.insert(candidateAligned).inserted,
                  ungappedResidues(in: candidateAligned) == ungappedResidues(in: originalAligned) else { return }
            let candidateCharacters = Array(candidateAligned)
            let afterMetrics = rowMetrics(characters: candidateCharacters, pairs: stemPairs)
            let allPairsAfterMetrics = rowMetrics(characters: candidateCharacters, pairs: allPairs)
            guard allPairsAfterMetrics.canonical >= allPairsBeforeMetrics.canonical,
                  allPairsAfterMetrics.noncanonical <= allPairsBeforeMetrics.noncanonical else { return }
            if afterMetrics.canonical > beforeMetrics.canonical, !helixPresent { return }
            let globalAfter = globalBefore - beforeMetrics.canonical + afterMetrics.canonical
            let candidateProfile = profileScore(
                characters: candidateCharacters,
                columns: unpairedNeighborhoodColumns,
                profile: profile
            )
            let structuralImprovement = afterMetrics.canonical > beforeMetrics.canonical
                || afterMetrics.noncanonical < beforeMetrics.noncanonical
            let improvement = structuralImprovement
                || (allowProfileOnly && candidateProfile - profileBefore >= minimumProfileGain)
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
                neighborhoodProfileBefore: profileBefore,
                neighborhoodProfileAfter: candidateProfile,
                residueDisplacement: residueDisplacement,
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
                    destinationColumns: plan.primaryDestinationColumns,
                    residueDisplacement: plan.moves.count
                )
            }
        }

        // Also test width-preserving gap transfers near either arm. This can
        // pull a residue that is just outside an SS_cons column into register,
        // which moving the already-aligned stem columns cannot do.
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
                    destinationColumns: endpoints,
                    residueDisplacement: 1
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
                    destinationColumns: endpoints,
                    residueDisplacement: 1
                )
            }
        }

        if includeHelixWindow, helixPresent, armWindows.count == 2 {
            let leftPlacements = uniformArmPlacements(
                characters: originalCharacters,
                range: armWindows[0],
                maximumShift: maximumUniformShift
            )
            let rightPlacements = uniformArmPlacements(
                characters: originalCharacters,
                range: armWindows[1],
                maximumShift: maximumUniformShift
            )
            var candidateCounter = 0
            for leftPlacement in leftPlacements {
                for rightPlacement in rightPlacements {
                    var replacement = originalCharacters
                    replacement.replaceSubrange(armWindows[0], with: leftPlacement.characters)
                    replacement.replaceSubrange(armWindows[1], with: rightPlacement.characters)
                    candidateCounter += 1
                    appendCandidate(
                        String(replacement),
                        identifier: "helix-arm-window:\(modelRow):\(cursorPair.stem):\(candidateCounter)",
                        title: "Optimize helix arms and ±\(neighborhoodFlank)-nt flanks",
                        direction: 0,
                        linked: true,
                        moves: [:],
                        destinationColumns: editableColumns,
                        residueDisplacement: leftPlacement.displacement + rightPlacement.displacement
                    )
                }
            }
        }

        if includeHelixWindow, includeRedistributionWindow, helixPresent, !refinementWindows.isEmpty {
            let placements = refinementWindows.map { range in
                windowPlacements(
                    characters: originalCharacters,
                    range: range,
                    unpairedColumns: unpairedNeighborhoodColumns,
                    profile: profile,
                    stemPairs: stemPairs
                )
            }
            var candidateCounter = 0

            func combinePlacements(
                windowIndex: Int,
                characters: [Character],
                displacement: Int
            ) {
                if windowIndex == refinementWindows.count {
                    candidateCounter += 1
                    appendCandidate(
                        String(characters),
                        identifier: "helix-window:\(modelRow):\(cursorPair.stem):\(candidateCounter)",
                        title: "Optimize helix and ±\(neighborhoodFlank)-nt neighborhood",
                        direction: 0,
                        linked: true,
                        moves: [:],
                        destinationColumns: editableColumns,
                        residueDisplacement: displacement
                    )
                    return
                }

                let range = refinementWindows[windowIndex]
                for placement in placements[windowIndex] {
                    var replacement = characters
                    replacement.replaceSubrange(range, with: placement.characters)
                    combinePlacements(
                        windowIndex: windowIndex + 1,
                        characters: replacement,
                        displacement: displacement + placement.displacement
                    )
                }
            }

            combinePlacements(windowIndex: 0, characters: originalCharacters, displacement: 0)
        }

        return Array(results.sorted {
            if $0.canonicalGain != $1.canonicalGain { return $0.canonicalGain > $1.canonicalGain }
            if $0.globalCanonicalGain != $1.globalCanonicalGain { return $0.globalCanonicalGain > $1.globalCanonicalGain }
            if $0.after.noncanonical != $1.after.noncanonical { return $0.after.noncanonical < $1.after.noncanonical }
            if abs($0.neighborhoodProfileGain - $1.neighborhoodProfileGain) > 0.000_001 {
                return $0.neighborhoodProfileGain > $1.neighborhoodProfileGain
            }
            if $0.residueDisplacement != $1.residueDisplacement { return $0.residueDisplacement < $1.residueDisplacement }
            if $0.linked != $1.linked { return $0.linked && !$1.linked }
            return $0.id < $1.id
        }.prefix(16))
    }

    private static func refinementArmWindows(
        stemPairs: [BasePair],
        allPairs: [BasePair],
        alignmentLength: Int,
        flank: Int
    ) -> [ClosedRange<Int>] {
        guard alignmentLength > 0,
              let leftMinimum = stemPairs.map(\.left).min(),
              let leftMaximum = stemPairs.map(\.left).max(),
              let rightMinimum = stemPairs.map(\.right).min(),
              let rightMaximum = stemPairs.map(\.right).max() else { return [] }
        let stemColumns = Set(stemPairs.flatMap { [$0.left, $0.right] })
        let blockedColumns = Set(allPairs.flatMap { [$0.left, $0.right] }).subtracting(stemColumns)

        func expanded(_ core: ClosedRange<Int>) -> ClosedRange<Int> {
            var lower = core.lowerBound
            var upper = core.upperBound
            var added = 0
            while lower > 0, added < flank {
                let candidate = lower - 1
                guard !blockedColumns.contains(candidate) else { break }
                lower = candidate
                added += 1
            }
            added = 0
            while upper + 1 < alignmentLength, added < flank {
                let candidate = upper + 1
                guard !blockedColumns.contains(candidate) else { break }
                upper = candidate
                added += 1
            }
            return lower...upper
        }

        var leftWindow = expanded(leftMinimum...leftMaximum)
        var rightWindow = expanded(rightMinimum...rightMaximum)
        if leftWindow.upperBound >= rightWindow.lowerBound {
            let split = (leftMaximum + rightMinimum) / 2
            leftWindow = leftWindow.lowerBound...max(leftWindow.lowerBound, split)
            rightWindow = min(rightWindow.upperBound, split + 1)...rightWindow.upperBound
        }
        return [leftWindow, rightWindow]
    }

    private static func mergedRanges(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sorted.first else { return [] }
        var result: [ClosedRange<Int>] = []
        for range in sorted.dropFirst() {
            if range.lowerBound <= current.upperBound + 1 {
                current = current.lowerBound...max(current.upperBound, range.upperBound)
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }

    private static func hasTwoArmOccupancy(
        characters: [Character],
        armWindows: [ClosedRange<Int>],
        pairCount: Int
    ) -> Bool {
        guard armWindows.count == 2 else { return false }
        let requiredPerArm = max(1, (pairCount + 1) / 2)
        return armWindows.allSatisfy { range in
            range.reduce(into: 0) { count, column in
                guard characters.indices.contains(column) else { return }
                if !isAlignmentGap(characters[column]) { count += 1 }
            } >= requiredPerArm
        }
    }

    private static func weightedAlignmentProfile(
        in file: StockholmFile,
        sequenceWeights: [Float]
    ) -> WeightedAlignmentColumnProfile {
        let sequenceRows = file.sequenceRows
        let sequences = sequenceRows.map { Array(file.records[$0.recordIndex].aligned) }
        var counts: [Int: [Character: Double]] = [:]
        var totals: [Int: Double] = [:]
        var weightByRecordIndex: [Int: Double] = [:]

        for sequenceIndex in sequenceRows.indices {
            let row = sequenceRows[sequenceIndex]
            let weight = sequenceIndex < sequenceWeights.count ? Double(sequenceWeights[sequenceIndex]) : 1
            guard weight > 0 else { continue }
            weightByRecordIndex[row.recordIndex] = weight
            for (column, character) in sequences[sequenceIndex].enumerated() {
                guard let symbol = profileSymbol(character) else { continue }
                counts[column, default: [:]][symbol, default: 0] += weight
                totals[column, default: 0] += weight
            }
        }
        return WeightedAlignmentColumnProfile(
            weightedCounts: counts,
            totals: totals,
            weightByRecordIndex: weightByRecordIndex
        )
    }

    static func profileSymbol(_ character: Character) -> Character? {
        if isAlignmentGap(character) { return "-" }
        let upper = Character(String(character).uppercased())
        switch upper {
        case "A", "C", "G", "U": return upper
        case "T": return "U"
        default: return nil
        }
    }

    private static func profileScore(
        characters: [Character],
        columns: Set<Int>,
        profile: RefinementColumnProfile
    ) -> Double {
        columns.reduce(0) { total, column in
            guard characters.indices.contains(column) else { return total }
            return total + profile.logProbability(of: characters[column], at: column)
        }
    }

    private static func windowPlacements(
        characters: [Character],
        range: ClosedRange<Int>,
        unpairedColumns: Set<Int>,
        profile: RefinementColumnProfile,
        stemPairs: [BasePair]
    ) -> [HelixWindowPlacement] {
        let original = Array(characters[range])
        let residues = original.enumerated().compactMap { offset, character -> (Character, Int)? in
            isAlignmentGap(character) ? nil : (character, offset)
        }
        let gaps = original.filter(isAlignmentGap)
        guard !residues.isEmpty, !gaps.isEmpty else {
            return [HelixWindowPlacement(
                characters: original,
                displacement: 0,
                profileScore: 0,
                structuralProxyScore: 0
            )]
        }

        var states = [HelixPlacementState(
            characters: [],
            residueIndex: 0,
            gapIndex: 0,
            displacement: 0,
            profileScore: 0,
            structuralProxyScore: 0
        )]
        let partnerByColumn = Dictionary(uniqueKeysWithValues: stemPairs.flatMap { pair in
            [(pair.left, pair.right), (pair.right, pair.left)]
        })

        for offset in original.indices {
            let globalColumn = range.lowerBound + offset
            var nextStates: [HelixPlacementState] = []
            nextStates.reserveCapacity(states.count * 2)

            for state in states {
                if state.residueIndex < residues.count {
                    let residue = residues[state.residueIndex]
                    let displacement = abs(offset - residue.1)
                    if displacement <= maximumResidueDisplacement {
                        var next = state
                        next.characters.append(residue.0)
                        next.residueIndex += 1
                        next.displacement += displacement
                        if unpairedColumns.contains(globalColumn) {
                            next.profileScore += profile.logProbability(of: residue.0, at: globalColumn)
                        }
                        if let partner = partnerByColumn[globalColumn], characters.indices.contains(partner) {
                            let partnerCharacter = characters[partner]
                            if !isAlignmentGap(partnerCharacter) {
                                next.structuralProxyScore += BasePairRules.isCanonical(residue.0, partnerCharacter) ? 1 : -0.5
                            }
                        }
                        nextStates.append(next)
                    }
                }

                if state.gapIndex < gaps.count {
                    var next = state
                    let gap = gaps[state.gapIndex]
                    next.characters.append(gap)
                    next.gapIndex += 1
                    if unpairedColumns.contains(globalColumn) {
                        next.profileScore += profile.logProbability(of: gap, at: globalColumn)
                    }
                    nextStates.append(next)
                }
            }

            var grouped: [Int: [HelixPlacementState]] = [:]
            for state in nextStates {
                grouped[state.residueIndex, default: []].append(state)
            }
            states = grouped.values.flatMap { group in
                group.sorted { lhs, rhs in
                    if abs(lhs.rankingScore - rhs.rankingScore) > 0.000_001 {
                        return lhs.rankingScore > rhs.rankingScore
                    }
                    return lhs.displacement < rhs.displacement
                }.prefix(24)
            }
            .sorted { $0.rankingScore > $1.rankingScore }
            if states.count > placementBeamWidth {
                states.removeLast(states.count - placementBeamWidth)
            }
        }

        let completed = states.filter {
            $0.residueIndex == residues.count && $0.gapIndex == gaps.count
        }
        var placements: [HelixWindowPlacement] = completed.map {
            HelixWindowPlacement(
                characters: $0.characters,
                displacement: $0.displacement,
                profileScore: $0.profileScore,
                structuralProxyScore: $0.structuralProxyScore
            )
        }
        if !placements.contains(where: { $0.characters == original }) {
            placements.append(HelixWindowPlacement(
                characters: original,
                displacement: 0,
                profileScore: original.enumerated().reduce(0) { score, item in
                    let column = range.lowerBound + item.offset
                    guard unpairedColumns.contains(column) else { return score }
                    return score + profile.logProbability(of: item.element, at: column)
                },
                structuralProxyScore: 0
            ))
        }
        var seen: Set<String> = []
        return Array(placements.sorted { lhs, rhs in
            let lhsScore = lhs.profileScore + lhs.structuralProxyScore * 2.0 - Double(lhs.displacement) * 0.025
            let rhsScore = rhs.profileScore + rhs.structuralProxyScore * 2.0 - Double(rhs.displacement) * 0.025
            if abs(lhsScore - rhsScore) > 0.000_001 { return lhsScore > rhsScore }
            return lhs.displacement < rhs.displacement
        }.filter { seen.insert(String($0.characters)).inserted }.prefix(placementsPerWindow))
    }

    private static func uniformArmPlacements(
        characters: [Character],
        range: ClosedRange<Int>,
        maximumShift: Int
    ) -> [HelixWindowPlacement] {
        let original = Array(characters[range])
        let sourceColumns = original.indices.filter { !isAlignmentGap(original[$0]) }
        guard !sourceColumns.isEmpty else {
            return [HelixWindowPlacement(
                characters: original,
                displacement: 0,
                profileScore: 0,
                structuralProxyScore: 0
            )]
        }
        var result = [HelixWindowPlacement(
            characters: original,
            displacement: 0,
            profileScore: 0,
            structuralProxyScore: 0
        )]
        let sources = Set(sourceColumns)
        let boundedShift = max(0, min(maximumResidueDisplacement, maximumShift))
        guard boundedShift > 0 else { return result }
        for direction in -boundedShift...boundedShift where direction != 0 {
            let destinations = sourceColumns.map { $0 + direction }
            guard destinations.allSatisfy(original.indices.contains),
                  Set(destinations).subtracting(sources).allSatisfy({ isAlignmentGap(original[$0]) }) else { continue }
            let moves = Dictionary(uniqueKeysWithValues: zip(sourceColumns, destinations))
            guard let shifted = StockholmFile.movedCharactersPreservingGaps(original, moves: moves) else { continue }
            result.append(HelixWindowPlacement(
                characters: shifted,
                displacement: sourceColumns.count * abs(direction),
                profileScore: 0,
                structuralProxyScore: 0
            ))
        }
        return result
    }

    /// Iteratively applies the strongest structural improvement available for
    /// each sequence. Every accepted edit preserves ungapped residues, never
    /// reduces the alignment-wide canonical count, and never increases the
    /// definite noncanonical count. Successive passes build on prior edits
    /// until no supported helix-window or adjacent move can safely improve the
    /// structural metrics. The neighboring GSC-weighted profile breaks ties;
    /// it cannot make an otherwise neutral automatic edit eligible.
    static func refineEntireAlignment(
        in source: StockholmFile,
        preferLinked: Bool,
        maximumPasses: Int = 50
    ) -> AlignmentRefinementResult {
        // Retain a synchronous convenience entry point for tests and callers
        // that do not need cancellation.
        (try? refineEntireAlignmentCancellable(
            in: source,
            preferLinked: preferLinked,
            maximumPasses: maximumPasses
        )) ?? AlignmentRefinementResult(
            file: source,
            before: alignmentScore(in: source, pairs: StructureParser.pairs(in: source)),
            after: alignmentScore(in: source, pairs: StructureParser.pairs(in: source)),
            editCount: 0,
            changedSequenceCount: 0,
            passes: 0,
            converged: false
        )
    }

    static func refineEntireAlignmentCancellable(
        in source: StockholmFile,
        preferLinked: Bool,
        maximumPasses: Int = 50,
        shouldCancel: @Sendable () -> Bool = { false },
        progress: (@Sendable (AlignmentRefinementProgress) -> Void)? = nil
    ) throws -> AlignmentRefinementResult {
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
        // GSC weights depend on ordered ungapped sequence identity, which the
        // refinement never changes, so calculate them once for the full run.
        let sequenceWeights = ConsensusAnalyzer.gscWeights(for: source.sequenceRows.map {
            Array(source.records[$0.recordIndex].aligned)
        })
        var refined = source
        var score = beforeScore
        var editCount = 0
        var changedRecordIndices: Set<Int> = []
        var passes = 0
        var converged = false

        while passes < maximumPasses {
            if shouldCancel() { throw CancellationError() }
            passes += 1
            var changedInPass = false
            let rows = refined.rows
            let sequenceModelRows = rows.indices.filter { rows[$0].kind.isSequence }
            let progressStride = max(1, sequenceModelRows.count / 100)
            let passProfile = weightedAlignmentProfile(
                in: refined,
                sequenceWeights: sequenceWeights
            )

            for (sequenceOffset, modelRow) in sequenceModelRows.enumerated() {
                if shouldCancel() { throw CancellationError() }
                if sequenceOffset == 0 || sequenceOffset % progressStride == 0 {
                    progress?(.init(
                        pass: passes,
                        completedRows: sequenceOffset,
                        totalRows: sequenceModelRows.count,
                        editCount: editCount
                    ))
                }
                let recordIndex = rows[modelRow].recordIndex
                let maximumRowIterations = max(1, stems.count * 3)
                var rowIterations = 0
                while rowIterations < maximumRowIterations {
                    let currentAligned = refined.records[recordIndex].aligned
                    let currentRowScore = refinementScore(
                        rowMetrics(characters: Array(currentAligned), pairs: allPairs)
                    )
                    var bestSuggestion: StemEditSuggestion?
                    var bestScore: AlignmentRefinementScore?
                    var seenAlignments: Set<String> = []

                    for stemPairs in stems {
                        if shouldCancel() { throw CancellationError() }
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
                                globalCanonicalBeforeOverride: 0,
                                alignmentProfile: passProfile,
                                includeHelixWindow: cursorIsLeft,
                                includeRedistributionWindow: false,
                                maximumUniformShift: 1,
                                allowProfileOnly: false
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
                          refined.records[recordIndex].aligned == bestSuggestion.expectedAligned else { break }
                    guard refined.replaceSequenceGapPlacement(
                        recordIndex: recordIndex,
                        with: bestSuggestion.proposedAligned
                    ) else { break }
                    score = bestScore
                    editCount += 1
                    changedRecordIndices.insert(recordIndex)
                    changedInPass = true
                    rowIterations += 1
                }
                if sequenceOffset + 1 == sequenceModelRows.count {
                    progress?(.init(
                        pass: passes,
                        completedRows: sequenceModelRows.count,
                        totalRows: sequenceModelRows.count,
                        editCount: editCount
                    ))
                }
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
        if abs(lhs.neighborhoodProfileGain - rhs.neighborhoodProfileGain) > 0.000_001 {
            return lhs.neighborhoodProfileGain > rhs.neighborhoodProfileGain
        }
        if lhs.residueDisplacement != rhs.residueDisplacement {
            return lhs.residueDisplacement < rhs.residueDisplacement
        }
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
            if AlignmentSymbol.isSequenceGap(left) || AlignmentSymbol.isSequenceGap(right) {
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
        let characters = Array(aligned)
        guard let result = StockholmFile.movedCharactersPreservingGaps(characters, moves: moves) else { return nil }
        let candidate = String(result)
        return candidate == aligned ? nil : candidate
    }

    private static func openingGap(in aligned: String, at column: Int) -> String? {
        var characters = Array(aligned)
        guard characters.indices.contains(column),
              let downstreamGap = ((column + 1)..<characters.count).first(where: { StockholmFile.isGap(characters[$0]) }) else { return nil }
        let displacedGap = characters.remove(at: downstreamGap)
        characters.insert(displacedGap, at: column)
        let candidate = String(characters)
        return candidate == aligned ? nil : candidate
    }

    private static func closingGap(in aligned: String, at column: Int) -> String? {
        var characters = Array(aligned)
        guard characters.indices.contains(column), StockholmFile.isGap(characters[column]) else { return nil }
        let downstreamGap = ((column + 1)..<characters.count).first(where: { StockholmFile.isGap(characters[$0]) }) ?? characters.count
        let displacedGap = characters.remove(at: column)
        characters.insert(displacedGap, at: min(downstreamGap, characters.count))
        let candidate = String(characters)
        return candidate == aligned ? nil : candidate
    }

    private static func ungappedResidues(in aligned: String) -> String {
        StockholmFile.ungappedResidues(in: aligned)
    }

    private static func isAlignmentGap(_ character: Character) -> Bool {
        AlignmentSymbol.isSequenceGap(character)
    }
}
