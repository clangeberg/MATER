import Foundation

struct BasePair: Identifiable, Hashable, Sendable {
    let left: Int
    let right: Int
    let recordIndex: Int
    let structureTag: String
    let open: Character
    let close: Character
    var stem: Int
    var element: Int

    var id: String { "\(recordIndex):\(left):\(right)" }
    var isPseudoknot: Bool { structureTag != "SS_cons" || open != "<" }
}

struct StemArmShiftPlan: Equatable, Sendable {
    let stem: Int
    let primaryColumns: Set<Int>
    let counterpartColumns: Set<Int>
    let direction: Int
    let linkPairedArm: Bool

    var isLinked: Bool { linkPairedArm && !counterpartColumns.isEmpty }
    var pairedColumns: Set<Int> { isLinked ? counterpartColumns : [] }
    var pairedDirection: Int { -direction }
    var primaryDestinationColumns: Set<Int> { Set(primaryColumns.map { $0 + direction }) }
    var counterpartDestinationColumns: Set<Int> {
        isLinked ? Set(counterpartColumns.map { $0 + pairedDirection }) : counterpartColumns
    }

    var moves: [Int: Int] {
        var result = Dictionary(uniqueKeysWithValues: primaryColumns.map { ($0, $0 + direction) })
        for column in pairedColumns {
            result[column] = column + pairedDirection
        }
        return result
    }
}

enum StructureParser {
    private struct PairingClassKey: Hashable {
        let recordIndex: Int
        let opener: Character
    }

    /// Keep short bulges/internal loops within one visual and editing stem.
    /// The value is the combined number of skipped columns across both arms.
    private static let maximumStemBulgeColumns = 2
    private static let explicitBrackets: [Character: Character] = ["<": ">", "(": ")", "[": "]", "{": "}"]
    private static let openToClose: [Character: Character] = {
        var result = explicitBrackets
        for scalar in UnicodeScalar("A").value...UnicodeScalar("Z").value {
            if let upper = UnicodeScalar(scalar), let lower = UnicodeScalar(scalar + 32) {
                result[Character(String(upper))] = Character(String(lower))
            }
        }
        return result
    }()
    private static let closeToOpen = Dictionary(uniqueKeysWithValues: openToClose.map { ($0.value, $0.key) })

    static func pairs(in file: StockholmFile) -> [BasePair] {
        var result: [BasePair] = []
        var nextStem = 0
        for row in file.structureRows {
            guard case .columnAnnotation(let tag) = row.kind else { continue }
            let structure = file.records[row.recordIndex].aligned
            var stacks: [Character: [Int]] = [:]
            var rowPairs: [BasePair] = []
            for (column, character) in structure.enumerated() {
                if openToClose[character] != nil {
                    stacks[character, default: []].append(column)
                } else if let opener = closeToOpen[character], let left = stacks[opener]?.popLast() {
                    rowPairs.append(BasePair(
                        left: left,
                        right: column,
                        recordIndex: row.recordIndex,
                        structureTag: tag,
                        open: opener,
                        close: character,
                        stem: -1,
                        element: -1
                    ))
                }
            }
            rowPairs.sort { $0.left == $1.left ? $0.right > $1.right : $0.left < $1.left }
            var priorByBracket: [Character: BasePair] = [:]
            for var pair in rowPairs {
                if let prior = priorByBracket[pair.open], continuesStem(prior, with: pair) {
                    pair.stem = prior.stem
                } else {
                    pair.stem = nextStem
                    nextStem += 1
                }
                priorByBracket[pair.open] = pair
                result.append(pair)
            }
        }
        return assigningMajorElements(to: result)
    }

    /// Immediately nested pairs stay in one stem even when a small insertion
    /// creates a one- or two-column bulge on one or both arms. A large internal
    /// loop, branch, disjoint helix, different WUSS class, or different
    /// SS_cons row starts a new stem.
    private static func continuesStem(_ outer: BasePair, with inner: BasePair) -> Bool {
        let leftStep = inner.left - outer.left
        let rightStep = outer.right - inner.right
        guard outer.recordIndex == inner.recordIndex,
              outer.open == inner.open,
              leftStep >= 1,
              rightStep >= 1 else { return false }
        return (leftStep - 1) + (rightStep - 1) <= maximumStemBulgeColumns
    }

    /// A major element follows a continuous helix through arbitrarily large
    /// bulges and internal loops. A chain of nested pairs remains one element
    /// while every pair has at most one direct child. Separate roots and each
    /// arm leaving a true branch junction begin new elements. WUSS opener
    /// classes and SS_cons rows are independent, so pseudoknot classes retain
    /// distinct, faithful identities instead of being merged merely because
    /// their spans cross.
    private static func assigningMajorElements(to pairs: [BasePair]) -> [BasePair] {
        let grouped = Dictionary(grouping: pairs) {
            PairingClassKey(recordIndex: $0.recordIndex, opener: $0.open)
        }
        let orderedGroups = grouped.values.sorted { lhs, rhs in
            guard let firstLHS = lhs.min(by: pairOrder),
                  let firstRHS = rhs.min(by: pairOrder) else { return lhs.count < rhs.count }
            if firstLHS.recordIndex != firstRHS.recordIndex {
                return firstLHS.recordIndex < firstRHS.recordIndex
            }
            if firstLHS.left != firstRHS.left { return firstLHS.left < firstRHS.left }
            if firstLHS.right != firstRHS.right { return firstLHS.right > firstRHS.right }
            return String(firstLHS.open) < String(firstRHS.open)
        }

        var elementByPairID: [String: Int] = [:]
        var nextElement = 0
        for group in orderedGroups {
            let ordered = group.sorted(by: pairOrder)
            var children = Array(repeating: [Int](), count: ordered.count)
            var roots: [Int] = []
            var containmentStack: [Int] = []

            for index in ordered.indices {
                let pair = ordered[index]
                while let candidate = containmentStack.last {
                    let outer = ordered[candidate]
                    if outer.left < pair.left && pair.right < outer.right { break }
                    containmentStack.removeLast()
                }
                if let parent = containmentStack.last {
                    children[parent].append(index)
                } else {
                    roots.append(index)
                }
                containmentStack.append(index)
            }

            for root in roots {
                let rootElement = nextElement
                nextElement += 1
                var pending: [(pairIndex: Int, element: Int)] = [(root, rootElement)]
                while let current = pending.popLast() {
                    elementByPairID[ordered[current.pairIndex].id] = current.element
                    let directChildren = children[current.pairIndex]
                    if directChildren.count == 1, let child = directChildren.first {
                        pending.append((child, current.element))
                    } else if !directChildren.isEmpty {
                        let childAssignments = directChildren.map { child -> (pairIndex: Int, element: Int) in
                            defer { nextElement += 1 }
                            return (child, nextElement)
                        }
                        pending.append(contentsOf: childAssignments.reversed())
                    }
                }
            }
        }

        return pairs.map { pair in
            var result = pair
            result.element = elementByPairID[pair.id] ?? pair.stem
            return result
        }
    }

    private static func pairOrder(_ lhs: BasePair, _ rhs: BasePair) -> Bool {
        lhs.left == rhs.left ? lhs.right > rhs.right : lhs.left < rhs.left
    }

    static func pair(at column: Int, in file: StockholmFile) -> BasePair? {
        pairs(in: file).first { $0.left == column || $0.right == column }
    }

    /// Expands a single selected base (or an explicitly selected complete arm)
    /// to its full structural stem arm. A linked paired arm moves in the
    /// opposite direction so corresponding base pairs remain in register.
    static func stemArmShiftPlan(
        selectedColumns: Set<Int>,
        cursorColumn: Int,
        direction: Int,
        linkPairedArm: Bool,
        in file: StockholmFile
    ) -> StemArmShiftPlan? {
        guard direction == -1 || direction == 1 else { return nil }
        let allPairs = pairs(in: file)
        guard let cursorPair = allPairs.first(where: { $0.left == cursorColumn || $0.right == cursorColumn }) else { return nil }
        let stemPairs = allPairs.filter { $0.stem == cursorPair.stem }
        let cursorIsOnLeftArm = cursorPair.left == cursorColumn
        let primaryColumns = Set(stemPairs.map { cursorIsOnLeftArm ? $0.left : $0.right })
        let singleCursorSelection = selectedColumns == Set([cursorColumn])
        guard singleCursorSelection || selectedColumns == primaryColumns else { return nil }
        let counterpartColumns = Set(stemPairs.map { cursorIsOnLeftArm ? $0.right : $0.left })
        return StemArmShiftPlan(
            stem: cursorPair.stem,
            primaryColumns: primaryColumns,
            counterpartColumns: counterpartColumns,
            direction: direction,
            linkPairedArm: linkPairedArm
        )
    }

    static func validationIssues(in file: StockholmFile) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for row in file.structureRows {
            let structure = file.records[row.recordIndex].aligned
            var stacks: [Character: [Int]] = [:]
            for (column, character) in structure.enumerated() {
                if openToClose[character] != nil {
                    stacks[character, default: []].append(column)
                } else if let opener = closeToOpen[character] {
                    if stacks[opener]?.popLast() == nil {
                        issues.append(.init(severity: .error, message: "\(row.label) has unmatched '\(character)' at column \(column + 1)."))
                    }
                }
            }
            for (opener, columns) in stacks where !columns.isEmpty {
                issues.append(.init(severity: .error, message: "\(row.label) has \(columns.count) unmatched '\(opener)' symbol(s)."))
            }
        }
        return issues
    }
}

enum CovariationClass: Int, Comparable, Sendable {
    case none = 0
    case conserved = 1
    case consistent = 2
    case compensatory = 3
    case gap = 4
    case noncanonical = 5

    static func < (lhs: CovariationClass, rhs: CovariationClass) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum BasePairRules {
    private static let canonical: Set<String> = ["AU", "UA", "GC", "CG", "GU", "UG"]

    static func isCanonical(_ left: Character, _ right: Character) -> Bool {
        func normalized(_ residue: Character) -> Character {
            let upper = Character(String(residue).uppercased())
            return upper == "T" ? "U" : upper
        }
        return canonical.contains(String([normalized(left), normalized(right)]))
    }
}

enum CovariationAnalyzer {
    static func classifications(in file: StockholmFile) -> [Int: [Int: CovariationClass]] {
        classifications(in: file, pairs: StructureParser.pairs(in: file))
    }

    static func classifications(in file: StockholmFile, pairs: [BasePair]) -> [Int: [Int: CovariationClass]] {
        let sequences: [(recordIndex: Int, characters: [Character])] = file.sequenceRows.map { row in
            let characters = file.records[row.recordIndex].aligned.uppercased().map { $0 == "T" ? "U" : $0 }
            return (row.recordIndex, characters)
        }
        var result: [Int: [Int: CovariationClass]] = [:]
        for pair in pairs {
            let observations: [(recordIndex: Int, bases: String?)] = sequences.map { sequence in
                guard sequence.characters.indices.contains(pair.left), sequence.characters.indices.contains(pair.right) else {
                    return (sequence.recordIndex, nil)
                }
                let left = sequence.characters[pair.left]
                let right = sequence.characters[pair.right]
                guard
                      !StockholmFile.isGap(left), !StockholmFile.isGap(right) else {
                    return (sequence.recordIndex, nil)
                }
                return (sequence.recordIndex, String([left, right]))
            }
            let canonicalCounts = Dictionary(grouping: observations.compactMap(\.bases).filter {
                guard let left = $0.first, let right = $0.last else { return false }
                return BasePairRules.isCanonical(left, right)
            }, by: { $0 }).mapValues(\.count)
            let reference = canonicalCounts.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key

            for observation in observations {
                let classification: CovariationClass
                guard let bases = observation.bases else {
                    classification = .gap
                    result[observation.recordIndex, default: [:]][pair.left] = classification
                    result[observation.recordIndex, default: [:]][pair.right] = classification
                    continue
                }
                guard let left = bases.first, let right = bases.last, BasePairRules.isCanonical(left, right) else {
                    classification = .noncanonical
                    result[observation.recordIndex, default: [:]][pair.left] = classification
                    result[observation.recordIndex, default: [:]][pair.right] = classification
                    continue
                }
                guard let reference, let observedLeft = bases.first, let observedRight = bases.last,
                      let referenceLeft = reference.first, let referenceRight = reference.last else {
                    classification = .conserved
                    result[observation.recordIndex, default: [:]][pair.left] = classification
                    result[observation.recordIndex, default: [:]][pair.right] = classification
                    continue
                }
                let leftChanged = observedLeft != referenceLeft
                let rightChanged = observedRight != referenceRight
                classification = leftChanged && rightChanged ? .compensatory : ((leftChanged || rightChanged) ? .consistent : .conserved)
                for column in [pair.left, pair.right] {
                    let prior = result[observation.recordIndex, default: [:]][column] ?? .none
                    result[observation.recordIndex, default: [:]][column] = max(prior, classification)
                }
            }
        }
        return result
    }
}

private extension String {
    func character(at offset: Int) -> Character? {
        guard offset >= 0, let index = index(startIndex, offsetBy: offset, limitedBy: endIndex), index < endIndex else { return nil }
        return self[index]
    }
}
