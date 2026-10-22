import SwiftUI

struct CanvasToolbarView: View {
    @ObservedObject var controller: NativeCanvasController
    var allowedTools: [CanvasToolKind]?

    private var tools: [CanvasToolKind] { allowedTools ?? controller.allowedTools }

    var body: some View {
        HStack(spacing: 11) {
            HStack(spacing: 6) {
                ForEach(tools) { tool in
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
            .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.14)) }
            .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Canvas tools")

            if !controller.isStandalone {
                Menu {
                    Picker("Grid Pattern", selection: Binding(
                        get: { controller.gridPattern },
                        set: { controller.setGridPattern($0) }
                    )) {
                        ForEach(NotebookGridPattern.allCases) { pattern in
                            Label(pattern.title, systemImage: pattern.symbolName)
                                .tag(pattern)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: controller.gridPattern.symbolName)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 25, height: 25)
                        Divider().frame(height: 22)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 48)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.16)) }
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Grid Pattern")
                .accessibilityLabel("Grid Pattern: \(controller.gridPattern.title)")
            }

            HStack(spacing: 5) {
                Button { controller.fitPage() } label: {
                    Text(controller.zoomScale, format: .percent.precision(.fractionLength(0...1)))
                        .monospacedDigit()
                        .frame(minWidth: 48)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .help(controller.isInfiniteCanvas ? "Fit Content" : "Fit Page")

                VStack(spacing: -2) {
                    Button { controller.zoomIn() } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 13, height: 10)
                    }
                    Button { controller.zoomOut() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 13, height: 10)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.16)) }
            .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Canvas zoom")
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
