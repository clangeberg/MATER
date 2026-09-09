import Foundation

@main
struct PerformanceBenchmarkMain {
    static func main() {
        let rows = Int(CommandLine.arguments.dropFirst().first ?? "5000") ?? 5000
        let columns = Int(CommandLine.arguments.dropFirst(2).first ?? "1000") ?? 1000
        precondition(rows > 0 && columns >= 8)

        let unit = "-ACGU..."
        let aligned = String(String(repeating: unit, count: columns / unit.count + 1).prefix(columns))
        var text = "# STOCKHOLM 1.0\n"
        text.reserveCapacity(rows * (columns + 24))
        for row in 0..<rows { text += "sequence_\(row) \(aligned)\n" }
        text += "#=GC SS_cons \(String(repeating: ".", count: columns))\n//\n"

        let parse = measure { StockholmParser.parse(text) }
        var file = parse.value
        let analysis = measure {
            let pairs = StructureParser.pairs(in: file)
            _ = file.validationIssues
            _ = EntropyAnalyzer.columnEntropies(in: file)
            _ = GapAnalyzer.columnGapFrequencies(in: file)
            _ = StructuralQualityAnalyzer.problemFractionsByColumn(in: file, pairs: pairs)
        }
        let before = file
        let edit = measure {
            precondition(file.shift(row: 0, selection: 1...4, direction: -1))
            precondition(SequenceIntegrityAnalyzer.preservesSequences(from: before, to: file))
        }
        let reanalysis = measure {
            let pairs = StructureParser.pairs(in: file)
            _ = file.validationIssues
            _ = EntropyAnalyzer.columnEntropies(in: file)
            _ = GapAnalyzer.columnGapFrequencies(in: file)
            _ = StructuralQualityAnalyzer.problemFractionsByColumn(in: file, pairs: pairs)
        }

        print("MATER synthetic benchmark: \(rows) sequences × \(columns) columns")
        print(String(format: "parse %.3f s | analysis %.3f s | protected shift %.3f s | reanalysis %.3f s", parse.seconds, analysis.seconds, edit.seconds, reanalysis.seconds))
    }

    private static func measure<T>(_ operation: () -> T) -> (value: T, seconds: TimeInterval) {
        let start = ContinuousClock.now
        let value = operation()
        let duration = start.duration(to: .now)
        let components = duration.components
        return (value, Double(components.seconds) + Double(components.attoseconds) / 1e18)
    }
}
