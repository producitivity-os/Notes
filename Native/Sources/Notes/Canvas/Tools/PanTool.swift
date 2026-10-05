import AppKit

@MainActor
final class PanTool: CanvasTool {
    private var lastViewPoint: CGPoint?

    func mouseDown(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        lastViewPoint = context.view.convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    func mouseDragged(to point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        let current = context.view.convert(event.locationInWindow, from: nil)
        guard let last = lastViewPoint else { return }
        context.view.viewport.offset.x -= current.x - last.x
        context.view.viewport.offset.y -= current.y - last.y
        lastViewPoint = current
        context.redraw()
    }

    func mouseUp(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        lastViewPoint = nil
        NSCursor.openHand.set()
    }

    func cancel(context: CanvasInteractionContext) { lastViewPoint = nil }
}
