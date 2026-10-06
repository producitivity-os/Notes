import AppKit

@MainActor
final class ArrowElementRenderer: CanvasElementRenderer {
    func supports(_ element: CanvasElementRecord) -> Bool {
        if case .arrow = element { return true }
        return false
    }

    func draw(_ element: CanvasElementRecord, context: CanvasDrawingContext) {
        guard case let .arrow(arrow) = element else { return }
        let start = ArrowPathGeometry.resolved(arrow.start, in: context.scene)
        let end = ArrowPathGeometry.resolved(arrow.end, in: context.scene)
        let bendPoint = ArrowPathGeometry.bendPoint(for: arrow, in: context.scene)
        let previous = ArrowPathGeometry.pointBeforeEnd(
            routing: arrow.routing,
            start: start,
            end: end,
            bendPoint: bendPoint
        )
        let headSize = max(8, arrow.lineWidth * 4)
        let shaftEnd = shaftEnd(for: arrow.head, tip: end, previous: previous, headSize: headSize)
        let path = ArrowPathGeometry.path(
            routing: arrow.routing,
            start: start,
            end: shaftEnd,
            bendPoint: bendPoint
        )
        let graphics = context.graphics
        let color = arrow.color == .text ? CanvasColor.accent : arrow.color
        graphics.setStrokeColor(NSColor(canvasColor: color).cgColor)
        graphics.setLineWidth(arrow.lineWidth)
        graphics.setLineCap(.butt)
        graphics.setLineJoin(.round)
        graphics.addPath(path)
        graphics.strokePath()
        drawHead(arrow.head, at: end, from: previous, size: headSize, color: color, graphics: graphics)
    }

    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool {
        guard case let .arrow(arrow) = element else { return false }
        let points = ArrowPathGeometry.sampledPoints(for: arrow, in: context.scene)
        let threshold = max(7, arrow.lineWidth + 5)
        return zip(points, points.dropFirst()).contains { start, end in
            distance(from: point.cgPoint, toSegmentFrom: start, to: end) <= threshold
        }
    }

    private func shaftEnd(
        for style: ArrowHeadStyle,
        tip: CGPoint,
        previous: CGPoint,
        headSize: CGFloat
    ) -> CGPoint {
        guard style == .triangle else { return tip }
        let dx = tip.x - previous.x
        let dy = tip.y - previous.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return tip }
        let baseDistance = min(headSize * cos(.pi / 6), distance * 0.8)
        return CGPoint(
            x: tip.x - dx / distance * baseDistance,
            y: tip.y - dy / distance * baseDistance
        )
    }

    private func drawHead(
        _ style: ArrowHeadStyle,
        at end: CGPoint,
        from previous: CGPoint,
        size: CGFloat,
        color: CanvasColor,
        graphics: CGContext
    ) {
        guard style != .none else { return }
        let angle = atan2(end.y - previous.y, end.x - previous.x)
        let left = CGPoint(x: end.x - cos(angle - .pi / 6) * size, y: end.y - sin(angle - .pi / 6) * size)
        let right = CGPoint(x: end.x - cos(angle + .pi / 6) * size, y: end.y - sin(angle + .pi / 6) * size)
        graphics.beginPath()
        graphics.move(to: end)
        graphics.addLine(to: left)
        if style == .triangle { graphics.addLine(to: right); graphics.closePath() } else { graphics.move(to: end); graphics.addLine(to: right) }
        if style == .triangle {
            graphics.setFillColor(NSColor(canvasColor: color).cgColor)
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
