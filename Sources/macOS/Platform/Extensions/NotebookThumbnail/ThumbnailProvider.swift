import AppKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let coverURL = request.fileURL.appendingPathComponent(NotebookFormat.coverPreviewPath)
        if FileManager.default.fileExists(atPath: coverURL.path) {
            let reply = QLThumbnailReply(imageFileURL: coverURL)
            reply.extensionBadge = "notebook"
            handler(reply, nil)
            return
        }

        let size = request.maximumSize
        let reply = QLThumbnailReply(contextSize: size) {
            let rect = CGRect(origin: .zero, size: size)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)).fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1)).stroke()
            let symbol = NSImage(systemSymbolName: "book.pages", accessibilityDescription: "Notebook")
            symbol?.draw(in: rect.insetBy(dx: size.width * 0.24, dy: size.height * 0.24))
            return true
        }
        reply.extensionBadge = "notebook"
        handler(reply, nil)
    }
}
