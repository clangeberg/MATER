import AppKit
import Combine
import SwiftUI

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case yaale
    case materClassic
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .yaale: return "Yaale-compatible"
        case .materClassic: return "MATER Classic"
        case .custom: return "Custom"
        }
    }
}

enum EditorShortcutAction: String, CaseIterable, Identifiable, Codable {
    case moveLeft, moveRight, pushLeft, pushRight
    case insertColumn, deleteColumn, removeAllGapColumns
    case openRowGap, closeRowGap, jumpPair, clearCells
    case fastLeft, fastRight, fastUp, fastDown
    case findForward, findReverse, gotoRow, gotoColumn
    case justifyLeft, justifyRight, transpose
    case structureColors, pairVariationColors, residueColors
    case fontIncrease, fontDecrease
    case copy, paste, selectAll, undo, redo
    case alignmentStatistics, detectProblems, permuteColumns, foldHairpin, writeConsensus

    var id: String { rawValue }
    var category: String {
        switch self {
        case .moveLeft, .moveRight, .pushLeft, .pushRight, .justifyLeft, .justifyRight, .transpose:
            return "Alignment editing"
        case .insertColumn, .deleteColumn, .removeAllGapColumns, .openRowGap, .closeRowGap, .clearCells:
            return "Gaps and columns"
        case .fastLeft, .fastRight, .fastUp, .fastDown, .findForward, .findReverse, .gotoRow, .gotoColumn, .jumpPair:
            return "Navigation"
        case .structureColors, .pairVariationColors, .residueColors, .fontIncrease, .fontDecrease:
            return "View"
        case .copy, .paste, .selectAll, .undo, .redo:
            return "Standard editing"
        case .alignmentStatistics, .detectProblems, .permuteColumns, .foldHairpin, .writeConsensus:
            return "Tools"
        }
    }
    var title: String {
        switch self {
        case .moveLeft: return "Move selection left"
        case .moveRight: return "Move selection right"
        case .pushLeft: return "Push selection fully left"
        case .pushRight: return "Push selection fully right"
        case .insertColumn: return "Insert alignment column"
        case .deleteColumn: return "Delete all-gap column"
        case .removeAllGapColumns: return "Remove all empty columns"
        case .openRowGap: return "Open gap in row"
        case .closeRowGap: return "Close gap in row"
        case .jumpPair: return "Jump to pair"
        case .clearCells: return "Clear selected cells"
        case .fastLeft: return "Fast navigation left"
        case .fastRight: return "Fast navigation right"
        case .fastUp: return "Fast navigation up"
        case .fastDown: return "Fast navigation down"
        case .findForward: return "Find forward"
        case .findReverse: return "Find backward"
        case .gotoRow: return "Go to row"
        case .gotoColumn: return "Go to column"
        case .justifyLeft: return "Left-justify selected residues"
        case .justifyRight: return "Right-justify selected residues"
        case .transpose: return "Transpose residue and neighboring gap"
        case .structureColors: return "Stem colors"
        case .pairVariationColors: return "Pair-variation colors"
        case .residueColors: return "Residue colors"
        case .fontIncrease: return "Increase text size"
        case .fontDecrease: return "Decrease text size"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .selectAll: return "Select all"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .alignmentStatistics: return "Alignment statistics"
        case .detectProblems: return "Detect alignment problems"
        case .permuteColumns: return "Permute around cursor"
        case .foldHairpin: return "Fold selection as hairpin"
        case .writeConsensus: return "Write R2R consensus"
        }
    }
}

struct ShortcutStroke: Codable, Hashable {
    var key: String
    var modifiers: UInt

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        self.modifiers = modifiers.intersection([.command, .control, .option, .shift]).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        Self.keyName(for: event) == key
            && event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue == modifiers
    }

    var displayName: String {
        let flags = modifierFlags
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        let names = [
            "left": "←", "right": "→", "up": "↑", "down": "↓",
            "delete": "⌫", "forwarddelete": "⌦", "return": "↩", "escape": "Esc",
            "home": "Home", "end": "End", "space": "Space"
        ]
        return result + (names[key] ?? key.uppercased())
    }

    static func from(event: NSEvent) -> ShortcutStroke? {
        let key = keyName(for: event)
        guard !key.isEmpty, !["shift", "control", "option", "command"].contains(key) else { return nil }
        return ShortcutStroke(key, event.modifierFlags)
    }

    static func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 51: return "delete"
        case 117: return "forwarddelete"
        case 36, 76: return "return"
        case 53: return "escape"
        case 115: return "home"
        case 119: return "end"
        case 49: return "space"
        default: return event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
    }
}

struct ShortcutBinding: Codable, Equatable {
    var primary: ShortcutStroke?
    var alternate: ShortcutStroke?
}

@MainActor
final class KeyboardShortcutSettings: ObservableObject {
    private static let presetKey = "keyboardShortcutPreset"
    private static let bindingsKey = "keyboardShortcutBindings.v1"
    private let defaults: UserDefaults

    @Published private(set) var preset: ShortcutPreset
    @Published private(set) var bindings: [EditorShortcutAction: ShortcutBinding]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedPreset = defaults.string(forKey: Self.presetKey).flatMap(ShortcutPreset.init(rawValue:)) ?? .yaale
        if savedPreset == .custom,
           let data = defaults.data(forKey: Self.bindingsKey),
           let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            self.preset = savedPreset
            self.bindings = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
                EditorShortcutAction(rawValue: key).map { ($0, value) }
            })
        } else {
            let initialPreset: ShortcutPreset = savedPreset == .custom ? .yaale : savedPreset
            self.preset = initialPreset
            self.bindings = Self.bindings(for: initialPreset)
        }
    }

    func binding(for action: EditorShortcutAction) -> ShortcutBinding { bindings[action] ?? ShortcutBinding() }

    func action(for event: NSEvent) -> EditorShortcutAction? {
        EditorShortcutAction.allCases.first { action in
            let value = binding(for: action)
            return value.primary?.matches(event) == true || value.alternate?.matches(event) == true
        }
    }

    func applyPreset(_ newPreset: ShortcutPreset) {
        guard newPreset != .custom else { return }
        preset = newPreset
        bindings = Self.bindings(for: newPreset)
        persist()
    }

    func set(_ stroke: ShortcutStroke?, for action: EditorShortcutAction, alternate: Bool) {
        var value = binding(for: action)
        if alternate { value.alternate = stroke } else { value.primary = stroke }
        bindings[action] = value
        preset = .custom
        persist()
    }

    func reset(action: EditorShortcutAction) {
        bindings[action] = Self.bindings(for: .yaale)[action]
        preset = .custom
        persist()
    }

    func conflicts(for action: EditorShortcutAction, alternate: Bool) -> [EditorShortcutAction] {
        let candidate = alternate ? binding(for: action).alternate : binding(for: action).primary
        guard let candidate else { return [] }
        return EditorShortcutAction.allCases.filter { other in
            guard other != action else { return false }
            let value = binding(for: other)
            return value.primary == candidate || value.alternate == candidate
        }
    }

    private func persist() {
        defaults.set(preset.rawValue, forKey: Self.presetKey)
        let encoded = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) { defaults.set(data, forKey: Self.bindingsKey) }
    }

    private static func bindings(for preset: ShortcutPreset) -> [EditorShortcutAction: ShortcutBinding] {
        func b(_ primary: ShortcutStroke?, _ alternate: ShortcutStroke? = nil) -> ShortcutBinding {
            ShortcutBinding(primary: primary, alternate: alternate)
        }
        let command = NSEvent.ModifierFlags.command
        let control = NSEvent.ModifierFlags.control
        let controlShift: NSEvent.ModifierFlags = [.control, .shift]
        let option = NSEvent.ModifierFlags.option
        let optionShift: NSEvent.ModifierFlags = [.option, .shift]
        if preset == .materClassic {
            return [
                .moveLeft: b(.init("left", option)), .moveRight: b(.init("right", option)),
                .pushLeft: b(.init("left", optionShift)), .pushRight: b(.init("right", optionShift)),
                .insertColumn: b(.init("i", [.command, .shift])), .deleteColumn: b(.init("d", [.command, .shift])),
                .removeAllGapColumns: b(.init("d", [.command, .option])),
                .openRowGap: b(.init("g", control)), .closeRowGap: b(.init("g", controlShift)),
                .jumpPair: b(.init("]", control)), .clearCells: b(.init("delete", [])),
                .findForward: b(.init("f", command)), .findReverse: b(.init("f", [.command, .shift])),
                .fontIncrease: b(.init("=", command)), .fontDecrease: b(.init("-", command)),
                .copy: b(.init("c", command)), .paste: b(.init("v", command)), .selectAll: b(.init("a", command)),
                .undo: b(.init("z", command)), .redo: b(.init("z", [.command, .shift]))
            ]
        }
        return [
            .moveLeft: b(.init(",", control)),
            .moveRight: b(.init(".", control)),
            .pushLeft: b(.init(",", controlShift)),
            .pushRight: b(.init(".", controlShift)),
            .insertColumn: b(.init("i", control)),
            .deleteColumn: b(.init("d", control)),
            .removeAllGapColumns: b(.init("d", controlShift)),
            .openRowGap: b(.init("i", [.control, .option])),
            .closeRowGap: b(.init("d", [.control, .option])),
            .jumpPair: b(.init("]", control)), .clearCells: b(.init("delete", control), .init("delete", [])),
            .fastLeft: b(.init("left", control)), .fastRight: b(.init("right", control)),
            .fastUp: b(.init("up", control)), .fastDown: b(.init("down", control)),
            .findForward: b(.init("f", control), .init("f", command)),
            .findReverse: b(.init("r", control), .init("f", [.command, .shift])),
            .gotoRow: b(.init("g", control)), .gotoColumn: b(.init("g", controlShift)),
            .justifyLeft: b(.init("[", controlShift)), .justifyRight: b(.init("]", controlShift)),
            .transpose: b(.init("t", control)),
            .structureColors: b(.init("b", control)), .pairVariationColors: b(.init("b", controlShift)),
            .residueColors: b(.init("n", control)),
            .fontIncrease: b(.init("=", control), .init("=", command)),
            .fontDecrease: b(.init("-", control), .init("-", command)),
            .copy: b(.init("c", command), .init("c", control)),
            .paste: b(.init("v", command), .init("v", control)),
            .selectAll: b(.init("a", command), .init("a", control)),
            .undo: b(.init("z", command), .init("z", control)),
            .redo: b(.init("z", [.command, .shift]), .init("y", control)),
            .alignmentStatistics: b(.init("s", [.control, .option])),
            .detectProblems: b(.init("k", [.control, .option])),
            .permuteColumns: b(.init("p", [.control, .option])),
            .foldHairpin: b(.init("h", [.control, .option])),
            .writeConsensus: b(.init("w", [.control, .option]))
        ]
    }
}

struct ShortcutMonitor: NSViewRepresentable {
    @ObservedObject var shortcuts: KeyboardShortcutSettings
    let handler: (EditorShortcutAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(shortcuts: shortcuts, handler: handler) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.shortcuts = shortcuts
        context.coordinator.handler = handler
        context.coordinator.hostView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    @MainActor
    final class Coordinator {
        var shortcuts: KeyboardShortcutSettings
        var handler: (EditorShortcutAction) -> Void
        weak var hostView: NSView?
        private var monitor: Any?

        init(shortcuts: KeyboardShortcutSettings, handler: @escaping (EditorShortcutAction) -> Void) {
            self.shortcuts = shortcuts
            self.handler = handler
        }

        func install(for view: NSView) {
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.hostView?.window else { return event }
                if event.window?.firstResponder is NSTextView { return event }
                guard let action = self.shortcuts.action(for: event) else { return event }
                self.handler(action)
                return nil
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let stroke: ShortcutStroke?
    let onChange: (ShortcutStroke?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = onChange
        button.stroke = stroke
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onChange = onChange
        if !nsView.isRecording { nsView.stroke = stroke }
    }

    final class RecorderButton: NSButton {
        var stroke: ShortcutStroke? { didSet { updateTitle() } }
        var onChange: ((ShortcutStroke?) -> Void)?
        var isRecording = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            bezelStyle = .rounded
            target = self
            action = #selector(beginRecording)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func beginRecording() {
            isRecording = true
            title = "Type shortcut…"
            window?.makeFirstResponder(self)
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            if event.keyCode == 53 {
                isRecording = false
                updateTitle()
                return
            }
            if event.keyCode == 51 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                stroke = nil
                isRecording = false
                onChange?(nil)
                return
            }
            guard let value = ShortcutStroke.from(event: event) else { return }
            stroke = value
            isRecording = false
            onChange?(value)
        }

        private func updateTitle() { title = stroke?.displayName ?? "None" }
    }
}
