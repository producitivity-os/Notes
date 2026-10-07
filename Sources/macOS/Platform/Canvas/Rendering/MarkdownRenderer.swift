import AppKit

@MainActor
final class MarkdownRenderer {
    private enum Segment {
        case markdown(String)
        case math(String, display: Bool)
    }

    private let mathRenderer = MathRenderer()
    private var cache: [String: NSAttributedString] = [:]

    func attributedString(markdown: String, fontSize: CGFloat, color: NSColor, maximumWidth: CGFloat) -> NSAttributedString {
        let key = "\(markdown)|\(fontSize)|\(color.description)|\(maximumWidth)"
        if let cached = cache[key] { return cached }
        let result = NSMutableAttributedString()
        for segment in segments(in: markdown) {
            switch segment {
            case let .markdown(source):
                result.append(nativeMarkdown(source, fontSize: fontSize, color: color))
            case let .math(source, display):
                if display, result.length > 0, result.string.last != "\n" { result.append(NSAttributedString(string: "\n")) }
                if let image = mathRenderer.image(
                    latex: source,
                    fontSize: fontSize,
                    color: color,
                    display: display,
                    maximumWidth: maximumWidth
                ) {
                    let attachment = NSTextAttachment()
                    attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    result.append(NSAttributedString(string: display ? "$$\(source)$$" : "$\(source)$"))
                }
                if display { result.append(NSAttributedString(string: "\n")) }
            }
        }
        cache[key] = result
        return result
    }

    private func nativeMarkdown(_ source: String, fontSize: CGFloat, color: NSColor) -> NSAttributedString {
        let converted: NSAttributedString
        if let value = try? AttributedString(markdown: source) {
            converted = NSAttributedString(value)
        } else {
            converted = NSAttributedString(string: source)
        }
        let mutable = NSMutableAttributedString(attributedString: converted)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.foregroundColor, value: color, range: range)
        mutable.enumerateAttribute(.font, in: range) { value, subrange, _ in
            if value == nil { mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: subrange) }
        }
        if mutable.length > 0, mutable.attribute(.font, at: 0, effectiveRange: nil) == nil {
            mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize), range: range)
        }
        return mutable
    }

    private func segments(in source: String) -> [Segment] {
        var result: [Segment] = []
        var cursor = source.startIndex
        var plainStart = cursor
        while cursor < source.endIndex {
            guard source[cursor] == "$", !isEscaped(cursor, in: source) else {
                cursor = source.index(after: cursor)
                continue
            }
            let second = source.index(after: cursor)
            let display = second < source.endIndex && source[second] == "$"
            let delimiterLength = display ? 2 : 1
            let contentStart = source.index(cursor, offsetBy: delimiterLength)
            guard let close = closingDelimiter(in: source, from: contentStart, display: display) else {
                cursor = source.index(after: cursor)
                continue
            }
            if plainStart < cursor { result.append(.markdown(String(source[plainStart..<cursor]))) }
            result.append(.math(String(source[contentStart..<close]), display: display))
            cursor = source.index(close, offsetBy: delimiterLength)
            plainStart = cursor
        }
        if plainStart < source.endIndex { result.append(.markdown(String(source[plainStart...]))) }
        return result.isEmpty ? [.markdown(source)] : result
    }

    private func closingDelimiter(in source: String, from start: String.Index, display: Bool) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "$", !isEscaped(cursor, in: source) {
                if !display { return cursor }
                let next = source.index(after: cursor)
                if next < source.endIndex, source[next] == "$" { return cursor }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private func isEscaped(_ index: String.Index, in source: String) -> Bool {
        guard index > source.startIndex else { return false }
        return source[source.index(before: index)] == "\\"
    }
}
