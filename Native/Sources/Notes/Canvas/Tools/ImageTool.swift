import AppKit

@MainActor
final class ImageTool: CanvasTool {
    func mouseDown(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        context.controller.importImage(at: point)
        context.redraw()
    }
}
