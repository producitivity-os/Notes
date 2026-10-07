import CoreGraphics

struct CanvasViewport: Equatable {
    var scale: CGFloat = 1
    var offset: CGPoint = .zero

    mutating func fit(pageSize: CGSize, in viewportSize: CGSize, padding: CGFloat = 56) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let available = CGSize(
            width: max(1, viewportSize.width - padding * 2),
            height: max(1, viewportSize.height - padding * 2)
        )
        scale = min(available.width / pageSize.width, available.height / pageSize.height)
        scale = min(max(scale, 0.1), 8)
        offset = CGPoint(
            x: (viewportSize.width - pageSize.width * scale) / 2,
            y: (viewportSize.height - pageSize.height * scale) / 2
        )
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

    mutating func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
        let world = worldPoint(fromView: viewPoint)
        scale = min(max(scale * factor, 0.1), 8)
        offset = CGPoint(x: viewPoint.x - world.x * scale, y: viewPoint.y - world.y * scale)
    }
}
