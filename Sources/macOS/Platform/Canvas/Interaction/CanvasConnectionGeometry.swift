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
        scene.attachmentPoint(for: attachment)
    }

    /// Resolves a drop to a visible named anchor first, then to the precise
    /// point inside the frontmost element under the pointer.
    static func attachment(
        to point: CanvasPoint,
        in scene: CanvasSceneDocument,
        excluding excludedID: String? = nil,
        maximumDistance: Double = 18
    ) -> ArrowAttachment? {
        if let named = nearestAttachment(
            to: point,
            in: scene,
            excluding: excludedID,
            maximumDistance: maximumDistance
        ) {
            return named
        }

        for element in scene.elements.reversed()
        where element.acceptsArrowAttachment && element.id != excludedID {
            let frame = element.geometry.frame.cgRect
            guard frame.width > 0, frame.height > 0 else { continue }
            let local = rotated(
                point.cgPoint,
                around: CGPoint(x: frame.midX, y: frame.midY),
                degrees: -element.geometry.rotation
            )
            guard frame.contains(local) else { continue }
            return ArrowAttachment(
                elementID: element.id,
                edge: .center,
                position: 0.5,
                normalizedPoint: CanvasPoint(
                    x: (local.x - frame.minX) / frame.width,
                    y: (local.y - frame.minY) / frame.height
                )
            )
        }
        return nil
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
                (.center, CGPoint(x: frame.midX, y: frame.midY)),
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
