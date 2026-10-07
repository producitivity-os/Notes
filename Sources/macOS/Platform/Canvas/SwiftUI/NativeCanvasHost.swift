import SwiftUI

struct NativeCanvasHost: NSViewRepresentable {
    @ObservedObject var controller: NativeCanvasController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NativeCanvasView {
        context.coordinator.loadGeneration = controller.loadGeneration
        return NativeCanvasView(controller: controller)
    }

    func updateNSView(_ view: NativeCanvasView, context: Context) {
        if context.coordinator.loadGeneration != controller.loadGeneration {
            context.coordinator.loadGeneration = controller.loadGeneration
            view.resetForPage()
        }
        view.needsDisplay = true
    }

    final class Coordinator {
        var loadGeneration = -1
    }
}
