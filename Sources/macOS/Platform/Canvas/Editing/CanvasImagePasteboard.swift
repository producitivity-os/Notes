import AppKit
import UniformTypeIdentifiers

struct CanvasClipboardImage {
    let data: Data
    let filename: String
    let mediaType: String
}

@MainActor
enum CanvasImagePasteboard {
    static func read(from pasteboard: NSPasteboard) -> CanvasClipboardImage? {
        if let path = pasteboard.string(forType: .fileURL),
           let url = URL(string: path),
           let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           values.contentType?.conforms(to: .image) == true,
           let data = try? Data(contentsOf: url) {
            return CanvasClipboardImage(
                data: data,
                filename: url.lastPathComponent,
                mediaType: values.contentType?.identifier ?? UTType.image.identifier
            )
        }
        if let data = pasteboard.data(forType: .png) {
            return CanvasClipboardImage(data: data, filename: "Pasted Image.png", mediaType: UTType.png.identifier)
        }
        if let data = pasteboard.data(forType: .tiff), let png = pngData(from: data) {
            return CanvasClipboardImage(data: png, filename: "Pasted Image.png", mediaType: UTType.png.identifier)
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = pngData(from: tiff) else { return nil }
        return CanvasClipboardImage(data: png, filename: "Pasted Image.png", mediaType: UTType.png.identifier)
    }

    static func write(_ data: Data, to pasteboard: NSPasteboard) {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let png = pngData(from: tiff) else { return }
        pasteboard.setData(png, forType: .png)
    }

    private static func pngData(from data: Data) -> Data? {
        NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
    }
}
