import AppKit

enum AlignmentPalette {
    /// Generates a stable color for every stem without wrapping through a
    /// finite palette. Golden-angle hue spacing keeps neighboring stem IDs far
    /// apart, while four saturation/brightness bands add separation once the
    /// hue circle becomes crowded.
    static func stemColor(for stem: Int) -> NSColor {
        let index = max(0, stem)
        let goldenRatioConjugate = 0.618_033_988_749_894_9
        let hue = (0.105 + Double(index) * goldenRatioConjugate).truncatingRemainder(dividingBy: 1)
        let saturations: [CGFloat] = [0.52, 0.42, 0.61, 0.47]
        let brightnesses: [CGFloat] = [0.98, 0.91, 0.96, 0.87]
        let band = index % saturations.count
        return NSColor(
            calibratedHue: CGFloat(hue),
            saturation: saturations[band],
            brightness: brightnesses[band],
            alpha: 0.78
        )
    }

    static let covariation: [CovariationClass: NSColor] = [
        .conserved: NSColor(calibratedRed: 0.47, green: 0.78, blue: 0.48, alpha: 0.78),
        .consistent: NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.96, alpha: 0.82),
        .compensatory: NSColor(calibratedRed: 0.12, green: 0.34, blue: 0.75, alpha: 0.92),
        .gap: NSColor(calibratedWhite: 0.72, alpha: 0.55),
        .noncanonical: NSColor(calibratedRed: 0.83, green: 0.16, blue: 0.18, alpha: 0.90)
    ]
}
