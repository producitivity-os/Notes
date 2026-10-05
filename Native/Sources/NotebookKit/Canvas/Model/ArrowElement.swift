import Foundation

enum ArrowAnchorEdge: String, Codable, CaseIterable, Sendable {
    case top
    case right
    case bottom
    case left
}

struct ArrowAttachment: Codable, Equatable, Hashable, Sendable {
    var elementID: String
    var edge: ArrowAnchorEdge
    var position: Double
}

struct ArrowEndpoint: Codable, Equatable, Hashable, Sendable {
    var point: CanvasPoint
    var attachment: ArrowAttachment?
}

enum ArrowRoutingStyle: String, Codable, CaseIterable, Sendable {
    case straight
    case curved
    case orthogonal
}

enum ArrowHeadStyle: String, Codable, CaseIterable, Sendable {
    case none
    case triangle
    case openTriangle
}

struct ArrowElement: CanvasElementModel {
    var id: String
    var geometry: CanvasElementGeometry
    var start: ArrowEndpoint
    var end: ArrowEndpoint
    var routing: ArrowRoutingStyle
    var head: ArrowHeadStyle
    var color: CanvasColor
    var lineWidth: Double

    static func make(start: CanvasPoint, end: CanvasPoint) -> ArrowElement {
        let bounds = Self.bounds(start: start, end: end)
        return ArrowElement(
            id: UUID().uuidString.lowercased(),
            geometry: CanvasElementGeometry(frame: bounds),
            start: ArrowEndpoint(point: start),
            end: ArrowEndpoint(point: end),
            routing: .straight,
            head: .triangle,
            color: .text,
            lineWidth: 2
        )
    }

    mutating func refreshBounds() {
        geometry.frame = Self.bounds(start: start.point, end: end.point)
    }

    private static func bounds(start: CanvasPoint, end: CanvasPoint) -> CanvasRect {
        CanvasRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(1, abs(end.x - start.x)),
            height: max(1, abs(end.y - start.y))
        )
    }
}
