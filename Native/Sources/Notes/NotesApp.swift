import SwiftUI
import AppKit

@main
struct NotesApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { NotebookDocument() }) { configuration in
            NotebookWorkspace(document: configuration.document, fileURL: configuration.fileURL)
                .frame(minWidth: 760, minHeight: 560)
                .onAppear {
                    guard let url = configuration.fileURL,
                          let store = try? ReviewFileStore() else { return }
                    try? store.register(notebookURL: url, manifest: configuration.document.package.manifest)
                }
                .onChange(of: configuration.fileURL) { _, url in
                    guard let url, let store = try? ReviewFileStore() else { return }
                    try? store.register(notebookURL: url, manifest: configuration.document.package.manifest)
                }
        }
        .defaultSize(width: 1100, height: 760)

        Settings {
            NotesSettingsView()
                .frame(width: 520, height: 300)
        }
    }
}

extension Notification.Name {
    static let notebookNavigationAvailable = Notification.Name("NotebookNavigationAvailable")
}

@MainActor
final class NotesNavigationCoordinator {
    static let shared = NotesNavigationCoordinator()
    private var pending: [NotebookNavigationRequest] = []

    func handle(_ url: URL) {
        guard url.scheme == "productivity-notes",
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let requestID = components.queryItems?.first(where: { $0.name == "request" })?.value,
              let store = try? ReviewFileStore(),
              let request = try? store.takeNavigationRequest(id: requestID),
              let registration = (try? store.registeredNotebooks())?.first(where: { $0.notebookID == request.notebookID }),
              let notebookURL = store.resolve(registration) else { return }
        pending.removeAll { $0.id == request.id }
        pending.append(request)
        NSWorkspace.shared.open(notebookURL)
        NotificationCenter.default.post(name: .notebookNavigationAvailable, object: nil)
    }

    func take(for notebookID: String) -> NotebookNavigationRequest? {
        guard let index = pending.firstIndex(where: { $0.notebookID == notebookID }) else { return nil }
        return pending.remove(at: index)
    }
}
