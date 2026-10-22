import AppKit

@MainActor
final class TextEditorStyler {
    func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.drawsBackground = false
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.insertionPointColor = .controlAccentColor
    }

    func apply(element: TextElement, scale: CGFloat, to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: max(1, element.fontSize * scale), weight: .regular)
        let color = NSColor(canvasColor: element.textColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]

        textView.font = font
        textView.textColor = color
        textView.typingAttributes = attributes
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }
}
