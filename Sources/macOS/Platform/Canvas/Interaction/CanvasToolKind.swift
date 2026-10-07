import Foundation

enum CanvasToolKind: String, CaseIterable, Identifiable {
    case select
    case pan
    case text
    case card
    case image
    case arrow

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select: "arrow.up.left"
        case .pan: "hand.draw"
        case .text: "textformat"
        case .card: "rectangle.on.rectangle"
        case .image: "photo"
        case .arrow: "arrow.up.right"
        }
    }

    var resourceIconName: String? {
        switch self {
        case .select: "pointer"
        case .text: "markdown"
        case .card: "square"
        case .arrow: "link"
        default: nil
        }
    }

    static let toolbarTools: [CanvasToolKind] = [.select, .text, .card, .image, .arrow]

    var label: String { rawValue.capitalized }
}
