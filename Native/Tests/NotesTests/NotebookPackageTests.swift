import AppKit
import Foundation
import XCTest
@testable import Notes

final class NotebookPackageTests: XCTestCase {
    func testNativeSceneRoundTrip() throws {
        var package = NotebookPackage.blank()
        let pageID = try XCTUnwrap(package.manifest.pages.first?.id)
        let text = TextElement.make(
            frame: CanvasRect(x: 40, y: 50, width: 260, height: 120),
            markdown: "# Inverses\n\n$A^{-1}$"
        )
        let card = CardElement.make(frame: CanvasRect(x: 80, y: 240, width: 320, height: 190))
        package.pagePayloads[pageID]?.scene.elements = [.text(text), .card(card)]

        let wrapper = try NotebookPackageIO.fileWrapper(for: package)
        let restored = try NotebookPackageIO.read(fileWrapper: wrapper)
        XCTAssertEqual(restored.pagePayloads[pageID]?.scene, package.pagePayloads[pageID]?.scene)
        XCTAssertEqual(restored.manifest.formatVersion, 2)
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
        XCTAssertEqual(restored.pagePayloads, package.pagePayloads)
    }

    func testVersionOneIsRejectedWithoutMutation() throws {
        var package = NotebookPackage.blank()
        package.manifest.formatVersion = 1
        XCTAssertThrowsError(try package.normalize()) { error in
            XCTAssertEqual(error as? NotebookPackageError, .unsupportedVersion(1))
        }
        XCTAssertEqual(package.manifest.formatVersion, 1)
    }

    func testVersionOnePackageIsRejectedBeforeLegacyPageDecoding() throws {
        var manifest = NotebookManifest.blank()
        manifest.formatVersion = 1
        let root = FileWrapper(directoryWithFileWrappers: [:])
        let manifestWrapper = FileWrapper(regularFileWithContents: try NotebookCoding.encoder.encode(manifest))
        manifestWrapper.preferredFilename = NotebookFormat.manifestName
        root.addFileWrapper(manifestWrapper)

        XCTAssertThrowsError(try NotebookPackageIO.read(fileWrapper: root)) { error in
            XCTAssertEqual(error as? NotebookPackageError, .unsupportedVersion(1))
        }
    }

    @MainActor
    func testDocumentSceneRevisionAndUndo() throws {
        let document = NotebookDocument()
        let controller = NativeCanvasController()
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        controller.load(document: document, pageID: document.selectedPageID)
        controller.addElement(
            .text(.make(frame: CanvasRect(x: 20, y: 20, width: 200, height: 80))),
            actionName: "Create Text"
        )
        XCTAssertEqual(document.package.pagePayloads[document.selectedPageID]?.revision, 1)
        XCTAssertEqual(controller.scene.elements.count, 1)
        controller.undo()
        XCTAssertTrue(controller.scene.elements.isEmpty)
        controller.redo()
        XCTAssertEqual(controller.scene.elements.count, 1)
    }

    @MainActor
    func testClipboardImageInsertionUsesNativeAssetEnvironment() throws {
        let controller = NativeCanvasController()
        var importedData: Data?
        controller.loadStandalone(
            scene: .blank(),
            pageSize: CanvasSize(width: 500, height: 500),
            assetData: { _ in nil },
            importAsset: { data, filename, mediaType in
                importedData = data
                return NotebookAssetMetadata(
                    hash: "clipboard-image",
                    filename: filename,
                    thumbnailFilename: nil,
                    mediaType: mediaType,
                    byteCount: data.count,
                    createdAt: Date()
                )
            },
            onCommit: { _ in }
        )
        let bytes = Data("clipboard image".utf8)
        XCTAssertTrue(controller.insertImage(data: bytes, filename: "Paste.png", mediaType: "image/png", at: .zero))
        XCTAssertEqual(importedData, bytes)
        guard case let .image(image)? = controller.scene.elements.first else {
            return XCTFail("Expected a native image element")
        }
        XCTAssertEqual(image.assetHash, "clipboard-image")
    }

    func testArrowAttachmentTracksTargetGeometry() throws {
        let text = TextElement.make(frame: CanvasRect(x: 100, y: 100, width: 200, height: 100))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(text)]
        let attachment = ArrowAttachment(elementID: text.id, edge: .right, position: 0.5)
        XCTAssertEqual(CanvasGeometry.attachmentPoint(attachment, in: scene), CanvasPoint(x: 300, y: 150))
        let center = ArrowAttachment(elementID: text.id, edge: .center, position: 0.5)
        XCTAssertEqual(CanvasGeometry.attachmentPoint(center, in: scene), CanvasPoint(x: 200, y: 150))
        XCTAssertEqual(
            CanvasGeometry.nearestAttachment(to: CanvasPoint(x: 202, y: 151), in: scene)?.edge,
            .center
        )
        XCTAssertEqual(
            CanvasGeometry.nearestAttachment(to: CanvasPoint(x: 299, y: 150), in: scene)?.edge,
            .right
        )

        var moved = text
        moved.geometry.frame.x = 180
        scene.replace(.text(moved))
        XCTAssertEqual(CanvasGeometry.attachmentPoint(attachment, in: scene), CanvasPoint(x: 380, y: 150))
        XCTAssertEqual(CanvasGeometry.attachmentPoint(center, in: scene), CanvasPoint(x: 280, y: 150))
    }

    func testArrowBendPointDefinesTheVisibleCurve() throws {
        var arrow = ArrowElement.make(start: CanvasPoint(x: 20, y: 40), end: CanvasPoint(x: 220, y: 40))
        arrow.routing = .curved
        arrow.bendPoint = CanvasPoint(x: 120, y: 120)
        arrow.refreshBounds()
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.arrow(arrow)]

        let points = ArrowPathGeometry.sampledPoints(for: arrow, in: scene, curveSegments: 32)
        XCTAssertEqual(points[16].x, 120, accuracy: 0.001)
        XCTAssertEqual(points[16].y, 120, accuracy: 0.001)
        XCTAssertEqual(arrow.geometry.frame.cgRect.minX, 20, accuracy: 0.001)
        XCTAssertEqual(arrow.geometry.frame.cgRect.maxX, 220, accuracy: 0.001)
        XCTAssertEqual(arrow.geometry.frame.cgRect.minY, 40, accuracy: 0.001)
        XCTAssertEqual(arrow.geometry.frame.cgRect.maxY, 120, accuracy: 0.001)

        let restored = try NotebookCoding.decoder.decode(
            ArrowElement.self,
            from: NotebookCoding.encoder.encode(arrow)
        )
        XCTAssertEqual(restored.bendPoint, arrow.bendPoint)
    }

    func testArrowWithoutPersistedBendPointRemainsCompatible() throws {
        let arrow = ArrowElement.make(start: CanvasPoint(x: 10, y: 20), end: CanvasPoint(x: 90, y: 120))
        let encoded = try NotebookCoding.encoder.encode(arrow)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "bendPoint")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let restored = try NotebookCoding.decoder.decode(ArrowElement.self, from: legacyData)
        XCTAssertNil(restored.bendPoint)
    }

    @MainActor
    func testArrowHitTestingUsesRenderedRouteAndVisualZOrder() throws {
        let renderer = CanvasSceneRenderer()
        var arrow = ArrowElement.make(start: CanvasPoint(x: 20, y: 100), end: CanvasPoint(x: 260, y: 100))
        arrow.routing = .curved
        arrow.bendPoint = CanvasPoint(x: 140, y: 180)
        arrow.refreshBounds()
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.arrow(arrow)]
        XCTAssertEqual(
            renderer.hitTest(scene: scene, point: CanvasPoint(x: 140, y: 180), assetData: { _ in nil })?.id,
            arrow.id
        )
        XCTAssertNil(renderer.hitTest(scene: scene, point: CanvasPoint(x: 140, y: 100), assetData: { _ in nil }))

        let card = CardElement.make(frame: CanvasRect(x: 110, y: 145, width: 60, height: 70))
        scene.elements.append(.card(card))
        XCTAssertEqual(
            renderer.hitTest(scene: scene, point: CanvasPoint(x: 140, y: 180), assetData: { _ in nil })?.id,
            card.id
        )
    }

    func testPageDeletionSafeguard() {
        let document = NotebookDocument()
        let original = document.selectedPageID
        document.deletePage(id: original)
        XCTAssertEqual(document.pages.count, 1)
        let added = document.addPage(after: original, orientation: .landscape)
        XCTAssertEqual(document.page(id: added)?.width, NotebookFormat.defaultHeight)
        XCTAssertEqual(document.page(id: added)?.height, NotebookFormat.defaultWidth)
    }

    func testPluginPeopleRemainFileBased() throws {
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
    }
}

final class CanvasViewportTests: XCTestCase {
    func testPanToolIsNotExposedInToolbar() {
        XCTAssertFalse(CanvasToolKind.toolbarTools.contains(.pan))
        XCTAssertEqual(CanvasToolKind.select.resourceIconName, "pointer")
        XCTAssertEqual(CanvasToolKind.text.resourceIconName, "markdown")
        XCTAssertEqual(CanvasToolKind.card.resourceIconName, "square")
        XCTAssertEqual(CanvasToolKind.arrow.resourceIconName, "link")
        XCTAssertEqual(ArrowElement.make(start: .zero, end: CanvasPoint(x: 20, y: 20)).color, .accent)
    }

    func testWorldAndViewCoordinateRoundTrip() {
        var viewport = CanvasViewport()
        viewport.fit(pageSize: CGSize(width: 794, height: 1123), in: CGSize(width: 1200, height: 800))
        let world = CGPoint(x: 310, y: 420)
        let restored = viewport.worldPoint(fromView: viewport.viewPoint(fromWorld: world))
        XCTAssertEqual(restored.x, world.x, accuracy: 0.0001)
        XCTAssertEqual(restored.y, world.y, accuracy: 0.0001)
    }

    func testCursorCenteredZoomKeepsWorldPointStable() {
        var viewport = CanvasViewport(scale: 1, offset: CGPoint(x: 50, y: 60))
        let cursor = CGPoint(x: 300, y: 250)
        let before = viewport.worldPoint(fromView: cursor)
        viewport.zoom(by: 2, around: cursor)
        let after = viewport.worldPoint(fromView: cursor)
        XCTAssertEqual(after.x, before.x, accuracy: 0.0001)
        XCTAssertEqual(after.y, before.y, accuracy: 0.0001)
    }
}
