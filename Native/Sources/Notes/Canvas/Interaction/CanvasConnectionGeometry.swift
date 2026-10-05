import CoreGraphics

enum CanvasGeometry {
    static func rotated(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let radians = CGFloat(degrees * .pi / 180)
        let translated = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let cosine = cos(radians)
        let sine = sin(radians)
        return CGPoint(
            x: center.x + translated.x * cosine - translated.y * sine,
            y: center.y + translated.x * sine + translated.y * cosine
        )
    }

    static func attachmentPoint(_ attachment: ArrowAttachment, in scene: CanvasSceneDocument) -> CanvasPoint? {
        guard let target = scene.element(id: attachment.elementID) else { return nil }
        let frame = target.geometry.frame.cgRect
        let t = CGFloat(min(max(attachment.position, 0), 1))
        let unrotated: CGPoint
        switch attachment.edge {
        case .top: unrotated = CGPoint(x: frame.minX + frame.width * t, y: frame.minY)
        case .right: unrotated = CGPoint(x: frame.maxX, y: frame.minY + frame.height * t)
        case .bottom: unrotated = CGPoint(x: frame.minX + frame.width * t, y: frame.maxY)
        case .left: unrotated = CGPoint(x: frame.minX, y: frame.minY + frame.height * t)
        }
        let value = rotated(unrotated, around: CGPoint(x: frame.midX, y: frame.midY), degrees: target.geometry.rotation)
        return CanvasPoint(x: value.x, y: value.y)
    }

    static func nearestAttachment(
        to point: CanvasPoint,
        in scene: CanvasSceneDocument,
        excluding excludedID: String? = nil,
        maximumDistance: Double = 18
    ) -> ArrowAttachment? {
        var best: (attachment: ArrowAttachment, distance: Double)?
        for element in scene.elements where element.acceptsArrowAttachment && element.id != excludedID {
            let frame = element.geometry.frame.cgRect
            let candidates: [(ArrowAnchorEdge, CGPoint)] = [
                (.top, CGPoint(x: frame.midX, y: frame.minY)),
                (.right, CGPoint(x: frame.maxX, y: frame.midY)),
                (.bottom, CGPoint(x: frame.midX, y: frame.maxY)),
                (.left, CGPoint(x: frame.minX, y: frame.midY)),
            ]
            for (edge, candidate) in candidates {
                let rotatedPoint = rotated(candidate, around: CGPoint(x: frame.midX, y: frame.midY), degrees: element.geometry.rotation)
                let distance = hypot(rotatedPoint.x - point.x, rotatedPoint.y - point.y)
                if distance <= maximumDistance, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                    best = (ArrowAttachment(elementID: element.id, edge: edge, position: 0.5), distance)
                }
            }
        }
        return best?.attachment
    }
}
