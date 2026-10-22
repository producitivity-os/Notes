import AppKit
import Foundation
import XCTest
@testable import Notes

final class NotebookPackageTests: XCTestCase {
    func testReviewIgnoreStateCanBeSetAndRestored() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notes-review-ignore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ReviewFileStore(rootURL: root)

        try store.setCard("card-1", in: "notebook-1", ignoredInReview: true)
        XCTAssertEqual(try store.reviewSchedule(notebookID: "notebook-1")?.ignoredCardIDs, ["card-1"])

        try store.setCard("card-1", in: "notebook-1", ignoredInReview: false)
        XCTAssertEqual(try store.reviewSchedule(notebookID: "notebook-1")?.ignoredCardIDs, [])
    }

    func testLegacyReviewScheduleDefaultsToNoIgnoredCards() throws {
        let data = Data("""
        {
          "formatVersion": 2,
          "notebookID": "notebook-1",
          "updatedAt": "2026-10-21T00:00:00Z",
          "cards": {}
        }
        """.utf8)

        let schedule = try NotebookCoding.decoder.decode(ReviewScheduleFile.self, from: data)
        XCTAssertTrue(schedule.ignoredCardIDs.isEmpty)
    }

    func testNewTextUsesCompactDefaultFont() {
        let text = TextElement.make(frame: CanvasRect(x: 0, y: 0, width: 260, height: 120))
        XCTAssertEqual(text.fontSize, 8)
        XCTAssertEqual(CardElement.contentPadding, 10)
    }

    @MainActor
    func testTextEditorKeepsCanvasColorInDarkMode() {
        let text = TextElement.make(frame: CanvasRect(x: 0, y: 0, width: 260, height: 120))
        let textView = NSTextView()
        textView.appearance = NSAppearance(named: .darkAqua)
        let styler = TextEditorStyler()

        styler.configure(textView)
        textView.string = "Visible text"
        styler.apply(element: text, scale: 1, to: textView)

        XCTAssertFalse(textView.usesAdaptiveColorMappingForDarkAppearance)
        XCTAssertEqual(textView.textColor, NSColor(canvasColor: .text))
        XCTAssertEqual(
            textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            NSColor(canvasColor: .text)
        )
    }

    @MainActor
    func testTextEditorOverlayPaintsVisibleGlyphs() throws {
        let text = TextElement.make(
            frame: CanvasRect(x: 40, y: 50, width: 260, height: 120),
            markdown: "Visible text"
        )
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(text)]
        let controller = NativeCanvasController()
        controller.loadStandalone(
            scene: scene,
            pageSize: CanvasSize(width: 500, height: 300),
            infiniteCanvas: true,
            assetData: { _ in nil },
            importAsset: { _, _, _ in nil },
            onCommit: { _ in }
        )
        let canvas = NativeCanvasView(controller: controller)
        canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        canvas.beginEditingText(text.id)

        let scrollView = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSScrollView }.first)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        let bitmap = try XCTUnwrap(scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds))
        scrollView.cacheDisplay(in: scrollView.bounds, to: bitmap)

        var darkPixelCount = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent < 0.4, color.greenComponent < 0.4, color.blueComponent < 0.4 {
                    darkPixelCount += 1
                }
            }
        }
        XCTAssertEqual(textView.string, "Visible text")
        XCTAssertGreaterThan(darkPixelCount, 20)
    }

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
        XCTAssertEqual(restored.manifest.formatVersion, 3)
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

    func testVersionTwoPackageIsUpgradedInMemory() throws {
        var package = NotebookPackage.blank()
        let page = try XCTUnwrap(package.manifest.pages.first)
        package.manifest.formatVersion = 2
        package.pagePayloads[page.id]?.formatVersion = 2

        let root = FileWrapper(directoryWithFileWrappers: [:])
        let manifest = FileWrapper(regularFileWithContents: try NotebookCoding.encoder.encode(package.manifest))
        manifest.preferredFilename = NotebookFormat.manifestName
        root.addFileWrapper(manifest)
        let pages = FileWrapper(directoryWithFileWrappers: [:])
        pages.preferredFilename = NotebookFormat.pagesDirectory
        let versionTwoPayload = try XCTUnwrap(package.pagePayloads[page.id])
        let payload = FileWrapper(regularFileWithContents: try NotebookCoding.encoder.encode(versionTwoPayload))
        payload.preferredFilename = "\(page.id).json"
        pages.addFileWrapper(payload)
        root.addFileWrapper(pages)

        let restored = try NotebookPackageIO.read(fileWrapper: root)
        XCTAssertEqual(restored.manifest.formatVersion, 3)
        XCTAssertEqual(restored.pagePayloads[page.id]?.formatVersion, 3)
    }

    @MainActor
    func testDocumentSceneRevisionAndUndo() throws {
        let document = NotebookDocument()
        let controller = NativeCanvasController()
        let undoManager = UndoManager()
        controller.undoManager = undoManager
        controller.load(document: document, pageID: document.selectedPageID)
        controller.addElement(
            .card(.make(frame: CanvasRect(x: 20, y: 20, width: 200, height: 120))),
            actionName: "Create Card"
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

    func testArrowAttachmentAtArbitraryElementPointTracksMoveResizeAndRotation() throws {
        let text = TextElement.make(frame: CanvasRect(x: 100, y: 100, width: 200, height: 100))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(text)]

        let attachment = try XCTUnwrap(CanvasGeometry.attachment(
            to: CanvasPoint(x: 140, y: 170),
            in: scene
        ))
        XCTAssertEqual(attachment.elementID, text.id)
        let normalized = try XCTUnwrap(attachment.normalizedPoint)
        XCTAssertEqual(normalized.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(normalized.y, 0.7, accuracy: 0.0001)
        XCTAssertEqual(CanvasGeometry.attachmentPoint(attachment, in: scene), CanvasPoint(x: 140, y: 170))

        var changed = text
        changed.geometry.frame = CanvasRect(x: 300, y: 200, width: 400, height: 200)
        scene.replace(.text(changed))
        XCTAssertEqual(CanvasGeometry.attachmentPoint(attachment, in: scene), CanvasPoint(x: 380, y: 340))

        changed.geometry.rotation = 90
        scene.replace(.text(changed))
        let rotated = try XCTUnwrap(CanvasGeometry.attachmentPoint(attachment, in: scene))
        XCTAssertEqual(rotated.x, 460, accuracy: 0.0001)
        XCTAssertEqual(rotated.y, 180, accuracy: 0.0001)

        let restored = try NotebookCoding.decoder.decode(
            ArrowAttachment.self,
            from: NotebookCoding.encoder.encode(attachment)
        )
        XCTAssertEqual(restored, attachment)
    }

    func testAttachedArrowPersistsCurrentFallbackAndBoundsAfterTargetChanges() throws {
        var target = TextElement.make(frame: CanvasRect(x: 100, y: 100, width: 200, height: 100))
        let attachment = ArrowAttachment(
            elementID: target.id,
            edge: .center,
            position: 0.5,
            normalizedPoint: CanvasPoint(x: 0.2, y: 0.7)
        )
        var arrow = ArrowElement.make(
            start: CanvasPoint(x: 140, y: 170),
            end: CanvasPoint(x: 20, y: 30)
        )
        arrow.start.attachment = attachment
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(target), .arrow(arrow)]

        target.geometry.frame = CanvasRect(x: 300, y: 200, width: 400, height: 200)
        scene.replace(.text(target))

        guard case let .arrow(updated)? = scene.element(id: arrow.id) else {
            return XCTFail("Expected the attached arrow")
        }
        XCTAssertEqual(updated.start.point, CanvasPoint(x: 380, y: 340))
        XCTAssertEqual(updated.geometry.frame.x, 20)
        XCTAssertEqual(updated.geometry.frame.width, 360)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(scene.contentBounds).cgRect.maxX, 700)
    }

    func testBothArrowEndpointsCanAttachToDistinctPointsOnOneElement() throws {
        let text = TextElement.make(frame: CanvasRect(x: 100, y: 100, width: 200, height: 100))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(text)]

        let first = try XCTUnwrap(CanvasGeometry.attachment(to: CanvasPoint(x: 135, y: 170), in: scene))
        let second = try XCTUnwrap(CanvasGeometry.attachment(to: CanvasPoint(x: 265, y: 125), in: scene))

        XCTAssertEqual(first.elementID, text.id)
        XCTAssertEqual(second.elementID, text.id)
        XCTAssertNotEqual(first.normalizedPoint, second.normalizedPoint)
    }

    func testNamedArrowAnchorTakesPriorityOverArbitraryInteriorAttachment() throws {
        let text = TextElement.make(frame: CanvasRect(x: 100, y: 100, width: 200, height: 100))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(text)]

        let attachment = try XCTUnwrap(CanvasGeometry.attachment(
            to: CanvasPoint(x: 298, y: 150),
            in: scene
        ))
        XCTAssertEqual(attachment.edge, .right)
        XCTAssertNil(attachment.normalizedPoint)
    }

    @MainActor
    func testSelectedArrowEndpointsRemainDraggableWithSelectTool() throws {
        let arrow = ArrowElement.make(start: CanvasPoint(x: 30, y: 40), end: CanvasPoint(x: 230, y: 140))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.arrow(arrow)]
        let controller = NativeCanvasController()
        controller.loadStandalone(
            scene: scene,
            pageSize: CanvasSize(width: 400, height: 300),
            infiniteCanvas: true,
            assetData: { _ in nil },
            importAsset: { _, _, _ in nil },
            onCommit: { _ in }
        )
        controller.activeTool = .select
        controller.selection.selectOnly(arrow.id)
        let canvas = NativeCanvasView(controller: controller)

        let endpoint = try XCTUnwrap(canvas.arrowEndpoint(at: arrow.end.point))
        XCTAssertEqual(endpoint.id, arrow.id)
        XCTAssertFalse(endpoint.isStart)
    }

    @MainActor
    func testPaperRendererNeverDrawsLegacyRedRulesOrHeader() throws {
        let size = CGSize(width: 420, height: 320)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let graphics = NSGraphicsContext.current?.cgContext else { return false }
            GraphPaperRenderer().draw(
                pageSize: CanvasSize(width: size.width, height: size.height),
                destination: rect,
                pattern: .isometric,
                pageTitle: "This title must not render",
                pageCreatedAt: .now,
                graphics: graphics
            )
            return true
        }
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        var redPixelCount = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.55,
                   color.redComponent > color.greenComponent * 1.35,
                   color.redComponent > color.blueComponent * 1.35 {
                    redPixelCount += 1
                }
            }
        }
        XCTAssertEqual(redPixelCount, 0)
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
        XCTAssertEqual(CanvasToolKind.toolbarTools, [.select, .card, .arrow])
        XCTAssertEqual(CanvasToolKind.cardEditorTools, [.select, .text, .image, .arrow])
        XCTAssertEqual(CanvasToolKind.select.resourceIconName, "pointer")
        XCTAssertEqual(CanvasToolKind.text.resourceIconName, "markdown")
        XCTAssertEqual(CanvasToolKind.card.resourceIconName, "square")
        XCTAssertEqual(CanvasToolKind.arrow.resourceIconName, "link")
        XCTAssertEqual(ArrowElement.make(start: .zero, end: CanvasPoint(x: 20, y: 20)).color, .accent)
    }

    @MainActor
    func testNotebookPagesOnlyCreateCardsAndArrows() {
        let document = NotebookDocument()
        let controller = NativeCanvasController()
        controller.load(document: document, pageID: document.selectedPageID)

        controller.addElement(.text(.make(frame: CanvasRect(x: 0, y: 0, width: 100, height: 80))), actionName: "Create Text")
        XCTAssertTrue(controller.scene.elements.isEmpty)

        controller.addElement(.card(.make(frame: CanvasRect(x: 0, y: 0, width: 100, height: 80))), actionName: "Create Card")
        XCTAssertEqual(controller.scene.elements.count, 1)
    }

    func testNewTextAndCardsHaveNoPlaceholderContent() {
        XCTAssertEqual(TextElement.make(frame: CanvasRect(x: 0, y: 0, width: 100, height: 80)).markdown, "")
        var card = CardElement.make(frame: CanvasRect(x: 0, y: 0, width: 100, height: 80))
        XCTAssertEqual(card.title, "")
        XCTAssertEqual(card.faces.map(\.name), ["Back"])
        XCTAssertEqual(card.faces.first?.previewRendererVersion, CardFace.currentPreviewRendererVersion)
        XCTAssertEqual(card.addFrontFace(), CardElement.frontFaceID)
        XCTAssertEqual(card.faces.map(\.name), ["Back", "Front"])
        XCTAssertEqual(card.faces.map(\.previewRendererVersion), [1, 1])
    }

    func testCardContentFitsExactlyWithoutAMinimumSize() {
        var card = CardElement.make(frame: CanvasRect(x: 0, y: 0, width: 520, height: 320))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(.make(frame: CanvasRect(x: 4, y: 8, width: 12, height: 7), markdown: "x"))]

        card.updateFace(id: CardElement.backFaceID, scene: scene)

        XCTAssertEqual(card.geometry.frame.width, 12 + CardElement.contentPadding * 2)
        XCTAssertEqual(card.geometry.frame.height, 7 + CardElement.contentPadding * 2)
    }

    func testLegacyCardFacesDecodeAndContentSizingSupportsNegativeCoordinates() throws {
        let geometry = CanvasElementGeometry(frame: CanvasRect(x: 20, y: 30, width: 400, height: 200))
        var front = CanvasSceneDocument.blank()
        front.elements = [.text(.make(frame: CanvasRect(x: -80, y: -40, width: 300, height: 120), markdown: "Question"))]
        var back = CanvasSceneDocument.blank()
        back.elements = [.text(.make(frame: CanvasRect(x: 10, y: 20, width: 260, height: 90), markdown: "Answer"))]
        let object: [String: Any] = [
            "id": "legacy-card",
            "geometry": try JSONSerialization.jsonObject(with: NotebookCoding.encoder.encode(geometry)),
            "title": "Legacy",
            "sideSize": ["width": 400, "height": 200],
            "front": try JSONSerialization.jsonObject(with: NotebookCoding.encoder.encode(front)),
            "back": try JSONSerialization.jsonObject(with: NotebookCoding.encoder.encode(back)),
            "previewRevision": 4,
        ]
        var card = try NotebookCoding.decoder.decode(
            CardElement.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(card.faces.map(\.name), ["Front", "Back"])
        XCTAssertEqual(card.faces.map(\.previewRevision), [4, 4])
        XCTAssertEqual(card.faces.map(\.previewRendererVersion), [nil, nil])
        card.updateFace(id: CardElement.frontFaceID, scene: front)
        XCTAssertEqual(card.frontFace?.previewRendererVersion, CardFace.currentPreviewRendererVersion)
        card.fitToDisplayContent()
        XCTAssertEqual(card.geometry.frame.width, 320)
        XCTAssertEqual(card.geometry.frame.height, 140)
    }

    @MainActor
    func testMultilineBracketLatexRendersAsAnAttachmentAtHighResolution() throws {
        let renderer = MarkdownRenderer()
        let rendered = renderer.attributedString(
            markdown: "Before\n\\[\n\\frac{1}{s + R}\n\\]\nAfter",
            fontSize: 18,
            color: .black,
            maximumWidth: 420
        )
        var attachments: [NSTextAttachment] = []
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }

        let image = try XCTUnwrap((attachments.first?.attachmentCell as? NSTextAttachmentCell)?.image)
        let bitmap = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
        XCTAssertEqual(attachments.count, 1)
        XCTAssertFalse(rendered.string.contains("\\["))
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsWide), image.size.width * 3.5)
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsHigh), image.size.height * 3.5)
    }

    @MainActor
    func testTextPreviewHasNoResizableSelectionChromeUntilSourceEditing() {
        let text = TextElement.make(frame: CanvasRect(x: 20, y: 30, width: 140, height: 80), markdown: "**Rendered**")
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(text)]
        let renderer = CanvasOverlayRenderer()
        let handle = CanvasPoint(x: 160, y: 110)

        XCTAssertNil(renderer.resizeHandle(
            scene: scene,
            selection: [text.id],
            editingTextID: nil,
            point: handle,
            viewport: CanvasViewport()
        ))
        XCTAssertEqual(renderer.resizeHandle(
            scene: scene,
            selection: [text.id],
            editingTextID: text.id,
            point: handle,
            viewport: CanvasViewport()
        ), text.id)
    }

    @MainActor
    func testRenderedLatexPreviewOutlineHugsVisibleContent() throws {
        var text = TextElement.make(
            frame: CanvasRect(x: 20, y: 30, width: 320, height: 160),
            markdown: "\\[x^2 + y^2\\]"
        )
        text.fontSize = 24
        let markdownRenderer = MarkdownRenderer()
        let layout = TextElementRenderer.layout(for: text, markdownRenderer: markdownRenderer)
        let renderedBounds = try XCTUnwrap(layout.renderedBounds)

        XCTAssertGreaterThan(renderedBounds.width, 0)
        XCTAssertGreaterThan(renderedBounds.height, 0)
        XCTAssertLessThan(renderedBounds.width, text.geometry.frame.width)
        XCTAssertLessThan(renderedBounds.height, text.geometry.frame.height)

        let overlay = CanvasOverlayRenderer(markdownRenderer: markdownRenderer)
        let outline = try XCTUnwrap(overlay.textPreviewOutlineBounds(for: text, viewport: CanvasViewport()))
        XCTAssertEqual(outline.width, renderedBounds.width + 6, accuracy: 0.5)
        XCTAssertEqual(outline.height, renderedBounds.height + 6, accuracy: 0.5)

        text.geometry.rotation = 35
        let rotated = try XCTUnwrap(overlay.textPreviewOutlineBounds(for: text, viewport: CanvasViewport()))
        XCTAssertGreaterThan(rotated.height, outline.height)
    }

    @MainActor
    func testRenderedTextBoundsFollowParagraphAlignment() throws {
        var leading = TextElement.make(
            frame: CanvasRect(x: 10, y: 20, width: 300, height: 100),
            markdown: "Rendered"
        )
        leading.fontSize = 18
        var trailing = leading
        trailing.alignment = .trailing
        let renderer = MarkdownRenderer()

        let leadingBounds = try XCTUnwrap(TextElementRenderer.layout(for: leading, markdownRenderer: renderer).renderedBounds)
        let trailingBounds = try XCTUnwrap(TextElementRenderer.layout(for: trailing, markdownRenderer: renderer).renderedBounds)
        XCTAssertGreaterThan(trailingBounds.minX, leadingBounds.minX)
        XCTAssertEqual(trailingBounds.width, leadingBounds.width, accuracy: 0.5)
    }

    func testPageGridPatternPersistsAndLegacyPagesDefaultToPolkaDots() throws {
        let document = NotebookDocument()
        let pageID = document.selectedPageID
        document.setGridPattern(.isometric, for: pageID)
        XCTAssertEqual(document.page(id: pageID)?.resolvedGridPattern, .isometric)

        let restored = try NotebookPackageIO.read(fileWrapper: NotebookPackageIO.fileWrapper(for: document.package))
        XCTAssertEqual(restored.manifest.pages.first?.resolvedGridPattern, .isometric)

        let metadata = NotebookPageMetadata.make()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: NotebookCoding.encoder.encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "gridPattern")
        let legacy = try NotebookCoding.decoder.decode(
            NotebookPageMetadata.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(legacy.resolvedGridPattern, .dots)
        XCTAssertEqual(NotebookPageMetadata.make().resolvedGridPattern, .dots)
    }

    @MainActor
    func testDocumentPagesUseAnInfiniteCanvasAndPreserveNegativeCoordinates() throws {
        let document = NotebookDocument()
        let controller = NativeCanvasController()
        controller.load(document: document, pageID: document.selectedPageID)

        XCTAssertTrue(controller.isInfiniteCanvas)
        var text = TextElement.make(frame: CanvasRect(x: -420, y: -180, width: 180, height: 90))
        controller.addElement(.card(.make(frame: CanvasRect(x: -260, y: -140, width: 220, height: 120))), actionName: "Create Card")
        controller.updateElement(.text(text), actionName: "Insert Text")
        text.geometry.frame.x = -780
        controller.updateElement(.text(text), actionName: "Move Text")

        guard case let .text(saved)? = document.selectedPayload?.scene.element(id: text.id) else {
            return XCTFail("Expected the unbounded text element to be persisted")
        }
        XCTAssertEqual(saved.geometry.frame.x, -780)
    }

    @MainActor
    func testEmptyDocumentCanvasStartsAt100PercentWithOriginCentered() {
        let document = NotebookDocument()
        let controller = NativeCanvasController()
        controller.load(document: document, pageID: document.selectedPageID)
        let canvas = NativeCanvasView(controller: controller)
        canvas.frame = CGRect(x: 0, y: 0, width: 1_200, height: 800)

        canvas.fitPage()

        XCTAssertEqual(canvas.viewport.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(canvas.viewport.viewPoint(fromWorld: .zero).x, 600, accuracy: 0.0001)
        XCTAssertEqual(canvas.viewport.viewPoint(fromWorld: .zero).y, 400, accuracy: 0.0001)
        XCTAssertEqual(controller.zoomScale, 1, accuracy: 0.0001)
    }

    func testInfinitePreviewLayoutFitsNegativeAndDistantElements() throws {
        let left = TextElement.make(frame: CanvasRect(x: -640, y: -310, width: 180, height: 90))
        let right = CardElement.make(frame: CanvasRect(x: 1_900, y: 1_150, width: 420, height: 260))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(left), .card(right)]

        let layout = InfiniteCanvasPreviewLayout.make(
            scene: scene,
            fallbackSize: CanvasSize(width: 794, height: 1123)
        )
        let fittedBounds = try XCTUnwrap(layout.scene.contentBounds?.cgRect)

        XCTAssertGreaterThanOrEqual(fittedBounds.minX, 0)
        XCTAssertGreaterThanOrEqual(fittedBounds.minY, 0)
        XCTAssertLessThanOrEqual(fittedBounds.maxX, layout.pageSize.width)
        XCTAssertLessThanOrEqual(fittedBounds.maxY, layout.pageSize.height)
        XCTAssertGreaterThan(layout.pageSize.width, NotebookFormat.defaultWidth)
        XCTAssertGreaterThan(layout.pageSize.height, NotebookFormat.defaultHeight)
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

    func testCardEditorZoomCannotShrinkBelowItsFittedScale() {
        let page = CGSize(width: 520, height: 320)
        let panel = CGSize(width: 760, height: 488)
        let fitted = CanvasViewport.fittingScale(pageSize: page, in: panel, padding: 12)
        var viewport = CanvasViewport(scale: fitted, offset: .zero)

        viewport.zoom(
            by: 0.01,
            around: CGPoint(x: panel.width / 2, y: panel.height / 2),
            minimumScale: fitted
        )

        XCTAssertEqual(viewport.scale, fitted, accuracy: 0.0001)
    }
}
