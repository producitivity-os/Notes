import Foundation

enum ArrowAnchorEdge: String, Codable, CaseIterable, Sendable {
    case center
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
    var bendPoint: CanvasPoint?
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
            bendPoint: nil,
            head: .triangle,
            color: .accent,
            lineWidth: 2
        )
    }

    mutating func refreshBounds() {
        geometry.frame = Self.bounds(start: start.point, end: end.point, bendPoint: bendPoint)
    }

    private static func bounds(start: CanvasPoint, end: CanvasPoint, bendPoint: CanvasPoint? = nil) -> CanvasRect {
        let points = [start, end] + [bendPoint].compactMap { $0 }
        let minimumX = points.map(\.x).min() ?? start.x
        let minimumY = points.map(\.y).min() ?? start.y
        let maximumX = points.map(\.x).max() ?? end.x
        let maximumY = points.map(\.y).max() ?? end.y
        return CanvasRect(
            x: minimumX,
            y: minimumY,
            width: max(1, maximumX - minimumX),
            height: max(1, maximumY - minimumY)
        )
    }
}
