import Foundation

enum CanvasTextAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

struct TextElement: CanvasElementModel {
    static let defaultFontSize = 8.0

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

    static func make(frame: CanvasRect, markdown: String = "") -> TextElement {
        TextElement(
            id: UUID().uuidString.lowercased(),
            geometry: CanvasElementGeometry(frame: frame),
            markdown: markdown,
            fontSize: defaultFontSize,
            alignment: .leading,
            textColor: .text,
            backgroundColor: .clear,
            borderColor: .clear,
            borderWidth: 0,
            cornerRadius: 4,
            padding: 4
        )
    }
}
