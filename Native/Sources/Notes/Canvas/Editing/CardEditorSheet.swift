import SwiftUI

struct CardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: CardEditorModel
    @State private var finished = false
    let onSave: (CardElement) -> Void

    init(card: CardElement, sourceController: NativeCanvasController, onSave: @escaping (CardElement) -> Void) {
        _model = StateObject(wrappedValue: CardEditorModel(card: card, sourceController: sourceController))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Side", selection: Binding(
                    get: { model.side },
                    set: { model.select($0) }
                )) {
                    ForEach(CardEditorModel.Side.allCases) { side in Text(side.rawValue).tag(side) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
            }
            .padding(12)
            .background(.bar)

            ZStack(alignment: .top) {
                NativeCanvasHost(controller: model.controller)
                CanvasToolbarView(
                    controller: model.controller,
                    allowedTools: [.select, .text, .image, .arrow]
                )
                .padding(.top, 12)
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                actionButtons
            }
            .padding(12)
            .background(.bar)
        }
        .onDisappear {
            if !finished { save() }
        }
    }

    private func save() {
        guard !finished else { return }
        finished = true
        onSave(model.card)
    }

    private func cancel() {
        guard !finished else { return }
        finished = true
        dismiss()
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button("Cancel") { cancel() }
                .keyboardShortcut(.cancelAction)
            Button("Save Card") {
                save()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
