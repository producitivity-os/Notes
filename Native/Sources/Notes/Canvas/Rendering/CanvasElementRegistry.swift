import AppKit

@MainActor
final class CanvasElementRegistry {
    private let renderers: [any CanvasElementRenderer]

    init(markdownRenderer: MarkdownRenderer) {
        renderers = [
            TextElementRenderer(),
            ImageElementRenderer(),
            CardElementRenderer(),
            ArrowElementRenderer(),
        ]
    }

    func draw(_ element: CanvasElementRecord, context: CanvasDrawingContext) {
        guard let renderer = renderers.first(where: { $0.supports(element) }) else { return }
        let geometry = element.geometry
        context.graphics.saveGState()
        context.graphics.setAlpha(CGFloat(geometry.opacity))
        if geometry.rotation != 0 {
            let center = geometry.frame.center.cgPoint
            context.graphics.translateBy(x: center.x, y: center.y)
            context.graphics.rotate(by: CGFloat(geometry.rotation * .pi / 180))
            context.graphics.translateBy(x: -center.x, y: -center.y)
        }
        renderer.draw(element, context: context)
        context.graphics.restoreGState()
    }

    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool {
        guard let renderer = renderers.first(where: { $0.supports(element) }) else { return false }
        let center = element.geometry.frame.center.cgPoint
        let unrotated = CanvasGeometry.rotated(point.cgPoint, around: center, degrees: -element.geometry.rotation)
        return renderer.hitTest(element, point: CanvasPoint(x: unrotated.x, y: unrotated.y), context: context)
    }
}
