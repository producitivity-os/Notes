import AppKit

@MainActor
class BoxCreationTool: CanvasTool {
    private var start: CanvasPoint?
    private let defaultSize: CanvasSize

    init(defaultSize: CanvasSize) {
        self.defaultSize = defaultSize
    }

    func makeElement(frame: CanvasRect) -> CanvasElementRecord {
        fatalError("Subclasses provide an element")
    }

    func mouseDown(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        start = point
        context.view.transientBox = CanvasRect(x: point.x, y: point.y, width: 1, height: 1)
        context.redraw()
    }

    func mouseDragged(to point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        guard let start else { return }
        context.view.transientBox = rect(from: start, to: point)
        context.redraw()
    }

    func mouseUp(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        guard let start else { return }
        var frame = rect(from: start, to: point)
        if frame.width < 12 || frame.height < 12 {
            frame = CanvasRect(x: start.x, y: start.y, width: defaultSize.width, height: defaultSize.height)
        }
        frame = frame.constrained(to: context.pageSize)
        let element = makeElement(frame: frame)
        context.controller.addElement(element, actionName: "Create \(context.controller.activeTool.label)")
        context.controller.activeTool = .select
        context.view.transientBox = nil
        self.start = nil
        context.redraw()
        if case .text = element { context.view.beginEditingText(element.id) }
    }

    func cancel(context: CanvasInteractionContext) {
        start = nil
        context.view.transientBox = nil
        context.redraw()
    }

    private func rect(from start: CanvasPoint, to end: CanvasPoint) -> CanvasRect {
        CanvasRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
