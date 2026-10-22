import AppKit
import SwiftMath

@MainActor
final class MathRenderer {
    /// Canvas content is routinely magnified while editing. Keep substantially
    /// more backing pixels than logical points so formulas remain crisp.
    static let backingScale: CGFloat = 4
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
        let pixelsWide = max(1, Int(ceil(measured.width * Self.backingScale)))
        let pixelsHigh = max(1, Int(ceil(measured.height * Self.backingScale)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = measured
        label.cacheDisplay(in: label.bounds, to: bitmap)
        let maximumWidth = max(40, maximumWidth)
        let resultSize = measured.width > maximumWidth
            ? CGSize(width: maximumWidth, height: measured.height * maximumWidth / measured.width)
            : measured
        bitmap.size = resultSize
        let result = NSImage(size: resultSize)
        result.addRepresentation(bitmap)
        cache[key] = result
        return result
    }
}
