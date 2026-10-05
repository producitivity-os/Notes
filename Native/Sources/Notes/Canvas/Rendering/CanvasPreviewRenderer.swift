import AppKit

@MainActor
final class CanvasPreviewRenderer {
    private let sceneRenderer = CanvasSceneRenderer()

    func png(scene: CanvasSceneDocument, pageSize: CanvasSize, assetData: @escaping (String) -> Data?, maximumPixelSize: CGFloat = 1200) -> Data? {
        let scale = min(1, maximumPixelSize / max(pageSize.width, pageSize.height))
        let imageSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let image = NSImage(size: imageSize, flipped: true) { [sceneRenderer] rect in
            NSColor.white.setFill()
            rect.fill()
            guard let graphics = NSGraphicsContext.current?.cgContext else { return false }
            sceneRenderer.draw(scene: scene, pageSize: pageSize, destination: rect, graphics: graphics, assetData: assetData)
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
