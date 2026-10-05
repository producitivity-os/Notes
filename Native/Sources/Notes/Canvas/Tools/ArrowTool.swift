import AppKit

@MainActor
final class ArrowTool: CanvasTool {
    private var start: ArrowEndpoint?

    func mouseDown(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        let attachment = CanvasGeometry.nearestAttachment(
            to: point,
            in: context.scene,
            maximumDistance: 18 / Double(context.view.viewport.scale)
        )
        let resolved = attachment.flatMap { CanvasGeometry.attachmentPoint($0, in: context.scene) } ?? point
        start = ArrowEndpoint(point: resolved, attachment: attachment)
        context.view.transientArrow = (resolved, resolved)
        context.redraw()
    }

    func mouseDragged(to point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        guard let start else { return }
        context.view.transientArrow = (start.point, point)
        context.redraw()
    }

    func mouseUp(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        guard let start else { return }
        let attachment = CanvasGeometry.nearestAttachment(
            to: point,
            in: context.scene,
            excluding: start.attachment?.elementID,
            maximumDistance: 18 / Double(context.view.viewport.scale)
        )
        let resolved = attachment.flatMap { CanvasGeometry.attachmentPoint($0, in: context.scene) } ?? point
        if hypot(resolved.x - start.point.x, resolved.y - start.point.y) > 2 {
            var arrow = ArrowElement.make(start: start.point, end: resolved)
            arrow.start = start
            arrow.end = ArrowEndpoint(point: resolved, attachment: attachment)
            arrow.refreshBounds()
            context.controller.addElement(.arrow(arrow), actionName: "Create Arrow")
        }
        self.start = nil
        context.view.transientArrow = nil
        context.controller.activeTool = .select
        context.redraw()
    }

    func cancel(context: CanvasInteractionContext) {
        start = nil
        context.view.transientArrow = nil
        context.redraw()
    }
}
