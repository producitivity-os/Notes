import AppKit
import SwiftUI

@MainActor
final class NativeCanvasController: ObservableObject {
    @Published var activeTool: CanvasToolKind = .select
    @Published private(set) var allowedTools = CanvasToolKind.toolbarTools
    @Published private(set) var zoomScale: CGFloat = 1
    @Published private(set) var scene: CanvasSceneDocument = .blank()
    @Published private(set) var pageSize = CanvasSize(width: NotebookFormat.defaultWidth, height: NotebookFormat.defaultHeight)
    @Published private(set) var gridPattern: NotebookGridPattern = .dots
    @Published private(set) var pageTitle = ""
    @Published private(set) var pageCreatedAt = Date()
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var loadGeneration = 0
    @Published private(set) var isStandalone = false
    @Published private(set) var isInfiniteCanvas = false
    @Published var cardEditorRequest: CardEditorRequest?

    let selection = CanvasSelectionController()
    weak var undoManager: UndoManager? { didSet { refreshUndoState() } }
    weak var canvasView: NativeCanvasView?

    private weak var document: NotebookDocument?
    private(set) var pageID: String?
    private var standaloneCommit: ((CanvasSceneDocument) -> Void)?
    private var environment = CanvasEnvironment.empty
    private var previewWorkItem: DispatchWorkItem?

    func load(document: NotebookDocument, pageID: String) {
        guard let page = document.page(id: pageID), let payload = document.package.pagePayloads[pageID] else { return }
        previewWorkItem?.cancel()
        undoManager?.removeAllActions(withTarget: self)
        self.document = document
        self.pageID = pageID
        isStandalone = false
        isInfiniteCanvas = true
        standaloneCommit = nil
        allowedTools = CanvasToolKind.toolbarTools
        activeTool = .select
        environment = CanvasEnvironment(
            assetData: { [weak document] hash in document?.assetData(for: hash) },
            importAsset: { [weak document] data, filename, mediaType in
                document?.importAsset(data: data, originalFilename: filename, mediaType: mediaType)
            }
        )
        pageSize = CanvasSize(width: page.width, height: page.height)
        gridPattern = page.resolvedGridPattern
        pageTitle = page.title
        pageCreatedAt = page.createdAt
        scene = payload.scene.synchronizedArrowAttachments()
        selection.clear()
        loadGeneration += 1
        refreshUndoState()
        schedulePreview()
    }

    func loadStandalone(
        scene: CanvasSceneDocument,
        pageSize: CanvasSize,
        infiniteCanvas: Bool = true,
        assetData: @escaping (String) -> Data?,
        importAsset: @escaping (Data, String, String) -> NotebookAssetMetadata?,
        onCommit: @escaping (CanvasSceneDocument) -> Void
    ) {
        undoManager?.removeAllActions(withTarget: self)
        document = nil
        pageID = nil
        isStandalone = true
        isInfiniteCanvas = infiniteCanvas
        allowedTools = CanvasToolKind.cardEditorTools
        activeTool = .select
        self.pageSize = pageSize
        gridPattern = .grid
        pageTitle = ""
        pageCreatedAt = .now
        self.scene = scene.synchronizedArrowAttachments()
        environment = CanvasEnvironment(assetData: assetData, importAsset: importAsset)
        standaloneCommit = onCommit
        selection.clear()
        loadGeneration += 1
        refreshUndoState()
    }

    func preview(_ value: CanvasSceneDocument) {
        scene = value.synchronizedArrowAttachments()
    }

    func commit(_ value: CanvasSceneDocument, replacing oldValue: CanvasSceneDocument? = nil, actionName: String) {
        let previous = (oldValue ?? scene).synchronizedArrowAttachments()
        let current = value.synchronizedArrowAttachments()
        execute(SceneMutationCommand(before: previous, after: current, actionName: actionName))
    }

    func updateElement(_ element: CanvasElementRecord, actionName: String) {
        var updated = scene
        updated.replace(element)
        commit(updated, actionName: actionName)
    }

    var selectedElement: CanvasElementRecord? {
        guard selection.ids.count == 1, let id = selection.ids.first else { return nil }
        return scene.element(id: id)
    }

    func mutateSelectedElement(actionName: String, _ change: (inout CanvasElementRecord) -> Void) {
        guard var element = selectedElement else { return }
        change(&element)
        updateElement(element, actionName: actionName)
    }

    func addElement(_ element: CanvasElementRecord, actionName: String) {
        guard canInsert(element) else { return }
        var updated = scene
        updated.elements.append(element)
        selection.selectOnly(element.id)
        commit(updated, actionName: actionName)
    }

    func deleteSelection() {
        guard !selection.ids.isEmpty else { return }
        var updated = scene
        updated.remove(ids: selection.ids)
        selection.clear()
        commit(updated, actionName: "Delete")
    }

    func requestCardEditor(for cardID: String) {
        guard case let .card(card)? = scene.element(id: cardID) else { return }
        cardEditorRequest = CardEditorRequest(card: card)
    }

    func isCardIgnoredInReview(_ cardID: String) -> Bool {
        guard let notebookID = document?.package.manifest.notebookID,
              let store = try? ReviewFileStore(),
              let schedule = try? store.reviewSchedule(notebookID: notebookID) else { return false }
        return schedule.ignoredCardIDs.contains(cardID)
    }

    func setCard(_ cardID: String, ignoredInReview: Bool) throws {
        guard let notebookID = document?.package.manifest.notebookID else {
            throw CardReviewStateError.notebookUnavailable
        }
        try ReviewFileStore().setCard(cardID, in: notebookID, ignoredInReview: ignoredInReview)
    }

    func saveEditedCard(_ card: CardElement) {
        persistEditedCard(card)
        cardEditorRequest = nil
    }

    func persistEditedCard(_ card: CardElement) {
        guard scene.element(id: card.id) != .card(card) else { return }
        updateElement(.card(card), actionName: "Edit Card")
        if let document, let pageID {
            let renderer = CanvasPreviewRenderer()
            let values = card.faces.compactMap { face -> (side: String, revision: Int, data: Data)? in
                let bounds = face.scene.contentBounds ?? CanvasRect(
                    x: 0,
                    y: 0,
                    width: card.geometry.frame.width,
                    height: card.geometry.frame.height
                )
                let size = card.contentSize(for: face)
                let translated = face.scene.translatedBy(
                    x: -bounds.x + CardElement.contentPadding,
                    y: -bounds.y + CardElement.contentPadding
                )
                return renderer.png(
                    scene: translated,
                    pageSize: size,
                    gridPattern: .blank,
                    assetData: { [weak self] in self?.assetData(hash: $0) }
                ).map { (face.id, face.previewRevision, $0) }
            }
            document.storeCardPreviews(pageID: pageID, cardID: card.id, previews: values)
        }
    }

    func importImage(at point: CanvasPoint) {
        guard allowedTools.contains(.image) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier) ?? "application/octet-stream"
        insertImage(data: data, filename: url.lastPathComponent, mediaType: type, at: point)
        activeTool = .select
    }

    @discardableResult
    func insertImage(data: Data, filename: String, mediaType: String, at point: CanvasPoint) -> Bool {
        guard allowedTools.contains(.image) else { return false }
        guard let metadata = environment.importAsset(data, filename, mediaType) else { return false }
        let imageSize = NSImage(data: data)?.size ?? CGSize(width: 240, height: 180)
        let maximum: CGFloat = 280
        let scale = min(1, maximum / max(imageSize.width, imageSize.height))
        var frame = CanvasRect(
            x: point.x,
            y: point.y,
            width: max(40, imageSize.width * scale),
            height: max(40, imageSize.height * scale)
        )
        if !isInfiniteCanvas { frame = frame.constrained(to: pageSize) }
        let label = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        addElement(.image(.make(frame: frame, assetHash: metadata.hash, label: label)), actionName: "Insert Image")
        return true
    }

    func assetData(hash: String) -> Data? { environment.assetData(hash) }

    func importAsset(data: Data, filename: String, mediaType: String) -> NotebookAssetMetadata? {
        environment.importAsset(data, filename, mediaType)
    }

    func canInsert(_ element: CanvasElementRecord) -> Bool {
        switch element {
        case .card: allowedTools.contains(.card)
        case .arrow: allowedTools.contains(.arrow)
        case .text: allowedTools.contains(.text)
        case .image: allowedTools.contains(.image)
        }
    }

    func constrainedFrame(_ frame: CanvasRect, for element: CanvasElementRecord) -> CanvasRect {
        if isInfiniteCanvas { return frame }
        if case .card = element { return frame }
        return frame.constrained(to: pageSize)
    }

    func attachCanvasView(_ view: NativeCanvasView) {
        canvasView = view
        updateZoomScale(view.viewport.scale)
    }

    func detachCanvasView(_ view: NativeCanvasView) {
        if canvasView === view { canvasView = nil }
    }

    func zoomIn() { canvasView?.zoom(by: 1.12) }
    func zoomOut() { canvasView?.zoom(by: 1 / 1.12) }
    func fitPage() { canvasView?.fitPage() }
    func commitActiveEditing() { canvasView?.commitActiveEditing() }

    func setGridPattern(_ pattern: NotebookGridPattern) {
        guard !isStandalone, pattern != gridPattern, let document, let pageID else { return }
        gridPattern = pattern
        document.setGridPattern(pattern, for: pageID)
        canvasView?.needsDisplay = true
        schedulePreview()
    }

    func updateZoomScale(_ value: CGFloat) {
        guard abs(zoomScale - value) > 0.0001 else { return }
        zoomScale = value
    }

    func undo() {
        undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        undoManager?.redo()
        refreshUndoState()
    }

    private func execute(_ command: any CanvasCommand) {
        scene = command.after
        if let pageID { _ = document?.updateScene(pageID: pageID, scene: command.after) }
        else { standaloneCommit?(command.after) }
        schedulePreview()
        undoManager?.registerUndo(withTarget: self) { target in
            target.execute(command.reversed())
        }
        undoManager?.setActionName(command.actionName)
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    private func schedulePreview() {
        guard let document, let pageID else { return }
        previewWorkItem?.cancel()
        let scene = scene
        let size = pageSize
        let pattern = gridPattern
        let title = pageTitle
        let createdAt = pageCreatedAt
        let infiniteCanvas = isInfiniteCanvas
        let item = DispatchWorkItem { [weak self, weak document] in
            guard let self, let document else { return }
            let renderer = CanvasPreviewRenderer()
            let data = if infiniteCanvas {
                renderer.pngFittingContent(
                    scene: scene,
                    fallbackSize: size,
                    gridPattern: pattern,
                    assetData: { [weak self] in self?.assetData(hash: $0) }
                )
            } else {
                renderer.png(
                    scene: scene,
                    pageSize: size,
                    gridPattern: pattern,
                    pageTitle: title,
                    pageCreatedAt: createdAt,
                    assetData: { [weak self] in self?.assetData(hash: $0) }
                )
            }
            if let data {
                document.storePreview(pageID: pageID, data: data)
            }
        }
        previewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }
}

private enum CardReviewStateError: LocalizedError {
    case notebookUnavailable

    var errorDescription: String? {
        "This card is not attached to a saved notebook."
    }
}

struct CardEditorRequest: Identifiable {
    let id = UUID()
    var card: CardElement
}
