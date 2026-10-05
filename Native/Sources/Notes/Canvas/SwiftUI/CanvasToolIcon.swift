import AppKit
import SwiftUI

struct CanvasToolIcon: View {
    let tool: CanvasToolKind

    var body: some View {
        Group {
            if let resourceName = tool.resourceIconName,
               let url = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: tool.symbolName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 19, height: 19)
    }
}
