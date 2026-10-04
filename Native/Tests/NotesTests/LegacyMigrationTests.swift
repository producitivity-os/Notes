import Foundation
import SQLite3
import XCTest
@testable import Notes

final class LegacyMigrationTests: XCTestCase {
    func testMigrationIsResumableAndKeepsNestedCardCoordinatesLocal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-migration-tests-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        let reviewStore = root.appendingPathComponent("ReviewStore", isDirectory: true)
        let database = root.appendingPathComponent("legacy.sqlite")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeLegacyDatabase(at: database)

        let migrator = LegacyNotebookMigrator(
            databaseURL: database,
            destinationURL: destination,
            reviewStoreURL: reviewStore
        )
        let first = try await migrator.run()
        XCTAssertEqual(first.imported, 1)
        XCTAssertEqual(first.skipped, 0)

        let notebookURL = destination
            .appendingPathComponent("Math", isDirectory: true)
            .appendingPathComponent("Algebra.notebook", isDirectory: true)
        let package = try NotebookPackageIO.read(at: notebookURL)
        let pageID = try XCTUnwrap(package.manifest.pages.first?.id)
        let objects = try XCTUnwrap(package.pagePayloads[pageID]?.canvas.objectValue?["objects"])
        guard case let .array(values) = objects,
              case let .object(card) = try XCTUnwrap(values.first),
              case let .array(elements) = card["elements"],
              case let .object(nested) = try XCTUnwrap(elements.first),
              case let .object(missingImage) = try XCTUnwrap(elements.last) else {
            return XCTFail("The imported card hierarchy is missing.")
        }
        XCTAssertEqual(card["x"]?.numberValue, 64)
        XCTAssertEqual(card["y"]?.numberValue, 64)
        XCTAssertEqual(nested["x"]?.numberValue, 5)
        XCTAssertEqual(nested["y"]?.numberValue, 6)
        XCTAssertEqual(missingImage["src"]?.stringValue, "notebook-asset://missing/missing-media")

        let second = try await migrator.run()
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.skipped, 1)
        let files = try FileManager.default.contentsOfDirectory(at: notebookURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "notebook" }.count, 1)
    }

    private func makeLegacyDatabase(at url: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let statements = [
            "CREATE TABLE canvas_documents (id TEXT, title TEXT, project TEXT, cover_media_id TEXT, created_at INTEGER, updated_at INTEGER, canvas_type TEXT)",
            "CREATE TABLE canvas_state (document_id TEXT, active_layer_id TEXT, focused_layer_id TEXT, unfocused_layer_opacity REAL, viewport_x REAL, viewport_y REAL, viewport_scale REAL)",
            "CREATE TABLE canvas_layers (document_id TEXT, layer_id TEXT, name TEXT, z_index INTEGER, visible INTEGER, opacity REAL, interaction_color INTEGER)",
            "CREATE TABLE canvas_objects (document_id TEXT, object_id TEXT, layer_id TEXT, object_type TEXT, payload_json TEXT, sort_index INTEGER)",
            "CREATE TABLE media_entries (id TEXT, canvas_id TEXT, original_name TEXT, mime_type TEXT, storage_key TEXT, created_at INTEGER)",
            "CREATE TABLE canvas_previews (document_id TEXT, data_url TEXT)",
            "CREATE TABLE card_tier_previews (document_id TEXT, card_id TEXT, tier_id TEXT, data_url TEXT)",
            "CREATE TABLE revision_schedules (document_id TEXT, card_id TEXT)",
            "CREATE TABLE revision_review_log (id TEXT, document_id TEXT, card_id TEXT, reviewed_at INTEGER)",
            "CREATE TABLE revision_sessions (id TEXT, origin TEXT, workflow_id TEXT, node_id TEXT, notebook_id TEXT, goal_type TEXT, goal_value INTEGER, elapsed_ms INTEGER, status TEXT, total_cards INTEGER, remaining_cards INTEGER, reviewed_count INTEGER, right_count INTEGER, wrong_count INTEGER, started_at INTEGER, created_at INTEGER, updated_at INTEGER)",
            "CREATE TABLE revision_session_results (session_id TEXT, sequence INTEGER, notebook_id TEXT, card_id TEXT, question TEXT, expected_answer TEXT, answer TEXT, correct INTEGER, answered_at INTEGER)",
            "CREATE TABLE revision_session_cards (session_id TEXT, sequence INTEGER, notebook_id TEXT, card_id TEXT)",
            "CREATE TABLE persons (id TEXT, name TEXT)",
            "CREATE TABLE plugin_installations (plugin_id TEXT, installed INTEGER, installed_at INTEGER)",
            "INSERT INTO canvas_documents VALUES ('notebook-1', 'Algebra', 'Math', NULL, 1700000000000, 1700000000000, 'notebook')",
            "INSERT INTO canvas_state VALUES ('notebook-1', 'main', NULL, 0.25, 0, 0, 1)",
            "INSERT INTO canvas_layers VALUES ('notebook-1', 'main', 'Main', 0, 1, 1, 3899126)",
            "INSERT INTO canvas_objects VALUES ('notebook-1', 'card-1', 'main', 'card', '{\"id\":\"card-1\",\"type\":\"card\",\"x\":-20,\"y\":-10,\"width\":200,\"height\":100,\"elements\":[{\"id\":\"nested\",\"type\":\"text\",\"x\":5,\"y\":6,\"text\":\"Question\"},{\"id\":\"missing\",\"type\":\"image\",\"src\":\"media://localhost/missing-media/content\"}]}', 0)",
            "INSERT INTO media_entries VALUES ('missing-media', 'notebook-1', 'missing.png', 'image/png', 'missing.png', 1700000000000)",
        ]
        for statement in statements {
            var error: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(database, statement, nil, nil, &error)
            if result != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
                sqlite3_free(error)
                XCTFail(message)
                throw NSError(domain: "LegacyMigrationTests", code: Int(result))
            }
        }
    }
}
