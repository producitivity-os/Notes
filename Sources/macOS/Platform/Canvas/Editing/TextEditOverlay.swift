import AppKit

@MainActor
final class TextEditOverlay: NSObject, NSTextViewDelegate {
    private let styler = TextEditorStyler()
    private weak var host: NativeCanvasView?
    private var elementID: String?
    private var scrollView: NSScrollView?
    private var sourceWidth: CGFloat?
    private var ending = false

    var isEditing: Bool { elementID != nil }
    var editingElementID: String? { elementID }

    func begin(element: TextElement, in host: NativeCanvasView) {
        finish(commit: true)
        self.host = host
        elementID = element.id
        sourceWidth = element.geometry.frame.width
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else {
            remove()
            return
        }
        styler.configure(textView)
        textView.string = element.markdown
        styler.apply(element: element, scale: 1, to: textView)
        textView.usesFindPanel = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.delegate = self
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scrollView = scroll
        host.addSubview(scroll)
        layout()
        host.window?.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    func layout() {
        guard let host, let elementID,
              case let .text(text)? = host.controller.scene.element(id: elementID) else { return }
        var editorFrame = host.viewport.viewRect(fromWorld: text.geometry.frame.cgRect)
        editorFrame.size.width = max(editorFrame.width, (sourceWidth ?? text.geometry.frame.width) * host.viewport.scale)
        editorFrame.size.width = min(editorFrame.width, max(80, host.bounds.maxX - editorFrame.minX - 12))
        scrollView?.frame = editorFrame
        if let textView = scrollView?.documentView as? NSTextView {
            let scale = host.viewport.scale
            styler.apply(element: text, scale: scale, to: textView)
            textView.textContainerInset = NSSize(
                width: text.padding * scale,
                height: text.padding * scale
            )
            textView.frame.size.width = editorFrame.width
        }
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
        if commit { commitCurrentText(host: host, text: &text) }
        remove()
        host.window?.makeFirstResponder(host)
        host.needsDisplay = true
    }

    func textDidEndEditing(_ notification: Notification) { finish(commit: true) }

    func textDidChange(_ notification: Notification) {
        host?.needsDisplay = true
    }

    private func commitCurrentText() {
        guard let host, let elementID,
              case var .text(text)? = host.controller.scene.element(id: elementID) else { return }
        commitCurrentText(host: host, text: &text)
    }

    private func commitCurrentText(host: NativeCanvasView, text: inout TextElement) {
        guard let textView = scrollView?.documentView as? NSTextView,
              text.markdown != textView.string else { return }
        text.markdown = textView.string
        host.controller.updateElement(.text(text), actionName: "Edit Text")
    }

    private func expandSourceEditorIfNeeded() {
        guard let host, let elementID,
              case let .text(text)? = host.controller.scene.element(id: elementID),
              let textView = scrollView?.documentView as? NSTextView else { return }
        let scale = host.viewport.scale
        let font = NSFont.systemFont(ofSize: max(1, text.fontSize * scale), weight: .regular)
        let widestLine = textView.string
            .components(separatedBy: .newlines)
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let desiredWidth = (widestLine + textView.textContainerInset.width * 2 + 20) / max(scale, 0.01)
        let requestedWidth = max(sourceWidth ?? text.geometry.frame.width, desiredWidth)
        let expandedWidth = host.controller.isInfiniteCanvas
            ? requestedWidth
            : min(requestedWidth, max(text.geometry.frame.width, host.controller.pageSize.width - text.geometry.frame.x))
        guard expandedWidth > text.geometry.frame.width + 0.5 else { return }
        var expandedText = text
        expandedText.geometry.frame.width = expandedWidth
        sourceWidth = expandedWidth
        host.controller.updateElement(.text(expandedText), actionName: "Expand Text")
        layout()
    }

    private func remove() {
        scrollView?.removeFromSuperview()
        scrollView = nil
        elementID = nil
        sourceWidth = nil
    }
}
