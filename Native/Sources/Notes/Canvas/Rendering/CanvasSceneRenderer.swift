import AppKit

@MainActor
final class CanvasSceneRenderer {
    let markdownRenderer = MarkdownRenderer()
    lazy var registry = CanvasElementRegistry(markdownRenderer: markdownRenderer)

    func draw(
        scene: CanvasSceneDocument,
        pageSize: CanvasSize,
        destination: CGRect,
        graphics: CGContext,
        assetData: @escaping (String) -> Data?,
        depth: Int = 0
    ) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        graphics.saveGState()
        graphics.translateBy(x: destination.minX, y: destination.minY)
        graphics.scaleBy(x: destination.width / pageSize.width, y: destination.height / pageSize.height)
        graphics.clip(to: CGRect(origin: .zero, size: pageSize.cgSize))
        let context = CanvasDrawingContext(
            graphics: graphics,
            scene: scene,
            assetData: assetData,
            markdownRenderer: markdownRenderer,
            drawScene: { [weak self] nested, size, target, nestedDepth in
                self?.draw(scene: nested, pageSize: size, destination: target, graphics: graphics, assetData: assetData, depth: nestedDepth)
            },
            depth: depth
        )
        for element in scene.elements { registry.draw(element, context: context) }
        graphics.restoreGState()
    }

    func hitTest(
        scene: CanvasSceneDocument,
        point: CanvasPoint,
        assetData: @escaping (String) -> Data?
    ) -> CanvasElementRecord? {
        guard let graphics = NSGraphicsContext.current?.cgContext ?? CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let context = CanvasDrawingContext(
            graphics: graphics,
            scene: scene,
            assetData: assetData,
            markdownRenderer: markdownRenderer,
            drawScene: { _, _, _, _ in },
            depth: 0
        )
        let frontToBack = Array(scene.elements.reversed())
        return frontToBack.first { registry.hitTest($0, point: point, context: context) }
    }
}
