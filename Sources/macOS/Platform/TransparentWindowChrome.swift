import AppKit
import SwiftUI

struct TransparentWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeView {
        WindowChromeView(frame: .zero)
    }

    func updateNSView(_ nsView: WindowChromeView, context: Context) {
        nsView.applyWindowStyle()
    }
}

final class WindowChromeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowStyle()
        DispatchQueue.main.async { [weak self] in
            self?.applyWindowStyle()
        }
    }

    func applyWindowStyle() {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .visible
        window.isOpaque = false
        window.backgroundColor = .clear
        window.toolbar?.showsBaselineSeparator = false
        window.toolbar?.isVisible = false
        if let titlebar = window.standardWindowButton(.closeButton)?.superview {
            titlebar.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
