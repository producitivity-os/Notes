import AppKit

extension NSColor {
    convenience init(canvasColor: CanvasColor) {
        self.init(
            calibratedRed: canvasColor.red,
            green: canvasColor.green,
            blue: canvasColor.blue,
            alpha: canvasColor.alpha
        )
    }
}
