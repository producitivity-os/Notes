import SwiftUI

struct NativeCanvasHost: NSViewRepresentable {
    @ObservedObject var controller: NativeCanvasController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NativeCanvasView {
        context.coordinator.loadGeneration = controller.loadGeneration
        let view = NativeCanvasView(controller: controller)
        controller.attachCanvasView(view)
        return view
    }

    func updateNSView(_ view: NativeCanvasView, context: Context) {
        if context.coordinator.loadGeneration != controller.loadGeneration {
            context.coordinator.loadGeneration = controller.loadGeneration
            view.resetForPage()
        }
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: NativeCanvasView, coordinator: Coordinator) {
        view.controller.detachCanvasView(view)
    }

    final class Coordinator {
        var loadGeneration = -1
    }
}
