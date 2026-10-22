import AppKit
import SwiftUI

struct NotebookWorkspace: View {
    @ObservedObject var document: NotebookDocument
    let fileURL: URL?
    @StateObject private var canvasController = NativeCanvasController()
    @State private var renamedPageID: String?
    @State private var renameText = ""
    @State private var cardEditorPanel: CardEditorPanelCoordinator?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var refreshedInfinitePreviews = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color(nsColor: NSColor(calibratedWhite: 0.27, alpha: 1)), location: 0),
                    .init(color: Color(nsColor: NSColor(calibratedWhite: 0.30, alpha: 1)), location: 0.023),
                    .init(color: Color(nsColor: NSColor(calibratedWhite: 0.34, alpha: 1)), location: 0.052),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .overlay(alignment: .topLeading) {
            TransparentWindowChrome()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
        .navigationTitle("")
        .onAppear {
            canvasController.load(document: document, pageID: document.selectedPageID)
            refreshInfinitePreviewsIfNeeded()
            if cardEditorPanel == nil {
                cardEditorPanel = CardEditorPanelCoordinator(sourceController: canvasController)
            }
            applyPendingNavigation()
            applyPendingPageCreation()
            Task { await NotebookRoutineProvider.publish() }
        }
        .onDisappear { cardEditorPanel?.close() }
        .onOpenURL { url in
            if url.host == "routine-action" { Task { await NotebookRoutineController.shared.handle(url: url) } }
            else { NotesNavigationCoordinator.shared.handle(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notebookNavigationAvailable)) { _ in
            applyPendingNavigation()
            applyPendingPageCreation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createNotebookPage)) { notification in
            guard let target = notification.object as? NativeCanvasController,
                  target === canvasController else { return }
            addPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNotebookSidebar)) { _ in
            withAnimation(.snappy(duration: 0.25)) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
        .onReceive(canvasController.$cardEditorRequest) { request in
            guard let request else { return }
            cardEditorPanel?.present(card: request.card)
            canvasController.cardEditorRequest = nil
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

    private func applyPendingPageCreation() {
        guard NotesNavigationCoordinator.shared.takePendingNewPage(for: document.package.manifest.notebookID) else { return }
        addPage()
    }

    private func refreshInfinitePreviewsIfNeeded() {
        guard !refreshedInfinitePreviews else { return }
        refreshedInfinitePreviews = true
        let renderer = CanvasPreviewRenderer()
        for page in document.pages {
            guard let scene = document.package.pagePayloads[page.id]?.scene,
                  let data = renderer.pngFittingContent(
                    scene: scene,
                    fallbackSize: CanvasSize(width: page.width, height: page.height),
                    gridPattern: page.resolvedGridPattern,
                    assetData: { document.assetData(for: $0) }
                  ) else { continue }
            document.storePreview(pageID: page.id, data: data)
        }
    }

    private var pageSidebar: some View {
        VStack(spacing: 0) {
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
        }
    }

    private func addPage() {
        document.addPage(after: document.selectedPageID)
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
            ZStack {
                Color(nsColor: .textBackgroundColor)
                if let previewData, let image = NSImage(data: previewData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.separator.opacity(0.55)))
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
