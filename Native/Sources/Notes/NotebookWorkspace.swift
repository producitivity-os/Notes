import AppKit
import SwiftUI

struct NotebookWorkspace: View {
    @ObservedObject var document: NotebookDocument
    let fileURL: URL?
    @StateObject private var canvasController = CanvasWebController()
    @State private var renamedPageID: String?
    @State private var renameText = ""
    @State private var errorMessage: String?
    @AppStorage("newPageOrientation") private var newPageOrientation = NotebookPageOrientation.portrait.rawValue

    var body: some View {
        NavigationSplitView {
            pageSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 300)
        } detail: {
            CanvasWebView(document: document, controller: canvasController)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationTitle(fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled Notebook")
        .onAppear { applyPendingNavigation() }
        .onOpenURL { NotesNavigationCoordinator.shared.handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .notebookNavigationAvailable)) { _ in
            applyPendingNavigation()
        }
        .onDisappear { canvasController.flush() }
        .onReceive(NotificationCenter.default.publisher(for: .notebookCanvasError)) { notification in
            errorMessage = notification.object as? String
        }
        .alert("Canvas Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Rename Page", isPresented: Binding(
            get: { renamedPageID != nil },
            set: { if !$0 { renamedPageID = nil } }
        )) {
            TextField("Page name", text: $renameText)
            Button("Cancel", role: .cancel) { renamedPageID = nil }
            Button("Rename") {
                if let renamedPageID { document.renamePage(id: renamedPageID, to: renameText) }
                renamedPageID = nil
            }
        }
    }

    private func applyPendingNavigation() {
        guard let request = NotesNavigationCoordinator.shared.take(for: document.package.manifest.notebookID) else { return }
        canvasController.navigate(pageID: request.pageID, objectID: request.objectID)
    }

    private var pageSidebar: some View {
        List(selection: selection) {
            ForEach(document.pages) { page in
                PageSidebarRow(
                    page: page,
                    previewData: document.preview(for: page.id),
                    isCover: document.package.manifest.coverPageID == page.id
                )
                .tag(page.id)
                .contextMenu { pageMenu(page) }
            }
            .onMove { document.movePages(from: $0, to: $1) }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { addPage() } label: {
                    Label("Add Page", systemImage: "plus")
                }
                Spacer()
                Text("Drag pages to reorder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.iconOnly)
            .padding(10)
            .background(.ultraThinMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { addPage() } label: {
                    Label("Add Page", systemImage: "plus")
                }
            }
        }
    }

    private func addPage() {
        let orientation = NotebookPageOrientation(rawValue: newPageOrientation) ?? .portrait
        document.addPage(after: document.selectedPageID, orientation: orientation)
        canvasController.refreshCurrentPage()
    }

    private var selection: Binding<String?> {
        Binding(
            get: { document.selectedPageID },
            set: { value in
                guard let value else { return }
                canvasController.selectPage(value)
            }
        )
    }

    @ViewBuilder
    private func pageMenu(_ page: NotebookPageMetadata) -> some View {
        Button("Rename", systemImage: "pencil") {
            renameText = page.title
            renamedPageID = page.id
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            document.duplicatePage(id: page.id)
            canvasController.refreshCurrentPage()
        }
        Menu("Orientation", systemImage: "rectangle.portrait.rotate") {
            Button("Portrait") {
                document.setOrientation(.portrait, for: page.id)
                canvasController.refreshCurrentPage()
            }
            Button("Landscape") {
                document.setOrientation(.landscape, for: page.id)
                canvasController.refreshCurrentPage()
            }
        }
        Button("Set as Cover", systemImage: "book.closed") { document.setCoverPage(id: page.id) }
            .disabled(document.package.manifest.coverPageID == page.id)
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            document.deletePage(id: page.id)
            canvasController.refreshCurrentPage()
        }
        .disabled(document.pages.count == 1)
    }
}

private struct PageSidebarRow: View {
    let page: NotebookPageMetadata
    let previewData: Data?
    let isCover: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let previewData, let image = NSImage(data: previewData) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    ZStack {
                        Color.white
                        Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: page.orientation == .portrait ? 52 : 68, height: page.orientation == .portrait ? 74 : 52)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator.opacity(0.55)))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(page.title).lineLimit(2)
                if isCover {
                    Label("Cover", systemImage: "book.closed.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}
