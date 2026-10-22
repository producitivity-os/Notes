import CoreGraphics

struct CanvasViewport: Equatable {
    var scale: CGFloat = 1
    var offset: CGPoint = .zero

    mutating func fit(pageSize: CGSize, in viewportSize: CGSize, padding: CGFloat = 56) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        scale = Self.fittingScale(pageSize: pageSize, in: viewportSize, padding: padding)
        offset = CGPoint(
            x: (viewportSize.width - pageSize.width * scale) / 2,
            y: (viewportSize.height - pageSize.height * scale) / 2
        )
    }

    mutating func fit(worldRect: CGRect, in viewportSize: CGSize, padding: CGFloat = 56) {
        guard worldRect.width > 0, worldRect.height > 0 else { return }
        scale = Self.fittingScale(pageSize: worldRect.size, in: viewportSize, padding: padding)
        offset = CGPoint(
            x: (viewportSize.width - worldRect.width * scale) / 2 - worldRect.minX * scale,
            y: (viewportSize.height - worldRect.height * scale) / 2 - worldRect.minY * scale
        )
    }

    static func fittingScale(pageSize: CGSize, in viewportSize: CGSize, padding: CGFloat = 56) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0 else { return 0.1 }
        let available = CGSize(
            width: max(1, viewportSize.width - padding * 2),
            height: max(1, viewportSize.height - padding * 2)
        )
        return min(max(min(available.width / pageSize.width, available.height / pageSize.height), 0.1), 8)
    }

    func viewPoint(fromWorld point: CGPoint) -> CGPoint {
        CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
    }

    func worldPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    func viewRect(fromWorld rect: CGRect) -> CGRect {
        CGRect(
            x: offset.x + rect.origin.x * scale,
            y: offset.y + rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    mutating func pan(byViewTranslation translation: CGPoint) {
        offset.x += translation.x
        offset.y += translation.y
    }

    mutating func zoom(by factor: CGFloat, around viewPoint: CGPoint, minimumScale: CGFloat = 0.1) {
        let world = worldPoint(fromView: viewPoint)
        scale = min(max(scale * factor, minimumScale), 8)
        offset = CGPoint(x: viewPoint.x - world.x * scale, y: viewPoint.y - world.y * scale)
    }
}
