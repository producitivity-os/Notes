import SwiftUI
import AppKit
import ProductivityRoutineKit

@main
struct NotesApp: App {
    @NSApplicationDelegateAdaptor(RoutineDockMenuApplicationDelegate.self) private var appDelegate

    init() {
        RoutineDockMenuController.shared.configure(items: { NotebookRoutineController.shared.dockMenuItems() }) { request in
            Task { await NotebookRoutineController.shared.handle(request) }
        }
    }

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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Page") {
                    NotesDocumentCommands.createPageOrNotebook()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Notebook") {
                    NSDocumentController.shared.newDocument(nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleNotebookSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }

    }
}

extension Notification.Name {
    static let notebookNavigationAvailable = Notification.Name("NotebookNavigationAvailable")
    static let createNotebookPage = Notification.Name("CreateNotebookPage")
    static let toggleNotebookSidebar = Notification.Name("ToggleNotebookSidebar")
}

@MainActor
enum NotesDocumentCommands {
    static func createPageOrNotebook() {
        let candidateWindow = NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow
        if let canvas = notebookCanvas(in: candidateWindow?.contentView) {
            NotificationCenter.default.post(name: .createNotebookPage, object: canvas.controller)
        } else {
            NSDocumentController.shared.newDocument(nil)
        }
    }

    private static func notebookCanvas(in view: NSView?) -> NativeCanvasView? {
        guard let view else { return nil }
        if let canvas = view as? NativeCanvasView, canvas.controller.pageID != nil { return canvas }
        for child in view.subviews {
            if let canvas = notebookCanvas(in: child) { return canvas }
        }
        return nil
    }
}

@MainActor
final class NotesNavigationCoordinator {
    static let shared = NotesNavigationCoordinator()
    private var pending: [NotebookNavigationRequest] = []
    private var pendingNewPages: Set<String> = []

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

    func openNotebook(id notebookID: String, createsPage: Bool) {
        guard let store = try? ReviewFileStore(),
              let registration = (try? store.registeredNotebooks())?.first(where: { $0.notebookID == notebookID }),
              let notebookURL = store.resolve(registration) else { return }
        if createsPage { pendingNewPages.insert(notebookID) }
        NSWorkspace.shared.open(notebookURL)
        NotificationCenter.default.post(name: .notebookNavigationAvailable, object: nil)
    }

    func takePendingNewPage(for notebookID: String) -> Bool {
        pendingNewPages.remove(notebookID) != nil
    }
}

@MainActor
final class NotebookRoutineController {
    static let shared = NotebookRoutineController()
    private init() {}

    func dockMenuItems() -> [RoutineDockMenuItem] {
        let registered = (try? ReviewFileStore().registeredNotebooks()) ?? []
        let notebooks = registered.map { notebook in
            RoutineDockMenuItem(
                providerID: NotebookRoutineProvider.providerID,
                actionID: "open-notebook",
                title: notebook.displayName,
                configuration: ["notebookID": notebook.notebookID]
            )
        }
        let pages = registered.map { notebook in
            RoutineDockMenuItem(
                providerID: NotebookRoutineProvider.providerID,
                actionID: "new-page",
                title: notebook.displayName,
                configuration: ["notebookID": notebook.notebookID]
            )
        }
        return [
            notebooks.isEmpty
                ? RoutineDockMenuItem(providerID: NotebookRoutineProvider.providerID, actionID: "open-notebook")
                : RoutineDockMenuItem(providerID: NotebookRoutineProvider.providerID, actionID: "open-notebook", children: notebooks),
            pages.isEmpty
                ? RoutineDockMenuItem(providerID: NotebookRoutineProvider.providerID, actionID: "new-page")
                : RoutineDockMenuItem(providerID: NotebookRoutineProvider.providerID, actionID: "new-page", children: pages)
        ]
    }

    func handle(url: URL) async {
        guard let request = try? await RoutineActionClient.shared.request(from: url) else { return }
        await handle(request)
    }

    func handle(_ request: RoutineActionRequest) async {
        guard request.providerID == NotebookRoutineProvider.providerID else { return }
        await RoutineActionClient.shared.update(request, state: .running, message: "Opening Notebook")
        let notebookID = request.configuration["notebookID"]
        switch request.actionID {
        case "open-notebook":
            if let notebookID { NotesNavigationCoordinator.shared.openNotebook(id: notebookID, createsPage: false) }
            else { NSApp.activate(ignoringOtherApps: true) }
        case "new-page":
            if let notebookID { NotesNavigationCoordinator.shared.openNotebook(id: notebookID, createsPage: true) }
            else { NotesDocumentCommands.createPageOrNotebook() }
        default:
            await RoutineActionClient.shared.update(request, state: .failed, message: "Unsupported Notebook action")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        await RoutineActionClient.shared.update(request, state: .completed, message: "Notebook opened")
    }
}
