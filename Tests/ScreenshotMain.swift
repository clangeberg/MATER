import AppKit
import SwiftUI

@main
struct ScreenshotMain {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: mater-screenshot INPUT.sto OUTPUT.png\n", stderr)
            exit(2)
        }
        do {
            let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
            let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
            let source = try String(contentsOf: inputURL, encoding: .utf8)
            let document = StockholmDocument(previewFile: StockholmParser.parse(source))
            let palette = ResiduePaletteSettings()
            let selectedColumn = document.analysis.structurePairs.first?.left ?? 0
            let root = DocumentEditorView(
                document: document,
                sourceURL: inputURL,
                initialSelectedColumn: selectedColumn
            )
                .environmentObject(palette)
                .frame(width: 1440, height: 900)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "RF01763 Guanidine-III — MATER"
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                hosting.layoutSubtreeIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                    fputs("could not allocate screenshot bitmap\n", stderr)
                    NSApplication.shared.terminate(nil)
                    return
                }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    fputs("could not encode screenshot\n", stderr)
                    NSApplication.shared.terminate(nil)
                    return
                }
                do {
                    try data.write(to: outputURL, options: .atomic)
                } catch {
                    fputs("could not write screenshot: \(error)\n", stderr)
                }
                NSApplication.shared.terminate(nil)
            }
            NSApplication.shared.run()
        } catch {
            fputs("screenshot failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
