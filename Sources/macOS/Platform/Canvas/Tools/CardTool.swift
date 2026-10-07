import Foundation

@MainActor
final class CardTool: BoxCreationTool {
    init() { super.init(defaultSize: CanvasSize(width: 320, height: 190)) }

    override func makeElement(frame: CanvasRect) -> CanvasElementRecord {
        .card(.make(frame: frame))
    }
}
