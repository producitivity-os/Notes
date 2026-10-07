import AppKit

@MainActor
final class CardTitleEditOverlay: NSObject, NSTextFieldDelegate {
    private weak var host: NativeCanvasView?
    private var cardID: String?
    private var textField: NSTextField?
    private var ending = false

    var isEditing: Bool { cardID != nil }

    func begin(card: CardElement, in host: NativeCanvasView) {
        finish(commit: true)
        self.host = host
        cardID = card.id

        let field = NSTextField(string: card.title)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .left
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self
        textField = field
        host.addSubview(field)
        layout()
        host.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func layout() {
        guard let host, let cardID,
              case let .card(card)? = host.controller.scene.element(id: cardID),
              let textField else { return }
        let frame = host.viewport.viewRect(fromWorld: card.geometry.frame.cgRect)
        let scale = host.viewport.scale
        let horizontalInset = 14 * scale
        let height = max(18, 30 * scale)
        textField.frame = CGRect(
            x: frame.minX + horizontalInset,
            y: frame.midY - height / 2,
            width: max(20, frame.width - horizontalInset * 2),
            height: height
        )
        textField.font = .systemFont(ofSize: max(1, 18 * scale), weight: .regular)
    }

    func finish(commit: Bool) {
        guard !ending else { return }
        ending = true
        defer { ending = false }
        guard let host, let cardID,
              case var .card(card)? = host.controller.scene.element(id: cardID) else {
            remove()
            return
        }
        if commit, let value = textField?.stringValue, value != card.title {
            card.title = value
            host.controller.updateElement(.card(card), actionName: "Edit Card Text")
        }
        remove()
        host.window?.makeFirstResponder(host)
        host.needsDisplay = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finish(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finish(commit: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finish(commit: false)
            return true
        }
        return false
    }

    private func remove() {
        textField?.removeFromSuperview()
        textField = nil
        cardID = nil
    }
}
