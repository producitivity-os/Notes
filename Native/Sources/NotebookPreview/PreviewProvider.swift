import AppKit
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        do {
            let package = try NotebookPackageIO.read(at: request.fileURL, verifyAssetHashes: false)
            guard let cover = package.previews["cover.png"], let image = NSImage(data: cover) else {
                handler(try textPreview(for: package, title: request.fileURL.deletingPathExtension().lastPathComponent), nil)
                return
            }
            let reply = QLPreviewReply(dataOfContentType: .png, contentSize: image.size) { _ in cover }
            reply.title = request.fileURL.deletingPathExtension().lastPathComponent
            handler(reply, nil)
        } catch {
            handler(nil, error)
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
