import SwiftUI

struct NotesSettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Infinite Canvas",
            systemImage: "circle.hexagongrid.fill",
            description: Text("Notebook pages grow with your ideas, so there is no page orientation to configure.")
        )
    }
}
