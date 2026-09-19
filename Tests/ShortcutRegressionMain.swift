import AppKit
import Foundation

@main
struct ShortcutRegressionMain {
    @MainActor
    static func main() {
        let suite = "MATER.ShortcutRegression.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Could not create test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = KeyboardShortcutSettings(defaults: defaults)
        precondition(settings.preset == .yaale)
        precondition(settings.binding(for: .moveLeft).primary == ShortcutStroke(",", .control))
        precondition(settings.binding(for: .moveRight).primary == ShortcutStroke(".", .control))
        precondition(settings.binding(for: .insertColumn).primary == ShortcutStroke("i", .control))
        precondition(settings.binding(for: .removeAllGapColumns).primary == ShortcutStroke("d", [.control, .shift]))
        precondition(settings.binding(for: .gotoRow).primary == ShortcutStroke("g", .control))
        precondition(settings.binding(for: .openRowGap).primary == ShortcutStroke("i", [.control, .option]))

        let collision = ShortcutStroke("q", [.control, .option])
        settings.set(collision, for: .moveLeft, alternate: false)
        settings.set(collision, for: .moveRight, alternate: false)
        precondition(settings.preset == .custom)
        precondition(settings.conflicts(for: .moveLeft, alternate: false) == [.moveRight])

        settings.applyPreset(.materClassic)
        precondition(settings.binding(for: .moveLeft).primary == ShortcutStroke("left", .option))
        settings.applyPreset(.yaale)
        precondition(settings.binding(for: .jumpPair).primary == ShortcutStroke("]", .control))

        print("MATER keyboard-shortcut regression tests passed.")
    }
}
