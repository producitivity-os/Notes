import AppKit
import Foundation
import SQLite3

struct LegacyMigrationResult: Sendable {
    var imported: Int
    var skipped: Int
}

struct LegacyNotebookMigrator: Sendable {
    let databaseURL: URL
    let destinationURL: URL
    let reviewStoreURL: URL?

    init(databaseURL: URL, destinationURL: URL, reviewStoreURL: URL? = nil) {
        self.databaseURL = databaseURL
        self.destinationURL = destinationURL
        self.reviewStoreURL = reviewStoreURL
    }

    func run() async throws -> LegacyMigrationResult {
        try await Task.detached {
            let database = try LegacySQLiteDatabase(url: databaseURL)
            let stateURL = destinationURL.appendingPathComponent(".notes-migration-state.json")
            var state = (try? LegacyMigrationState.read(from: stateURL)) ?? .init(completedNotebookIDs: [])
            var result = LegacyMigrationResult(imported: 0, skipped: 0)
            let reviewStore = try reviewStoreURL.map { try ReviewFileStore(rootURL: $0) } ?? ReviewFileStore()

            for notebook in try database.notebooks() {
                if state.completedNotebookIDs.contains(notebook.id) {
                    result.skipped += 1
                    continue
                }
                let package = try database.package(for: notebook)
                let projectFolder = destinationURL.appendingPathComponent(Self.safeFilename(notebook.project.isEmpty ? "Notebooks" : notebook.project), isDirectory: true)
                try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
                if let existing = Self.existingNotebook(id: notebook.id, in: projectFolder) {
                    let existingPackage = try NotebookPackageIO.read(at: existing)
                    try reviewStore.register(notebookURL: existing, manifest: existingPackage.manifest)
                    try database.migrateReviewData(for: notebook.id, to: reviewStore)
                    state.completedNotebookIDs.insert(notebook.id)
                    try state.write(to: stateURL)
                    result.skipped += 1
                    continue
                }
                let outputURL = Self.availableURL(in: projectFolder, title: notebook.title)
                try NotebookPackageIO.writeAtomically(package, to: outputURL)
                try reviewStore.register(notebookURL: outputURL, manifest: package.manifest)
                try database.migrateReviewData(for: notebook.id, to: reviewStore)
                state.completedNotebookIDs.insert(notebook.id)
                try state.write(to: stateURL)
                result.imported += 1
            }

            try database.exportApplicationSupportRecords(to: reviewStore.rootURL)
            return result
        }.value
    }

    private static func safeFilename(_ input: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:")
        let cleaned = input.components(separatedBy: forbidden).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled Notebook" : cleaned
    }

    private static func availableURL(in directory: URL, title: String) -> URL {
        let base = safeFilename(title)
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("notebook")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix)").appendingPathExtension("notebook")
            suffix += 1
        }
        return candidate
    }

    private static func existingNotebook(id: String, in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.first { url in
            guard ["notebook", "ntbk"].contains(url.pathExtension.lowercased()),
                  let package = try? NotebookPackageIO.read(at: url, verifyAssetHashes: true) else { return false }
            return package.manifest.notebookID == id
        }
    }
}

private struct LegacyMigrationState: Codable {
    var completedNotebookIDs: Set<String>

    static func read(from url: URL) throws -> Self {
        try NotebookCoding.decoder.decode(Self.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        try NotebookCoding.encoder.encode(self).write(to: url, options: .atomic)
    }
}

private struct LegacyNotebookRow {
    var id: String
    var title: String
    var project: String
    var coverMediaID: String?
    var createdAt: Date
    var updatedAt: Date
}

private final class LegacySQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let databaseURL: URL
    private let mediaRoot: URL

    init(url: URL) throws {
        databaseURL = url
        mediaRoot = url.deletingLastPathComponent().appendingPathComponent("media", isDirectory: true)
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            throw LegacyMigrationError.database(String(cString: sqlite3_errmsg(handle)))
        }
    }

    deinit { sqlite3_close(handle) }

    func notebooks() throws -> [LegacyNotebookRow] {
        try rows("SELECT id, title, project, cover_media_id, created_at, updated_at FROM canvas_documents WHERE canvas_type='notebook' ORDER BY updated_at, id").map { row in
            LegacyNotebookRow(
                id: row.string("id"),
                title: row.string("title"),
                project: row.string("project"),
                coverMediaID: row.optionalString("cover_media_id"),
                createdAt: Self.date(milliseconds: row.int64("created_at")),
                updatedAt: Self.date(milliseconds: row.int64("updated_at"))
            )
        }
    }

    func package(for notebook: LegacyNotebookRow) throws -> NotebookPackage {
        let state = try row(
            "SELECT active_layer_id, focused_layer_id, unfocused_layer_opacity, viewport_x, viewport_y, viewport_scale FROM canvas_state WHERE document_id=?",
            bindings: [notebook.id]
        )
        let layers: [JSONValue] = try rows(
            "SELECT layer_id, name, z_index, visible, opacity, interaction_color FROM canvas_layers WHERE document_id=? ORDER BY z_index, layer_id",
            bindings: [notebook.id]
        ).map { layer in
            .object([
                "id": .string(layer.string("layer_id")),
                "name": .string(layer.string("name")),
                "zIndex": .number(layer.double("z_index")),
                "visible": .bool(layer.int64("visible") != 0),
                "opacity": .number(layer.double("opacity")),
                "interactionColor": .number(layer.double("interaction_color")),
            ])
        }

        var objectValues: [JSONValue] = []
        for object in try rows(
            "SELECT object_id, layer_id, object_type, payload_json FROM canvas_objects WHERE document_id=? ORDER BY sort_index, object_id",
            bindings: [notebook.id]
        ) {
            guard let data = object.string("payload_json").data(using: .utf8) else { continue }
            var value = try JSONValue(any: JSONSerialization.jsonObject(with: data))
            if case var .object(payload) = value {
                payload["id"] = payload["id"] ?? .string(object.string("object_id"))
                payload["layerId"] = payload["layerId"] ?? .string(object.string("layer_id"))
                payload["type"] = payload["type"] ?? .string(object.string("object_type"))
                value = .object(payload)
            }
            objectValues.append(value)
        }

        let contentBounds = Self.contentBounds(objects: objectValues)
        let margin = 64.0
        let shiftX = contentBounds.map { margin - $0.minX } ?? 0
        let shiftY = contentBounds.map { margin - $0.minY } ?? 0
        if shiftX != 0 || shiftY != 0 {
            objectValues = objectValues.map { Self.translatingRootObject($0, x: shiftX, y: shiftY) }
        }

        var canvas = JSONValue.object([
            "layers": .array(layers),
            "activeLayerId": .string(state?.string("active_layer_id") ?? layers.first?.objectValue?["id"]?.stringValue ?? "main"),
            "focusedLayerId": state?.optionalString("focused_layer_id").map(JSONValue.string) ?? .null,
            "unfocusedLayerOpacity": .number(state?.double("unfocused_layer_opacity") ?? 0.25),
            "viewport": .object([
                "x": .number(0),
                "y": .number(0),
                "scale": .number(1),
            ]),
            "objects": .array(objectValues),
        ])
        if layers.isEmpty, case var .object(root) = canvas {
            root["layers"] = NotebookPagePayload.blank(pageID: "placeholder").canvas.objectValue?["layers"]
            canvas = .object(root)
        }

        let contentWidth = contentBounds.map { $0.width + margin * 2 } ?? NotebookFormat.defaultWidth
        let contentHeight = contentBounds.map { $0.height + margin * 2 } ?? NotebookFormat.defaultHeight
        var importedPage = NotebookPageMetadata.make(title: "Imported Canvas")
        importedPage.id = UUID().uuidString.lowercased()
        importedPage.width = max(NotebookFormat.defaultWidth, ceil(contentWidth))
        importedPage.height = max(NotebookFormat.defaultHeight, ceil(contentHeight))
        importedPage.orientation = importedPage.width > importedPage.height ? .landscape : .portrait
        importedPage.revision = 1
        importedPage.createdAt = notebook.createdAt
        importedPage.updatedAt = notebook.updatedAt

        var metadata = try media(for: notebook.id)
        var assets: [String: Data] = [:]
        var assetMetadata: [NotebookAssetMetadata] = []
        for index in metadata.indices {
            guard let data = metadata[index].data else { continue }
            let hash = NotebookPackageIO.contentHash(for: data)
            let filename = NotebookPackageIO.assetFilename(hash: hash, originalFilename: metadata[index].originalName)
            assets[filename] = data
            let thumbnailFilename = NotebookPackageIO.thumbnailPNG(for: data).map { thumbnail in
                let path = "thumbnails/\(hash).png"
                assets[path] = thumbnail
                return path
            }
            assetMetadata.append(.init(
                hash: hash,
                filename: filename,
                thumbnailFilename: thumbnailFilename,
                mediaType: metadata[index].mimeType,
                byteCount: data.count,
                createdAt: metadata[index].createdAt
            ))
            metadata[index].packageFilename = filename
        }
        let mediaFiles = Dictionary(uniqueKeysWithValues: metadata.compactMap { media in
            media.packageFilename.map { (media.id, $0) }
        })
        let mediaIdentifiers = Set(metadata.map(\.id))
        objectValues = objectValues.map {
            Self.rewritingMediaReferences($0, mediaFiles: mediaFiles, mediaIdentifiers: mediaIdentifiers)
        }
        if case var .object(root) = canvas {
            root["objects"] = .array(objectValues)
            canvas = .object(root)
        }
        let importedPayload = NotebookPagePayload(
            formatVersion: 1,
            pageID: importedPage.id,
            revision: 1,
            canvas: canvas
        )

        var pages = [importedPage]
        var payloads = [importedPage.id: importedPayload]
        var coverPageID = importedPage.id
        var previewsForCoverPage: (pageID: String, data: Data)?
        if let coverID = notebook.coverMediaID,
           let cover = metadata.first(where: { $0.id == coverID }),
           let filename = cover.packageFilename {
            var coverPage = NotebookPageMetadata.make(title: "Cover")
            coverPage.createdAt = notebook.createdAt
            coverPage.updatedAt = notebook.updatedAt
            let object: JSONValue = .object([
                "id": .string(UUID().uuidString.lowercased()),
                "layerId": .string("main"),
                "type": .string("image"),
                "x": .number(64), "y": .number(64),
                "width": .number(NotebookFormat.defaultWidth - 128),
                "height": .number(NotebookFormat.defaultHeight - 128),
                "rotation": .number(0), "opacity": .number(1),
                "src": .string("notebook-asset://asset/\(filename)"),
                "name": .string(cover.originalName),
                "uploadStatus": .string("ready"),
                "lockAspectRatio": .bool(true),
                "cornerRadius": .number(0),
            ])
            var blank = NotebookPagePayload.blank(pageID: coverPage.id)
            if case var .object(root) = blank.canvas { root["objects"] = .array([object]); blank.canvas = .object(root) }
            pages.insert(coverPage, at: 0)
            payloads[coverPage.id] = blank
            coverPageID = coverPage.id
            if let data = cover.data, let preview = Self.pngData(data) {
                previewsForCoverPage = (coverPage.id, preview)
            }
        }

        var previews: [String: Data] = [:]
        if let previewsForCoverPage {
            previews["pages/\(previewsForCoverPage.pageID).png"] = previewsForCoverPage.data
            previews["cover.png"] = previewsForCoverPage.data
        }
        if let previewRow = try row("SELECT data_url FROM canvas_previews WHERE document_id=?", bindings: [notebook.id]),
           let preview = Self.dataURL(previewRow.string("data_url")) {
            previews["pages/\(importedPage.id).png"] = preview
            if coverPageID == importedPage.id { previews["cover.png"] = preview }
        }
        for tier in try rows("SELECT card_id, tier_id, data_url FROM card_tier_previews WHERE document_id=?", bindings: [notebook.id]) {
            if let preview = Self.dataURL(tier.string("data_url")) {
                previews["cards/\(tier.string("card_id"))/\(tier.string("tier_id")).png"] = preview
            }
        }

        return NotebookPackage(
            manifest: .init(
                formatVersion: 1,
                notebookID: notebook.id,
                createdAt: notebook.createdAt,
                updatedAt: notebook.updatedAt,
                pages: pages,
                coverPageID: coverPageID,
                requiredPlugins: Self.pluginRequirements(in: objectValues),
                assets: assetMetadata
            ),
            pagePayloads: payloads,
            assets: assets,
            previews: previews
        )
    }

    func migrateReviewData(for notebookID: String, to store: ReviewFileStore) throws {
        let scheduleRows = try rows("SELECT * FROM revision_schedules WHERE document_id=?", bindings: [notebookID])
        var cards: [String: JSONValue] = [:]
        for value in scheduleRows {
            cards[value.string("card_id")] = value.jsonValue
        }
        if !cards.isEmpty {
            try store.writeSchedule(.init(notebookID: notebookID, updatedAt: Date(), cards: cards))
        }
        let history = try rows(
            "SELECT * FROM revision_review_log WHERE document_id=? ORDER BY reviewed_at, id",
            bindings: [notebookID]
        ).map(\.jsonValue)
        try store.replaceHistory(notebookID: notebookID, events: history)
        try migrateSessions(for: notebookID, to: store)
    }

    private func migrateSessions(for notebookID: String, to store: ReviewFileStore) throws {
        guard try tableExists("revision_sessions") else { return }
        for session in try rows("SELECT * FROM revision_sessions WHERE notebook_id=?", bindings: [notebookID]) {
            let id = session.string("id")
            let goalType = session.string("goal_type")
            let goal: JSONValue = goalType == "time"
                ? .object(["type": .string("time"), "durationMs": .number(session.double("goal_value"))])
                : .object(["type": .string("cards"), "cardCount": .number(session.double("goal_value"))])
            let results = try rows(
                "SELECT * FROM revision_session_results WHERE session_id=? ORDER BY sequence",
                bindings: [id]
            ).map { row in
                JSONValue.object([
                    "sequence": .number(row.double("sequence")),
                    "notebookId": .string(row.string("notebook_id")),
                    "cardId": .string(row.string("card_id")),
                    "question": .string(row.string("question")),
                    "expectedAnswer": .string(row.string("expected_answer")),
                    "answer": .string(row.string("answer")),
                    "correct": .bool(row.int64("correct") != 0),
                    "answeredAt": .number(row.double("answered_at")),
                ])
            }
            let queue = try rows(
                "SELECT notebook_id, card_id FROM revision_session_cards WHERE session_id=? ORDER BY sequence",
                bindings: [id]
            ).map { row in
                JSONValue.object([
                    "notebookId": .string(row.string("notebook_id")),
                    "cardId": .string(row.string("card_id")),
                ])
            }
            let payload: JSONValue = .object([
                "session": .object([
                    "id": .string(id),
                    "origin": .string(session.string("origin")),
                    "workflowId": session.optionalString("workflow_id").map(JSONValue.string) ?? .null,
                    "nodeId": session.optionalString("node_id").map(JSONValue.string) ?? .null,
                    "notebookId": .string(notebookID),
                    "goal": goal,
                    "elapsedMs": .number(session.double("elapsed_ms")),
                    "status": .string(session.string("status")),
                    "totalCards": .number(session.double("total_cards")),
                    "remainingCards": .number(session.double("remaining_cards")),
                    "reviewedCount": .number(session.double("reviewed_count")),
                    "rightCount": .number(session.double("right_count")),
                    "wrongCount": .number(session.double("wrong_count")),
                    "startedAt": session.values["started_at"] ?? .null,
                    "createdAt": .number(session.double("created_at")),
                    "updatedAt": .number(session.double("updated_at")),
                    "results": .array(results),
                ]),
                "queue": .array(queue),
            ])
            try NotebookCoding.encoder
                .encode(payload)
                .write(to: store.sessionsURL.appendingPathComponent("\(id).json"), options: .atomic)
        }
    }

    func exportApplicationSupportRecords(to root: URL) throws {
        let destination = root.appendingPathComponent("notes-migration", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for table in ["persons", "plugin_installations"] where try tableExists(table) {
            let values = try rows("SELECT * FROM \(table)").map(\.jsonValue)
            try NotebookCoding.encoder.encode(values).write(to: destination.appendingPathComponent("\(table).json"), options: .atomic)
        }
    }

    private struct LegacyMedia {
        var id: String
        var originalName: String
        var mimeType: String
        var createdAt: Date
        var data: Data?
        var packageFilename: String?
    }

    private func media(for notebookID: String) throws -> [LegacyMedia] {
        try rows("SELECT id, original_name, mime_type, storage_key, created_at FROM media_entries WHERE canvas_id=?", bindings: [notebookID]).map { row in
            let key = row.string("storage_key")
            let safeURL = mediaRoot.appendingPathComponent(key).standardizedFileURL
            let data = safeURL.path.hasPrefix(mediaRoot.standardizedFileURL.path) ? try? Data(contentsOf: safeURL) : nil
            return LegacyMedia(
                id: row.string("id"),
                originalName: row.string("original_name"),
                mimeType: row.string("mime_type"),
                createdAt: Self.date(milliseconds: row.int64("created_at")),
                data: data,
                packageFilename: nil
            )
        }
    }

    private func tableExists(_ name: String) throws -> Bool {
        try row("SELECT name FROM sqlite_master WHERE type='table' AND name=?", bindings: [name]) != nil
    }

    private func row(_ sql: String, bindings: [String] = []) throws -> LegacySQLiteRow? {
        try rows(sql, bindings: bindings).first
    }

    private func rows(_ sql: String, bindings: [String] = []) throws -> [LegacySQLiteRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LegacyMigrationError.database(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var output: [LegacySQLiteRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var values: [String: JSONValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: values[name] = .number(Double(sqlite3_column_int64(statement, index)))
                case SQLITE_FLOAT: values[name] = .number(sqlite3_column_double(statement, index))
                case SQLITE_TEXT: values[name] = .string(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, index))
                    let data = Data(bytes: sqlite3_column_blob(statement, index), count: count)
                    values[name] = .string(data.base64EncodedString())
                default: values[name] = .null
                }
            }
            output.append(.init(values: values))
        }
        let code = sqlite3_errcode(handle)
        guard code == SQLITE_OK || code == SQLITE_DONE else { throw LegacyMigrationError.database(errorMessage) }
        return output
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    private static func date(milliseconds: Int64) -> Date { Date(timeIntervalSince1970: Double(milliseconds) / 1000) }

    private static func dataURL(_ value: String) -> Data? {
        guard let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...]))
    }

    private static func pngData(_ source: Data) -> Data? {
        guard let image = NSImage(data: source),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func pluginRequirements(in objects: [JSONValue]) -> [NotebookPluginRequirement] {
        var requirements: [String: String] = [:]
        func collect(_ value: JSONValue) {
            switch value {
            case let .object(values):
                if values["kind"]?.stringValue == "plugin", let identifier = values["pluginId"]?.stringValue {
                    let version = values["pluginVersion"]?.numberValue.map { String(Int($0)) } ?? "1"
                    requirements[identifier] = version
                }
                values.values.forEach(collect)
            case let .array(values):
                values.forEach(collect)
            default:
                break
            }
        }
        objects.forEach(collect)
        return requirements.map { .init(identifier: $0.key, version: $0.value) }.sorted { $0.identifier < $1.identifier }
    }

    private struct Bounds {
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
        var width: Double { maxX - minX }
        var height: Double { maxY - minY }
    }

    private static func contentBounds(objects: [JSONValue]) -> Bounds? {
        var result: Bounds?
        for object in objects {
            guard let values = object.objectValue,
                  let x = values["x"]?.numberValue,
                  let y = values["y"]?.numberValue else { continue }
            let width = values["width"]?.numberValue ?? 0
            let height = values["height"]?.numberValue ?? 0
            let bounds = Bounds(minX: x, minY: y, maxX: x + width, maxY: y + height)
            if let current = result {
                result = .init(minX: min(current.minX, bounds.minX), minY: min(current.minY, bounds.minY), maxX: max(current.maxX, bounds.maxX), maxY: max(current.maxY, bounds.maxY))
            } else { result = bounds }
        }
        return result
    }

    private static func translatingRootObject(_ value: JSONValue, x: Double, y: Double) -> JSONValue {
        guard case var .object(values) = value else { return value }
        if let currentX = values["x"]?.numberValue { values["x"] = .number(currentX + x) }
        if let currentY = values["y"]?.numberValue { values["y"] = .number(currentY + y) }
        return .object(values)
    }

    private static func rewritingMediaReferences(
        _ value: JSONValue,
        mediaFiles: [String: String],
        mediaIdentifiers: Set<String>,
        key: String? = nil
    ) -> JSONValue {
        switch value {
        case let .string(string):
            if let key, ["coverMediaId", "mediaId"].contains(key), mediaIdentifiers.contains(string) {
                return .string(mediaFiles[string].map { "notebook-asset://asset/\($0)" } ?? "notebook-asset://missing/\(string)")
            }
            if let identifier = legacyMediaIdentifier(in: string) {
                return .string(mediaFiles[identifier].map { "notebook-asset://asset/\($0)" } ?? "notebook-asset://missing/\(identifier)")
            }
            return value
        case let .array(values):
            return .array(values.map {
                rewritingMediaReferences($0, mediaFiles: mediaFiles, mediaIdentifiers: mediaIdentifiers)
            })
        case let .object(values):
            return .object(Dictionary(uniqueKeysWithValues: values.map { childKey, child in
                (childKey, rewritingMediaReferences(
                    child,
                    mediaFiles: mediaFiles,
                    mediaIdentifiers: mediaIdentifiers,
                    key: childKey
                ))
            }))
        default:
            return value
        }
    }

    private static func legacyMediaIdentifier(in value: String) -> String? {
        guard value.hasPrefix("media://") else { return nil }
        let remainder = value.dropFirst("media://".count)
        let pieces = remainder.split(separator: "/")
        guard pieces.count >= 2 else { return nil }
        return String(pieces[1]).removingPercentEncoding
    }
}

private struct LegacySQLiteRow {
    let values: [String: JSONValue]
    var jsonValue: JSONValue { .object(values) }
    func string(_ key: String) -> String { values[key]?.stringValue ?? "" }
    func optionalString(_ key: String) -> String? { values[key]?.stringValue }
    func double(_ key: String) -> Double { values[key]?.numberValue ?? 0 }
    func int64(_ key: String) -> Int64 { Int64(double(key)) }
}

private enum LegacyMigrationError: LocalizedError {
    case database(String)

    var errorDescription: String? {
        switch self {
        case let .database(message): "The legacy database could not be imported: \(message)"
        }
    }
}
