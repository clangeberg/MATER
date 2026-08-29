import SwiftUI

@main
struct MATERApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { StockholmDocument() }) { configuration in
            DocumentEditorView(document: configuration.document)
        }
        .commands {
            CommandGroup(after: .textEditing) {
                Divider()
                Text("MATER: Shift–arrows selects a rectangle; Option–Left/Right shifts it; Control–G opens a gap; Control–Shift–G closes one.")
            }
        }

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("MATER").font(.title2.bold())
                Text("Manual Alignment Tool for Evolutionary RNA")
                    .font(.headline)
                Text("A structure-aware Stockholm alignment editor with pseudoknot support.")
                    .foregroundStyle(.secondary)
                Text("This is an independent implementation focused on manual RNA alignment curation.")
                    .font(.caption)
            }
            .padding(24)
            .frame(width: 480)
        }
    }
}
