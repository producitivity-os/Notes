import XCTest
import UIKit
@testable import NotebookIOS

final class NotebookIOSTests: XCTestCase {
    func testNotebookPackageRoundTripsOnIOS() throws {
        var package = NotebookPackage.blank()
        let pageID = try XCTUnwrap(package.manifest.pages.first?.id)
        package.pagePayloads[pageID]?.scene.elements.append(
            .card(.make(frame: CanvasRect(x: 20, y: 30, width: 240, height: 140)))
        )

        let wrapper = try NotebookPackageIO.fileWrapper(for: package)
        let restored = try NotebookPackageIO.read(fileWrapper: wrapper)

        XCTAssertEqual(restored.manifest.notebookID, package.manifest.notebookID)
        XCTAssertEqual(restored.pagePayloads, package.pagePayloads)
    }

    func testNewDocumentContainsOneEditablePage() {
        let document = NotebookDocument()
        XCTAssertEqual(document.pages.count, 1)
        XCTAssertNotNil(document.selectedPayload)
    }

    @MainActor
    func testMobilePreviewRendersMultilineBracketLatexAtHighResolution() throws {
        let rendered = MobileMarkdownRenderer.attributedString(
            markdown: "Before\n\\[\n\\frac{1}{s + R}\n\\]\nAfter",
            fontSize: 18,
            color: .black,
            alignment: .leading,
            maximumWidth: 420
        )
        var attachments: [NSTextAttachment] = []
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }

        let image = try XCTUnwrap(attachments.first?.image)
        let pixelsWide = try XCTUnwrap(image.cgImage).width
        XCTAssertEqual(attachments.count, 1)
        XCTAssertFalse(rendered.string.contains("\\["))
        XCTAssertGreaterThanOrEqual(CGFloat(pixelsWide), image.size.width * 3.5)
    }

    func testMobileArrowAttachmentTracksAnArbitraryPointThroughTargetChanges() throws {
        var text = TextElement.make(frame: CanvasRect(x: 100, y: 100, width: 200, height: 100))
        var scene = CanvasSceneDocument.blank()
        scene.elements = [.text(text)]
        let attachment = try XCTUnwrap(MobileCanvasConnectionGeometry.attachment(
            to: CanvasPoint(x: 140, y: 170),
            in: scene
        ))

        text.geometry.frame = CanvasRect(x: 300, y: 200, width: 400, height: 200)
        scene.replace(.text(text))
        XCTAssertEqual(
            MobileCanvasConnectionGeometry.attachmentPoint(attachment, in: scene),
            CanvasPoint(x: 380, y: 340)
        )
    }
}
