import AppKit

@MainActor
final class TextElementRenderer: CanvasElementRenderer {
    func supports(_ element: CanvasElementRecord) -> Bool {
        if case .text = element { return true }
        return false
    }

    func draw(_ element: CanvasElementRecord, context: CanvasDrawingContext) {
        guard case let .text(text) = element else { return }
        let frame = text.geometry.frame.cgRect
        let content = frame.insetBy(dx: text.padding, dy: text.padding)
        let attributed = NSMutableAttributedString(attributedString: context.markdownRenderer.attributedString(
            markdown: text.markdown,
            fontSize: text.fontSize,
            color: NSColor(canvasColor: text.textColor),
            maximumWidth: content.width
        ))
        let style = NSMutableParagraphStyle()
        style.alignment = switch text.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attributed.length))
        attributed.draw(with: content, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool {
        element.geometry.frame.contains(point)
    }
}
