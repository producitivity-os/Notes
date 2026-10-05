import Foundation

struct ImageElement: CanvasElementModel {
    var id: String
    var geometry: CanvasElementGeometry
    var assetHash: String
    var preservesAspectRatio: Bool
    var accessibilityLabel: String

    static func make(frame: CanvasRect, assetHash: String, label: String) -> ImageElement {
        ImageElement(
            id: UUID().uuidString.lowercased(),
            geometry: CanvasElementGeometry(frame: frame),
            assetHash: assetHash,
            preservesAspectRatio: true,
            accessibilityLabel: label
        )
    }
}
