import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

extension UTType {
    static let stockholmAlignment = UTType(exportedAs: "org.mater.rnaeditor.stockholm-alignment", conformingTo: .plainText)
}

struct StockholmDocumentAnalysis {
    let rows: [AlignmentRow]
    let sequenceCount: Int
    let alignmentLength: Int
    let validationIssues: [ValidationIssue]
    let entropyByColumn: [Double]
    let gapFrequencyByColumn: [Double]
    let structurePairs: [BasePair]
    let structuralProblemFractions: [Double]

    init(file: StockholmFile) {
        rows = file.rows
        sequenceCount = rows.lazy.filter(\.kind.isSequence).count
        alignmentLength = file.alignmentLength
        validationIssues = file.validationIssues
        entropyByColumn = EntropyAnalyzer.columnEntropies(in: file)
        gapFrequencyByColumn = GapAnalyzer.columnGapFrequencies(in: file)
        structurePairs = StructureParser.pairs(in: file)
        structuralProblemFractions = StructuralQualityAnalyzer.problemFractionsByColumn(in: file, pairs: structurePairs)
    }
}

final class StockholmDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = String

    static var readableContentTypes: [UTType] { [.stockholmAlignment, .plainText] }
    static var writableContentTypes: [UTType] { [.stockholmAlignment] }

    @Published private(set) var file: StockholmFile
    @Published var sequenceEditingUnlocked = false
    @Published private(set) var integrityNotice = ""
    private(set) var analysis: StockholmDocumentAnalysis
    private(set) var revision: UInt64 = 0
    private(set) var baselineFile: StockholmFile
    private let recoveryIdentifier: String
    private var stemQualityCache: [Int: StemQuality] = [:]

    init() {
        let parsed = StockholmParser.parse(Self.example)
        file = parsed
        baselineFile = parsed
        analysis = StockholmDocumentAnalysis(file: parsed)
        recoveryIdentifier = Self.recoveryIdentifier(for: parsed.rendered)
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let string = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let string else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let parsed = StockholmParser.parse(string)
        file = parsed
        baselineFile = parsed
        analysis = StockholmDocumentAnalysis(file: parsed)
        recoveryIdentifier = Self.recoveryIdentifier(for: parsed.rendered)
    }

    func snapshot(contentType: UTType) throws -> String {
        let report = integrityReport
        if !sequenceEditingUnlocked, !report.isIntact {
            throw AlignmentIntegrityError(report: report)
        }
        return file.rendered
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    func mutate(
        _ actionName: String,
        undoManager: UndoManager?,
        allowIntegrityRestoration: Bool = false,
        _ mutation: (inout StockholmFile) -> Void
    ) {
        let before = file
        var after = before
        mutation(&after)
        guard after != before else { return }
        let restoresIntegrity = allowIntegrityRestoration
            && SequenceIntegrityAnalyzer.differenceScore(current: after, baseline: baselineFile)
                < SequenceIntegrityAnalyzer.differenceScore(current: before, baseline: baselineFile)
        if !sequenceEditingUnlocked,
           !SequenceIntegrityAnalyzer.preservesSequences(from: before, to: after),
           !restoresIntegrity {
            integrityNotice = "Blocked \(actionName.lowercased()): unlock sequence editing to change ungapped residues."
            return
        }
        RecoveryStore.schedule(before, identifier: recoveryIdentifier)
        apply(after, replacing: before, actionName: actionName, undoManager: undoManager)
    }

    @discardableResult
    func createRecoverySnapshot() -> URL? {
        RecoveryStore.save(file, identifier: recoveryIdentifier)
    }

    @discardableResult
    func restoreLatestRecovery(undoManager: UndoManager?) -> Bool {
        guard let recovery = RecoveryStore.latest(identifier: recoveryIdentifier), recovery != file else { return false }
        if !sequenceEditingUnlocked, !SequenceIntegrityAnalyzer.preservesSequences(from: file, to: recovery) {
            integrityNotice = "Recovery would change ungapped sequence data; unlock sequence editing first."
            return false
        }
        apply(recovery, replacing: file, actionName: "Restore Recovery Snapshot", undoManager: undoManager)
        return true
    }

    var recoverySnapshotCount: Int { RecoveryStore.snapshotCount(identifier: recoveryIdentifier) }

    var integrityReport: SequenceIntegrityReport {
        SequenceIntegrityAnalyzer.report(current: file, baseline: baselineFile)
    }

    func structuralQuality(containing column: Int) -> StemQuality? {
        guard let stem = analysis.structurePairs.first(where: { $0.left == column || $0.right == column })?.stem else { return nil }
        return structuralQuality(stem: stem)
    }

    func structuralQuality(stem: Int) -> StemQuality? {
        if let cached = stemQualityCache[stem] { return cached }
        guard let quality = StructuralQualityAnalyzer.quality(stem: stem, pairs: analysis.structurePairs, in: file) else { return nil }
        stemQualityCache[stem] = quality
        return quality
    }

    var changeSummary: AlignmentChangeSummary {
        AlignmentChangeSummary(current: file, baseline: baselineFile)
    }

    var changedColumnsByRecordIndex: [Int: Set<Int>] {
        let baselineRows = Dictionary(baselineFile.rows.map { ($0.label, $0.recordIndex) }, uniquingKeysWith: { first, _ in first })
        var result: [Int: Set<Int>] = [:]
        for row in file.rows {
            guard let baselineIndex = baselineRows[row.label] else {
                result[row.recordIndex] = Set(0..<file.records[row.recordIndex].aligned.count)
                continue
            }
            let current = Array(file.records[row.recordIndex].aligned)
            let baseline = Array(baselineFile.records[baselineIndex].aligned)
            let length = max(current.count, baseline.count)
            let changed = Set((0..<length).filter { column in
                guard current.indices.contains(column), baseline.indices.contains(column) else { return true }
                return current[column] != baseline[column]
            })
            if !changed.isEmpty { result[row.recordIndex] = changed }
        }
        return result
    }

    @discardableResult
    func restoreBaselineSelection(rows selectedRows: Set<Int>, columns: Set<Int>, undoManager: UndoManager?) -> Int {
        let currentRows = file.rows
        let baselineRows = Dictionary(baselineFile.rows.map { ($0.label, $0.recordIndex) }, uniquingKeysWith: { first, _ in first })
        var restored = 0
        mutate(
            "Revert Selected Region",
            undoManager: undoManager,
            allowIntegrityRestoration: true
        ) { replacement in
            for modelRow in selectedRows where currentRows.indices.contains(modelRow) {
                let currentRow = currentRows[modelRow]
                guard let baselineIndex = baselineRows[currentRow.label] else { continue }
                let baselineCharacters = Array(baselineFile.records[baselineIndex].aligned)
                for column in columns where baselineCharacters.indices.contains(column) && column < replacement.alignmentLength {
                    replacement.replaceCharacter(row: modelRow, column: column, with: baselineCharacters[column])
                    restored += 1
                }
            }
        }
        return restored
    }

    @discardableResult
    func restoreBaselineRows(_ selectedRows: Set<Int>, undoManager: UndoManager?) -> Int {
        let currentRows = file.rows
        let baselineRows = Dictionary(baselineFile.rows.map { ($0.label, $0.recordIndex) }, uniquingKeysWith: { first, _ in first })
        let currentLength = file.alignmentLength
        var restored = 0
        mutate(
            "Revert Selected Rows",
            undoManager: undoManager,
            allowIntegrityRestoration: true
        ) { replacement in
            for modelRow in selectedRows where currentRows.indices.contains(modelRow) {
                let currentRow = currentRows[modelRow]
                guard let baselineIndex = baselineRows[currentRow.label] else { continue }
                let baselineAligned = baselineFile.records[baselineIndex].aligned
                guard baselineAligned.count == currentLength else { continue }
                replacement.records[currentRow.recordIndex].aligned = baselineAligned
                restored += 1
            }
        }
        return restored
    }

    private func apply(_ replacement: StockholmFile, replacing previous: StockholmFile, actionName: String, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { document in
            document.apply(previous, replacing: replacement, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
        analysis = StockholmDocumentAnalysis(file: replacement)
        stemQualityCache = [:]
        revision &+= 1
        file = replacement
    }

    private static func recoveryIdentifier(for text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static let example = """
    # STOCKHOLM 1.0
    #=GF ID New_alignment
    sequence_1    GCGAAACGCUUC
    sequence_2    GUGAAACGCAAC
    sequence_3    ACGAAACGUUCG
    #=GC SS_cons  <<......>>..
    //
    """
}

struct AlignmentIntegrityError: LocalizedError {
    let report: SequenceIntegrityReport

    var errorDescription: String? { "MATER blocked saving because sequence integrity is locked." }
    var recoverySuggestion: String? {
        let details = report.violations.prefix(5).map(\.message).joined(separator: " ")
        return "Revert the sequence changes, or explicitly unlock sequence editing before saving. \(details)"
    }
}

struct AlignmentChangeSummary {
    let changedCells: Int
    let changedRows: Int
    let changedSequenceCells: Int
    let changedAnnotationCells: Int

    init(current: StockholmFile, baseline: StockholmFile) {
        let baselineRows = Dictionary(baseline.rows.map { ($0.label, $0.recordIndex) }, uniquingKeysWith: { first, _ in first })
        var cells = 0
        var rows = 0
        var sequenceCells = 0
        var annotationCells = 0
        for row in current.rows {
            let currentCharacters = Array(current.records[row.recordIndex].aligned)
            let baselineCharacters = baselineRows[row.label].map { Array(baseline.records[$0].aligned) } ?? []
            let length = max(currentCharacters.count, baselineCharacters.count)
            let rowChanges = (0..<length).reduce(into: 0) { count, column in
                if !currentCharacters.indices.contains(column)
                    || !baselineCharacters.indices.contains(column)
                    || currentCharacters[column] != baselineCharacters[column] {
                    count += 1
                }
            }
            guard rowChanges > 0 else { continue }
            rows += 1
            cells += rowChanges
            if row.kind.isSequence { sequenceCells += rowChanges } else { annotationCells += rowChanges }
        }
        changedCells = cells
        changedRows = rows
        changedSequenceCells = sequenceCells
        changedAnnotationCells = annotationCells
    }
}

private enum RecoveryStore {
    private static let ioQueue = DispatchQueue(label: "org.mater.rnaeditor.recovery", qos: .utility)
    private static var pending: [String: DispatchWorkItem] = [:]

    static func schedule(_ file: StockholmFile, identifier: String) {
        pending[identifier]?.cancel()
        let work = DispatchWorkItem {
            ioQueue.async { _ = save(file, identifier: identifier) }
        }
        pending[identifier] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    static func save(_ file: StockholmFile, identifier: String) -> URL? {
        do {
            let directory = try directoryURL(identifier: identifier)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("\(timestamp)-\(UUID().uuidString.prefix(8)).sto")
            try Data(file.rendered.utf8).write(to: url, options: .atomic)
            let snapshots = snapshotURLs(in: directory)
            for obsolete in snapshots.dropFirst(30) { try? FileManager.default.removeItem(at: obsolete) }
            return url
        } catch {
            return nil
        }
    }

    static func latest(identifier: String) -> StockholmFile? {
        guard let directory = try? directoryURL(identifier: identifier), let url = snapshotURLs(in: directory).first,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return StockholmParser.parse(text)
    }

    static func snapshotCount(identifier: String) -> Int {
        guard let directory = try? directoryURL(identifier: identifier) else { return 0 }
        return snapshotURLs(in: directory).count
    }

    private static func directoryURL(identifier: String) throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MATER_RECOVERY_DIRECTORY"], !override.isEmpty {
            let directory = URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(identifier, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("MATER", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func snapshotURLs(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "sto" }.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
    }
}
