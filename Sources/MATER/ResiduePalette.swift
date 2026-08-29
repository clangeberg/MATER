import AppKit
import SwiftUI

@MainActor
final class ResiduePaletteSettings: ObservableObject {
    @Published var adenine: NSColor { didSet { save(adenine, key: "residue.A") } }
    @Published var cytosine: NSColor { didSet { save(cytosine, key: "residue.C") } }
    @Published var guanine: NSColor { didSet { save(guanine, key: "residue.G") } }
    @Published var uracil: NSColor { didSet { save(uracil, key: "residue.U") } }

    init() {
        adenine = Self.load(key: "residue.A") ?? Self.defaults["A"]!
        cytosine = Self.load(key: "residue.C") ?? Self.defaults["C"]!
        guanine = Self.load(key: "residue.G") ?? Self.defaults["G"]!
        uracil = Self.load(key: "residue.U") ?? Self.defaults["U"]!
    }

    func color(for residue: Character) -> NSColor? {
        switch Character(String(residue).uppercased()) {
        case "A": return adenine
        case "C": return cytosine
        case "G": return guanine
        case "U", "T": return uracil
        default: return nil
        }
    }

    func reset() {
        adenine = Self.defaults["A"]!
        cytosine = Self.defaults["C"]!
        guanine = Self.defaults["G"]!
        uracil = Self.defaults["U"]!
    }

    func binding(for residue: Character) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: self.color(for: residue) ?? .clear) },
            set: { newValue in
                let color = NSColor(newValue)
                switch residue {
                case "A": self.adenine = color
                case "C": self.cytosine = color
                case "G": self.guanine = color
                default: self.uracil = color
                }
            }
        )
    }

    private func save(_ color: NSColor, key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load(key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    private static let defaults: [Character: NSColor] = [
        "A": NSColor(calibratedRed: 0.52, green: 0.82, blue: 0.49, alpha: 0.78),
        "C": NSColor(calibratedRed: 0.42, green: 0.72, blue: 0.96, alpha: 0.80),
        "G": NSColor(calibratedRed: 0.98, green: 0.68, blue: 0.30, alpha: 0.82),
        "U": NSColor(calibratedRed: 0.95, green: 0.48, blue: 0.48, alpha: 0.80)
    ]
}
