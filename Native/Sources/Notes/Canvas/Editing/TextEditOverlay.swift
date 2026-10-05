import AppKit

@MainActor
final class TextEditOverlay: NSObject, NSTextViewDelegate {
    private weak var host: NativeCanvasView?
    private var elementID: String?
    private var scrollView: NSScrollView?
    private var ending = false

    var isEditing: Bool { elementID != nil }

    func begin(element: TextElement, in host: NativeCanvasView) {
        finish(commit: true)
        self.host = host
        elementID = element.id
        let textView = NSTextView()
        textView.string = element.markdown
        textView.font = .monospacedSystemFont(ofSize: max(12, element.fontSize), weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isRichText = false
        textView.usesFindPanel = true
        textView.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 6
        scrollView = scroll
        host.addSubview(scroll)
        layout()
        host.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    func layout() {
        guard let host, let elementID,
              case let .text(text)? = host.controller.scene.element(id: elementID) else { return }
        scrollView?.frame = host.viewport.viewRect(fromWorld: text.geometry.frame.cgRect)
    }

    func finish(commit: Bool) {
        guard !ending else { return }
        ending = true
        defer { ending = false }
        guard let host, let elementID,
              case var .text(text)? = host.controller.scene.element(id: elementID) else {
            remove()
            return
        }
        if commit, let textView = scrollView?.documentView as? NSTextView, text.markdown != textView.string {
            text.markdown = textView.string
            host.controller.updateElement(.text(text), actionName: "Edit Text")
        }
        remove()
        host.window?.makeFirstResponder(host)
        host.needsDisplay = true
    }

    func textDidEndEditing(_ notification: Notification) { finish(commit: true) }

    private func remove() {
        scrollView?.removeFromSuperview()
        scrollView = nil
        elementID = nil
    }
}
