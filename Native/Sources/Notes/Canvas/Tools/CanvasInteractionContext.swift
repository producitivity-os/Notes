import AppKit

@MainActor
final class CanvasInteractionContext {
    unowned let view: NativeCanvasView
    let controller: NativeCanvasController

    init(view: NativeCanvasView, controller: NativeCanvasController) {
        self.view = view
        self.controller = controller
    }

    var scene: CanvasSceneDocument { controller.scene }
    var pageSize: CanvasSize { controller.pageSize }

    func hitTest(_ point: CanvasPoint) -> CanvasElementRecord? { view.hitTestElement(at: point) }
    func redraw() { view.needsDisplay = true }
}
