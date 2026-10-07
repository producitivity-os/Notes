import Foundation

@MainActor
struct CanvasEnvironment {
    var assetData: (String) -> Data?
    var importAsset: (Data, String, String) -> NotebookAssetMetadata?

    static let empty = CanvasEnvironment(
        assetData: { _ in nil },
        importAsset: { _, _, _ in nil }
    )
}
