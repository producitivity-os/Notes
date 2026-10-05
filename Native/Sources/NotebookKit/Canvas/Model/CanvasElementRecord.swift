import Foundation

indirect enum CanvasElementRecord: Codable, Equatable, Identifiable, Sendable {
    case text(TextElement)
    case image(ImageElement)
    case card(CardElement)
    case arrow(ArrowElement)

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable { case text, image, card, arrow }

    var id: String {
        switch self {
        case let .text(value): value.id
        case let .image(value): value.id
        case let .card(value): value.id
        case let .arrow(value): value.id
        }
    }

    var geometry: CanvasElementGeometry {
        get {
            switch self {
            case let .text(value): value.geometry
            case let .image(value): value.geometry
            case let .card(value): value.geometry
            case let .arrow(value): value.geometry
            }
        }
        set {
            switch self {
            case var .text(value): value.geometry = newValue; self = .text(value)
            case var .image(value): value.geometry = newValue; self = .image(value)
            case var .card(value): value.geometry = newValue; self = .card(value)
            case var .arrow(value): value.geometry = newValue; self = .arrow(value)
            }
        }
    }

    var acceptsArrowAttachment: Bool {
        if case .arrow = self { return false }
        return true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text: self = .text(try container.decode(TextElement.self, forKey: .payload))
        case .image: self = .image(try container.decode(ImageElement.self, forKey: .payload))
        case .card: self = .card(try container.decode(CardElement.self, forKey: .payload))
        case .arrow: self = .arrow(try container.decode(ArrowElement.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .payload)
        case let .image(value):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(value, forKey: .payload)
        case let .card(value):
            try container.encode(Kind.card, forKey: .kind)
            try container.encode(value, forKey: .payload)
        case let .arrow(value):
            try container.encode(Kind.arrow, forKey: .kind)
            try container.encode(value, forKey: .payload)
        }
    }
}
