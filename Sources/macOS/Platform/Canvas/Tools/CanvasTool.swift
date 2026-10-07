import AppKit

@MainActor
protocol CanvasTool: AnyObject {
    func mouseDown(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext)
    func mouseDragged(to point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext)
    func mouseUp(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext)
    func cancel(context: CanvasInteractionContext)
}

extension CanvasTool {
    func mouseDragged(to point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {}
    func mouseUp(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {}
    func cancel(context: CanvasInteractionContext) {}
}
