import AppKit
import PDFKit
import SwiftUI

@MainActor
final class RScapeController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case succeeded
        case failed
        case cancelled
    }

    @Published var phase: Phase = .idle
    @Published var isPanelVisible = false
    @Published var result: RScapeResult?
    @Published var message = "Run R-scape to evaluate the current SS_cons structure."

    private var processHandle: RScapeProcessHandle?
    private var runTask: Task<Void, Never>?

    var isRunning: Bool { phase == .running }
    var hasPresentableState: Bool { result != nil || phase == .running || phase == .failed || phase == .cancelled }

    func presentMissingExecutable() {
        phase = .failed
        message = RScapeRunError.executableUnavailable.localizedDescription
        isPanelVisible = true
    }

    func presentError(_ error: Error) {
        phase = .failed
        message = error.localizedDescription
        isPanelVisible = true
    }

    func run(
        executableURL: URL,
        stockholmText: String,
        outputDirectory: URL,
        outputName: String
    ) {
        runTask?.cancel()
        let handle = RScapeProcessHandle()
        processHandle = handle
        result = nil
        phase = .running
        message = "R-scape is evaluating the given structure…"
        isPanelVisible = true

        runTask = Task {
            do {
                let completed = try await RScapeRunner.run(
                    executableURL: executableURL,
                    stockholmText: stockholmText,
                    outputDirectory: outputDirectory,
                    outputName: outputName,
                    processHandle: handle
                )
                guard !Task.isCancelled else { return }
                result = completed
                phase = .succeeded
                let summary = completed.summary
                if let total = summary.annotatedBasePairs {
                    message = "R-scape found \(summary.significantAnnotatedPairs) significant annotated pair\(summary.significantAnnotatedPairs == 1 ? "" : "s") among \(total) proposed pairs."
                } else {
                    message = "R-scape found \(summary.significantPairs) significant pair\(summary.significantPairs == 1 ? "" : "s")."
                }
            } catch RScapeRunError.cancelled {
                phase = .cancelled
                message = RScapeRunError.cancelled.localizedDescription
            } catch {
                phase = .failed
                message = error.localizedDescription
            }
            processHandle = nil
        }
    }

    func cancel() {
        processHandle?.cancel()
        message = "Cancelling R-scape…"
    }
}

struct RScapeResultsPanel: View {
    @ObservedObject var controller: RScapeController
    let locateExecutable: () -> Void
    let runAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            switch controller.phase {
            case .running:
                runningView
            case .succeeded:
                if let result = controller.result {
                    resultView(result)
                } else {
                    messageView(icon: "exclamationmark.triangle", title: "R-scape result unavailable")
                }
            case .failed, .cancelled:
                errorView
            case .idle:
                messageView(icon: "waveform.path.ecg", title: "R-scape is ready")
            }
        }
        .frame(minWidth: 330, idealWidth: 420, maxWidth: 560)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("R-scape", systemImage: "waveform.path.ecg")
                .font(.headline)
            if let version = controller.result?.summary.version {
                Text("v\(version)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.isPanelVisible = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close the R-scape panel. A running analysis continues in the background.")
        }
        .padding(12)
    }

    private var runningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Evaluating the given structure").font(.headline)
            Text("MATER is running R-scape’s two-set `-s` test on a snapshot of the current alignment. The editor remains usable.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 330)
            Button("Cancel", action: controller.cancel)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: controller.phase == .cancelled ? "stop.circle" : "exclamationmark.triangle")
                .font(.system(size: 38))
                .foregroundStyle(controller.phase == .cancelled ? Color.secondary : Color.orange)
            Text(controller.phase == .cancelled ? "Analysis cancelled" : "R-scape could not run")
                .font(.headline)
            Text(controller.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 350)
            HStack {
                Button("Locate R-scape…", action: locateExecutable)
                Button("Try Again", action: runAgain)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultView(_ result: RScapeResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryView(result.summary)
                .padding(12)
            Divider()
            RScapePDFPreview(url: result.r2rPDFURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let warning = result.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Open Full Size") { NSWorkspace.shared.open(result.r2rPDFURL) }
                    Button("Pair Table") { openInTextEdit(result.covarianceTableURL) }
                    if let powerURL = result.powerTableURL {
                        Button("Power Table") { openInTextEdit(powerURL) }
                    }
                    Button("Reveal Files") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.outputDirectory])
                    }
                }
                HStack {
                    Button("Run Again", action: runAgain)
                    Spacer()
                    Text("Statistical given-structure test (`-s`); separate from CaCoFold-refine")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(10)
        }
    }

    private func summaryView(_ summary: RScapeSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(controller.message).font(.subheadline.bold())
            HStack(spacing: 12) {
                Text("\(summary.significantPairs) significant total")
                if let expected = summary.expectedCovaryingPairs {
                    Text(String(format: "%.1f expected", expected))
                }
                if let observed = summary.observedCovaryingPairs {
                    Text("\(observed) observed")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            Text("A lack of significant pairs is inconclusive when the alignment has low covariation-detection power; consult the saved .power table.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func messageView(icon: String, title: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(controller.message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Run R-scape", action: runAgain)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openInTextEdit(_ url: URL) {
        let workspace = NSWorkspace.shared
        guard let textEditURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
            workspace.open(url)
            return
        }
        workspace.open(
            [url],
            withApplicationAt: textEditURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct RScapePDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.minScaleFactor = 0.10
        view.maxScaleFactor = 10.0
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .white
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document?.documentURL != url else { return }
        view.document = PDFDocument(url: url)
        view.autoScales = true
    }
}
