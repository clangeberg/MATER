import Foundation

struct BasePair: Identifiable, Hashable, Sendable {
    let left: Int
    let right: Int
    let recordIndex: Int
    let structureTag: String
    let open: Character
    let close: Character
    var stem: Int

    var id: String { "\(recordIndex):\(left):\(right)" }
    var isPseudoknot: Bool { structureTag != "SS_cons" || open != "<" }
}

enum StructureParser {
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
                    rowPairs.append(BasePair(left: left, right: column, recordIndex: row.recordIndex, structureTag: tag, open: opener, close: character, stem: -1))
                }
            }
            rowPairs.sort { $0.left == $1.left ? $0.right > $1.right : $0.left < $1.left }
            var priorByBracket: [Character: BasePair] = [:]
            var stemByBracket: [Character: Int] = [:]
            for var pair in rowPairs {
                if let prior = priorByBracket[pair.open], prior.left + 1 == pair.left, prior.right - 1 == pair.right {
                    pair.stem = stemByBracket[pair.open] ?? nextStem
                } else {
                    pair.stem = nextStem
                    stemByBracket[pair.open] = nextStem
                    nextStem += 1
                }
                priorByBracket[pair.open] = pair
                stemByBracket[pair.open] = pair.stem
                result.append(pair)
            }
        }
        return result
    }

    static func pair(at column: Int, in file: StockholmFile) -> BasePair? {
        pairs(in: file).first { $0.left == column || $0.right == column }
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
