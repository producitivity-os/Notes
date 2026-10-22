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
        NSColor(calibratedWhite: 0.46, alpha: 1).setStroke()
        shape.lineWidth = 1.5
        shape.stroke()
        guard context.depth < 2 else { return }
        let face = card.displayFace
        guard let contentBounds = face.scene.contentBounds else {
            drawTitle(card, in: frame)
            return
        }
        context.graphics.saveGState()
        shape.addClip()
        let translated = face.scene.translatedBy(
            x: -contentBounds.x + CardElement.contentPadding,
            y: -contentBounds.y + CardElement.contentPadding
        )
        let sourceSize = card.contentSize(for: face)
        context.drawScene(translated, sourceSize, frame, context.depth + 1)
        context.graphics.restoreGState()
    }

    private func drawTitle(_ card: CardElement, in frame: CGRect) {
        guard !card.title.isEmpty, card.title != "Card" else { return }
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
