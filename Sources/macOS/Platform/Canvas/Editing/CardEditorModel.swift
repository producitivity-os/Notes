import Foundation

@MainActor
final class CardEditorModel: ObservableObject {
    enum Side: String, CaseIterable, Identifiable {
        case front = "Front"
        case back = "Back"
        var id: String { rawValue }
    }

    @Published private(set) var card: CardElement
    @Published var side: Side = .front
    let controller = NativeCanvasController()

    private weak var sourceController: NativeCanvasController?

    init(card: CardElement, sourceController: NativeCanvasController) {
        self.card = card
        self.sourceController = sourceController
        loadCurrentSide()
    }

    func select(_ side: Side) {
        guard self.side != side else { return }
        self.side = side
        loadCurrentSide()
    }

    private func loadCurrentSide() {
        guard let sourceController else { return }
        let scene = side == .front ? card.front : card.back
        controller.loadStandalone(
            scene: scene,
            pageSize: card.sideSize,
            assetData: { [weak sourceController] hash in sourceController?.assetData(hash: hash) },
            importAsset: { [weak sourceController] data, filename, mediaType in
                sourceController?.importAsset(data: data, filename: filename, mediaType: mediaType)
            },
            onCommit: { [weak self] scene in
                guard let self else { return }
                if self.side == .front { self.card.front = scene } else { self.card.back = scene }
                self.card.previewRevision += 1
                self.objectWillChange.send()
            }
        )
    }
}
