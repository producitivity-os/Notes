import AppKit

@MainActor
enum CardResizeDialog {
    static func requestSize(current: CanvasRect, maximum: CanvasSize) -> CanvasSize? {
        let alert = NSAlert()
        alert.messageText = "Resize Card"
        alert.informativeText = "Set the card preview size on this notebook page."
        alert.addButton(withTitle: "Resize")
        alert.addButton(withTitle: "Cancel")

        let widthField = numberField(value: current.width)
        let heightField = numberField(value: current.height)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Width"), widthField],
            [NSTextField(labelWithString: "Height"), heightField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 110
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        alert.accessoryView = grid

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let width = min(max(widthField.doubleValue, 120), maximum.width)
        let height = min(max(heightField.doubleValue, 80), maximum.height)
        return CanvasSize(width: width, height: height)
    }

    private static func numberField(value: Double) -> NSTextField {
        let field = NSTextField(string: String(Int(value.rounded())))
        field.alignment = .right
        field.formatter = NumberFormatter()
        return field
    }
}
