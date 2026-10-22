import Foundation
import ProductivityRoutineKit

@MainActor
enum NotebookRoutineProvider {
    static let providerID = "com.productivity-os.notes"

    static func publish() async {
        guard var manifest = RoutineActionRegistry.provider(id: providerID) else { return }
        manifest.updatedAt = .now
        await RoutineActionClient.shared.publish(manifest)
        #if os(macOS)
        guard let store = try? ReviewFileStore(), let notebooks = try? store.registeredNotebooks() else { return }
        for actionID in ["open-notebook", "new-page"] {
            let statuses = notebooks.map { notebook in
                RoutineStatusSnapshot(
                    id: "notes.\(actionID).\(notebook.notebookID)",
                    providerID: providerID,
                    actionID: actionID,
                    title: notebook.displayName,
                    subtitle: actionID == "new-page" ? "Create a page" : "Open notebook",
                    metadata: ["notebookID": notebook.notebookID]
                )
            }
            await RoutineActionClient.shared.replaceStatuses(providerID: providerID, actionID: actionID, with: statuses)
        }
        #endif
    }
}
