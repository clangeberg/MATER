import SwiftUI

struct StructuralQualityInspector: View {
    @ObservedObject var document: StockholmDocument
    @ObservedObject var state: EditorState
    let suggestEdits: () -> Void

    private var quality: StemQuality? {
        document.structuralQuality(containing: state.selectedColumn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Quality Inspector", systemImage: "stethoscope")
                    .font(.headline)
                Spacer()
                Button {
                    state.showInspector = false
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .buttonStyle(.plain)
                .help("Hide the Structural Quality Inspector")
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    navigationControls
                    Divider()
                    if let quality {
                        qualitySummary(quality)
                        pairTypeSummary(quality)
                        pairBreakdown(quality)
                        issueList(quality)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text("No stem selected").font(.headline)
                            Text("Select a paired column or a colored block in the alignment overview to inspect its stem.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 220)
                    }
                }
                .padding(12)
            }

            Divider()
            Text("Pair variation is descriptive; it is not a statistical covariation test.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .frame(minWidth: 270, idealWidth: 310, maxWidth: 360)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var navigationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Large-alignment view").font(.subheadline.bold())
            Picker("Filter", selection: $state.sequenceFilterMode) {
                ForEach(SequenceFilterMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Sort", selection: $state.sequenceSortMode) {
                ForEach(SequenceSortMode.allCases) { Text($0.title).tag($0) }
            }
            if state.sequenceFilterMode != .all {
                Button("Show all sequences") { state.sequenceFilterMode = .all }
                    .buttonStyle(.link)
            }
        }
        .controlSize(.small)
    }

    private func qualitySummary(_ quality: StemQuality) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stem \(quality.stem + 1)").font(.title3.bold())
                    Text("\(quality.structureTag) • \(quality.pairs.count) base pair\(quality.pairs.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select stem") {
                    state.selectColumns(Set(quality.pairs.flatMap { [$0.left, $0.right] }))
                    state.statusMessage = "Selected stem \(quality.stem + 1)."
                }
            }

            if quality.evaluable > 0 {
                MetricBar(label: "Canonical", value: quality.canonicalFraction, color: .green, count: quality.canonical)
                MetricBar(label: "Noncanonical", value: quality.noncanonicalFraction, color: .red, count: quality.noncanonical)
            } else {
                Text("No occupied, unambiguous pairs are available to score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MetricBar(label: "Gaps", value: quality.gapFraction, color: .gray, count: quality.gaps)
            if quality.ambiguous > 0 {
                MetricBar(label: "Ambiguous", value: quality.ambiguousFraction, color: .orange, count: quality.ambiguous)
            }
            Text("Canonical and noncanonical rates use occupied, unambiguous pairs. Gaps and ambiguity are reported separately and are not violations.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    state.sequenceFilterMode = .structuralProblems
                    state.sequenceSortMode = .mostProblems
                } label: {
                    Label("Show violating sequences", systemImage: "line.3.horizontal.decrease.circle")
                }
                Button(action: suggestEdits) {
                    Label("Suggest fixes", systemImage: "wand.and.stars")
                }
                .disabled(!selectedRowIsSequence)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func pairTypeSummary(_ quality: StemQuality) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Observed residue pairs").font(.subheadline.bold())
            if quality.pairTypeCounts.isEmpty {
                Text("No unambiguous residue pairs.").foregroundStyle(.secondary)
            } else {
                let sorted = quality.pairTypeCounts.sorted {
                    if $0.value != $1.value { return $0.value > $1.value }
                    return $0.key < $1.key
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(sorted, id: \.key) { pair, count in
                        HStack(spacing: 4) {
                            Text(pair).font(.system(.caption, design: .monospaced).bold())
                            Spacer(minLength: 2)
                            Text("\(count)").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
    }

    private func pairBreakdown(_ quality: StemQuality) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pairs in this stem").font(.subheadline.bold())
            ForEach(quality.pairQualities) { pairQuality in
                Button {
                    state.selectColumns([pairQuality.pair.left, pairQuality.pair.right])
                    state.statusMessage = "Selected columns \(pairQuality.pair.left + 1) and \(pairQuality.pair.right + 1)."
                } label: {
                    HStack {
                        Text("\(pairQuality.pair.left + 1)–\(pairQuality.pair.right + 1)")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        if pairQuality.evaluable > 0 {
                            Text("\(Int((pairQuality.canonicalFraction * 100).rounded()))% canonical occupied")
                                .font(.caption)
                                .foregroundStyle(pairQuality.canonicalFraction >= 0.8 ? .green : .orange)
                        } else {
                            Text("no evaluable pairs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if pairQuality.noncanonical > 0 {
                            Text("\(pairQuality.noncanonical) bad").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func issueList(_ quality: StemQuality) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Observations to review (\(quality.issues.count))").font(.subheadline.bold())
            if quality.issues.isEmpty {
                Label("No gaps, ambiguity codes, or pair violations in this stem.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                ForEach(quality.issues.prefix(80)) { issue in
                    Button {
                        state.select(row: issue.modelRow, column: issue.pair.left)
                        state.statusMessage = "\(issue.sequenceName): \(issue.observedPair) at columns \(issue.pair.left + 1)–\(issue.pair.right + 1)."
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: issue.kind == .gap ? "minus.circle" : "exclamationmark.circle")
                                .foregroundStyle(issue.kind == .noncanonical ? .red : (issue.kind == .ambiguous ? .orange : .secondary))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.sequenceName).lineLimit(1)
                                Text("\(issue.observedPair) • \(issue.pair.left + 1)–\(issue.pair.right + 1) • \(issue.kind.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                if quality.issues.count > 80 {
                    Text("Showing the first 80 observations.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var selectedRowIsSequence: Bool {
        document.analysis.rows.indices.contains(state.selectedRow)
            && document.analysis.rows[state.selectedRow].kind.isSequence
            && !state.selectingConsensus
    }
}

private struct MetricBar: View {
    let label: String
    let value: Double
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(label).font(.caption).frame(width: 82, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color.opacity(0.78)).frame(width: geometry.size.width * max(0, min(1, value)))
                }
            }
            .frame(height: 7)
            Text("\(Int((value * 100).rounded()))% (\(count))")
                .font(.caption.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
        }
    }
}

struct AlignmentMinimapView: View {
    @ObservedObject var document: StockholmDocument
    @ObservedObject var state: EditorState

    private struct StemBlock: Identifiable {
        let stem: Int
        let columns: ClosedRange<Int>
        let isPseudoknot: Bool

        var id: String { "\(stem):\(columns.lowerBound):\(columns.upperBound)" }
    }

    var body: some View {
        let entropy = document.analysis.entropyByColumn
        let gaps = document.analysis.gapFrequencyByColumn
        let problems = document.analysis.structuralProblemFractions
        let pairs = document.analysis.structurePairs
        let blocks = stemBlocks(for: pairs)
        VStack(spacing: 4) {
            HStack {
                Label("Structure and alignment overview", systemImage: "rectangle.3.group")
                Text("\(Set(pairs.map(\.stem)).count) stems • \(pairs.filter(\.isPseudoknot).count) pseudoknot pairs")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Click or drag to navigate").foregroundStyle(.secondary)
            }
            .font(.caption)

            GeometryReader { geometry in
                Canvas { context, size in
                    let length = max(1, document.analysis.alignmentLength)
                    let columnWidth = max(0.6, size.width / CGFloat(length))
                    let structureY: CGFloat = 0
                    let structureHeight: CGFloat = 10
                    let entropyY: CGFloat = 15
                    let gapY: CGFloat = 24
                    let problemY: CGFloat = 33
                    let heatmapHeight: CGFloat = 6

                    for rect in [
                        CGRect(x: 0, y: structureY, width: size.width, height: structureHeight),
                        CGRect(x: 0, y: entropyY, width: size.width, height: heatmapHeight),
                        CGRect(x: 0, y: gapY, width: size.width, height: heatmapHeight),
                        CGRect(x: 0, y: problemY, width: size.width, height: heatmapHeight)
                    ] {
                        context.fill(Path(rect), with: .color(.secondary.opacity(0.10)))
                    }

                    let selectedStem = pairs.first {
                        $0.left == state.selectedColumn || $0.right == state.selectedColumn
                    }?.stem
                    for block in blocks {
                        let x = CGFloat(block.columns.lowerBound) / CGFloat(length) * size.width
                        let blockWidth = max(
                            columnWidth,
                            CGFloat(block.columns.count) / CGFloat(length) * size.width
                        )
                        let rect = CGRect(x: x, y: structureY, width: blockWidth, height: structureHeight)
                        let color = Color(nsColor: AlignmentPalette.stemColor(for: block.stem))
                        context.fill(Path(rect), with: .color(color.opacity(selectedStem == block.stem ? 1 : 0.78)))
                        if block.isPseudoknot {
                            context.stroke(
                                Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                                with: .color(.primary.opacity(0.72)),
                                style: StrokeStyle(lineWidth: 1, dash: [2, 1.5])
                            )
                        } else if selectedStem == block.stem {
                            context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.primary), lineWidth: 1.5)
                        }
                    }

                    for column in 0..<length {
                        let x = CGFloat(column) / CGFloat(length) * size.width
                        if entropy.indices.contains(column), entropy[column] > 0 {
                            context.fill(
                                Path(CGRect(x: x, y: entropyY, width: columnWidth, height: heatmapHeight)),
                                with: .color(.indigo.opacity(min(0.95, entropy[column] / 2)))
                            )
                        }
                        if gaps.indices.contains(column), gaps[column] > 0 {
                            context.fill(
                                Path(CGRect(x: x, y: gapY, width: columnWidth, height: heatmapHeight)),
                                with: .color(.teal.opacity(min(0.95, gaps[column])))
                            )
                        }
                        if problems.indices.contains(column), problems[column] > 0 {
                            context.fill(
                                Path(CGRect(x: x, y: problemY, width: columnWidth, height: heatmapHeight)),
                                with: .color(.red.opacity(min(0.95, problems[column])))
                            )
                        }
                    }
                    let selectedX = CGFloat(state.selectedColumn) / CGFloat(max(1, length - 1)) * size.width
                    context.fill(Path(CGRect(x: selectedX - 1, y: 0, width: 2, height: 40)), with: .color(.yellow.opacity(0.9)))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    guard document.analysis.alignmentLength > 0, geometry.size.width > 0 else { return }
                    let column = max(0, min(
                        document.analysis.alignmentLength - 1,
                        Int((gesture.location.x / geometry.size.width * CGFloat(document.analysis.alignmentLength)).rounded(.down))
                    ))
                    state.select(row: state.selectedRow, column: column, wholeColumn: true)
                    if let pair = pairs.first(where: { $0.left == column || $0.right == column }) {
                        state.statusMessage = "Alignment overview • stem \(pair.stem + 1), column \(column + 1)"
                    } else {
                        state.statusMessage = "Alignment overview • column \(column + 1)"
                    }
                })
            }
            .frame(height: 40)
            HStack(spacing: 12) {
                Label("stem blocks", systemImage: "square.fill").foregroundStyle(.orange)
                Text("dashed outline = pseudoknot").foregroundStyle(.secondary)
                Label("entropy", systemImage: "square.fill").foregroundStyle(.indigo)
                Label("gaps", systemImage: "square.fill").foregroundStyle(.teal)
                Label("occupied-pair violations", systemImage: "square.fill")
                    .foregroundStyle(.red)
                    .help("Noncanonical pairs divided by occupied, unambiguous observations. Gaps and ambiguity codes are excluded.")
                Spacer()
            }
            .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func stemBlocks(for pairs: [BasePair]) -> [StemBlock] {
        Dictionary(grouping: pairs, by: \.stem).flatMap { stem, stemPairs in
            let pseudoknot = stemPairs.contains(where: \.isPseudoknot)
            return contiguousRanges(stemPairs.map(\.left)).map {
                StemBlock(stem: stem, columns: $0, isPseudoknot: pseudoknot)
            } + contiguousRanges(stemPairs.map(\.right)).map {
                StemBlock(stem: stem, columns: $0, isPseudoknot: pseudoknot)
            }
        }
        .sorted {
            if $0.columns.lowerBound != $1.columns.lowerBound {
                return $0.columns.lowerBound < $1.columns.lowerBound
            }
            return $0.stem < $1.stem
        }
    }

    private func contiguousRanges(_ columns: [Int]) -> [ClosedRange<Int>] {
        let sorted = Array(Set(columns)).sorted()
        guard var start = sorted.first else { return [] }
        var previous = start
        var result: [ClosedRange<Int>] = []
        for column in sorted.dropFirst() {
            if column != previous + 1 {
                result.append(start...previous)
                start = column
            }
            previous = column
        }
        result.append(start...previous)
        return result
    }
}

struct SuggestedEditsView: View {
    let suggestions: [StemEditSuggestion]
    let cancel: () -> Void
    let apply: (StemEditSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Suggested gap shifts").font(.title2.bold())
                    Text("Suggestions never change the ungapped sequence and each accepted edit is undoable.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: cancel).keyboardShortcut(.cancelAction)
            }

            Divider()

            if suggestions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("No safe improvement found").font(.headline)
                    Text("MATER tested adjacent one-column shifts for the selected stem. Opening a nearby gap or selecting the other arm may expose another option.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            suggestionCard(suggestion)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 430)
    }

    private func suggestionCard(_ suggestion: StemEditSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.directionTitle).font(.headline)
                    Text("\(suggestion.sequenceName) • Stem \(suggestion.stem + 1) • \(suggestion.linked ? "both arms linked" : "selected arm only")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Apply") { apply(suggestion) }
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 16) {
                delta("Canonical", before: suggestion.before.canonical, after: suggestion.after.canonical, favorableIncrease: true)
                delta("Noncanonical", before: suggestion.before.noncanonical, after: suggestion.after.noncanonical, favorableIncrease: false)
                delta("Gaps", before: suggestion.before.gaps, after: suggestion.after.gaps, favorableIncrease: false)
                Text("Whole alignment: \(suggestion.globalCanonicalBefore) → \(suggestion.globalCanonicalAfter) canonical")
                    .font(.caption)
                    .foregroundStyle(suggestion.globalCanonicalGain > 0 ? .green : .secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow {
                    Text("").gridColumnAlignment(.trailing)
                    Text("Left arm").foregroundStyle(.secondary)
                    Text("Right arm").foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Before").foregroundStyle(.secondary)
                    Text(suggestion.leftBefore).font(.system(.body, design: .monospaced))
                    Text(suggestion.rightBefore).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("After").foregroundStyle(.secondary)
                    Text(suggestion.leftAfter).font(.system(.body, design: .monospaced)).foregroundStyle(.blue)
                    Text(suggestion.rightAfter).font(.system(.body, design: .monospaced)).foregroundStyle(.blue)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func delta(_ label: String, before: Int, after: Int, favorableIncrease: Bool) -> some View {
        let improved = favorableIncrease ? after > before : after < before
        return VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(before) → \(after)").font(.caption.monospacedDigit()).foregroundStyle(improved ? .green : .primary)
        }
    }
}
