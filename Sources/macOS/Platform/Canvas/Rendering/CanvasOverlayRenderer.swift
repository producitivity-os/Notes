import AppKit

@MainActor
final class CanvasOverlayRenderer {
    private let handleSize: CGFloat = 9

    func draw(
        scene: CanvasSceneDocument,
        selection: Set<String>,
        hoveredElementID: String?,
        hoveredAttachment: ArrowAttachment?,
        viewport: CanvasViewport,
        marquee: CanvasRect?,
        transientBox: CanvasRect?,
        transientArrow: (CanvasPoint, CanvasPoint)?
    ) {
        drawOccludedConnections(scene: scene, hoveredElementID: hoveredElementID, viewport: viewport)
        NSColor.systemBlue.setStroke()
        NSColor.systemBlue.setFill()
        for element in scene.elements {
            let isSelected = selection.contains(element.id)
            let isHovered = element.id == hoveredElementID
            guard isSelected || isHovered else { continue }
            if case let .arrow(arrow) = element {
                NSColor.systemBlue.setFill()
                circle(at: viewport.viewPoint(fromWorld: resolved(arrow.start, scene: scene).cgPoint)).fill()
                circle(at: viewport.viewPoint(fromWorld: resolved(arrow.end, scene: scene).cgPoint)).fill()
                if isSelected {
                    let bend = viewport.viewPoint(fromWorld: ArrowPathGeometry.bendPoint(for: arrow, in: scene))
                    let handle = circle(at: bend, size: 12)
                    NSColor.windowBackgroundColor.setFill()
                    handle.fill()
                    NSColor.systemBlue.setStroke()
                    handle.lineWidth = 2.5
                    handle.stroke()
                }
                continue
            }
            let frame = viewport.viewRect(fromWorld: element.geometry.frame.cgRect)
            let outline: NSBezierPath
            if case .card = element {
                let radius = 14 * viewport.scale
                outline = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
            } else {
                outline = NSBezierPath(rect: frame)
            }
            outline.lineWidth = 2.5
            outline.stroke()
            if isSelected {
                NSColor.systemBlue.setFill()
                circle(at: CGPoint(x: frame.maxX, y: frame.maxY)).fill()
                circle(at: CGPoint(x: frame.midX, y: frame.minY - 24)).fill()
            }
            for (edge, point) in connectionPoints(for: frame, rotation: element.geometry.rotation) {
                let handle = circle(at: point)
                NSColor.windowBackgroundColor.setFill()
                handle.fill()
                NSColor.systemBlue.setStroke()
                let endpointIsHovered = hoveredAttachment?.elementID == element.id && hoveredAttachment?.edge == edge
                handle.lineWidth = endpointIsHovered ? 4 : 2
                handle.stroke()
            }
        }
        if let marquee {
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            NSColor.systemBlue.setStroke()
            let shape = NSBezierPath(rect: viewport.viewRect(fromWorld: marquee.cgRect))
            shape.fill()
            shape.stroke()
        }
        if let transientBox {
            NSColor.systemBlue.withAlphaComponent(0.1).setFill()
            NSColor.systemBlue.setStroke()
            let shape = NSBezierPath(roundedRect: viewport.viewRect(fromWorld: transientBox.cgRect), xRadius: 8, yRadius: 8)
            shape.fill()
            shape.stroke()
        }
        if let transientArrow {
            let path = NSBezierPath()
            path.move(to: viewport.viewPoint(fromWorld: transientArrow.0.cgPoint))
            path.line(to: viewport.viewPoint(fromWorld: transientArrow.1.cgPoint))
            path.lineWidth = 2
            path.stroke()
        }
    }

    func resizeHandle(scene: CanvasSceneDocument, selection: Set<String>, point: CanvasPoint, viewport: CanvasViewport) -> String? {
        guard selection.count == 1, let id = selection.first,
              let element = scene.element(id: id), !isArrow(element) else { return nil }
        let frame = element.geometry.frame.cgRect
        return distance(point.cgPoint, CGPoint(x: frame.maxX, y: frame.maxY)) <= handleRadius(viewport) ? id : nil
    }

    func rotationHandle(scene: CanvasSceneDocument, selection: Set<String>, point: CanvasPoint, viewport: CanvasViewport) -> String? {
        guard selection.count == 1, let id = selection.first,
              let element = scene.element(id: id), !isArrow(element) else { return nil }
        let frame = element.geometry.frame.cgRect
        let handle = CGPoint(x: frame.midX, y: frame.minY - 24 / viewport.scale)
        return distance(point.cgPoint, handle) <= handleRadius(viewport) ? id : nil
    }

    func arrowEndpoint(scene: CanvasSceneDocument, selection: Set<String>, point: CanvasPoint, viewport: CanvasViewport) -> (id: String, isStart: Bool)? {
        guard selection.count == 1, let id = selection.first,
              case let .arrow(arrow)? = scene.element(id: id) else { return nil }
        let radius = handleRadius(viewport)
        if distance(point.cgPoint, resolved(arrow.start, scene: scene).cgPoint) <= radius { return (id, true) }
        if distance(point.cgPoint, resolved(arrow.end, scene: scene).cgPoint) <= radius { return (id, false) }
        return nil
    }

    func arrowCurveHandle(
        scene: CanvasSceneDocument,
        selection: Set<String>,
        point: CanvasPoint,
        viewport: CanvasViewport
    ) -> String? {
        guard selection.count == 1, let id = selection.first,
              case let .arrow(arrow)? = scene.element(id: id) else { return nil }
        let bend = ArrowPathGeometry.bendPoint(for: arrow, in: scene)
        return distance(point.cgPoint, bend) <= handleRadius(viewport) ? id : nil
    }

    private func resolved(_ endpoint: ArrowEndpoint, scene: CanvasSceneDocument) -> CanvasPoint {
        endpoint.attachment.flatMap { CanvasGeometry.attachmentPoint($0, in: scene) } ?? endpoint.point
    }

    private func connectionPoints(for frame: CGRect, rotation: Double) -> [(ArrowAnchorEdge, CGPoint)] {
        let points: [(ArrowAnchorEdge, CGPoint)] = [
            (.center, CGPoint(x: frame.midX, y: frame.midY)),
            (.top, CGPoint(x: frame.midX, y: frame.minY)),
            (.right, CGPoint(x: frame.maxX, y: frame.midY)),
            (.bottom, CGPoint(x: frame.midX, y: frame.maxY)),
            (.left, CGPoint(x: frame.minX, y: frame.midY)),
        ]
        return points.map { edge, point in
            (edge, CanvasGeometry.rotated(point, around: CGPoint(x: frame.midX, y: frame.midY), degrees: rotation))
        }
    }

    private func drawOccludedConnections(
        scene: CanvasSceneDocument,
        hoveredElementID: String?,
        viewport: CanvasViewport
    ) {
        guard let hoveredElementID, let hovered = scene.element(id: hoveredElementID) else { return }
        var connections: [(ArrowElement, String)] = []
        switch hovered {
        case let .arrow(arrow):
            if let cardID = attachedCardID(arrow.start, scene: scene) { connections.append((arrow, cardID)) }
            if let cardID = attachedCardID(arrow.end, scene: scene) { connections.append((arrow, cardID)) }
        case .card:
            for element in scene.elements {
                guard case let .arrow(arrow) = element else { continue }
                if arrow.start.attachment?.elementID == hoveredElementID { connections.append((arrow, hoveredElementID)) }
                if arrow.end.attachment?.elementID == hoveredElementID { connections.append((arrow, hoveredElementID)) }
            }
        default:
            return
        }

        var rendered: Set<String> = []
        for (arrow, cardID) in connections where rendered.insert("\(arrow.id):\(cardID)").inserted {
            guard case let .card(card)? = scene.element(id: cardID) else { continue }
            let frame = viewport.viewRect(fromWorld: card.geometry.frame.cgRect)
            let clip = NSBezierPath(roundedRect: frame, xRadius: 14 * viewport.scale, yRadius: 14 * viewport.scale)
            let points = ArrowPathGeometry.sampledPoints(for: arrow, in: scene).map(viewport.viewPoint(fromWorld:))
            guard let first = points.first else { continue }
            let hiddenPath = NSBezierPath()
            hiddenPath.move(to: first)
            points.dropFirst().forEach(hiddenPath.line(to:))

            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            NSColor.secondaryLabelColor.withAlphaComponent(0.42).setStroke()
            hiddenPath.lineWidth = 1.75
            hiddenPath.setLineDash([5, 4], count: 2, phase: 0)
            hiddenPath.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func attachedCardID(_ endpoint: ArrowEndpoint, scene: CanvasSceneDocument) -> String? {
        guard let id = endpoint.attachment?.elementID, case .card? = scene.element(id: id) else { return nil }
        return id
    }

    private func circle(at point: CGPoint, size: CGFloat? = nil) -> NSBezierPath {
        let size = size ?? handleSize
        return NSBezierPath(ovalIn: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
    }

    private func handleRadius(_ viewport: CanvasViewport) -> CGFloat { 10 / viewport.scale }
    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat { hypot(lhs.x - rhs.x, lhs.y - rhs.y) }
    private func isArrow(_ element: CanvasElementRecord) -> Bool { if case .arrow = element { true } else { false } }
}
