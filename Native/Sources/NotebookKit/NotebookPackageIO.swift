import CryptoKit
import Foundation
import ImageIO
import AppKit

enum NotebookPackageIO {
    static func read(fileWrapper: FileWrapper) throws -> NotebookPackage {
        try read(fileWrapper: fileWrapper, verifyAssetHashes: true)
    }

    private static func read(fileWrapper: FileWrapper, verifyAssetHashes: Bool) throws -> NotebookPackage {
        guard fileWrapper.isDirectory, let root = fileWrapper.fileWrappers else {
            throw NotebookPackageError.invalidPackage
        }
        guard let manifestData = root[NotebookFormat.manifestName]?.regularFileContents else {
            throw NotebookPackageError.missingManifest
        }

        let manifest = try NotebookCoding.decoder.decode(NotebookManifest.self, from: manifestData)
        guard let pageFiles = root[NotebookFormat.pagesDirectory]?.fileWrappers else {
            throw NotebookPackageError.missingPages
        }

        var pages: [String: NotebookPagePayload] = [:]
        for metadata in manifest.pages {
            let filename = "\(metadata.id).json"
            guard let data = pageFiles[filename]?.regularFileContents else {
                throw NotebookPackageError.missingPage(metadata.id)
            }
            pages[metadata.id] = try NotebookCoding.decoder.decode(NotebookPagePayload.self, from: data)
        }

        var package = NotebookPackage(
            manifest: manifest,
            pagePayloads: pages,
            assets: readFiles(in: root[NotebookFormat.assetsDirectory]),
            previews: readFiles(in: root[NotebookFormat.previewsDirectory])
        )
        try package.normalize()
        if verifyAssetHashes { try verifyAssets(in: package) }
        return package
    }

    static func read(at packageURL: URL, verifyAssetHashes: Bool = true) throws -> NotebookPackage {
        let wrapper = try FileWrapper(url: packageURL, options: [.immediate])
        var package = try read(fileWrapper: wrapper, verifyAssetHashes: verifyAssetHashes)
        try package.normalize()
        return package
    }

    static func fileWrapper(for package: NotebookPackage) throws -> FileWrapper {
        var normalized = package
        try normalized.normalize()

        let root = FileWrapper(directoryWithFileWrappers: [:])
        let manifest = FileWrapper(regularFileWithContents: try NotebookCoding.encoder.encode(normalized.manifest))
        manifest.preferredFilename = NotebookFormat.manifestName
        root.addFileWrapper(manifest)

        let pages = FileWrapper(directoryWithFileWrappers: [:])
        pages.preferredFilename = NotebookFormat.pagesDirectory
        for metadata in normalized.manifest.pages {
            guard let page = normalized.pagePayloads[metadata.id] else {
                throw NotebookPackageError.missingPage(metadata.id)
            }
            let wrapper = FileWrapper(regularFileWithContents: try NotebookCoding.encoder.encode(page))
            wrapper.preferredFilename = "\(metadata.id).json"
            pages.addFileWrapper(wrapper)
        }
        root.addFileWrapper(pages)

        root.addFileWrapper(directory(named: NotebookFormat.assetsDirectory, files: normalized.assets))
        root.addFileWrapper(directory(named: NotebookFormat.previewsDirectory, files: normalized.previews))
        return root
    }

    static func writeAtomically(_ package: NotebookPackage, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: true)
        let wrapper = try fileWrapper(for: package)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try wrapper.write(to: temporary, options: [.atomic, .withNameUpdating], originalContentsURL: nil)
        _ = try read(at: temporary)

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func assetFilename(hash: String, originalFilename: String) -> String {
        let suffix = URL(fileURLWithPath: originalFilename).pathExtension.lowercased()
        return suffix.isEmpty ? hash : "\(hash).\(suffix)"
    }

    static func thumbnailPNG(for data: Data, maximumPixelSize: Int = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
              ] as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func directory(named name: String, files: [String: Data]) -> FileWrapper {
        let directory = FileWrapper(directoryWithFileWrappers: [:])
        directory.preferredFilename = name
        for (path, data) in files {
            addFile(path: path, data: data, to: directory)
        }
        return directory
    }

    private static func addFile(path: String, data: Data, to root: FileWrapper) {
        let components = path.split(separator: "/").map(String.init)
        guard let filename = components.last else { return }
        var directory = root
        for component in components.dropLast() {
            if let existing = directory.fileWrappers?[component], existing.isDirectory {
                directory = existing
            } else {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = component
                directory.addFileWrapper(child)
                directory = child
            }
        }
        let file = FileWrapper(regularFileWithContents: data)
        file.preferredFilename = filename
        directory.addFileWrapper(file)
    }

    private static func readFiles(in wrapper: FileWrapper?) -> [String: Data] {
        guard let wrapper, wrapper.isDirectory else { return [:] }
        var result: [String: Data] = [:]
        collectFiles(in: wrapper, prefix: "", result: &result)
        return result
    }

    private static func collectFiles(in wrapper: FileWrapper, prefix: String, result: inout [String: Data]) {
        for (name, child) in wrapper.fileWrappers ?? [:] {
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if child.isDirectory {
                collectFiles(in: child, prefix: path, result: &result)
            } else if let data = child.regularFileContents {
                result[path] = data
            }
        }
    }

    private static func verifyAssets(in package: NotebookPackage) throws {
        for metadata in package.manifest.assets {
            guard let data = package.assets[metadata.filename], contentHash(for: data) == metadata.hash else {
                throw NotebookPackageError.invalidAssetHash(metadata.hash)
            }
            if let thumbnail = metadata.thumbnailFilename, package.assets[thumbnail] == nil {
                throw NotebookPackageError.invalidAssetHash(metadata.hash)
            }
        }
    }
}
