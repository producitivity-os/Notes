import AppKit
import PDFKit
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        do {
            let package = try NotebookPackageIO.read(at: request.fileURL, verifyAssetHashes: false)
            guard let data = pdfPreview(for: package) else {
                handler(try textPreview(for: package, title: request.fileURL.deletingPathExtension().lastPathComponent), nil)
                return
            }
            let size = package.manifest.pages.lazy.compactMap { metadata in
                package.previews["pages/\(metadata.id).png"]
                    .flatMap(NSImage.init(data:))?
                    .size
            }.first ?? CGSize(width: 640, height: 480)
            let reply = QLPreviewReply(dataOfContentType: .pdf, contentSize: size) { _ in data }
            reply.title = request.fileURL.deletingPathExtension().lastPathComponent
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }

    private func pdfPreview(for package: NotebookPackage) -> Data? {
        let document = PDFDocument()
        for metadata in package.manifest.pages {
            let preview = package.previews["pages/\(metadata.id).png"]
            let image = preview.flatMap(NSImage.init(data:)) ?? placeholder(for: metadata)
            guard let page = PDFPage(image: image) else { continue }
            document.insert(page, at: document.pageCount)
        }
        guard document.pageCount > 0 else { return nil }
        return document.dataRepresentation()
    }

    private func placeholder(for page: NotebookPageMetadata) -> NSImage {
        let size = CGSize(width: page.width, height: page.height)
        return NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            let spacing: CGFloat = 28
            NSColor(calibratedWhite: 0.38, alpha: 0.34).setFill()
            switch page.resolvedGridPattern {
            case .blank:
                break
            case .grid:
                let path = NSBezierPath()
                var x = rect.minX
                while x <= rect.maxX {
                    path.move(to: CGPoint(x: x, y: rect.minY))
                    path.line(to: CGPoint(x: x, y: rect.maxY))
                    x += spacing
                }
                var y = rect.minY
                while y <= rect.maxY {
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.line(to: CGPoint(x: rect.maxX, y: y))
                    y += spacing
                }
                NSColor(calibratedWhite: 0.42, alpha: 0.28).setStroke()
                path.lineWidth = 1
                path.stroke()
            case .dots, .isometric:
                let isometric = page.resolvedGridPattern == .isometric
                let verticalSpacing = isometric ? spacing * sqrt(3) / 2 : spacing
                for row in 0...Int(ceil(rect.height / verticalSpacing)) {
                    let offset = isometric && !row.isMultiple(of: 2) ? spacing / 2 : 0
                    var x = rect.minX + offset
                    let y = rect.minY + CGFloat(row) * verticalSpacing
                    while x <= rect.maxX {
                        NSBezierPath(ovalIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
                        x += spacing
                    }
                }
            }
            return true
        }
    }

    private func textPreview(for package: NotebookPackage, title: String) throws -> QLPreviewReply {
        let pageNames = package.manifest.pages.map(\.title).joined(separator: "\n")
        let source = "\(title)\n\n\(package.manifest.pages.count) pages\n\n\(pageNames)"
        let data = Data(source.utf8)
        let reply = QLPreviewReply(dataOfContentType: .plainText, contentSize: CGSize(width: 640, height: 800)) { _ in data }
        reply.title = title
        return reply
    }
}
