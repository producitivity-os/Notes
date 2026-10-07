import AppKit

@MainActor
final class GraphPaperRenderer {
    private let minorSpacing = 24.0
    private let majorInterval = 5

    func draw(pageSize: CanvasSize, destination: CGRect, graphics: CGContext) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        graphics.saveGState()
        graphics.clip(to: destination)
        graphics.setFillColor(NSColor.white.cgColor)
        graphics.fill(destination)

        drawLines(
            pageSize: pageSize,
            destination: destination,
            graphics: graphics,
            every: 1,
            color: NSColor(calibratedRed: 0.64, green: 0.79, blue: 0.96, alpha: 0.24),
            lineWidth: 0.55
        )
        drawLines(
            pageSize: pageSize,
            destination: destination,
            graphics: graphics,
            every: majorInterval,
            color: NSColor(calibratedRed: 0.42, green: 0.66, blue: 0.92, alpha: 0.28),
            lineWidth: 0.85
        )
        graphics.restoreGState()
    }

    private func drawLines(
        pageSize: CanvasSize,
        destination: CGRect,
        graphics: CGContext,
        every interval: Int,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        let scaleX = destination.width / pageSize.width
        let scaleY = destination.height / pageSize.height
        let columnCount = Int(ceil(pageSize.width / minorSpacing))
        let rowCount = Int(ceil(pageSize.height / minorSpacing))
        graphics.beginPath()
        for column in stride(from: 0, through: columnCount, by: interval) {
            let x = destination.minX + Double(column) * minorSpacing * scaleX
            graphics.move(to: CGPoint(x: x, y: destination.minY))
            graphics.addLine(to: CGPoint(x: x, y: destination.maxY))
        }
        for row in stride(from: 0, through: rowCount, by: interval) {
            let y = destination.minY + Double(row) * minorSpacing * scaleY
            graphics.move(to: CGPoint(x: destination.minX, y: y))
            graphics.addLine(to: CGPoint(x: destination.maxX, y: y))
        }
        graphics.setStrokeColor(color.cgColor)
        graphics.setLineWidth(lineWidth)
        graphics.strokePath()
    }
}
