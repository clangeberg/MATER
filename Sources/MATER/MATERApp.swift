import AppKit
import SwiftUI

@main
struct MATERApp: App {
    @StateObject private var residuePalette: ResiduePaletteSettings
    @StateObject private var keyboardShortcuts: KeyboardShortcutSettings

    init() {
        PreferencesMigration.migrateLegacyDefaultsIfNeeded()
        _residuePalette = StateObject(wrappedValue: ResiduePaletteSettings())
        _keyboardShortcuts = StateObject(wrappedValue: KeyboardShortcutSettings())
        StockholmDocument.cleanupRecoveryData(olderThanDays: 30)
    }

    var body: some Scene {
        DocumentGroup(newDocument: { StockholmDocument() }) { configuration in
            DocumentEditorView(document: configuration.document, sourceURL: configuration.fileURL)
                .environmentObject(residuePalette)
                .environmentObject(keyboardShortcuts)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MATER") { MATERApplicationActions.showAboutPanel() }
            }
            CommandGroup(after: .textEditing) {
                Divider()
                Text("MATER: drag selected cells to move them; Yaale-compatible shortcuts are the default and can be changed in Settings.")
            }
            CommandGroup(replacing: .help) {
                Button("MATER User Guide") { MATERApplicationActions.openUserGuide() }
                    .keyboardShortcut("?", modifiers: [.command])
            }
        }

        Settings {
            MATERSettingsView()
                .environmentObject(residuePalette)
                .environmentObject(keyboardShortcuts)
        }
    }
}

private struct MATERSettingsView: View {
    @EnvironmentObject private var residuePalette: ResiduePaletteSettings
    @EnvironmentObject private var keyboardShortcuts: KeyboardShortcutSettings
    @State private var rScapePath = UserDefaults.standard.string(forKey: RScapeExecutableLocator.savedPathKey) ?? "Not configured"
    @State private var showingClearConfirmation = false
    @State private var recoveryMessage = "Snapshots older than 30 days are removed automatically."

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }
            KeyboardShortcutSettingsView()
                .environmentObject(keyboardShortcuts)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
        }
        .padding(14)
        .frame(width: 650, height: 600)
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

    private var generalSettings: some View {
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

private struct KeyboardShortcutSettingsView: View {
    @EnvironmentObject private var shortcuts: KeyboardShortcutSettings

    private var categories: [String] {
        Array(Set(EditorShortcutAction.allCases.map(\.category))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Preset", selection: Binding(
                    get: { shortcuts.preset },
                    set: { shortcuts.applyPreset($0) }
                )) {
                    ForEach(ShortcutPreset.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 280)
                Spacer()
                Button("Reset to Yaale-compatible") { shortcuts.applyPreset(.yaale) }
            }
            Text("Click a shortcut field and type the new combination. Delete clears it; Escape cancels recording. Conflicts are shown in red.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        ForEach(EditorShortcutAction.allCases.filter { $0.category == category }) { action in
                            shortcutRow(action)
                        }
                    }
                }
            }
        }
    }

    private func shortcutRow(_ action: EditorShortcutAction) -> some View {
        let primaryConflicts = shortcuts.conflicts(for: action, alternate: false)
        let alternateConflicts = shortcuts.conflicts(for: action, alternate: true)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if !primaryConflicts.isEmpty || !alternateConflicts.isEmpty {
                    Text("Conflict with \((primaryConflicts + alternateConflicts).map(\.title).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            ShortcutRecorder(stroke: shortcuts.binding(for: action).primary) {
                shortcuts.set($0, for: action, alternate: false)
            }
            .frame(width: 100, height: 25)
            ShortcutRecorder(stroke: shortcuts.binding(for: action).alternate) {
                shortcuts.set($0, for: action, alternate: true)
            }
            .frame(width: 100, height: 25)
            Button("Reset") { shortcuts.reset(action: action) }
                .controlSize(.small)
        }
    }
}

enum PreferencesMigration {
    private static let migrationKey = "MATER.didMigrateOrgMaterRNAEditorDefaults"
    private static let keys = [
        "residue.A", "residue.C", "residue.G", "residue.U",
        RScapeExecutableLocator.savedPathKey,
        "keyboardShortcutPreset", "keyboardShortcutBindings.v1"
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
