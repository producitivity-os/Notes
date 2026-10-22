import Foundation

struct CardFace: Codable, Equatable, Identifiable, Sendable {
    static let currentPreviewRendererVersion = 1

    var id: String
    var name: String
    var scene: CanvasSceneDocument
    var previewRevision: Int
    var previewRendererVersion: Int?

    init(
        id: String,
        name: String,
        scene: CanvasSceneDocument,
        previewRevision: Int,
        previewRendererVersion: Int? = currentPreviewRendererVersion
    ) {
        self.id = id
        self.name = name
        self.scene = scene
        self.previewRevision = previewRevision
        self.previewRendererVersion = previewRendererVersion
    }

    static func make(name: String, id: String = UUID().uuidString.lowercased()) -> CardFace {
        CardFace(id: id, name: name, scene: .blank(), previewRevision: 0)
    }
}

struct CardElement: CanvasElementModel {
    static let frontFaceID = "front"
    static let backFaceID = "back"
    static let contentPadding = 10.0

    var id: String
    var geometry: CanvasElementGeometry
    var title: String
    var faces: [CardFace]

    /// The face shown on the notebook canvas. Face order is persisted so old
    /// cards keep their existing visible side while new cards begin on Back.
    var displayFace: CardFace {
        faces.first ?? .make(name: "Back", id: Self.backFaceID)
    }

    var frontFace: CardFace? {
        faces.first(where: {
            $0.id == Self.frontFaceID || $0.name.caseInsensitiveCompare("Front") == .orderedSame
        })
    }

    var hasFrontFace: Bool { frontFace != nil }

    var hasBackFace: Bool {
        faces.contains { $0.id == Self.backFaceID || $0.name.caseInsensitiveCompare("Back") == .orderedSame }
    }

    static func make(frame: CanvasRect) -> CardElement {
        CardElement(
            id: UUID().uuidString.lowercased(),
            geometry: CanvasElementGeometry(frame: frame),
            title: "",
            faces: [.make(name: "Back", id: backFaceID)]
        )
    }

    mutating func addFrontFace() -> String {
        if let existing = frontFace { return existing.id }
        let face = CardFace.make(name: "Front", id: Self.frontFaceID)
        faces.append(face)
        return face.id
    }

    /// Kept for decoding and manipulating cards created by earlier versions.
    mutating func addBackFace() -> String {
        if let existing = faces.first(where: {
            $0.id == Self.backFaceID || $0.name.caseInsensitiveCompare("Back") == .orderedSame
        }) {
            return existing.id
        }
        let face = CardFace.make(name: "Back", id: Self.backFaceID)
        faces.append(face)
        return face.id
    }

    mutating func updateFace(id: String, scene: CanvasSceneDocument) {
        guard let index = faces.firstIndex(where: { $0.id == id }) else { return }
        faces[index].scene = scene
        faces[index].previewRevision += 1
        faces[index].previewRendererVersion = CardFace.currentPreviewRendererVersion
        if index == 0 { fitToDisplayContent() }
    }

    mutating func fitToDisplayContent() {
        guard let bounds = displayFace.scene.contentBounds else { return }
        geometry.frame.width = bounds.width + Self.contentPadding * 2
        geometry.frame.height = bounds.height + Self.contentPadding * 2
    }

    func contentSize(for face: CardFace) -> CanvasSize {
        guard let bounds = face.scene.contentBounds else { return geometry.frame.size }
        return CanvasSize(
            width: bounds.width + Self.contentPadding * 2,
            height: bounds.height + Self.contentPadding * 2
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, geometry, title, faces
        case sideSize, front, back, previewRevision
    }

    init(id: String, geometry: CanvasElementGeometry, title: String, faces: [CardFace]) {
        self.id = id
        self.geometry = geometry
        self.title = title
        self.faces = faces.isEmpty ? [.make(name: "Back", id: Self.backFaceID)] : faces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        geometry = try container.decode(CanvasElementGeometry.self, forKey: .geometry)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""

        if let decodedFaces = try container.decodeIfPresent([CardFace].self, forKey: .faces), !decodedFaces.isEmpty {
            faces = decodedFaces
            return
        }

        let revision = try container.decodeIfPresent(Int.self, forKey: .previewRevision) ?? 0
        let front = try container.decodeIfPresent(CanvasSceneDocument.self, forKey: .front) ?? .blank()
        faces = [CardFace(
            id: Self.frontFaceID,
            name: "Front",
            scene: front,
            previewRevision: revision,
            previewRendererVersion: nil
        )]
        if let back = try container.decodeIfPresent(CanvasSceneDocument.self, forKey: .back), !back.elements.isEmpty {
            faces.append(CardFace(
                id: Self.backFaceID,
                name: "Back",
                scene: back,
                previewRevision: revision,
                previewRendererVersion: nil
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(title, forKey: .title)
        try container.encode(faces, forKey: .faces)
    }
}
