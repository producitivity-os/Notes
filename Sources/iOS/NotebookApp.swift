import SwiftUI
import ProductivityRoutineKit

@main
struct NotebookIOSApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { NotebookDocument() }) { configuration in
            NotebookMobileWorkspace(document: configuration.document)
                .task { await NotebookRoutineProvider.publish() }
                .onOpenURL { url in
                    Task {
                        guard let request = try? await RoutineActionClient.shared.request(from: url),
                              request.providerID == NotebookRoutineProvider.providerID else { return }
                        await RoutineActionClient.shared.update(request, state: .running, message: "Opening Notebook")
                        if request.actionID == "new-page" {
                            _ = configuration.document.addPage(after: configuration.document.selectedPageID)
                        }
                        await RoutineActionClient.shared.update(request, state: .completed, message: "Notebook opened")
                    }
                }
        }
    }
}
