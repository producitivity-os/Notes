import AppKit
import UniformTypeIdentifiers

@objc(ReviseNotebookAction)
final class ReviseNotebookAction: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            context.cancelRequest(withError: ActionError.missingNotebook)
            return
        }
        let context = SendableExtensionContext(context)

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
            if let error {
                context.value.cancelRequest(withError: error)
                return
            }
            let url: URL?
            if let value = value as? URL { url = value }
            else if let data = value as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = nil }
            guard let url else {
                context.value.cancelRequest(withError: ActionError.missingNotebook)
                return
            }
            do {
                let package = try NotebookPackageIO.read(at: url, verifyAssetHashes: false)
                let request = try ReviewFileStore().createLaunchRequest(notebookURL: url, manifest: package.manifest)
                guard let deepLink = URL(string: "productivity-review://notebook?request=\(request.id)") else {
                    throw ActionError.invalidDeepLink
                }
                context.value.open(deepLink) { success in
                    if success { context.value.completeRequest(returningItems: [], completionHandler: nil) }
                    else { context.value.cancelRequest(withError: ActionError.couldNotOpenReview) }
                }
            } catch {
                context.value.cancelRequest(withError: error)
            }
        }
    }
}

private final class SendableExtensionContext: @unchecked Sendable {
    let value: NSExtensionContext

    init(_ value: NSExtensionContext) {
        self.value = value
    }
}

private enum ActionError: LocalizedError {
    case missingNotebook
    case invalidDeepLink
    case couldNotOpenReview

    var errorDescription: String? {
        switch self {
        case .missingNotebook: "Select one notebook to review."
        case .invalidDeepLink: "The Review launch request is invalid."
        case .couldNotOpenReview: "Review could not be opened."
        }
    }
}
