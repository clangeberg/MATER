import Foundation

struct RScapeSummary: Equatable, Sendable {
    let version: String?
    let significantPairs: Int
    let significantAnnotatedPairs: Int
    let annotatedBasePairs: Int?
    let expectedCovaryingPairs: Double?
    let observedCovaryingPairs: Int?
}

struct RScapeResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let outputDirectory: URL
    let covarianceTableURL: URL
    let powerTableURL: URL?
    let r2rPDFURL: URL
    let r2rSVGURL: URL?
    let inputSnapshotURL: URL?
    let logURL: URL
    let summary: RScapeSummary
    let warning: String?
}

enum RScapeRunError: LocalizedError, Equatable {
    case executableUnavailable
    case invalidExecutable(String)
    case couldNotLaunch(String)
    case cancelled
    case analysisFailed(status: Int32, details: String)
    case missingCovarianceTable
    case missingR2RDrawing

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "R-scape was not found in MATER's app environment. Finder-launched apps do not inherit the same PATH as Terminal. Use Locate R-scape to select its executable, bin folder, or installation folder."
        case .invalidExecutable(let path):
            return "The selected file is not an executable R-scape program: \(path)"
        case .couldNotLaunch(let details):
            return "MATER could not launch R-scape. \(details)"
        case .cancelled:
            return "The R-scape analysis was cancelled."
        case .analysisFailed(let status, let details):
            return "R-scape exited with status \(status). \(details)"
        case .missingCovarianceTable:
            return "R-scape did not produce its pairwise .cov significance table."
        case .missingR2RDrawing:
            return "The statistical test completed, but R-scape did not produce an R2R PDF drawing. Check that the R2R and Perl components of the R-scape installation are available."
        }
    }
}

enum RScapeExecutableLocator {
    static let savedPathKey = "MATER.RScapeExecutablePath"

    static func locate(
        savedPath: String? = UserDefaults.standard.string(forKey: savedPathKey),
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> URL? {
        var candidates: [URL] = []
        if let savedPath {
            candidates.append(URL(fileURLWithPath: savedPath))
        }
        let pathDirectories = (pathEnvironment ?? "").split(separator: ":").map(String.init)
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ]
        for directory in pathDirectories + commonDirectories where !directory.isEmpty {
            for name in ["R-scape", "r-scape"] {
                candidates.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name))
            }
        }

        var resolved: [URL] = []
        var seenPaths: Set<String> = []
        for candidate in candidates {
            guard let executable = resolveSelection(candidate), seenPaths.insert(executable.path).inserted else { continue }
            resolved.append(executable)
        }
        // Prefer an installed bin copy with the R2R companion needed for the
        // requested PDF, even if an older saved path points at src/R-scape.
        return resolved.first(where: hasSiblingR2R) ?? resolved.first
    }

    static func resolveSelection(_ selection: URL) -> URL? {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: selection.path, isDirectory: &isDirectory)
        var candidates: [URL] = []

        if exists, isDirectory.boolValue {
            let directory = selection.standardizedFileURL
            if directory.lastPathComponent.caseInsensitiveCompare("bin") == .orderedSame {
                candidates.append(directory.appendingPathComponent("R-scape"))
                candidates.append(directory.appendingPathComponent("r-scape"))
            } else if directory.lastPathComponent.caseInsensitiveCompare("src") == .orderedSame {
                candidates.append(directory.deletingLastPathComponent().appendingPathComponent("bin/R-scape"))
                candidates.append(directory.deletingLastPathComponent().appendingPathComponent("bin/r-scape"))
            }
            candidates.append(directory.appendingPathComponent("bin/R-scape"))
            candidates.append(directory.appendingPathComponent("bin/r-scape"))
            candidates.append(directory.appendingPathComponent("R-scape"))
            candidates.append(directory.appendingPathComponent("r-scape"))
            candidates.append(directory.appendingPathComponent("src/R-scape"))
        } else {
            let file = selection.standardizedFileURL
            let parent = file.deletingLastPathComponent()
            if parent.lastPathComponent.caseInsensitiveCompare("src") == .orderedSame {
                candidates.append(parent.deletingLastPathComponent().appendingPathComponent("bin/R-scape"))
                candidates.append(parent.deletingLastPathComponent().appendingPathComponent("bin/r-scape"))
            }
            candidates.append(file)
        }

        let usable = candidates.compactMap { candidate -> URL? in
            guard ["r-scape"].contains(candidate.lastPathComponent.lowercased()),
                  isUsableExecutable(candidate) else { return nil }
            return candidate.resolvingSymlinksInPath()
        }
        return usable.first(where: hasSiblingR2R) ?? usable.first
    }

    static func isUsableExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    private static func hasSiblingR2R(_ executableURL: URL) -> Bool {
        let directory = executableURL.deletingLastPathComponent()
        return ["R2R", "r2r"].contains { name in
            isUsableExecutable(directory.appendingPathComponent(name))
        }
    }
}

final class RScapeProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel, process.isRunning { process.terminate() }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = self.process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }
}

enum RScapeOutputParser {
    static func summary(covarianceText: String, powerText: String?, processText: String) -> RScapeSummary {
        // A .cov table can contain un-commented column separators in some
        // releases, so recognize data rows by their two integer positions
        // rather than counting every non-comment line.
        let significantRows = covarianceText.split(whereSeparator: \.isNewline).compactMap { rawLine -> Bool? in
            let fields = rawLine.split(whereSeparator: \.isWhitespace)
            guard !fields.isEmpty else { return nil }
            let isAnnotated = fields.first == "*"
            let positionOffset = isAnnotated ? 1 : 0
            guard fields.count > positionOffset + 1,
                  Int(fields[positionOffset]) != nil,
                  Int(fields[positionOffset + 1]) != nil else { return nil }
            return isAnnotated
        }
        let annotatedSignificant = significantRows.filter { $0 }.count

        var annotatedBasePairs: Int?
        var expectedCovaryingPairs: Double?
        var observedCovaryingPairs: Int?
        if let powerText {
            for rawLine in powerText.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("# BPAIRS expected to covary") {
                    expectedCovaryingPairs = firstDouble(after: "# BPAIRS expected to covary", in: line)
                } else if line.hasPrefix("# BPAIRS observed to covary") {
                    observedCovaryingPairs = firstInt(after: "# BPAIRS observed to covary", in: line)
                } else if line.hasPrefix("# BPAIRS ") {
                    annotatedBasePairs = firstInt(after: "# BPAIRS", in: line)
                }
            }
        }

        let version = processText.split(whereSeparator: \.isNewline).compactMap { rawLine -> String? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("# R-scape ") else { return nil }
            guard let candidate = line.dropFirst("# R-scape ".count).split(separator: " ").first,
                  candidate.first?.isNumber == true else { return nil }
            return String(candidate)
        }.first

        return RScapeSummary(
            version: version,
            significantPairs: significantRows.count,
            significantAnnotatedPairs: annotatedSignificant,
            annotatedBasePairs: annotatedBasePairs,
            expectedCovaryingPairs: expectedCovaryingPairs,
            observedCovaryingPairs: observedCovaryingPairs
        )
    }

    private static func firstDouble(after prefix: String, in line: String) -> Double? {
        guard let range = line.range(of: prefix) else { return nil }
        return line[range.upperBound...].split(whereSeparator: \.isWhitespace).compactMap { Double($0) }.first
    }

    private static func firstInt(after prefix: String, in line: String) -> Int? {
        guard let range = line.range(of: prefix) else { return nil }
        return line[range.upperBound...].split(whereSeparator: \.isWhitespace).compactMap { Int($0) }.first
    }
}

enum RScapeRunner {
    private struct ProcessOutput {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(
        executableURL: URL,
        stockholmText: String,
        outputDirectory: URL,
        outputName: String,
        processHandle: RScapeProcessHandle
    ) async throws -> RScapeResult {
        guard let resolvedExecutable = RScapeExecutableLocator.resolveSelection(executableURL) else {
            throw RScapeRunError.invalidExecutable(executableURL.path)
        }

        return try await Task.detached(priority: .userInitiated) {
            try runSynchronously(
                executableURL: resolvedExecutable,
                stockholmText: stockholmText,
                outputDirectory: outputDirectory,
                outputName: outputName,
                processHandle: processHandle
            )
        }.value
    }

    private static func runSynchronously(
        executableURL: URL,
        stockholmText: String,
        outputDirectory: URL,
        outputName: String,
        processHandle: RScapeProcessHandle
    ) throws -> RScapeResult {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MATER-RScape-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let safeName = sanitizedOutputName(outputName)
        let inputURL = temporaryDirectory.appendingPathComponent("\(safeName)-input.sto")
        try stockholmText.write(to: inputURL, atomically: true, encoding: .utf8)
        let retainedInputURL = outputDirectory.appendingPathComponent("\(safeName)-input.sto")
        try stockholmText.write(to: retainedInputURL, atomically: true, encoding: .utf8)

        let arguments = [
            "-s",
            "--onemsa",
            "--outdir", temporaryDirectory.path,
            "--outname", safeName,
            inputURL.path
        ]
        let processOutput = try launch(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectoryURL: temporaryDirectory,
            processHandle: processHandle
        )
        let combinedOutput = processOutput.stdout + (processOutput.stderr.isEmpty ? "" : "\n--- stderr ---\n\(processOutput.stderr)")
        let logURL = outputDirectory.appendingPathComponent("\(safeName).log")
        let commandDescription = ([executableURL.path] + arguments).map(shellQuoted).joined(separator: " ")
        try ("Command: \(commandDescription)\n\n" + combinedOutput)
            .write(to: logURL, atomically: true, encoding: .utf8)

        let artifactNames = [
            "\(safeName).cov",
            "\(safeName).sorted.cov",
            "\(safeName).power",
            "\(safeName).original.sto",
            "\(safeName).R2R.sto.pdf",
            "\(safeName).R2R.sto.svg"
        ]
        for name in artifactNames {
            let source = temporaryDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = outputDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.copyItem(at: source, to: destination)
        }

        if processHandle.wasCancelled { throw RScapeRunError.cancelled }
        let covarianceURL = outputDirectory.appendingPathComponent("\(safeName).cov")
        guard fileManager.fileExists(atPath: covarianceURL.path) else {
            if processOutput.status != 0 {
                throw RScapeRunError.analysisFailed(
                    status: processOutput.status,
                    details: failureDetails(
                        processOutput: processOutput,
                        logURL: logURL
                    )
                )
            }
            throw RScapeRunError.missingCovarianceTable
        }
        let pdfURL = outputDirectory.appendingPathComponent("\(safeName).R2R.sto.pdf")
        guard fileManager.fileExists(atPath: pdfURL.path) else { throw RScapeRunError.missingR2RDrawing }

        let powerURL = outputDirectory.appendingPathComponent("\(safeName).power")
        let svgURL = outputDirectory.appendingPathComponent("\(safeName).R2R.sto.svg")
        let covarianceText = (try? String(contentsOf: covarianceURL, encoding: .utf8)) ?? ""
        let powerText = fileManager.fileExists(atPath: powerURL.path)
            ? try? String(contentsOf: powerURL, encoding: .utf8)
            : nil
        let summary = RScapeOutputParser.summary(
            covarianceText: covarianceText,
            powerText: powerText,
            processText: combinedOutput
        )
        let warning = processOutput.status == 0 ? warningMessage(from: processOutput.stderr) :
            "R-scape returned status \(processOutput.status), but the requested .cov and R2R PDF outputs were produced and retained. See the run log for details."

        return RScapeResult(
            outputDirectory: outputDirectory,
            covarianceTableURL: covarianceURL,
            powerTableURL: fileManager.fileExists(atPath: powerURL.path) ? powerURL : nil,
            r2rPDFURL: pdfURL,
            r2rSVGURL: fileManager.fileExists(atPath: svgURL.path) ? svgURL : nil,
            inputSnapshotURL: retainedInputURL,
            logURL: logURL,
            summary: summary,
            warning: warning
        )
    }

    private static func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        processHandle: RScapeProcessHandle
    ) throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let dataLock = NSLock()
        var stdoutData = Data()
        var stderrData = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            dataLock.lock()
            stdoutData.append(data)
            dataLock.unlock()
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            dataLock.lock()
            stderrData.append(data)
            dataLock.unlock()
        }

        process.executableURL = executableURL
        process.arguments = arguments
        // R-scape creates its temporary FastTree input and tree in the
        // subprocess's current directory rather than in --outdir. Finder-
        // launched applications can inherit an unwritable current directory
        // (commonly `/`), which R-scape reports only as "Failed to create
        // external tree". Keep every internal temporary file in MATER's
        // private writable run directory.
        process.currentDirectoryURL = workingDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = executableURL.deletingLastPathComponent().path
        environment["PATH"] = executableDirectory + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw RScapeRunError.couldNotLaunch(error.localizedDescription)
        }
        processHandle.attach(process)
        process.waitUntilExit()
        processHandle.detach()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let stdoutRemainder = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrRemainder = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        dataLock.lock()
        stdoutData.append(stdoutRemainder)
        stderrData.append(stderrRemainder)
        let capturedStdout = stdoutData
        let capturedStderr = stderrData
        dataLock.unlock()

        return ProcessOutput(
            status: process.terminationStatus,
            stdout: String(decoding: capturedStdout, as: UTF8.self),
            stderr: String(decoding: capturedStderr, as: UTF8.self)
        )
    }

    private static func sanitizedOutputName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return result.isEmpty ? "MATER-R-scape" : result
    }

    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func conciseDetails(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).suffix(8).map(String.init)
        return lines.joined(separator: " ").prefix(900).description
    }

    private static func failureDetails(processOutput: ProcessOutput, logURL: URL) -> String {
        let combined = processOutput.stdout
            + (processOutput.stderr.isEmpty ? "" : "\n\(processOutput.stderr)")
        let diagnostic = conciseDetails(combined)
        let logMessage = "Full diagnostics were saved to \(logURL.path)."
        return diagnostic.isEmpty ? logMessage : "\(diagnostic) \(logMessage)"
    }

    private static func warningMessage(from stderr: String) -> String? {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.localizedCaseInsensitiveContains("gnuplot not found")
            || trimmed.localizedCaseInsensitiveContains("RFview")
            || trimmed.localizedCaseInsensitiveContains("Abort trap") {
            return "R-scape produced the requested significance table and R2R drawing. Optional RFview or gnuplot output reported a warning; see the run log for details."
        }
        return "R-scape produced the requested outputs with additional diagnostic messages. See the run log for details."
    }
}
