import Foundation

enum MATERDiagnostics {
    static func report(document: StockholmDocument, sourceURL: URL?) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "15"
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        let architecture: String
#if arch(arm64)
        architecture = "Apple silicon (arm64)"
#elseif arch(x86_64)
        architecture = "Intel (x86_64)"
#else
        architecture = "unknown"
#endif

        let errors = document.analysis.validationIssues.filter { $0.severity == .error }
        let warnings = document.analysis.validationIssues.filter { $0.severity == .warning }
        let rScape = RScapeExecutableLocator.locate()?.path ?? "not found"
        let sourceName = sourceURL?.lastPathComponent ?? "untitled"
        let structureLayers = document.file.structureRows.count
        let pseudoknotPairs = document.analysis.structurePairs.filter { $0.isPseudoknot }.count
        let issueLines = document.analysis.validationIssues.isEmpty
            ? ["- none"]
            : document.analysis.validationIssues.prefix(20).map { "- [\($0.severity.rawValue)] \($0.message)" }

        return ([
            "MATER diagnostics",
            "Version: \(version) (build \(build))",
            "macOS: \(operatingSystem)",
            "Architecture: \(architecture)",
            "Document: \(sourceName)",
            "Alignment: \(document.analysis.sequenceCount) sequences × \(document.analysis.alignmentLength) columns",
            "Parsed display rows: \(document.analysis.rows.count)",
            "Structure: \(structureLayers) layer(s), \(document.analysis.structurePairs.count) pair(s), \(pseudoknotPairs) pseudoknot-layer pair(s)",
            "Validation: \(errors.count) error(s), \(warnings.count) warning(s)",
            "Integrity: \(document.integrityReport.summary)",
            "Sequence editing unlocked: \(document.sequenceEditingUnlocked ? "yes" : "no")",
            "Invalid-save override: \(document.invalidSavingUnlocked ? "enabled" : "disabled")",
            "R-scape executable: \(rScape)",
            "Validation details:"
        ] + issueLines + [
            "",
            "Privacy: this report contains no alignment sequences or annotation-row contents. Review the executable path and document filename before sharing if they are sensitive."
        ]).joined(separator: "\n")
    }
}
