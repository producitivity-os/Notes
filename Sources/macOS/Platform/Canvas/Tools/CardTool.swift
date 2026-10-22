import Foundation

@MainActor
final class CardTool: BoxCreationTool {
    init() { super.init(defaultSize: CanvasSize(width: 520, height: 320)) }

    override func makeElement(frame: CanvasRect) -> CanvasElementRecord {
        .card(.make(frame: frame))
    }
}
