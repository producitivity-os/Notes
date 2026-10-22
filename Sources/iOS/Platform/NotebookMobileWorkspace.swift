import SwiftUI
import UIKit

struct NotebookMobileWorkspace: View {
    @ObservedObject var document: NotebookDocument
    @State private var showsPages = false
    @State private var showsNewCard = false
    @State private var cardTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if let page = document.selectedPage,
                   let payload = document.selectedPayload {
                    NotebookMobileCanvas(
                        page: page,
                        scene: payload.scene,
                        assetData: document.assetData,
                        onSceneChange: { updated in
                            document.updateScene(pageID: page.id, scene: updated)
                        }
                    )
                } else {
                    ContentUnavailableView("No Page", systemImage: "doc")
                }
            }
            .background(Color(uiColor: .systemGray5))
            .navigationTitle(document.selectedPage?.title ?? "Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Pages", systemImage: "sidebar.left") { showsPages = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Card", systemImage: "rectangle") {
                            cardTitle = ""
                            showsNewCard = true
                        }
                        Button("Arrow", systemImage: "arrow.right") { addArrow() }
                        Divider()
                        Button("Page", systemImage: "doc.badge.plus") { addPage() }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showsPages) {
            NavigationStack {
                List(selection: pageSelection) {
                    ForEach(document.pages) { page in
                        HStack(spacing: 12) {
                            PagePreview(data: document.preview(for: page.id))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(page.title)
                                Text("Infinite Canvas")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(page.id)
                        .swipeActions {
                            Button(role: .destructive) { document.deletePage(id: page.id) } label: {
                                Label("Delete", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                                    .frame(width: 24, height: 24, alignment: .center)
                            }
                            .disabled(document.pages.count == 1)
                        }
                    }
                    .onMove { document.movePages(from: $0, to: $1) }
                }
                .navigationTitle("Pages")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showsPages = false }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Page", systemImage: "plus") { addPage() }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("New Card", isPresented: $showsNewCard) {
            TextField("Title", text: $cardTitle)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addCard() }
        } message: {
            Text("Give the card a short title. You can leave it blank.")
        }
    }

    private var pageSelection: Binding<String?> {
        Binding(
            get: { document.selectedPageID },
            set: { value in
                guard let value else { return }
                document.selectedPageID = value
                showsPages = false
            }
        )
    }

    private func addPage() {
        document.addPage(after: document.selectedPageID)
    }

    private func addCard() {
        guard var scene = document.selectedPayload?.scene else { return }
        var card = CardElement.make(frame: CanvasRect(x: 197, y: 260, width: 400, height: 240))
        card.title = cardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        scene.elements.append(.card(card))
        document.updateScene(pageID: document.selectedPageID, scene: scene)
    }

    private func addArrow() {
        guard var scene = document.selectedPayload?.scene else { return }
        let arrow = ArrowElement.make(
            start: CanvasPoint(x: 200, y: 560),
            end: CanvasPoint(x: 590, y: 560)
        )
        scene.elements.append(.arrow(arrow))
        document.updateScene(pageID: document.selectedPageID, scene: scene)
    }
}

private struct PagePreview: View {
    let data: Data?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
    }
}
