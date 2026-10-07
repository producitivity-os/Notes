import SwiftUI

struct NotesSettingsView: View {
    @AppStorage("newPageOrientation") private var newPageOrientation = NotebookPageOrientation.portrait.rawValue

    var body: some View {
        Form {
            Picker("New page orientation", selection: $newPageOrientation) {
                Text("Portrait").tag(NotebookPageOrientation.portrait.rawValue)
                Text("Landscape").tag(NotebookPageOrientation.landscape.rawValue)
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .padding()
    }
}
