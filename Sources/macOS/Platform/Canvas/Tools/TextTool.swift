import Foundation

@MainActor
final class TextTool: BoxCreationTool {
    init() { super.init(defaultSize: CanvasSize(width: 260, height: 120)) }

    override func makeElement(frame: CanvasRect) -> CanvasElementRecord {
        .text(.make(frame: frame))
    }
}
