import Foundation
import XCTest
@testable import Notes

final class NotebookPackageTests: XCTestCase {
    func testPackageRoundTripPreservesUnknownCanvasFields() throws {
        var package = NotebookPackage.blank()
        let pageID = try XCTUnwrap(package.manifest.pages.first?.id)
        package.pagePayloads[pageID]?.canvas = .object([
            "layers": .array([]),
            "objects": .array([
                .object([
                    "id": .string("plugin-object"),
                    "type": .string("card"),
                    "pluginID": .string("third-party.example"),
                    "futurePayload": .object([
                        "nested": .array([.number(1), .string("preserved")]),
                    ]),
                ]),
            ]),
        ])

        let wrapper = try NotebookPackageIO.fileWrapper(for: package)
        let restored = try NotebookPackageIO.read(fileWrapper: wrapper)
        XCTAssertEqual(restored.pagePayloads[pageID]?.canvas, package.pagePayloads[pageID]?.canvas)
    }

    func testAssetDeduplicationAndHashVerification() throws {
        let document = NotebookDocument()
        let bytes = Data("same image".utf8)
        let first = document.importAsset(data: bytes, originalFilename: "first.png", mediaType: "image/png")
        let second = document.importAsset(data: bytes, originalFilename: "second.png", mediaType: "image/png")
        XCTAssertEqual(first.hash, second.hash)
        XCTAssertEqual(document.package.manifest.assets.count, 1)

        var corrupt = document.package
        corrupt.assets[first.filename] = Data("corrupt".utf8)
        let wrapper = try NotebookPackageIO.fileWrapper(for: corrupt)
        XCTAssertThrowsError(try NotebookPackageIO.read(fileWrapper: wrapper)) { error in
            XCTAssertEqual(error as? NotebookPackageError, .invalidAssetHash(first.hash))
        }
    }

    func testAtomicWriteAndReopen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-package-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Algebra.notebook", isDirectory: true)
        let package = NotebookPackage.blank()
        try NotebookPackageIO.writeAtomically(package, to: destination)
        let restored = try NotebookPackageIO.read(at: destination)
        XCTAssertEqual(restored.manifest.notebookID, package.manifest.notebookID)
        XCTAssertEqual(restored.manifest.pages.map(\.id), package.manifest.pages.map(\.id))
        XCTAssertEqual(restored.pagePayloads, package.pagePayloads)
        XCTAssertEqual(restored.assets, package.assets)
        XCTAssertEqual(restored.previews, package.previews)
    }

    func testPageDeletionSafeguardAndRevisionRejection() throws {
        let document = NotebookDocument()
        let original = document.selectedPageID
        document.deletePage(id: original)
        XCTAssertEqual(document.pages.count, 1)

        let added = document.addPage(after: original, orientation: .landscape)
        XCTAssertEqual(document.page(id: added)?.width, NotebookFormat.defaultHeight)
        XCTAssertEqual(document.page(id: added)?.height, NotebookFormat.defaultWidth)
        let canvas = try XCTUnwrap(document.package.pagePayloads[added]?.canvas)
        XCTAssertNil(document.updateCanvas(pageID: added, expectedRevision: 9, canvas: canvas))
        var canvasWithPlugin = try XCTUnwrap(canvas.objectValue)
        canvasWithPlugin["objects"] = .array([
            .object([
                "kind": .string("plugin"),
                "pluginId": .string("example.card"),
                "pluginVersion": .number(4),
                "futureField": .string("kept"),
            ]),
        ])
        XCTAssertEqual(document.updateCanvas(pageID: added, expectedRevision: 0, canvas: .object(canvasWithPlugin)), 1)
        XCTAssertEqual(
            document.package.manifest.requiredPlugins,
            [NotebookPluginRequirement(identifier: "example.card", version: "4")]
        )
    }

    func testOlderPackageVersionMigratesDuringNormalization() throws {
        var package = NotebookPackage.blank()
        package.manifest.formatVersion = 0
        let pageID = try XCTUnwrap(package.manifest.pages.first?.id)
        package.pagePayloads[pageID]?.formatVersion = 0
        try package.normalize()
        XCTAssertEqual(package.manifest.formatVersion, NotebookFormat.currentVersion)
        XCTAssertEqual(package.pagePayloads[pageID]?.formatVersion, NotebookFormat.currentVersion)
    }

    func testPluginPeopleAndCardTierPreviewsRemainFileBased() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-review-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ReviewFileStore(rootURL: root)
        let saved = try store.savePluginPerson(
            id: "person-1",
            name: "Ada Lovelace",
            role: "Author",
            organization: "",
            notes: ""
        )
        XCTAssertEqual(saved.name, "Ada Lovelace")
        XCTAssertEqual(try store.pluginPeople(query: "lovelace").map(\.id), ["person-1"])

        let document = NotebookDocument()
        let pageID = document.selectedPageID
        document.storeCardTierPreviews(
            pageID: pageID,
            cardID: "card/1",
            previews: [(tierID: "front", revision: 3, data: Data("preview".utf8))]
        )
        XCTAssertEqual(document.package.previews["cards/card-1/front-3.jpg"], Data("preview".utf8))
    }

    @MainActor
    func testCanvasControllerReusesOneWebView() {
        let controller = CanvasWebController()
        XCTAssertTrue(controller.webView === controller.webView)
    }
}
