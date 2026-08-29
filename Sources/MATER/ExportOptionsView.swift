import SwiftUI

struct AlignmentExportConfiguration {
    var title = ""
    var includeLegend = true
    var numberingInterval = 10
    var labelWidth = 220.0
    var selectedRowsOnly = false
    var selectedColumnsOnly = false
    var tiledPDF = false
}

struct ExportOptionsView: View {
    let format: AlignmentExportFormat
    let selectedRowCount: Int
    let selectedColumnCount: Int
    @Binding var configuration: AlignmentExportConfiguration
    let cancel: () -> Void
    let export: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export colored alignment as \(format.rawValue.uppercased())")
                .font(.title2.bold())

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Title")
                    TextField("Optional figure title", text: $configuration.title)
                        .frame(width: 310)
                }
                GridRow {
                    Text("Column numbers")
                    Stepper("Every \(configuration.numberingInterval) columns", value: $configuration.numberingInterval, in: 1...100, step: 1)
                }
                GridRow {
                    Text("Name width")
                    HStack {
                        Slider(value: $configuration.labelWidth, in: 140...480, step: 10)
                            .frame(width: 230)
                        Text("\(Int(configuration.labelWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 55, alignment: .trailing)
                    }
                }
            }

            Toggle("Include color legend", isOn: $configuration.includeLegend)
            Toggle("Export only the \(selectedRowCount) selected row\(selectedRowCount == 1 ? "" : "s")", isOn: $configuration.selectedRowsOnly)
            Toggle("Export only the \(selectedColumnCount) selected column\(selectedColumnCount == 1 ? "" : "s")", isOn: $configuration.selectedColumnsOnly)
            if format == .pdf {
                Toggle("Tile oversized alignment across landscape Letter pages", isOn: $configuration.tiledPDF)
            }

            Text("Colors, custom nucleotide colors, the grid, PP visibility, and entropy visibility follow the current MATER view.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Choose Save Location…", action: export)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 540)
    }
}
