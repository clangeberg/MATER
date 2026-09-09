import SwiftUI

struct PinnedReferencePanel: View {
    @ObservedObject var document: StockholmDocument
    @ObservedObject var state: EditorState
    @ObservedObject var residuePalette: ResiduePaletteSettings
    @State private var renderedRows: [PinnedRow] = []

    var body: some View {
        Group {
            if !renderedRows.isEmpty {
                VStack(spacing: 2) {
                ForEach(renderedRows, id: \.title) { row in
                    HStack(spacing: 0) {
                        Text(row.title)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 180, alignment: .leading)
                            .padding(.leading, 12)
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 0) {
                                ForEach(Array(row.characters.enumerated()), id: \.offset) { column, character in
                                    Text(String(character))
                                        .font(.system(size: state.fontSize, design: .monospaced))
                                        .foregroundStyle(foreground(row: row, column: column))
                                        .frame(width: max(10, state.fontSize * 0.72 + 2), height: 22)
                                        .background(background(row: row, column: column))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            state.select(row: row.modelRow ?? state.selectedRow, column: column)
                                            state.statusMessage = "\(row.title) • column \(column + 1)"
                                        }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                }
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: document.revision) { _ in rebuild() }
        .onChange(of: state.referenceSequenceName) { _ in rebuild() }
        .onChange(of: state.colorMode) { _ in rebuild() }
        .onChange(of: residuePalette.adenine) { _ in rebuild() }
        .onChange(of: residuePalette.cytosine) { _ in rebuild() }
        .onChange(of: residuePalette.guanine) { _ in rebuild() }
        .onChange(of: residuePalette.uracil) { _ in rebuild() }
    }

    private struct PinnedRow {
        let title: String
        let characters: [Character]
        let modelRow: Int?
        let backgrounds: [NSColor?]
        let lightForegroundColumns: Set<Int>
    }

    private func rebuild() {
        renderedRows = makeDisplayedRows()
    }

    private func makeDisplayedRows() -> [PinnedRow] {
        var result: [PinnedRow] = []
        let rows = document.analysis.rows
        let pairs = document.analysis.structurePairs
        var pairByColumn: [Int: BasePair] = [:]
        for pair in pairs {
            if pairByColumn[pair.left] == nil { pairByColumn[pair.left] = pair }
            if pairByColumn[pair.right] == nil { pairByColumn[pair.right] = pair }
        }
        let covariance = state.colorMode == .covariation
            ? CovariationAnalyzer.classifications(in: document.file, pairs: pairs)
            : [:]

        func makeRow(title: String, characters: [Character], modelRow: Int?, recordIndex: Int?) -> PinnedRow {
            var backgrounds = Array<NSColor?>(repeating: nil, count: characters.count)
            var lightForegroundColumns: Set<Int> = []
            for column in characters.indices {
                switch state.colorMode {
                case .residue:
                    backgrounds[column] = residuePalette.color(for: characters[column])
                case .stem:
                    if let pair = pairByColumn[column], characters.indices.contains(pair.left), characters.indices.contains(pair.right),
                       BasePairRules.isCanonical(characters[pair.left], characters[pair.right]) {
                        backgrounds[column] = AlignmentPalette.stemColor(for: pair.stem)
                    }
                case .element:
                    if let pair = pairByColumn[column], characters.indices.contains(pair.left), characters.indices.contains(pair.right),
                       BasePairRules.isCanonical(characters[pair.left], characters[pair.right]) {
                        backgrounds[column] = AlignmentPalette.stemColor(for: pair.element)
                    }
                case .covariation:
                    if let recordIndex, let classification = covariance[recordIndex]?[column] {
                        backgrounds[column] = AlignmentPalette.covariation[classification]
                        if classification == .compensatory || classification == .noncanonical {
                            lightForegroundColumns.insert(column)
                        }
                    }
                case .none:
                    break
                }
            }
            return PinnedRow(title: title, characters: characters, modelRow: modelRow, backgrounds: backgrounds, lightForegroundColumns: lightForegroundColumns)
        }

        if let referenceName = state.referenceSequenceName,
           let modelRow = rows.firstIndex(where: {
               if case .sequence(let name) = $0.kind { return name == referenceName }
               return false
           }) {
            let row = rows[modelRow]
            result.append(makeRow(
                title: "Reference: \(referenceName)",
                characters: Array(document.file.records[row.recordIndex].aligned),
                modelRow: modelRow,
                recordIndex: row.recordIndex
            ))
        }
        return result
    }

    private func background(row: PinnedRow, column: Int) -> Color {
        guard row.backgrounds.indices.contains(column), let color = row.backgrounds[column] else { return .clear }
        return Color(nsColor: color)
    }

    private func foreground(row: PinnedRow, column: Int) -> Color {
        row.lightForegroundColumns.contains(column) ? .white : .primary
    }
}
