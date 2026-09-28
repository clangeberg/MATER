import AppKit
import SwiftUI

enum MATERApplicationActions {
    private static var guideWindowController: NSWindowController?

    static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Manual Alignment Tool for Evolutionary RNA\nA structure-aware Stockholm editor with pseudoknot support.",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "MATER",
            .applicationVersion: "1.1.2",
            .version: "Build 19",
            .credits: credits
        ])
    }

    static func openUserGuide() {
        if let window = guideWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MATER User Guide"
        window.contentView = NSHostingView(rootView: InAppUserGuideView())
        window.center()
        let controller = NSWindowController(window: window)
        guideWindowController = controller
        controller.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct InAppUserGuideView: View {
    private let guide: AttributedString

    init() {
        let fallback = "MATER User Guide\n\nThe bundled guide could not be loaded."
        let text = Bundle.main.url(forResource: "MATER-User-Guide", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? fallback
        guide = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .full))) ?? AttributedString(text)
    }

    var body: some View {
        ScrollView {
            Text(guide)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("MATER User Guide").font(.headline)
                Spacer()
                Text("⌘? opens this window").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}
