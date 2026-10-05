import AppKit

@MainActor
protocol CanvasElementRenderer: AnyObject {
    func supports(_ element: CanvasElementRecord) -> Bool
    func draw(_ element: CanvasElementRecord, context: CanvasDrawingContext)
    func hitTest(_ element: CanvasElementRecord, point: CanvasPoint, context: CanvasDrawingContext) -> Bool
}

@MainActor
struct CanvasDrawingContext {
    let graphics: CGContext
    let scene: CanvasSceneDocument
    let assetData: (String) -> Data?
    let markdownRenderer: MarkdownRenderer
    let drawScene: (CanvasSceneDocument, CanvasSize, CGRect, Int) -> Void
    let depth: Int
}
