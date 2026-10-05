import Foundation

struct CardElement: CanvasElementModel {
    var id: String
    var geometry: CanvasElementGeometry
    var title: String
    var sideSize: CanvasSize
    var front: CanvasSceneDocument
    var back: CanvasSceneDocument
    var previewRevision: Int

    static func make(frame: CanvasRect) -> CardElement {
        CardElement(
            id: UUID().uuidString.lowercased(),
            geometry: CanvasElementGeometry(frame: frame),
            title: "Card",
            sideSize: CanvasSize(width: max(240, frame.width), height: max(140, frame.height)),
            front: .blank(),
            back: .blank(),
            previewRevision: 0
        )
    }
}
