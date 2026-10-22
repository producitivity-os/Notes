import Foundation

@MainActor
final class CardEditorModel: ObservableObject {
    @Published private(set) var card: CardElement
    @Published private(set) var selectedFaceID: String
    @Published private(set) var isIgnoredInReview: Bool
    @Published var reviewStateError: String?
    let controller = NativeCanvasController()

    private weak var sourceController: NativeCanvasController?

    init(card: CardElement, sourceController: NativeCanvasController) {
        self.card = card
        selectedFaceID = card.faces.first?.id ?? CardElement.backFaceID
        isIgnoredInReview = sourceController.isCardIgnoredInReview(card.id)
        self.sourceController = sourceController
        loadCurrentSide()
    }

    var selectedFace: CardFace? { card.faces.first { $0.id == selectedFaceID } }
    var selectedFaceIndex: Int { card.faces.firstIndex { $0.id == selectedFaceID } ?? 0 }

    func select(faceID: String) {
        guard selectedFaceID != faceID, card.faces.contains(where: { $0.id == faceID }) else { return }
        controller.commitActiveEditing()
        selectedFaceID = faceID
        loadCurrentSide()
    }

    func selectFace(at index: Int) {
        guard card.faces.indices.contains(index) else { return }
        select(faceID: card.faces[index].id)
    }

    func addFront() {
        controller.commitActiveEditing()
        let id = card.addFrontFace()
        objectWillChange.send()
        selectedFaceID = id
        loadCurrentSide()
    }

    func toggleIgnoredInReview() {
        let updated = !isIgnoredInReview
        do {
            try sourceController?.setCard(card.id, ignoredInReview: updated)
            isIgnoredInReview = updated
        } catch {
            reviewStateError = error.localizedDescription
        }
    }

    private func loadCurrentSide() {
        guard let sourceController else { return }
        guard let face = selectedFace else { return }
        controller.loadStandalone(
            scene: face.scene,
            pageSize: card.geometry.frame.size,
            infiniteCanvas: true,
            assetData: { [weak sourceController] hash in sourceController?.assetData(hash: hash) },
            importAsset: { [weak sourceController] data, filename, mediaType in
                sourceController?.importAsset(data: data, filename: filename, mediaType: mediaType)
            },
            onCommit: { [weak self] scene in
                guard let self else { return }
                self.card.updateFace(id: self.selectedFaceID, scene: scene)
                self.objectWillChange.send()
            }
        )
    }
}
