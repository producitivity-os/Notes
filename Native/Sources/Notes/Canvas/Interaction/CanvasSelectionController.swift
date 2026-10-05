import Foundation

@MainActor
final class CanvasSelectionController: ObservableObject {
    @Published private(set) var ids: Set<String> = []

    func selectOnly(_ id: String?) {
        ids = id.map { [$0] } ?? []
    }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    func select(_ values: Set<String>) { ids = values }
    func clear() { ids.removeAll() }
}
