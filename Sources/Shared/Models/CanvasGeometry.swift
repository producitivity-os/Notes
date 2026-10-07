import CoreGraphics
import Foundation

struct CanvasPoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    static let zero = CanvasPoint(x: 0, y: 0)

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct CanvasSize: Codable, Equatable, Hashable, Sendable {
    var width: Double
    var height: Double

    var cgSize: CGSize { CGSize(width: width, height: height) }
}

struct CanvasRect: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var center: CanvasPoint { CanvasPoint(x: x + width / 2, y: y + height / 2) }

    func contains(_ point: CanvasPoint) -> Bool { cgRect.contains(point.cgPoint) }

    func constrained(to size: CanvasSize) -> CanvasRect {
        let boundedWidth = min(max(width, 24), size.width)
        let boundedHeight = min(max(height, 24), size.height)
        return CanvasRect(
            x: min(max(0, x), max(0, size.width - boundedWidth)),
            y: min(max(0, y), max(0, size.height - boundedHeight)),
            width: boundedWidth,
            height: boundedHeight
        )
    }
}

struct CanvasColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let clear = CanvasColor(red: 0, green: 0, blue: 0, alpha: 0)
    static let text = CanvasColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
    static let accent = CanvasColor(red: 0.12, green: 0.45, blue: 0.96, alpha: 1)
    static let white = CanvasColor(red: 1, green: 1, blue: 1, alpha: 1)
}

struct CanvasElementGeometry: Codable, Equatable, Hashable, Sendable {
    var frame: CanvasRect
    var rotation: Double = 0
    var opacity: Double = 1
    var locked: Bool = false
}
