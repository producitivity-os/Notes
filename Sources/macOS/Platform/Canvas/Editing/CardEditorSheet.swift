import SwiftUI

struct CardEditorSheet: View {
    @StateObject private var model: CardEditorModel
    let onSave: (CardElement) -> Void
    let onClose: () -> Void

    init(
        card: CardElement,
        sourceController: NativeCanvasController,
        onSave: @escaping (CardElement) -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: CardEditorModel(card: card, sourceController: sourceController))
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .top) {
                NativeCanvasHost(controller: model.controller)
                CanvasToolbarView(
                    controller: model.controller,
                    allowedTools: CanvasToolKind.cardEditorTools
                )
                .padding(.top, 12)

                CardFacePager(
                    faceNames: model.card.faces.map(\.name),
                    selectedIndex: model.selectedFaceIndex,
                    selectFace: model.selectFace(at:)
                )
            }

            HStack(spacing: 10) {
                Button(
                    model.isIgnoredInReview ? "Include in Review" : "Ignore in Review",
                    systemImage: model.isIgnoredInReview ? "eye" : "eye.slash"
                ) {
                    model.toggleIgnoredInReview()
                }

                if !model.card.hasFrontFace {
                    Button("Add Front", systemImage: "plus.rectangle.on.rectangle") {
                        model.addFront()
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background {
            CardEditorKeyboardMonitor {
                saveAndDismiss()
            }
            .frame(width: 0, height: 0)
        }
        .onDisappear {
            saveNow()
        }
        .alert("Review", isPresented: Binding(
            get: { model.reviewStateError != nil },
            set: { if !$0 { model.reviewStateError = nil } }
        )) {
            Button("OK", role: .cancel) { model.reviewStateError = nil }
        } message: {
            Text(model.reviewStateError ?? "")
        }
    }

    private func saveNow() {
        model.controller.commitActiveEditing()
        onSave(model.card)
    }

    private func saveAndDismiss() {
        saveNow()
        onClose()
    }
}

private struct CardEditorKeyboardMonitor: NSViewRepresentable {
    let onSaveAndDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: onSaveAndDismiss)
    }

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateNSView(_ view: MonitoringView, context: Context) {
        context.coordinator.action = onSaveAndDismiss
        context.coordinator.install(in: view.window)
    }

    static func dismantleNSView(_ view: MonitoringView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var action: () -> Void
        private weak var window: NSWindow?
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func install(in window: NSWindow?) {
            guard self.window !== window else { return }
            stop()
            self.window = window
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let isEscape = event.keyCode == 53
                let isCommandReturn = [36, 76].contains(event.keyCode) && event.modifierFlags.contains(.command)
                guard isEscape || isCommandReturn else { return event }
                self.action()
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            window = nil
        }
    }

    final class MonitoringView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }
}
