import SwiftUI

struct CanvasToolbarView: View {
    @ObservedObject var controller: NativeCanvasController
    var allowedTools: [CanvasToolKind] = CanvasToolKind.toolbarTools

    var body: some View {
        HStack(spacing: 6) {
            ForEach(allowedTools) { tool in
                Button {
                    controller.activeTool = tool
                } label: {
                    CanvasToolIcon(tool: tool)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(CanvasToolButtonStyle(selected: controller.activeTool == tool))
                .help(tool.label)
                .accessibilityLabel(tool.label)
            }

            Divider().frame(height: 22).padding(.horizontal, 3)

            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!controller.canUndo)
            .help("Undo")

            Button { controller.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(!controller.canRedo)
            .help("Redo")
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.09), .clear], startPoint: .top, endPoint: .bottom)
                .blur(radius: 14)
                .frame(height: 42)
                .offset(y: 22)
                .allowsHitTesting(false)
        }
    }
}

private struct CanvasToolButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
