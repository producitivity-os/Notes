import Foundation

enum CanvasTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

struct TextElement: CanvasElementModel {
    var id: String
    var geometry: CanvasElementGeometry
    var markdown: String
    var fontSize: Double
    var alignment: CanvasTextAlignment
    var textColor: CanvasColor
    var backgroundColor: CanvasColor
    var borderColor: CanvasColor
    var borderWidth: Double
    var cornerRadius: Double
    var padding: Double

    static func make(frame: CanvasRect, markdown: String = "Text") -> TextElement {
        TextElement(
            id: UUID().uuidString.lowercased(),
            geometry: CanvasElementGeometry(frame: frame),
            markdown: markdown,
            fontSize: 18,
            alignment: .leading,
            textColor: .text,
            backgroundColor: .clear,
            borderColor: .clear,
            borderWidth: 0,
            cornerRadius: 8,
            padding: 8
        )
    }
}
