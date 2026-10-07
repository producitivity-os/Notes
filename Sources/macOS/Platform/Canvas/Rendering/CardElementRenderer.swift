import AppKit

@MainActor
final class CardElementRenderer: CanvasElementRenderer {
    func supports(_ element: CanvasElementRecord) -> Bool {
        if case .card = element { return true }
        return false
    }

    func draw(_ element: CanvasElementRecord, context: CanvasDrawingContext) {
        guard case let .card(card) = element else { return }
        let frame = card.geometry.frame.cgRect
        NSColor.white.setFill()
        let shape = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
        shape.fill()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        guard context.depth < 2 else { return }
        context.graphics.saveGState()
        shape.addClip()
        context.drawScene(card.front, card.sideSize, frame.insetBy(dx: 2, dy: 2), context.depth + 1)
        context.graphics.restoreGState()
        guard !card.title.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: card.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )
        let titleFrame = frame.insetBy(dx: 14, dy: 0)
        let measured = title.boundingRect(
            with: CGSize(width: titleFrame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        title.draw(in: CGRect(
            x: titleFrame.minX,
            y: frame.midY - measured.height / 2,
            width: titleFrame.width,
            height: measured.height
        ))
    }

    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool {
        element.geometry.frame.contains(point)
    }
}
