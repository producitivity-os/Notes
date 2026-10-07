import AppKit
import SwiftUI

struct NotebookWorkspace: View {
    @ObservedObject var document: NotebookDocument
    let fileURL: URL?
    @StateObject private var canvasController = NativeCanvasController()
    @State private var renamedPageID: String?
    @State private var renameText = ""
    @AppStorage("newPageOrientation") private var newPageOrientation = NotebookPageOrientation.portrait.rawValue

    var body: some View {
        NavigationSplitView {
            pageSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 300)
        } detail: {
            ZStack(alignment: .top) {
                NativeCanvasHost(controller: canvasController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CanvasToolbarView(controller: canvasController)
                    .padding(.top, 12)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationTitle("")
        .onAppear {
            canvasController.load(document: document, pageID: document.selectedPageID)
            applyPendingNavigation()
        }
        .onOpenURL { NotesNavigationCoordinator.shared.handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .notebookNavigationAvailable)) { _ in
            applyPendingNavigation()
        }
        .sheet(item: Binding(
            get: { canvasController.cardEditorRequest },
            set: { canvasController.cardEditorRequest = $0 }
        )) { request in
            CardEditorSheet(card: request.card, sourceController: canvasController) { card in
                canvasController.saveEditedCard(card)
            }
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
        if let pageID = request.pageID, document.page(id: pageID) != nil {
            document.selectedPageID = pageID
            canvasController.load(document: document, pageID: pageID)
        }
        if canvasController.scene.element(id: request.objectID) != nil {
            canvasController.selection.selectOnly(request.objectID)
        }
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
        canvasController.load(document: document, pageID: document.selectedPageID)
    }

    private var selection: Binding<String?> {
        Binding(
            get: { document.selectedPageID },
            set: { value in
                guard let value else { return }
                document.selectedPageID = value
                canvasController.load(document: document, pageID: value)
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
            canvasController.load(document: document, pageID: document.selectedPageID)
        }
        Menu("Orientation", systemImage: "rectangle.portrait.rotate") {
            Button("Portrait") {
                document.setOrientation(.portrait, for: page.id)
                if document.selectedPageID == page.id { canvasController.load(document: document, pageID: page.id) }
            }
            Button("Landscape") {
                document.setOrientation(.landscape, for: page.id)
                if document.selectedPageID == page.id { canvasController.load(document: document, pageID: page.id) }
            }
        }
        Button("Set as Cover", systemImage: "book.closed") { document.setCoverPage(id: page.id) }
            .disabled(document.package.manifest.coverPageID == page.id)
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            document.deletePage(id: page.id)
            canvasController.load(document: document, pageID: document.selectedPageID)
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
