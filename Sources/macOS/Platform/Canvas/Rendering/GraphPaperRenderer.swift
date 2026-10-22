import AppKit

@MainActor
final class GraphPaperRenderer {
    private let spacing = 28.0

    func draw(
        pageSize: CanvasSize,
        destination: CGRect,
        pattern: NotebookGridPattern = .dots,
        pageTitle: String? = nil,
        pageCreatedAt: Date? = nil,
        graphics: CGContext
    ) {
        guard pageSize.width > 0, pageSize.height > 0 else { return }
        graphics.saveGState()
        graphics.clip(to: destination)
        graphics.setFillColor(NSColor.white.cgColor)
        graphics.fill(destination)

        let color = NSColor(calibratedWhite: 0.42, alpha: 0.28)
        switch pattern {
        case .grid:
            drawGrid(pageSize: pageSize, destination: destination, graphics: graphics, color: color)
        case .dots:
            drawDots(pageSize: pageSize, destination: destination, graphics: graphics, color: color)
        case .isometric:
            drawIsometric(pageSize: pageSize, destination: destination, graphics: graphics, color: color)
        case .blank:
            break
        }
        graphics.restoreGState()
    }

    func drawInfinite(
        destination: CGRect,
        viewport: CanvasViewport,
        pattern: NotebookGridPattern,
        graphics: CGContext
    ) {
        graphics.saveGState()
        graphics.clip(to: destination)
        graphics.setFillColor(NSColor.white.cgColor)
        graphics.fill(destination)
        switch pattern {
        case .grid:
            drawInfiniteGrid(destination: destination, viewport: viewport, graphics: graphics)
        case .dots:
            drawInfiniteDots(destination: destination, viewport: viewport, isometric: false, graphics: graphics)
        case .isometric:
            drawInfiniteDots(destination: destination, viewport: viewport, isometric: true, graphics: graphics)
        case .blank:
            break
        }
        graphics.restoreGState()
    }

    private func drawInfiniteGrid(destination: CGRect, viewport: CanvasViewport, graphics: CGContext) {
        let step = visibleSpacing(for: viewport.scale)
        let origin = viewport.viewPoint(fromWorld: .zero)
        var x = alignedCoordinate(destination.minX, origin: origin.x, step: step)
        var y = alignedCoordinate(destination.minY, origin: origin.y, step: step)
        graphics.beginPath()
        while x <= destination.maxX {
            graphics.move(to: CGPoint(x: x, y: destination.minY))
            graphics.addLine(to: CGPoint(x: x, y: destination.maxY))
            x += step
        }
        while y <= destination.maxY {
            graphics.move(to: CGPoint(x: destination.minX, y: y))
            graphics.addLine(to: CGPoint(x: destination.maxX, y: y))
            y += step
        }
        graphics.setStrokeColor(NSColor(calibratedWhite: 0.42, alpha: 0.30).cgColor)
        graphics.setLineWidth(1.1)
        graphics.strokePath()
    }

    private func drawInfiniteDots(
        destination: CGRect,
        viewport: CanvasViewport,
        isometric: Bool,
        graphics: CGContext
    ) {
        let horizontalStep = visibleSpacing(for: viewport.scale)
        let verticalStep = isometric ? horizontalStep * sqrt(3) / 2 : horizontalStep
        let origin = viewport.viewPoint(fromWorld: .zero)
        let firstRow = Int(floor((destination.minY - origin.y) / verticalStep))
        let lastRow = Int(ceil((destination.maxY - origin.y) / verticalStep))
        let radius = max(0.8, min(1.45, 1.05 * sqrt(viewport.scale)))
        graphics.setFillColor(NSColor(calibratedWhite: 0.38, alpha: 0.34).cgColor)

        for row in firstRow...lastRow {
            let y = origin.y + Double(row) * verticalStep
            let rowOffset = isometric && abs(row % 2) == 1 ? horizontalStep / 2 : 0
            var x = alignedCoordinate(destination.minX, origin: origin.x + rowOffset, step: horizontalStep)
            while x <= destination.maxX {
                graphics.fillEllipse(in: CGRect(
                    x: x - radius,
                    y: y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                x += horizontalStep
            }
        }
    }

    private func visibleSpacing(for scale: CGFloat) -> CGFloat {
        var result = spacing * scale
        while result < 7 { result *= 2 }
        return result
    }

    private func alignedCoordinate(_ value: CGFloat, origin: CGFloat, step: CGFloat) -> CGFloat {
        origin + floor((value - origin) / step) * step
    }

    private func drawGrid(
        pageSize: CanvasSize,
        destination: CGRect,
        graphics: CGContext,
        color: NSColor
    ) {
        let scaleX = destination.width / pageSize.width
        let scaleY = destination.height / pageSize.height
        let columnCount = Int(ceil(pageSize.width / spacing))
        let rowCount = Int(ceil(pageSize.height / spacing))
        graphics.beginPath()
        for column in 0...columnCount {
            let x = destination.minX + Double(column) * spacing * scaleX
            graphics.move(to: CGPoint(x: x, y: destination.minY))
            graphics.addLine(to: CGPoint(x: x, y: destination.maxY))
        }
        for row in 0...rowCount {
            let y = destination.minY + Double(row) * spacing * scaleY
            graphics.move(to: CGPoint(x: destination.minX, y: y))
            graphics.addLine(to: CGPoint(x: destination.maxX, y: y))
        }
        graphics.setStrokeColor(color.cgColor)
        graphics.setLineWidth(1.1)
        graphics.strokePath()
    }

    private func drawDots(
        pageSize: CanvasSize,
        destination: CGRect,
        graphics: CGContext,
        color: NSColor
    ) {
        let scaleX = destination.width / pageSize.width
        let scaleY = destination.height / pageSize.height
        let radius = max(0.75, 1.15 * min(scaleX, scaleY))
        let columnCount = Int(ceil(pageSize.width / spacing))
        let rowCount = Int(ceil(pageSize.height / spacing))
        graphics.setFillColor(color.withAlphaComponent(0.32).cgColor)
        for row in 0...rowCount {
            for column in 0...columnCount {
                let center = CGPoint(
                    x: destination.minX + Double(column) * spacing * scaleX,
                    y: destination.minY + Double(row) * spacing * scaleY
                )
                graphics.fillEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        }
    }

    private func drawIsometric(
        pageSize: CanvasSize,
        destination: CGRect,
        graphics: CGContext,
        color: NSColor
    ) {
        let scaleX = destination.width / pageSize.width
        let scaleY = destination.height / pageSize.height
        let horizontalSpacing = spacing * scaleX
        let verticalSpacing = spacing * sqrt(3) / 2 * scaleY
        let radius = max(0.75, 1.15 * min(scaleX, scaleY))
        let rowCount = Int(ceil(destination.height / verticalSpacing))
        graphics.setFillColor(color.withAlphaComponent(0.34).cgColor)

        for row in 0...rowCount {
            let rowOffset = row.isMultiple(of: 2) ? 0 : horizontalSpacing / 2
            var x = destination.minX + rowOffset
            let y = destination.minY + Double(row) * verticalSpacing
            while x <= destination.maxX {
                graphics.fillEllipse(in: CGRect(
                    x: x - radius,
                    y: y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                x += horizontalSpacing
            }
        }
    }
}
