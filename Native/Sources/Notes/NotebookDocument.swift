import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class NotebookDocument: ReferenceFileDocument, ObservableObject, @unchecked Sendable {
    typealias Snapshot = NotebookPackage

    static var readableContentTypes: [UTType] { [.productivityNotebook] }
    static var writableContentTypes: [UTType] { [.productivityNotebook] }

    @Published private(set) var package: NotebookPackage
    @Published var selectedPageID: String

    init() {
        let package = NotebookPackage.blank()
        self.package = package
        self.selectedPageID = package.manifest.pages[0].id
    }

    required init(configuration: ReadConfiguration) throws {
        let package = try NotebookPackageIO.read(fileWrapper: configuration.file)
        self.package = package
        self.selectedPageID = package.manifest.pages[0].id
    }

    func snapshot(contentType: UTType) throws -> NotebookPackage { package }

    func fileWrapper(snapshot: NotebookPackage, configuration: WriteConfiguration) throws -> FileWrapper {
        try NotebookPackageIO.fileWrapper(for: snapshot)
    }

    var pages: [NotebookPageMetadata] { package.manifest.pages }
    var selectedPage: NotebookPageMetadata? { page(id: selectedPageID) }
    var selectedPayload: NotebookPagePayload? { package.pagePayloads[selectedPageID] }

    func page(id: String) -> NotebookPageMetadata? {
        package.manifest.pages.first { $0.id == id }
    }

    @discardableResult
    func addPage(
        after pageID: String? = nil,
        orientation: NotebookPageOrientation = .portrait
    ) -> String {
        var metadata = NotebookPageMetadata.make(title: nextPageTitle(), orientation: orientation)
        metadata.revision = 0
        let insertionIndex = pageID.flatMap { id in
            package.manifest.pages.firstIndex { $0.id == id }.map { $0 + 1 }
        } ?? package.manifest.pages.endIndex
        package.manifest.pages.insert(metadata, at: insertionIndex)
        package.pagePayloads[metadata.id] = .blank(pageID: metadata.id)
        package.manifest.updatedAt = Date()
        selectedPageID = metadata.id
        objectWillChange.send()
        return metadata.id
    }

    @discardableResult
    func duplicatePage(id: String) -> String? {
        guard let index = package.manifest.pages.firstIndex(where: { $0.id == id }),
              let source = package.pagePayloads[id] else { return nil }
        var copy = package.manifest.pages[index]
        copy.id = UUID().uuidString.lowercased()
        copy.title = uniquePageTitle(base: "\(copy.title) Copy")
        copy.revision = 0
        copy.createdAt = Date()
        copy.updatedAt = copy.createdAt
        var payload = source
        payload.pageID = copy.id
        payload.revision = 0
        package.manifest.pages.insert(copy, at: index + 1)
        package.pagePayloads[copy.id] = payload
        package.manifest.updatedAt = Date()
        selectedPageID = copy.id
        objectWillChange.send()
        return copy.id
    }

    func deletePage(id: String) {
        guard package.manifest.pages.count > 1,
              let index = package.manifest.pages.firstIndex(where: { $0.id == id }) else { return }
        package.manifest.pages.remove(at: index)
        package.pagePayloads[id] = nil
        package.previews["pages/\(id).png"] = nil
        if package.manifest.coverPageID == id {
            package.manifest.coverPageID = package.manifest.pages[0].id
            refreshCoverPreview()
        }
        if selectedPageID == id {
            selectedPageID = package.manifest.pages[min(index, package.manifest.pages.count - 1)].id
        }
        package.manifest.updatedAt = Date()
        objectWillChange.send()
    }

    func movePages(from offsets: IndexSet, to destination: Int) {
        package.manifest.pages.move(fromOffsets: offsets, toOffset: destination)
        package.manifest.updatedAt = Date()
        objectWillChange.send()
    }

    func renamePage(id: String, to proposedTitle: String) {
        guard let index = package.manifest.pages.firstIndex(where: { $0.id == id }) else { return }
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        package.manifest.pages[index].title = title.isEmpty ? "Untitled Page" : title
        package.manifest.pages[index].updatedAt = Date()
        package.manifest.updatedAt = Date()
        objectWillChange.send()
    }

    func setCoverPage(id: String) {
        guard page(id: id) != nil else { return }
        package.manifest.coverPageID = id
        package.manifest.updatedAt = Date()
        refreshCoverPreview()
        objectWillChange.send()
    }

    func setOrientation(_ orientation: NotebookPageOrientation, for id: String) {
        guard let index = package.manifest.pages.firstIndex(where: { $0.id == id }) else { return }
        package.manifest.pages[index].orientation = orientation
        package.manifest.pages[index].width = orientation == .portrait ? NotebookFormat.defaultWidth : NotebookFormat.defaultHeight
        package.manifest.pages[index].height = orientation == .portrait ? NotebookFormat.defaultHeight : NotebookFormat.defaultWidth
        package.manifest.pages[index].updatedAt = Date()
        package.manifest.updatedAt = Date()
        objectWillChange.send()
    }

    @discardableResult
    func updateCanvas(pageID: String, expectedRevision: Int, canvas: JSONValue) -> Int? {
        guard let index = package.manifest.pages.firstIndex(where: { $0.id == pageID }),
              var payload = package.pagePayloads[pageID],
              payload.revision == expectedRevision,
              package.manifest.pages[index].revision == expectedRevision else { return nil }
        payload.revision += 1
        payload.canvas = canvas
        package.pagePayloads[pageID] = payload
        package.manifest.requiredPlugins = Self.pluginRequirements(in: package.pagePayloads.values.map(\.canvas))
        package.manifest.pages[index].revision = payload.revision
        package.manifest.pages[index].updatedAt = Date()
        package.manifest.updatedAt = Date()
        objectWillChange.send()
        return payload.revision
    }

    func storePreview(pageID: String, data: Data) {
        guard page(id: pageID) != nil else { return }
        package.previews["pages/\(pageID).png"] = data
        if package.manifest.coverPageID == pageID {
            package.previews["cover.png"] = data
        }
        package.manifest.updatedAt = Date()
        objectWillChange.send()
    }

    func storeCardTierPreviews(pageID: String, cardID: String, previews: [(tierID: String, revision: Int, data: Data)]) {
        guard page(id: pageID) != nil else { return }
        let card = Self.safePreviewComponent(cardID)
        for preview in previews {
            let tier = Self.safePreviewComponent(preview.tierID)
            let prefix = "cards/\(card)/\(tier)-"
            package.previews = package.previews.filter { !$0.key.hasPrefix(prefix) }
            package.previews["\(prefix)\(preview.revision).jpg"] = preview.data
        }
        package.manifest.updatedAt = Date()
        objectWillChange.send()
    }

    @discardableResult
    func importAsset(data: Data, originalFilename: String, mediaType: String) -> NotebookAssetMetadata {
        let hash = NotebookPackageIO.contentHash(for: data)
        if let existing = package.manifest.assets.first(where: { $0.hash == hash }) {
            return existing
        }
        let filename = NotebookPackageIO.assetFilename(hash: hash, originalFilename: originalFilename)
        let thumbnailFilename = NotebookPackageIO.thumbnailPNG(for: data).map { thumbnail in
            let path = "thumbnails/\(hash).png"
            package.assets[path] = thumbnail
            return path
        }
        let metadata = NotebookAssetMetadata(
            hash: hash,
            filename: filename,
            thumbnailFilename: thumbnailFilename,
            mediaType: mediaType,
            byteCount: data.count,
            createdAt: Date()
        )
        package.assets[filename] = data
        package.manifest.assets.append(metadata)
        package.manifest.updatedAt = Date()
        objectWillChange.send()
        return metadata
    }

    func preview(for pageID: String) -> Data? {
        package.previews["pages/\(pageID).png"]
    }

    private func refreshCoverPreview() {
        if let preview = package.previews["pages/\(package.manifest.coverPageID).png"] {
            package.previews["cover.png"] = preview
        }
    }

    private func nextPageTitle() -> String {
        var index = package.manifest.pages.count + 1
        while package.manifest.pages.contains(where: { $0.title == "Page \(index)" }) { index += 1 }
        return "Page \(index)"
    }

    private func uniquePageTitle(base: String) -> String {
        if !package.manifest.pages.contains(where: { $0.title == base }) { return base }
        var index = 2
        while package.manifest.pages.contains(where: { $0.title == "\(base) \(index)" }) { index += 1 }
        return "\(base) \(index)"
    }

    private static func safePreviewComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private static func pluginRequirements(in values: [JSONValue]) -> [NotebookPluginRequirement] {
        var requirements: [String: String] = [:]
        func collect(_ value: JSONValue) {
            switch value {
            case let .object(fields):
                let identifier = fields["pluginId"]?.stringValue ?? fields["pluginID"]?.stringValue
                if let identifier {
                    let version = fields["pluginVersion"]?.stringValue
                        ?? fields["pluginVersion"]?.numberValue.map { String(Int($0)) }
                        ?? "1"
                    requirements[identifier] = version
                }
                fields.values.forEach(collect)
            case let .array(items):
                items.forEach(collect)
            default:
                break
            }
        }
        values.forEach(collect)
        return requirements.keys.sorted().map {
            NotebookPluginRequirement(identifier: $0, version: requirements[$0] ?? "1")
        }
    }
}
