import Foundation

protocol CanvasElementModel: Codable, Equatable, Identifiable, Sendable {
    var id: String { get }
    var geometry: CanvasElementGeometry { get set }
}
