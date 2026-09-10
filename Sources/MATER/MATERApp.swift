import AppKit
import SwiftUI

@main
struct MATERApp: App {
    @StateObject private var residuePalette: ResiduePaletteSettings

    init() {
        PreferencesMigration.migrateLegacyDefaultsIfNeeded()
        _residuePalette = StateObject(wrappedValue: ResiduePaletteSettings())
        StockholmDocument.cleanupRecoveryData(olderThanDays: 30)
    }

    var body: some Scene {
        DocumentGroup(newDocument: { StockholmDocument() }) { configuration in
            DocumentEditorView(document: configuration.document, sourceURL: configuration.fileURL)
                .environmentObject(residuePalette)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MATER") { MATERApplicationActions.showAboutPanel() }
            }
            CommandGroup(after: .textEditing) {
                Divider()
                Text("MATER: Shift–arrows selects a rectangle; Option–Left/Right shifts it or a complete stem arm; Link stem arms moves the paired arm in register; Control–G opens a gap.")
            }
            CommandGroup(replacing: .help) {
                Button("MATER User Guide") { MATERApplicationActions.openUserGuide() }
                    .keyboardShortcut("?", modifiers: [.command])
            }
        }

        Settings {
            MATERSettingsView()
                .environmentObject(residuePalette)
        }
    }
}

private enum MATERApplicationActions {
    static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Manual Alignment Tool for Evolutionary RNA\nA structure-aware Stockholm editor with pseudoknot support.",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "MATER",
            .applicationVersion: "1.0.0",
            .version: "Build 16",
            .credits: credits
        ])
    }

    static func openUserGuide() {
        if let bundled = Bundle.main.url(forResource: "MATER-User-Guide", withExtension: "md") {
            NSWorkspace.shared.open(bundled)
            return
        }
        if let online = URL(string: "https://github.com/clangeberg/MATER/blob/v1.0.0/docs/MATER-User-Guide.md") {
            NSWorkspace.shared.open(online)
        }
    }
}

private struct MATERSettingsView: View {
    @EnvironmentObject private var residuePalette: ResiduePaletteSettings
    @State private var rScapePath = UserDefaults.standard.string(forKey: RScapeExecutableLocator.savedPathKey) ?? "Not configured"
    @State private var showingClearConfirmation = false
    @State private var recoveryMessage = "Snapshots older than 30 days are removed automatically."

    var body: some View {
        Form {
            Section("Residue colors") {
                ColorPicker("Adenine (A)", selection: residuePalette.binding(for: "A"), supportsOpacity: false)
                ColorPicker("Cytosine (C)", selection: residuePalette.binding(for: "C"), supportsOpacity: false)
                ColorPicker("Guanine (G)", selection: residuePalette.binding(for: "G"), supportsOpacity: false)
                ColorPicker("Uracil / thymine (U/T)", selection: residuePalette.binding(for: "U"), supportsOpacity: false)
                Button("Reset residue colors", action: residuePalette.reset)
            }

            Section("R-scape") {
                Text(rScapePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack {
                    Button("Locate R-scape…", action: locateRScape)
                    Button("Clear saved path") {
                        UserDefaults.standard.removeObject(forKey: RScapeExecutableLocator.savedPathKey)
                        rScapePath = "Not configured"
                    }
                }
            }

            Section("Recovery") {
                Text(recoveryMessage).font(.caption).foregroundStyle(.secondary)
                Button("Clear all recovery data…", role: .destructive) {
                    showingClearConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding(14)
        .frame(width: 540, height: 520)
        .alert("Clear all MATER recovery data?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Recovery Data", role: .destructive) {
                recoveryMessage = StockholmDocument.clearAllRecoveryData()
                    ? "All recovery snapshots were cleared."
                    : "MATER could not clear all recovery snapshots."
            }
        } message: {
            Text("This permanently removes MATER's automatic and manual recovery snapshots. Your saved Stockholm files are not affected.")
        }
    }

    private func locateRScape() {
        let panel = NSOpenPanel()
        panel.title = "Locate R-scape"
        panel.message = "Choose the R-scape executable, bin folder, or installation folder."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        guard let executable = RScapeExecutableLocator.resolveSelection(selected) else {
            rScapePath = "Selection did not contain a usable R-scape executable."
            return
        }
        UserDefaults.standard.set(executable.path, forKey: RScapeExecutableLocator.savedPathKey)
        rScapePath = executable.path
    }
}

enum PreferencesMigration {
    private static let migrationKey = "MATER.didMigrateOrgMaterRNAEditorDefaults"
    private static let keys = [
        "residue.A", "residue.C", "residue.G", "residue.U",
        RScapeExecutableLocator.savedPathKey
    ]

    static func migrateLegacyDefaultsIfNeeded() {
        let current = UserDefaults.standard
        guard !current.bool(forKey: migrationKey) else { return }
        if let legacy = UserDefaults(suiteName: "org.mater.rnaeditor") {
            for key in keys where current.object(forKey: key) == nil {
                if let value = legacy.object(forKey: key) { current.set(value, forKey: key) }
            }
        }
        current.set(true, forKey: migrationKey)
    }
}
