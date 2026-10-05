import AppKit

@MainActor
final class SelectTool: CanvasTool {
    private enum Mode {
        case move(start: CanvasPoint, original: CanvasSceneDocument)
        case resize(id: String, start: CanvasPoint, original: CanvasSceneDocument)
        case rotate(id: String, original: CanvasSceneDocument)
        case endpoint(id: String, isStart: Bool, original: CanvasSceneDocument)
        case marquee(start: CanvasPoint)
    }

    private var mode: Mode?

    func mouseDown(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        let shift = event.modifierFlags.contains(.shift)
        if let endpoint = context.view.arrowEndpoint(at: point) {
            mode = .endpoint(id: endpoint.id, isStart: endpoint.isStart, original: context.scene)
            return
        }
        if let id = context.view.rotationHandle(at: point) {
            mode = .rotate(id: id, original: context.scene)
            return
        }
        if let id = context.view.resizeHandle(at: point) {
            mode = .resize(id: id, start: point, original: context.scene)
            return
        }
        if let hit = context.hitTest(point) {
            if event.clickCount == 2 {
                switch hit {
                case .text: context.view.beginEditingText(hit.id)
                case .card: context.controller.requestCardEditor(for: hit.id)
                default: break
                }
                return
            }
            if shift { context.controller.selection.toggle(hit.id) }
            else if !context.controller.selection.ids.contains(hit.id) { context.controller.selection.selectOnly(hit.id) }
            if !hit.geometry.locked { mode = .move(start: point, original: context.scene) }
        } else {
            if !shift { context.controller.selection.clear() }
            context.view.transientMarquee = CanvasRect(x: point.x, y: point.y, width: 0, height: 0)
            mode = .marquee(start: point)
        }
        context.redraw()
    }

    func mouseDragged(to point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        guard let mode else { return }
        switch mode {
        case let .move(start, original): move(from: start, to: point, original: original, context: context)
        case let .resize(id, start, original):
            resize(
                id: id,
                from: start,
                to: point,
                original: original,
                preserveAspectRatio: !event.modifierFlags.contains(.option),
                context: context
            )
        case let .rotate(id, original): rotate(id: id, to: point, original: original, context: context)
        case let .endpoint(id, isStart, original): moveEndpoint(id: id, isStart: isStart, to: point, original: original, context: context)
        case let .marquee(start): marquee(from: start, to: point, context: context)
        }
        context.redraw()
    }

    func mouseUp(at point: CanvasPoint, event: NSEvent, context: CanvasInteractionContext) {
        guard let mode else { return }
        let original: CanvasSceneDocument?
        let actionName: String
        switch mode {
        case let .move(_, value): original = value; actionName = "Move"
        case let .resize(_, _, value): original = value; actionName = "Resize"
        case let .rotate(_, value): original = value; actionName = "Rotate"
        case let .endpoint(id, isStart, value):
            original = value
            actionName = "Move Arrow Endpoint"
            bindEndpoint(id: id, isStart: isStart, at: point, context: context)
        case .marquee:
            original = nil
            actionName = "Select"
        }
        if let original, original != context.scene {
            context.controller.commit(context.scene, replacing: original, actionName: actionName)
        }
        context.view.transientMarquee = nil
        self.mode = nil
        context.redraw()
    }

    func cancel(context: CanvasInteractionContext) {
        switch mode {
        case let .move(_, original), let .resize(_, _, original), let .rotate(_, original), let .endpoint(_, _, original):
            context.controller.preview(original)
        default: break
        }
        mode = nil
        context.view.transientMarquee = nil
        context.redraw()
    }

    private func move(from start: CanvasPoint, to point: CanvasPoint, original: CanvasSceneDocument, context: CanvasInteractionContext) {
        let dx = point.x - start.x
        let dy = point.y - start.y
        var updated = original
        for index in updated.elements.indices where context.controller.selection.ids.contains(updated.elements[index].id) {
            var element = updated.elements[index]
            if case var .arrow(arrow) = element {
                arrow.start.point.x += dx
                arrow.start.point.y += dy
                arrow.end.point.x += dx
                arrow.end.point.y += dy
                arrow.start.attachment = nil
                arrow.end.attachment = nil
                arrow.refreshBounds()
                element = .arrow(arrow)
            } else {
                var geometry = element.geometry
                geometry.frame.x += dx
                geometry.frame.y += dy
                geometry.frame = geometry.frame.constrained(to: context.pageSize)
                element.geometry = geometry
            }
            updated.elements[index] = element
        }
        context.controller.preview(updated)
    }

    private func resize(
        id: String,
        from start: CanvasPoint,
        to point: CanvasPoint,
        original: CanvasSceneDocument,
        preserveAspectRatio: Bool,
        context: CanvasInteractionContext
    ) {
        guard let originalElement = original.element(id: id), !originalElement.geometry.locked else { return }
        var element = originalElement
        var geometry = element.geometry
        let proposedWidth = max(24, geometry.frame.width + point.x - start.x)
        let proposedHeight = max(24, geometry.frame.height + point.y - start.y)
        if case let .image(image) = originalElement, image.preservesAspectRatio, preserveAspectRatio {
            let ratio = max(0.01, geometry.frame.width / max(1, geometry.frame.height))
            if abs(proposedWidth - geometry.frame.width) >= abs(proposedHeight - geometry.frame.height) {
                geometry.frame.width = proposedWidth
                geometry.frame.height = max(24, proposedWidth / ratio)
            } else {
                geometry.frame.height = proposedHeight
                geometry.frame.width = max(24, proposedHeight * ratio)
            }
        } else {
            geometry.frame.width = proposedWidth
            geometry.frame.height = proposedHeight
        }
        geometry.frame = geometry.frame.constrained(to: context.pageSize)
        element.geometry = geometry
        var updated = original
        updated.replace(element)
        context.controller.preview(updated)
    }

    private func rotate(id: String, to point: CanvasPoint, original: CanvasSceneDocument, context: CanvasInteractionContext) {
        guard let originalElement = original.element(id: id), !originalElement.geometry.locked else { return }
        var element = originalElement
        let center = element.geometry.frame.center
        var geometry = element.geometry
        geometry.rotation = atan2(point.y - center.y, point.x - center.x) * 180 / .pi + 90
        element.geometry = geometry
        var updated = original
        updated.replace(element)
        context.controller.preview(updated)
    }

    private func moveEndpoint(id: String, isStart: Bool, to point: CanvasPoint, original: CanvasSceneDocument, context: CanvasInteractionContext) {
        guard case var .arrow(arrow)? = original.element(id: id) else { return }
        if isStart { arrow.start = ArrowEndpoint(point: point) } else { arrow.end = ArrowEndpoint(point: point) }
        arrow.refreshBounds()
        var updated = original
        updated.replace(.arrow(arrow))
        context.controller.preview(updated)
    }

    private func bindEndpoint(id: String, isStart: Bool, at point: CanvasPoint, context: CanvasInteractionContext) {
        guard case var .arrow(arrow)? = context.scene.element(id: id) else { return }
        let otherTarget = isStart ? arrow.end.attachment?.elementID : arrow.start.attachment?.elementID
        let attachment = CanvasGeometry.nearestAttachment(
            to: point,
            in: context.scene,
            excluding: otherTarget,
            maximumDistance: 18 / Double(context.view.viewport.scale)
        )
        let resolved = attachment.flatMap { CanvasGeometry.attachmentPoint($0, in: context.scene) } ?? point
        if isStart { arrow.start = ArrowEndpoint(point: resolved, attachment: attachment) }
        else { arrow.end = ArrowEndpoint(point: resolved, attachment: attachment) }
        arrow.refreshBounds()
        var updated = context.scene
        updated.replace(.arrow(arrow))
        context.controller.preview(updated)
    }

    private func marquee(from start: CanvasPoint, to point: CanvasPoint, context: CanvasInteractionContext) {
        let rect = CanvasRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        context.view.transientMarquee = rect
        let ids = Set(context.scene.elements.filter { rect.cgRect.intersects($0.geometry.frame.cgRect) }.map(\.id))
        context.controller.selection.select(ids)
    }
}
