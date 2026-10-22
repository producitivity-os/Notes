import SwiftUI

struct CardFacePager: View {
    let faceNames: [String]
    let selectedIndex: Int
    let selectFace: (Int) -> Void

    private var canMoveBackward: Bool { selectedIndex > 0 }
    private var canMoveForward: Bool { selectedIndex + 1 < faceNames.count }

    var body: some View {
        ZStack {
            HStack {
                navigationButton(
                    systemImage: "chevron.left",
                    label: "Previous face",
                    enabled: canMoveBackward
                ) {
                    selectFace(selectedIndex - 1)
                }

                Spacer()

                navigationButton(
                    systemImage: "chevron.right",
                    label: "Next face",
                    enabled: canMoveForward
                ) {
                    selectFace(selectedIndex + 1)
                }
            }
            .padding(.horizontal, 16)

            VStack {
                Spacer()
                HStack(spacing: 7) {
                    ForEach(faceNames.indices, id: \.self) { index in
                        Button {
                            selectFace(index)
                        } label: {
                            Circle()
                                .fill(index == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.35))
                                .frame(width: index == selectedIndex ? 9 : 7, height: index == selectedIndex ? 9 : 7)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(faceNames[index])
                        .accessibilityLabel("Show \(faceNames[index]) face")
                        .accessibilityValue(index == selectedIndex ? "Current face" : "")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 14)
            }
        }
    }

    private func navigationButton(
        systemImage: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.28)
        .help(label)
        .accessibilityLabel(label)
    }
}
