import AppKit
import SwiftUI

@MainActor
final class CardEditorPanelCoordinator: NSObject, NSWindowDelegate {
    private weak var sourceController: NativeCanvasController?
    private var panel: NSPanel?

    init(sourceController: NativeCanvasController) {
        self.sourceController = sourceController
    }

    func present(card: CardElement) {
        guard let sourceController else { return }
        let panel = panel ?? makePanel()
        panel.title = card.title.isEmpty ? "Card" : card.title
        panel.contentViewController = NSHostingController(rootView: CardEditorSheet(
            card: card,
            sourceController: sourceController,
            onSave: { [weak sourceController] updated in
                sourceController?.persistEditedCard(updated)
            },
            onClose: { [weak panel] in panel?.performClose(nil) }
        ))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        panel?.contentViewController = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 760, height: 540)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrameAutosaveName("NotebookCardEditorPanel")
        panel.center()
        panel.delegate = self
        self.panel = panel
        return panel
    }
}
