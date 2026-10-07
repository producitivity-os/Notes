import AppKit
import SwiftMath

@MainActor
final class MathRenderer {
    private var cache: [String: NSImage] = [:]

    func image(latex: String, fontSize: CGFloat, color: NSColor, display: Bool, maximumWidth: CGFloat) -> NSImage? {
        let key = "\(latex)|\(fontSize)|\(color.description)|\(display)|\(maximumWidth)"
        if let cached = cache[key] { return cached }

        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.labelMode = display ? .display : .text
        label.textColor = color
        label.displayErrorInline = true
        let measured = label.fittingSize
        guard measured.width.isFinite, measured.height.isFinite, measured.width > 0, measured.height > 0 else { return nil }
        label.frame = CGRect(origin: .zero, size: measured)
        label.layoutSubtreeIfNeeded()
        guard let bitmap = label.bitmapImageRepForCachingDisplay(in: label.bounds) else { return nil }
        label.cacheDisplay(in: label.bounds, to: bitmap)
        let naturalImage = NSImage(size: measured)
        naturalImage.addRepresentation(bitmap)
        let maximumWidth = max(40, maximumWidth)
        let result: NSImage
        if measured.width > maximumWidth {
            let target = CGSize(width: maximumWidth, height: measured.height * maximumWidth / measured.width)
            result = NSImage(size: target, flipped: false) { rect in
                naturalImage.draw(in: rect)
                return true
            }
        } else {
            result = naturalImage
        }
        cache[key] = result
        return result
    }
}
