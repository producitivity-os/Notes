import Foundation

struct CanvasSceneDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var schemaVersion: Int
    var elements: [CanvasElementRecord]

    static func blank() -> CanvasSceneDocument {
        CanvasSceneDocument(schemaVersion: currentVersion, elements: [])
    }

    func element(id: String) -> CanvasElementRecord? {
        elements.first { $0.id == id }
    }

    mutating func replace(_ element: CanvasElementRecord) {
        guard let index = elements.firstIndex(where: { $0.id == element.id }) else {
            elements.append(element)
            return
        }
        elements[index] = element
    }

    mutating func remove(ids: Set<String>) {
        elements.removeAll { ids.contains($0.id) }
        for index in elements.indices {
            guard case var .arrow(arrow) = elements[index] else { continue }
            if let target = arrow.start.attachment?.elementID, ids.contains(target) { arrow.start.attachment = nil }
            if let target = arrow.end.attachment?.elementID, ids.contains(target) { arrow.end.attachment = nil }
            elements[index] = .arrow(arrow)
        }
    }
}
