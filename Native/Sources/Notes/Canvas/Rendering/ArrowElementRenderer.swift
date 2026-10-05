import AppKit

@MainActor
final class ArrowElementRenderer: CanvasElementRenderer {
    func supports(_ element: CanvasElementRecord) -> Bool {
        if case .arrow = element { return true }
        return false
    }

    func draw(_ element: CanvasElementRecord, context: CanvasDrawingContext) {
        guard case let .arrow(arrow) = element else { return }
        let start = resolved(arrow.start, in: context.scene).cgPoint
        let end = resolved(arrow.end, in: context.scene).cgPoint
        let path = path(for: arrow.routing, start: start, end: end)
        let graphics = context.graphics
        graphics.setStrokeColor(NSColor(canvasColor: arrow.color).cgColor)
        graphics.setLineWidth(arrow.lineWidth)
        graphics.setLineCap(.round)
        graphics.setLineJoin(.round)
        graphics.addPath(path)
        graphics.strokePath()
        drawHead(arrow.head, at: end, from: pointBeforeEnd(for: arrow.routing, start: start, end: end), arrow: arrow, graphics: graphics)
    }

    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool {
        guard case let .arrow(arrow) = element else { return false }
        let start = resolved(arrow.start, in: context.scene).cgPoint
        let end = resolved(arrow.end, in: context.scene).cgPoint
        return distance(from: point.cgPoint, toSegmentFrom: start, to: end) <= max(6, arrow.lineWidth + 4)
    }

    private func resolved(_ endpoint: ArrowEndpoint, in scene: CanvasSceneDocument) -> CanvasPoint {
        endpoint.attachment.flatMap { CanvasGeometry.attachmentPoint($0, in: scene) } ?? endpoint.point
    }

    private func path(for style: ArrowRoutingStyle, start: CGPoint, end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        switch style {
        case .straight:
            path.addLine(to: end)
        case .curved:
            let distance = hypot(end.x - start.x, end.y - start.y)
            let bend = min(120, distance * 0.35)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + bend, y: start.y),
                control2: CGPoint(x: end.x - bend, y: end.y)
            )
        case .orthogonal:
            let middleX = (start.x + end.x) / 2
            path.addLine(to: CGPoint(x: middleX, y: start.y))
            path.addLine(to: CGPoint(x: middleX, y: end.y))
            path.addLine(to: end)
        }
        return path
    }

    private func pointBeforeEnd(for style: ArrowRoutingStyle, start: CGPoint, end: CGPoint) -> CGPoint {
        switch style {
        case .straight: start
        case .curved: CGPoint(x: end.x - min(120, hypot(end.x - start.x, end.y - start.y) * 0.35), y: end.y)
        case .orthogonal: CGPoint(x: (start.x + end.x) / 2, y: end.y)
        }
    }

    private func drawHead(_ style: ArrowHeadStyle, at end: CGPoint, from previous: CGPoint, arrow: ArrowElement, graphics: CGContext) {
        guard style != .none else { return }
        let angle = atan2(end.y - previous.y, end.x - previous.x)
        let size = max(8, arrow.lineWidth * 4)
        let left = CGPoint(x: end.x - cos(angle - .pi / 6) * size, y: end.y - sin(angle - .pi / 6) * size)
        let right = CGPoint(x: end.x - cos(angle + .pi / 6) * size, y: end.y - sin(angle + .pi / 6) * size)
        graphics.beginPath()
        graphics.move(to: end)
        graphics.addLine(to: left)
        if style == .triangle { graphics.addLine(to: right); graphics.closePath() } else { graphics.move(to: end); graphics.addLine(to: right) }
        if style == .triangle {
            graphics.setFillColor(NSColor(canvasColor: arrow.color).cgColor)
            graphics.fillPath()
        } else {
            graphics.strokePath()
        }
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}
