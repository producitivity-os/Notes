import AppKit
import SwiftUI

@MainActor
final class NativeCanvasController: ObservableObject {
    @Published var activeTool: CanvasToolKind = .select
    @Published private(set) var scene: CanvasSceneDocument = .blank()
    @Published private(set) var pageSize = CanvasSize(width: NotebookFormat.defaultWidth, height: NotebookFormat.defaultHeight)
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var loadGeneration = 0
    @Published var cardEditorRequest: CardEditorRequest?

    let selection = CanvasSelectionController()
    weak var undoManager: UndoManager? { didSet { refreshUndoState() } }

    private weak var document: NotebookDocument?
    private(set) var pageID: String?
    private var standaloneCommit: ((CanvasSceneDocument) -> Void)?
    private var environment = CanvasEnvironment.empty
    private var previewWorkItem: DispatchWorkItem?

    func load(document: NotebookDocument, pageID: String) {
        guard let page = document.page(id: pageID), let payload = document.package.pagePayloads[pageID] else { return }
        undoManager?.removeAllActions(withTarget: self)
        self.document = document
        self.pageID = pageID
        standaloneCommit = nil
        environment = CanvasEnvironment(
            assetData: { [weak document] hash in document?.assetData(for: hash) },
            importAsset: { [weak document] data, filename, mediaType in
                document?.importAsset(data: data, originalFilename: filename, mediaType: mediaType)
            }
        )
        pageSize = CanvasSize(width: page.width, height: page.height)
        scene = payload.scene
        selection.clear()
        loadGeneration += 1
        refreshUndoState()
    }

    func loadStandalone(
        scene: CanvasSceneDocument,
        pageSize: CanvasSize,
        assetData: @escaping (String) -> Data?,
        importAsset: @escaping (Data, String, String) -> NotebookAssetMetadata?,
        onCommit: @escaping (CanvasSceneDocument) -> Void
    ) {
        undoManager?.removeAllActions(withTarget: self)
        document = nil
        pageID = nil
        self.pageSize = pageSize
        self.scene = scene
        environment = CanvasEnvironment(assetData: assetData, importAsset: importAsset)
        standaloneCommit = onCommit
        selection.clear()
        loadGeneration += 1
        refreshUndoState()
    }

    func preview(_ value: CanvasSceneDocument) {
        scene = value
    }

    func commit(_ value: CanvasSceneDocument, replacing oldValue: CanvasSceneDocument? = nil, actionName: String) {
        let previous = oldValue ?? scene
        execute(SceneMutationCommand(before: previous, after: value, actionName: actionName))
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

    func saveEditedCard(_ card: CardElement) {
        updateElement(.card(card), actionName: "Edit Card")
        if let document, let pageID {
            let renderer = CanvasPreviewRenderer()
            let candidates: [(side: String, revision: Int, data: Data)?] = [
                renderer.png(scene: card.front, pageSize: card.sideSize, assetData: { [weak self] in self?.assetData(hash: $0) })
                    .map { ("front", card.previewRevision, $0) },
                renderer.png(scene: card.back, pageSize: card.sideSize, assetData: { [weak self] in self?.assetData(hash: $0) })
                    .map { ("back", card.previewRevision, $0) },
            ]
            let values = candidates.compactMap { $0 }
            document.storeCardPreviews(pageID: pageID, cardID: card.id, previews: values)
        }
        cardEditorRequest = nil
    }

    func importImage(at point: CanvasPoint) {
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
        guard let metadata = environment.importAsset(data, filename, mediaType) else { return false }
        let imageSize = NSImage(data: data)?.size ?? CGSize(width: 240, height: 180)
        let maximum: CGFloat = 280
        let scale = min(1, maximum / max(imageSize.width, imageSize.height))
        let frame = CanvasRect(
            x: point.x,
            y: point.y,
            width: max(40, imageSize.width * scale),
            height: max(40, imageSize.height * scale)
        ).constrained(to: pageSize)
        let label = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        addElement(.image(.make(frame: frame, assetHash: metadata.hash, label: label)), actionName: "Insert Image")
        return true
    }

    func assetData(hash: String) -> Data? { environment.assetData(hash) }

    func importAsset(data: Data, filename: String, mediaType: String) -> NotebookAssetMetadata? {
        environment.importAsset(data, filename, mediaType)
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
        let item = DispatchWorkItem { [weak self, weak document] in
            guard let self, let document else { return }
            let renderer = CanvasPreviewRenderer()
            if let data = renderer.png(scene: scene, pageSize: size, assetData: { [weak self] in self?.assetData(hash: $0) }) {
                document.storePreview(pageID: pageID, data: data)
            }
        }
        previewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }
}

struct CardEditorRequest: Identifiable {
    let id = UUID()
    var card: CardElement
}
