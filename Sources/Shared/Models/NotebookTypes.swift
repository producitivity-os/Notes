import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let productivityNotebook = UTType(exportedAs: "com.productivity-os.notebook", conformingTo: .package)
}

enum NotebookFormat {
    static let currentVersion = 2
    static let manifestName = "manifest.json"
    static let pagesDirectory = "pages"
    static let assetsDirectory = "assets"
    static let previewsDirectory = "previews"
    static let coverPreviewPath = "previews/cover.png"
    static let defaultWidth = 794.0
    static let defaultHeight = 1123.0
}

enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    init(any value: Any) throws {
        switch value {
        case is NSNull: self = .null
        case let value as Bool: self = .bool(value)
        case let value as NSNumber: self = .number(value.doubleValue)
        case let value as String: self = .string(value)
        case let value as [Any]: self = .array(try value.map(JSONValue.init(any:)))
        case let value as [String: Any]: self = .object(try value.mapValues(JSONValue.init(any:)))
        default: throw NotebookPackageError.invalidPackage
        }
    }
}

enum NotebookPageOrientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape
}

struct NotebookPageMetadata: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var orientation: NotebookPageOrientation
    var width: Double
    var height: Double
    var revision: Int
    var createdAt: Date
    var updatedAt: Date

    static func make(title: String = "Page 1", orientation: NotebookPageOrientation = .portrait) -> Self {
        let now = Date()
        return .init(
            id: UUID().uuidString.lowercased(),
            title: title,
            orientation: orientation,
            width: orientation == .portrait ? NotebookFormat.defaultWidth : NotebookFormat.defaultHeight,
            height: orientation == .portrait ? NotebookFormat.defaultHeight : NotebookFormat.defaultWidth,
            revision: 0,
            createdAt: now,
            updatedAt: now
        )
    }
}

struct NotebookPluginRequirement: Codable, Equatable, Sendable {
    var identifier: String
    var version: String
}

struct NotebookAssetMetadata: Codable, Identifiable, Equatable, Sendable {
    var id: String { hash }
    var hash: String
    var filename: String
    var thumbnailFilename: String?
    var mediaType: String
    var byteCount: Int
    var createdAt: Date
}

struct NotebookManifest: Codable, Equatable, Sendable {
    var formatVersion: Int
    var notebookID: String
    var createdAt: Date
    var updatedAt: Date
    var pages: [NotebookPageMetadata]
    var coverPageID: String
    var requiredPlugins: [NotebookPluginRequirement]
    var assets: [NotebookAssetMetadata]

    static func blank() -> Self {
        let page = NotebookPageMetadata.make()
        let now = Date()
        return .init(
            formatVersion: NotebookFormat.currentVersion,
            notebookID: UUID().uuidString.lowercased(),
            createdAt: now,
            updatedAt: now,
            pages: [page],
            coverPageID: page.id,
            requiredPlugins: [],
            assets: []
        )
    }
}

struct NotebookPagePayload: Codable, Equatable, Sendable {
    var formatVersion: Int
    var pageID: String
    var revision: Int
    var scene: CanvasSceneDocument

    static func blank(pageID: String) -> Self {
        .init(
            formatVersion: NotebookFormat.currentVersion,
            pageID: pageID,
            revision: 0,
            scene: .blank()
        )
    }
}

struct NotebookPackage: Equatable, Sendable {
    var manifest: NotebookManifest
    var pagePayloads: [String: NotebookPagePayload]
    var assets: [String: Data]
    var previews: [String: Data]

    static func blank() -> Self {
        let manifest = NotebookManifest.blank()
        let page = manifest.pages[0]
        return .init(
            manifest: manifest,
            pagePayloads: [page.id: .blank(pageID: page.id)],
            assets: [:],
            previews: [:]
        )
    }

    mutating func normalize() throws {
        guard manifest.formatVersion == NotebookFormat.currentVersion else {
            throw NotebookPackageError.unsupportedVersion(manifest.formatVersion)
        }
        guard !manifest.pages.isEmpty else { throw NotebookPackageError.missingPages }

        var seen = Set<String>()
        for page in manifest.pages {
            guard seen.insert(page.id).inserted else {
                throw NotebookPackageError.duplicatePage(page.id)
            }
            if pagePayloads[page.id] == nil {
                pagePayloads[page.id] = .blank(pageID: page.id)
            }
            if let payload = pagePayloads[page.id] {
                guard payload.pageID == page.id else { throw NotebookPackageError.invalidPackage }
                guard payload.formatVersion == NotebookFormat.currentVersion else {
                    throw NotebookPackageError.unsupportedVersion(payload.formatVersion)
                }
                guard payload.scene.schemaVersion == CanvasSceneDocument.currentVersion else {
                    throw NotebookPackageError.unsupportedSceneVersion(payload.scene.schemaVersion)
                }
                pagePayloads[page.id] = payload
            }
        }
        pagePayloads = pagePayloads.filter { seen.contains($0.key) }
        if !seen.contains(manifest.coverPageID) {
            manifest.coverPageID = manifest.pages[0].id
        }
    }
}

enum NotebookPackageError: LocalizedError, Equatable {
    case invalidPackage
    case missingManifest
    case missingPages
    case missingPage(String)
    case duplicatePage(String)
    case unsupportedVersion(Int)
    case unsupportedSceneVersion(Int)
    case invalidAssetHash(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage: "This file is not a valid notebook package."
        case .missingManifest: "The notebook manifest is missing."
        case .missingPages: "A notebook must contain at least one page."
        case let .missingPage(id): "Page \(id) is missing."
        case let .duplicatePage(id): "The notebook contains duplicate page \(id)."
        case let .unsupportedVersion(version): "Notebook format \(version) is not supported by this native version of Notes."
        case let .unsupportedSceneVersion(version): "Canvas scene format \(version) is not supported."
        case let .invalidAssetHash(hash): "The embedded asset \(hash) is corrupt."
        }
    }
}

enum NotebookCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
