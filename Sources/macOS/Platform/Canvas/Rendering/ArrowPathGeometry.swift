import CoreGraphics

enum ArrowPathGeometry {
    static func resolved(_ endpoint: ArrowEndpoint, in scene: CanvasSceneDocument) -> CGPoint {
        (endpoint.attachment.flatMap { CanvasGeometry.attachmentPoint($0, in: scene) } ?? endpoint.point).cgPoint
    }

    static func bendPoint(for arrow: ArrowElement, in scene: CanvasSceneDocument) -> CGPoint {
        if let bendPoint = arrow.bendPoint { return bendPoint.cgPoint }
        let start = resolved(arrow.start, in: scene)
        let end = resolved(arrow.end, in: scene)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        guard arrow.routing == .curved else { return midpoint }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return midpoint }
        let offset = min(64, length * 0.2)
        return CGPoint(x: midpoint.x - dy / length * offset, y: midpoint.y + dx / length * offset)
    }

    static func path(
        routing: ArrowRoutingStyle,
        start: CGPoint,
        end: CGPoint,
        bendPoint: CGPoint
    ) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        switch routing {
        case .straight:
            path.addLine(to: end)
        case .curved:
            path.addQuadCurve(to: end, control: curveControl(start: start, end: end, bendPoint: bendPoint))
        case .orthogonal:
            let middleX = (start.x + end.x) / 2
            path.addLine(to: CGPoint(x: middleX, y: start.y))
            path.addLine(to: CGPoint(x: middleX, y: end.y))
            path.addLine(to: end)
        }
        return path
    }

    static func pointBeforeEnd(
        routing: ArrowRoutingStyle,
        start: CGPoint,
        end: CGPoint,
        bendPoint: CGPoint
    ) -> CGPoint {
        switch routing {
        case .straight:
            return start
        case .curved:
            return curveControl(start: start, end: end, bendPoint: bendPoint)
        case .orthogonal:
            return CGPoint(x: (start.x + end.x) / 2, y: end.y)
        }
    }

    static func sampledPoints(
        for arrow: ArrowElement,
        in scene: CanvasSceneDocument,
        curveSegments: Int = 32
    ) -> [CGPoint] {
        let start = resolved(arrow.start, in: scene)
        let end = resolved(arrow.end, in: scene)
        switch arrow.routing {
        case .straight:
            return [start, end]
        case .curved:
            let control = curveControl(start: start, end: end, bendPoint: bendPoint(for: arrow, in: scene))
            return (0...max(2, curveSegments)).map { index in
                let t = CGFloat(index) / CGFloat(max(2, curveSegments))
                let inverse = 1 - t
                return CGPoint(
                    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
                )
            }
        case .orthogonal:
            let middleX = (start.x + end.x) / 2
            return [
                start,
                CGPoint(x: middleX, y: start.y),
                CGPoint(x: middleX, y: end.y),
                end,
            ]
        }
    }

    static func curveControl(start: CGPoint, end: CGPoint, bendPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: 2 * bendPoint.x - (start.x + end.x) / 2,
            y: 2 * bendPoint.y - (start.y + end.y) / 2
        )
    }
}
