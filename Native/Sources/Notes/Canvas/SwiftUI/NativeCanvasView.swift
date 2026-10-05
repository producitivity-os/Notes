import AppKit
import Combine

@MainActor
final class NativeCanvasView: NSView {
    let controller: NativeCanvasController
    var viewport = CanvasViewport()
    var transientBox: CanvasRect?
    var transientArrow: (CanvasPoint, CanvasPoint)?
    var transientMarquee: CanvasRect?

    private let sceneRenderer = CanvasSceneRenderer()
    private let overlayRenderer = CanvasOverlayRenderer()
    private let textEditor = TextEditOverlay()
    private var cancellables: Set<AnyCancellable> = []
    private var tools: [CanvasToolKind: any CanvasTool] = [:]
    private var interactionContext: CanvasInteractionContext!
    private var activeInteractionTool: (any CanvasTool)?
    private var hasFittedPage = false
    private var spaceHeld = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(controller: NativeCanvasController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Notebook page canvas")
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        interactionContext = CanvasInteractionContext(view: self, controller: controller)
        tools = [
            .select: SelectTool(),
            .pan: PanTool(),
            .text: TextTool(),
            .card: CardTool(),
            .image: ImageTool(),
            .arrow: ArrowTool(),
        ]
        controller.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }.store(in: &cancellables)
        controller.selection.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }.store(in: &cancellables)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller.undoManager = window?.undoManager
        window?.acceptsMouseMovedEvents = true
    }

    override func layout() {
        super.layout()
        if !hasFittedPage, bounds.width > 0, bounds.height > 0 {
            fitPage()
            hasFittedPage = true
        }
        textEditor.layout()
    }

    func resetForPage() {
        textEditor.finish(commit: true)
        hasFittedPage = false
        needsLayout = true
        needsDisplay = true
    }

    func fitPage() {
        viewport.fit(pageSize: controller.pageSize.cgSize, in: bounds.size)
        textEditor.layout()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        let pageRect = viewport.viewRect(fromWorld: CGRect(origin: .zero, size: controller.pageSize.cgSize))
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: 5)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(rect: pageRect).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let graphics = NSGraphicsContext.current?.cgContext else { return }
        sceneRenderer.draw(
            scene: controller.scene,
            pageSize: controller.pageSize,
            destination: pageRect,
            graphics: graphics,
            assetData: { [weak controller] hash in controller?.assetData(hash: hash) }
        )
        overlayRenderer.draw(
            scene: controller.scene,
            selection: controller.selection.ids,
            viewport: viewport,
            marquee: transientMarquee,
            transientBox: transientBox,
            transientArrow: transientArrow
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = worldPoint(for: event)
        let kind: CanvasToolKind = spaceHeld ? .pan : controller.activeTool
        activeInteractionTool = tools[kind]
        activeInteractionTool?.mouseDown(at: point, event: event, context: interactionContext)
    }

    override func mouseDragged(with event: NSEvent) {
        activeInteractionTool?.mouseDragged(to: worldPoint(for: event), event: event, context: interactionContext)
    }

    override func mouseUp(with event: NSEvent) {
        activeInteractionTool?.mouseUp(at: worldPoint(for: event), event: event, context: interactionContext)
        activeInteractionTool = nil
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        activeInteractionTool = tools[.pan]
        activeInteractionTool?.mouseDown(at: worldPoint(for: event), event: event, context: interactionContext)
    }

    override func otherMouseDragged(with event: NSEvent) {
        activeInteractionTool?.mouseDragged(to: worldPoint(for: event), event: event, context: interactionContext)
    }

    override func otherMouseUp(with event: NSEvent) {
        activeInteractionTool?.mouseUp(at: worldPoint(for: event), event: event, context: interactionContext)
        activeInteractionTool = nil
    }

    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        viewport.zoom(by: 1 + event.magnification, around: location)
        textEditor.layout()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            viewport.offset.x += event.scrollingDeltaX
            viewport.offset.y += event.scrollingDeltaY
        } else {
            let location = convert(event.locationInWindow, from: nil)
            viewport.zoom(by: exp(-event.scrollingDeltaY * 0.04), around: location)
        }
        textEditor.layout()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = true
            NSCursor.openHand.set()
            return
        }
        if event.keyCode == 53 {
            activeInteractionTool?.cancel(context: interactionContext)
            textEditor.finish(commit: false)
            return
        }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": copySelection(); return
            case "v": pasteSelection(); return
            case "d": duplicateSelection(); return
            default: break
            }
        }
        switch event.keyCode {
        case 51, 117: controller.deleteSelection()
        case 36, 76: editSelectedElement()
        case 123: nudge(dx: -1, dy: 0, event: event)
        case 124: nudge(dx: 1, dy: 0, event: event)
        case 125: nudge(dx: 0, dy: 1, event: event)
        case 126: nudge(dx: 0, dy: -1, event: event)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": controller.activeTool = .select
            case "t": controller.activeTool = .text
            case "c": controller.activeTool = .card
            case "i": controller.activeTool = .image
            case "a": controller.activeTool = .arrow
            default: super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            NSCursor.arrow.set()
        } else {
            super.keyUp(with: event)
        }
    }

    func hitTestElement(at point: CanvasPoint) -> CanvasElementRecord? {
        sceneRenderer.hitTest(scene: controller.scene, point: point, assetData: { [weak controller] hash in controller?.assetData(hash: hash) })
    }

    func resizeHandle(at point: CanvasPoint) -> String? {
        overlayRenderer.resizeHandle(scene: controller.scene, selection: controller.selection.ids, point: point, viewport: viewport)
    }

    func rotationHandle(at point: CanvasPoint) -> String? {
        overlayRenderer.rotationHandle(scene: controller.scene, selection: controller.selection.ids, point: point, viewport: viewport)
    }

    func arrowEndpoint(at point: CanvasPoint) -> (id: String, isStart: Bool)? {
        overlayRenderer.arrowEndpoint(scene: controller.scene, selection: controller.selection.ids, point: point, viewport: viewport)
    }

    func beginEditingText(_ id: String) {
        guard case let .text(text)? = controller.scene.element(id: id) else { return }
        controller.selection.selectOnly(id)
        textEditor.begin(element: text, in: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = worldPoint(for: event)
        if let hit = hitTestElement(at: point), !controller.selection.ids.contains(hit.id) {
            controller.selection.selectOnly(hit.id)
        }
        guard !controller.selection.ids.isEmpty else { return nil }
        let menu = NSMenu()
        menu.addItem(withTitle: "Edit", action: #selector(editSelection), keyEquivalent: "")
        menu.addItem(withTitle: "Duplicate", action: #selector(duplicateSelectionAction), keyEquivalent: "")
        if case .text? = controller.selectedElement { addTextControls(to: menu) }
        if case .arrow? = controller.selectedElement { addArrowControls(to: menu) }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Bring to Front", action: #selector(bringToFront), keyEquivalent: "")
        menu.addItem(withTitle: "Send to Back", action: #selector(sendToBack), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Delete", action: #selector(deleteSelectionAction), keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func editSelection() { editSelectedElement() }
    @objc private func duplicateSelectionAction() { duplicateSelection() }
    @objc private func deleteSelectionAction() { controller.deleteSelection() }
    @objc private func bringToFront() { reorderSelection(toFront: true) }
    @objc private func sendToBack() { reorderSelection(toFront: false) }

    @objc private func setArrowRouting(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let routing = ArrowRoutingStyle(rawValue: raw) else { return }
        controller.mutateSelectedElement(actionName: "Change Arrow Route") { element in
            guard case var .arrow(arrow) = element else { return }
            arrow.routing = routing
            element = .arrow(arrow)
        }
    }

    @objc private func setArrowHead(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let head = ArrowHeadStyle(rawValue: raw) else { return }
        controller.mutateSelectedElement(actionName: "Change Arrowhead") { element in
            guard case var .arrow(arrow) = element else { return }
            arrow.head = head
            element = .arrow(arrow)
        }
    }

    @objc private func setTextAlignment(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let alignment = CanvasTextAlignment(rawValue: raw) else { return }
        controller.mutateSelectedElement(actionName: "Align Text") { element in
            guard case var .text(text) = element else { return }
            text.alignment = alignment
            element = .text(text)
        }
    }

    @objc private func setTextSize(_ sender: NSMenuItem) {
        let size = Double(sender.tag)
        controller.mutateSelectedElement(actionName: "Change Text Size") { element in
            guard case var .text(text) = element else { return }
            text.fontSize = size
            element = .text(text)
        }
    }

    @objc private func setTextBackground(_ sender: NSMenuItem) {
        let colors: [CanvasColor] = [
            .clear,
            .white,
            CanvasColor(red: 0.88, green: 0.94, blue: 1, alpha: 1),
        ]
        guard colors.indices.contains(sender.tag) else { return }
        controller.mutateSelectedElement(actionName: "Change Text Background") { element in
            guard case var .text(text) = element else { return }
            text.backgroundColor = colors[sender.tag]
            element = .text(text)
        }
    }

    @objc private func toggleTextBorder() {
        controller.mutateSelectedElement(actionName: "Toggle Text Border") { element in
            guard case var .text(text) = element else { return }
            let enabled = text.borderWidth == 0
            text.borderWidth = enabled ? 1 : 0
            text.borderColor = enabled ? CanvasColor(red: 0.72, green: 0.74, blue: 0.78, alpha: 1) : .clear
            element = .text(text)
        }
    }

    private func worldPoint(for event: NSEvent) -> CanvasPoint {
        let view = convert(event.locationInWindow, from: nil)
        let world = viewport.worldPoint(fromView: view)
        return CanvasPoint(x: world.x, y: world.y)
    }

    private func editSelectedElement() {
        guard controller.selection.ids.count == 1, let id = controller.selection.ids.first,
              let element = controller.scene.element(id: id) else { return }
        switch element {
        case .text: beginEditingText(id)
        case .card: controller.requestCardEditor(for: id)
        default: break
        }
    }

    private func addArrowControls(to menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())
        let routeMenu = NSMenu()
        [("Straight", ArrowRoutingStyle.straight), ("Curved", .curved), ("Orthogonal", .orthogonal)].forEach { title, value in
            let item = routeMenu.addItem(withTitle: title, action: #selector(setArrowRouting(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
        }
        let route = NSMenuItem(title: "Path", action: nil, keyEquivalent: "")
        route.submenu = routeMenu
        menu.addItem(route)

        let headMenu = NSMenu()
        [("None", ArrowHeadStyle.none), ("Filled", .triangle), ("Open", .openTriangle)].forEach { title, value in
            let item = headMenu.addItem(withTitle: title, action: #selector(setArrowHead(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
        }
        let head = NSMenuItem(title: "Arrowhead", action: nil, keyEquivalent: "")
        head.submenu = headMenu
        menu.addItem(head)
    }

    private func addTextControls(to menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())
        let alignmentMenu = NSMenu()
        [("Left", CanvasTextAlignment.leading), ("Center", .center), ("Right", .trailing)].forEach { title, value in
            let item = alignmentMenu.addItem(withTitle: title, action: #selector(setTextAlignment(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
        }
        let alignment = NSMenuItem(title: "Alignment", action: nil, keyEquivalent: "")
        alignment.submenu = alignmentMenu
        menu.addItem(alignment)

        let sizeMenu = NSMenu()
        [("Small", 14), ("Body", 18), ("Large", 28), ("Heading", 38)].forEach { title, size in
            let item = sizeMenu.addItem(withTitle: title, action: #selector(setTextSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = size
        }
        let size = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
        size.submenu = sizeMenu
        menu.addItem(size)

        let backgroundMenu = NSMenu()
        ["None", "White", "Blue"].enumerated().forEach { index, title in
            let item = backgroundMenu.addItem(withTitle: title, action: #selector(setTextBackground(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
        }
        let background = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        background.submenu = backgroundMenu
        menu.addItem(background)

        let border = menu.addItem(withTitle: "Toggle Border", action: #selector(toggleTextBorder), keyEquivalent: "")
        border.target = self
    }

    private func nudge(dx: Double, dy: Double, event: NSEvent) {
        let multiplier = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        var updated = controller.scene
        for index in updated.elements.indices where controller.selection.ids.contains(updated.elements[index].id) {
            var element = updated.elements[index]
            if case var .arrow(arrow) = element {
                arrow.start.point.x += dx * multiplier
                arrow.start.point.y += dy * multiplier
                arrow.end.point.x += dx * multiplier
                arrow.end.point.y += dy * multiplier
                arrow.start.attachment = nil
                arrow.end.attachment = nil
                arrow.refreshBounds()
                element = .arrow(arrow)
            } else {
                var geometry = element.geometry
                geometry.frame.x += dx * multiplier
                geometry.frame.y += dy * multiplier
                geometry.frame = geometry.frame.constrained(to: controller.pageSize)
                element.geometry = geometry
            }
            updated.elements[index] = element
        }
        if updated != controller.scene { controller.commit(updated, actionName: "Nudge") }
    }

    private func copySelection() {
        let elements = controller.scene.elements.filter { controller.selection.ids.contains($0.id) }
        guard let data = try? NotebookCoding.encoder.encode(elements) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: NSPasteboard.PasteboardType("com.productivity-os.notes.canvas-elements"))
    }

    private func pasteSelection() {
        let type = NSPasteboard.PasteboardType("com.productivity-os.notes.canvas-elements")
        guard let data = NSPasteboard.general.data(forType: type),
              let values = try? NotebookCoding.decoder.decode([CanvasElementRecord].self, from: data) else { return }
        let copies = duplicate(values)
        var updated = controller.scene
        updated.elements.append(contentsOf: copies)
        controller.selection.select(Set(copies.map(\.id)))
        controller.commit(updated, actionName: "Paste")
    }

    private func duplicateSelection() {
        let values = controller.scene.elements.filter { controller.selection.ids.contains($0.id) }
        guard !values.isEmpty else { return }
        let copies = duplicate(values)
        var updated = controller.scene
        updated.elements.append(contentsOf: copies)
        controller.selection.select(Set(copies.map(\.id)))
        controller.commit(updated, actionName: "Duplicate")
    }

    private func duplicate(_ values: [CanvasElementRecord]) -> [CanvasElementRecord] {
        let mapping = Dictionary(uniqueKeysWithValues: values.map { ($0.id, UUID().uuidString.lowercased()) })
        return values.map { value in
            var copy = value
            var geometry = copy.geometry
            geometry.frame.x += 16
            geometry.frame.y += 16
            geometry.frame = geometry.frame.constrained(to: controller.pageSize)
            copy.geometry = geometry
            switch copy {
            case var .text(text): text.id = mapping[value.id]!; return .text(text)
            case var .image(image): image.id = mapping[value.id]!; return .image(image)
            case var .card(card): card.id = mapping[value.id]!; return .card(card)
            case var .arrow(arrow):
                arrow.id = mapping[value.id]!
                if let id = arrow.start.attachment?.elementID { arrow.start.attachment?.elementID = mapping[id] ?? id }
                if let id = arrow.end.attachment?.elementID { arrow.end.attachment?.elementID = mapping[id] ?? id }
                arrow.start.point.x += 16; arrow.start.point.y += 16
                arrow.end.point.x += 16; arrow.end.point.y += 16
                arrow.refreshBounds()
                return .arrow(arrow)
            }
        }
    }

    private func reorderSelection(toFront: Bool) {
        let selected = controller.scene.elements.filter { controller.selection.ids.contains($0.id) }
        var others = controller.scene.elements.filter { !controller.selection.ids.contains($0.id) }
        if toFront { others.append(contentsOf: selected) } else { others.insert(contentsOf: selected, at: 0) }
        var updated = controller.scene
        updated.elements = others
        controller.commit(updated, actionName: toFront ? "Bring to Front" : "Send to Back")
    }
}
