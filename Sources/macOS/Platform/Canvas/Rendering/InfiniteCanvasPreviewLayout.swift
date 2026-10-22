import CoreGraphics

struct InfiniteCanvasPreviewLayout: Equatable {
    let worldBounds: CGRect
    let pageSize: CanvasSize
    let scene: CanvasSceneDocument

    static func make(
        scene: CanvasSceneDocument,
        fallbackSize: CanvasSize,
        padding: CGFloat = 56,
        minimumSize: CGSize = CGSize(width: 360, height: 260)
    ) -> Self {
        guard let contentBounds = scene.contentBounds?.cgRect else {
            let width = max(minimumSize.width, fallbackSize.width)
            let height = max(minimumSize.height, fallbackSize.height)
            let bounds = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            return .init(
                worldBounds: bounds,
                pageSize: CanvasSize(width: width, height: height),
                scene: scene
            )
        }

        var bounds = contentBounds.insetBy(dx: -padding, dy: -padding)
        if bounds.width < minimumSize.width {
            bounds = bounds.insetBy(dx: -(minimumSize.width - bounds.width) / 2, dy: 0)
        }
        if bounds.height < minimumSize.height {
            bounds = bounds.insetBy(dx: 0, dy: -(minimumSize.height - bounds.height) / 2)
        }
        let translated = scene.translatedBy(x: -bounds.minX, y: -bounds.minY)
        return .init(
            worldBounds: bounds,
            pageSize: CanvasSize(width: bounds.width, height: bounds.height),
            scene: translated
        )
    }
}
