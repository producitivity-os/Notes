import AppKit

struct RenderedTextLayout {
    let attributedString: NSAttributedString
    let renderedBounds: CGRect?
}

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
        let layout = Self.layout(for: text, markdownRenderer: context.markdownRenderer)
        layout.attributedString.draw(with: content, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool {
        guard case let .text(text) = element else { return false }
        guard let bounds = Self.layout(for: text, markdownRenderer: context.markdownRenderer).renderedBounds else {
            return text.geometry.frame.contains(point)
        }
        return bounds.insetBy(dx: -4, dy: -4).contains(point.cgPoint)
    }

    static func layout(for text: TextElement, markdownRenderer: MarkdownRenderer) -> RenderedTextLayout {
        let frame = text.geometry.frame.cgRect
        let content = frame.insetBy(dx: text.padding, dy: text.padding)
        let attributed = NSMutableAttributedString(attributedString: markdownRenderer.attributedString(
            markdown: text.markdown,
            fontSize: text.fontSize,
            color: NSColor(canvasColor: text.textColor),
            maximumWidth: max(1, content.width)
        ))
        let style = NSMutableParagraphStyle()
        style.alignment = switch text.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attributed.length))

        guard attributed.length > 0, content.width > 0, content.height > 0 else {
            return RenderedTextLayout(attributedString: attributed, renderedBounds: nil)
        }

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: content.width, height: content.height))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let source = attributed.string as NSString
        var visibleLength = source.length
        while visibleLength > 0 {
            let scalar = source.character(at: visibleLength - 1)
            guard let unicode = UnicodeScalar(scalar), CharacterSet.whitespacesAndNewlines.contains(unicode) else { break }
            visibleLength -= 1
        }
        guard visibleLength > 0 else {
            return RenderedTextLayout(attributedString: attributed, renderedBounds: nil)
        }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: visibleLength),
            actualCharacterRange: nil
        )
        var bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        bounds.origin.x += content.minX
        bounds.origin.y += content.minY
        bounds = bounds.intersection(content)
        return RenderedTextLayout(
            attributedString: attributed,
            renderedBounds: bounds.isNull || bounds.isEmpty ? nil : bounds
        )
    }
}
