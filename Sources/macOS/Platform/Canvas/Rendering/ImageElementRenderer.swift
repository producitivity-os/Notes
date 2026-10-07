import AppKit

@MainActor
final class ImageElementRenderer: CanvasElementRenderer {
    private var cache: [String: NSImage] = [:]

    func supports(_ element: CanvasElementRecord) -> Bool {
        if case .image = element { return true }
        return false
    }

    func draw(_ element: CanvasElementRecord, context: CanvasDrawingContext) {
        guard case let .image(imageElement) = element else { return }
        let image: NSImage?
        if let cached = cache[imageElement.assetHash] {
            image = cached
        } else if let data = context.assetData(imageElement.assetHash), let loaded = NSImage(data: data) {
            cache[imageElement.assetHash] = loaded
            image = loaded
        } else {
            image = nil
        }
        let frame = imageElement.geometry.frame.cgRect
        guard let image else {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
            NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: "Missing image")?
                .draw(in: frame.insetBy(dx: frame.width * 0.3, dy: frame.height * 0.3))
            return
        }
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool {
        element.geometry.frame.contains(point)
    }
}
