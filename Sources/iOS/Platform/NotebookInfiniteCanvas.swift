import SwiftUI
import UIKit
import SwiftMath

struct NotebookMobileCanvas: View {
    let page: NotebookPageMetadata
    let scene: CanvasSceneDocument
    let assetData: (String) -> Data?
    let onSceneChange: (CanvasSceneDocument) -> Void

    @State private var viewport = MobileCanvasViewport()
    @State private var hasPositionedViewport = false
    @State private var selectedArrowID: String?
    @State private var endpointPreview: MobileEndpointDragPreview?
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    init(
        page: NotebookPageMetadata,
        scene: CanvasSceneDocument,
        assetData: @escaping (String) -> Data?,
        onSceneChange: @escaping (CanvasSceneDocument) -> Void = { _ in }
    ) {
        self.page = page
        self.scene = scene
        self.assetData = assetData
        self.onSceneChange = onSceneChange
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = viewport.clampedScale(viewport.scale * magnification)
            let magnifiedOffset = viewport.offset(
                scaledFrom: viewport.scale,
                to: scale,
                around: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            )
            let offset = CGPoint(
                x: magnifiedOffset.x + dragTranslation.width,
                y: magnifiedOffset.y + dragTranslation.height
            )

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemBackground)
                InfiniteNotebookGrid(pattern: page.resolvedGridPattern, scale: scale, offset: offset)
                NotebookWorldLayer(
                    scene: scene,
                    assetData: assetData,
                    selectedArrowID: selectedArrowID,
                    endpointPreview: endpointPreview,
                    viewportScale: scale,
                    onArrowSelected: { selectedArrowID = $0 },
                    onEndpointChanged: { id, isStart, point in
                        endpointPreview = MobileEndpointDragPreview(
                            arrowID: id,
                            isStart: isStart,
                            point: worldPoint(from: point, scale: scale, offset: offset)
                        )
                    },
                    onEndpointEnded: { id, isStart, point in
                        let worldPoint = worldPoint(from: point, scale: scale, offset: offset)
                        endpointPreview = nil
                        commitEndpoint(arrowID: id, isStart: isStart, at: worldPoint, scale: scale)
                    }
                )
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: offset.x, y: offset.y)
            }
            .coordinateSpace(name: MobileCanvasCoordinateSpace.viewport)
            .contentShape(Rectangle())
            .clipped()
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture(in: geometry.size))
            .onAppear { positionViewport(in: geometry.size) }
            .onChange(of: page.id) { _, _ in
                hasPositionedViewport = false
                selectedArrowID = nil
                endpointPreview = nil
                positionViewport(in: geometry.size)
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                guard hasPositionedViewport, oldSize.width > 0, oldSize.height > 0 else {
                    positionViewport(in: newSize)
                    return
                }
                viewport.offset.x += (newSize.width - oldSize.width) / 2
                viewport.offset.y += (newSize.height - oldSize.height) / 2
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Infinite notebook canvas")
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                viewport.offset.x += value.translation.width
                viewport.offset.y += value.translation.height
            }
    }

    private func zoomGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { value in
                viewport.zoom(
                    by: value.magnification,
                    around: CGPoint(x: size.width / 2, y: size.height / 2)
                )
            }
    }

    private func positionViewport(in size: CGSize) {
        guard !hasPositionedViewport, size.width > 0, size.height > 0 else { return }
        let bounds = scene.contentBounds?.cgRect.insetBy(dx: -56, dy: -56)
            ?? CGRect(x: 0, y: 0, width: page.width, height: page.height)
        viewport.fit(worldRect: bounds, in: size, padding: 18)
        hasPositionedViewport = true
    }

    private func worldPoint(from viewportPoint: CGPoint, scale: CGFloat, offset: CGPoint) -> CanvasPoint {
        CanvasPoint(
            x: (viewportPoint.x - offset.x) / max(scale, 0.001),
            y: (viewportPoint.y - offset.y) / max(scale, 0.001)
        )
    }

    private func commitEndpoint(arrowID: String, isStart: Bool, at point: CanvasPoint, scale: CGFloat) {
        guard case var .arrow(arrow)? = scene.element(id: arrowID) else { return }
        let attachment = MobileCanvasConnectionGeometry.attachment(
            to: point,
            in: scene,
            maximumDistance: 18 / Double(max(scale, 0.001))
        )
        let resolved = attachment.flatMap {
            MobileCanvasConnectionGeometry.attachmentPoint($0, in: scene)
        } ?? point
        let endpoint = ArrowEndpoint(point: resolved, attachment: attachment)
        if isStart { arrow.start = endpoint } else { arrow.end = endpoint }
        arrow.refreshBounds()
        var updated = scene
        updated.replace(.arrow(arrow))
        onSceneChange(updated)
    }
}

private enum MobileCanvasCoordinateSpace {
    static let viewport = "notebook-mobile-viewport"
}

private struct MobileEndpointDragPreview: Equatable {
    let arrowID: String
    let isStart: Bool
    let point: CanvasPoint
}

private struct MobileCanvasViewport {
    var scale: CGFloat = 1
    var offset: CGPoint = .zero

    mutating func fit(worldRect: CGRect, in viewportSize: CGSize, padding: CGFloat) {
        guard worldRect.width > 0, worldRect.height > 0 else { return }
        let availableWidth = max(1, viewportSize.width - padding * 2)
        let availableHeight = max(1, viewportSize.height - padding * 2)
        scale = clampedScale(min(availableWidth / worldRect.width, availableHeight / worldRect.height))
        offset = CGPoint(
            x: (viewportSize.width - worldRect.width * scale) / 2 - worldRect.minX * scale,
            y: (viewportSize.height - worldRect.height * scale) / 2 - worldRect.minY * scale
        )
    }

    mutating func zoom(by factor: CGFloat, around anchor: CGPoint) {
        let nextScale = clampedScale(scale * factor)
        offset = offset(scaledFrom: scale, to: nextScale, around: anchor)
        scale = nextScale
    }

    func offset(scaledFrom oldScale: CGFloat, to newScale: CGFloat, around anchor: CGPoint) -> CGPoint {
        let world = CGPoint(
            x: (anchor.x - offset.x) / oldScale,
            y: (anchor.y - offset.y) / oldScale
        )
        return CGPoint(x: anchor.x - world.x * newScale, y: anchor.y - world.y * newScale)
    }

    func clampedScale(_ proposed: CGFloat) -> CGFloat { min(max(proposed, 0.08), 6) }
}

private struct InfiniteNotebookGrid: View {
    let pattern: NotebookGridPattern
    let scale: CGFloat
    let offset: CGPoint

    var body: some View {
        Canvas { context, size in
            switch pattern {
            case .grid:
                drawGrid(context: &context, size: size)
            case .dots:
                drawDots(context: &context, size: size, isometric: false)
            case .isometric:
                drawDots(context: &context, size: size, isometric: true)
            case .blank:
                break
            }
        }
        .allowsHitTesting(false)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let step = visibleSpacing
        var path = Path()
        var x = alignedCoordinate(0, origin: offset.x, step: step)
        var y = alignedCoordinate(0, origin: offset.y, step: step)
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(path, with: .color(.gray.opacity(0.18)), lineWidth: 1)
    }

    private func drawDots(context: inout GraphicsContext, size: CGSize, isometric: Bool) {
        let horizontalStep = visibleSpacing
        let verticalStep = isometric ? horizontalStep * sqrt(3) / 2 : horizontalStep
        let firstRow = Int(floor((0 - offset.y) / verticalStep))
        let lastRow = Int(ceil((size.height - offset.y) / verticalStep))
        let radius = max(0.85, min(1.5, 1.05 * sqrt(scale)))

        for row in firstRow...lastRow {
            let y = offset.y + CGFloat(row) * verticalStep
            let rowOffset = isometric && abs(row % 2) == 1 ? horizontalStep / 2 : 0
            var x = alignedCoordinate(0, origin: offset.x + rowOffset, step: horizontalStep)
            while x <= size.width {
                let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(.gray.opacity(0.32)))
                x += horizontalStep
            }
        }
    }

    private var visibleSpacing: CGFloat {
        var result = 28 * scale
        while result < 7 { result *= 2 }
        return result
    }

    private func alignedCoordinate(_ value: CGFloat, origin: CGFloat, step: CGFloat) -> CGFloat {
        origin + floor((value - origin) / step) * step
    }
}

private struct NotebookWorldLayer: View {
    let scene: CanvasSceneDocument
    let assetData: (String) -> Data?
    let selectedArrowID: String?
    let endpointPreview: MobileEndpointDragPreview?
    let viewportScale: CGFloat
    let onArrowSelected: (String) -> Void
    let onEndpointChanged: (String, Bool, CGPoint) -> Void
    let onEndpointEnded: (String, Bool, CGPoint) -> Void
    let depth: Int

    init(
        scene: CanvasSceneDocument,
        assetData: @escaping (String) -> Data?,
        selectedArrowID: String? = nil,
        endpointPreview: MobileEndpointDragPreview? = nil,
        viewportScale: CGFloat = 1,
        onArrowSelected: @escaping (String) -> Void = { _ in },
        onEndpointChanged: @escaping (String, Bool, CGPoint) -> Void = { _, _, _ in },
        onEndpointEnded: @escaping (String, Bool, CGPoint) -> Void = { _, _, _ in },
        depth: Int = 0
    ) {
        self.scene = scene
        self.assetData = assetData
        self.selectedArrowID = selectedArrowID
        self.endpointPreview = endpointPreview
        self.viewportScale = viewportScale
        self.onArrowSelected = onArrowSelected
        self.onEndpointChanged = onEndpointChanged
        self.onEndpointEnded = onEndpointEnded
        self.depth = depth
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(scene.elements) { element in
                elementView(element)
            }
        }
        .frame(width: 1, height: 1, alignment: .topLeading)
    }

    @ViewBuilder
    private func elementView(_ element: CanvasElementRecord) -> some View {
        switch element {
        case let .arrow(arrow):
            MobileArrowView(
                arrow: arrow,
                scene: scene,
                isSelected: selectedArrowID == arrow.id,
                endpointPreview: endpointPreview,
                viewportScale: viewportScale,
                onSelected: { onArrowSelected(arrow.id) },
                onEndpointChanged: onEndpointChanged,
                onEndpointEnded: onEndpointEnded
            )
        default:
            positionedContent(for: element)
        }
    }

    @ViewBuilder
    private func positionedContent(for element: CanvasElementRecord) -> some View {
        let geometry = element.geometry
        elementContent(element)
            .frame(width: geometry.frame.width, height: geometry.frame.height)
            .rotationEffect(.degrees(geometry.rotation))
            .opacity(geometry.opacity)
            .position(x: geometry.frame.center.x, y: geometry.frame.center.y)
    }

    @ViewBuilder
    private func elementContent(_ element: CanvasElementRecord) -> some View {
        switch element {
        case let .text(text):
            MobileMarkdownText(
                markdown: text.markdown,
                fontSize: text.fontSize,
                textColor: uiColor(text.textColor),
                alignment: text.alignment,
                maximumWidth: max(1, text.geometry.frame.width - text.padding * 2)
            )
            .padding(text.padding)
            .background(color(text.backgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: text.cornerRadius))
            .overlay {
                if text.borderWidth > 0, text.borderColor.alpha > 0 {
                    RoundedRectangle(cornerRadius: text.cornerRadius)
                        .stroke(color(text.borderColor), lineWidth: text.borderWidth)
                }
            }
        case let .card(card):
            MobileCardView(card: card, assetData: assetData, viewportScale: viewportScale, depth: depth)
        case let .image(image):
            if let data = assetData(image.assetHash), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: image.preservesAspectRatio ? .fit : .fill)
                    .clipped()
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .foregroundStyle(.secondary)
            }
        case .arrow:
            EmptyView()
        }
    }

    private func color(_ value: CanvasColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    private func uiColor(_ value: CanvasColor) -> UIColor {
        UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
    }
}

private struct MobileCardView: View {
    let card: CardElement
    let assetData: (String) -> Data?
    let viewportScale: CGFloat
    let depth: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: 14)
                .stroke(.gray.opacity(0.55), lineWidth: 1.5)

            if depth < 2, let bounds = card.displayFace.scene.contentBounds?.cgRect {
                let padding = CGFloat(CardElement.contentPadding)
                let sourceWidth = max(1, bounds.width + padding * 2)
                let sourceHeight = max(1, bounds.height + padding * 2)
                let scaleX = card.geometry.frame.width / sourceWidth
                let scaleY = card.geometry.frame.height / sourceHeight
                NotebookWorldLayer(
                    scene: card.displayFace.scene,
                    assetData: assetData,
                    viewportScale: viewportScale,
                    depth: depth + 1
                )
                .offset(x: -bounds.minX + padding, y: -bounds.minY + padding)
                .scaleEffect(x: scaleX, y: scaleY, anchor: .topLeading)
            } else if !card.title.isEmpty, card.title != "Card" {
                Text(card.title)
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MobileArrowView: View {
    let arrow: ArrowElement
    let scene: CanvasSceneDocument
    let isSelected: Bool
    let endpointPreview: MobileEndpointDragPreview?
    let viewportScale: CGFloat
    let onSelected: () -> Void
    let onEndpointChanged: (String, Bool, CGPoint) -> Void
    let onEndpointEnded: (String, Bool, CGPoint) -> Void
    private let inset = 14.0

    var body: some View {
        let start = previewPoint(isStart: true) ?? resolved(arrow.start)
        let end = previewPoint(isStart: false) ?? resolved(arrow.end)
        let points = [start, end] + [arrow.bendPoint].compactMap { $0 }
        let minimumX = points.map(\.x).min() ?? start.x
        let minimumY = points.map(\.y).min() ?? start.y
        let maximumX = points.map(\.x).max() ?? end.x
        let maximumY = points.map(\.y).max() ?? end.y
        let bounds = CGRect(
            x: minimumX,
            y: minimumY,
            width: max(1, maximumX - minimumX),
            height: max(1, maximumY - minimumY)
        ).insetBy(dx: -inset / max(viewportScale, 0.001), dy: -inset / max(viewportScale, 0.001))

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var path = Path()
                path.move(to: local(start, in: bounds))
                if arrow.routing == .curved, let bend = arrow.bendPoint {
                    path.addQuadCurve(to: local(end, in: bounds), control: local(bend, in: bounds))
                } else if arrow.routing == .orthogonal {
                    let middleX = (start.x + end.x) / 2
                    path.addLine(to: local(CanvasPoint(x: middleX, y: start.y), in: bounds))
                    path.addLine(to: local(CanvasPoint(x: middleX, y: end.y), in: bounds))
                    path.addLine(to: local(end, in: bounds))
                } else {
                    path.addLine(to: local(end, in: bounds))
                }
                context.stroke(
                    path,
                    with: .color(Color(red: arrow.color.red, green: arrow.color.green, blue: arrow.color.blue)),
                    style: StrokeStyle(lineWidth: max(2, arrow.lineWidth), lineCap: .round, lineJoin: .round)
                )
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelected)

            if isSelected {
                endpointHandle(at: start, in: bounds, isStart: true)
                endpointHandle(at: end, in: bounds, isStart: false)
            }
        }
        .frame(width: max(1, bounds.width), height: max(1, bounds.height))
        .position(x: bounds.midX, y: bounds.midY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Arrow")
    }

    private func endpointHandle(at point: CanvasPoint, in bounds: CGRect, isStart: Bool) -> some View {
        let size = 18 / max(viewportScale, 0.001)
        return Circle()
            .fill(.white)
            .overlay(Circle().stroke(.blue, lineWidth: 2 / max(viewportScale, 0.001)))
            .frame(width: size, height: size)
            .position(x: point.x - bounds.minX, y: point.y - bounds.minY)
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(MobileCanvasCoordinateSpace.viewport))
                    .onChanged { onEndpointChanged(arrow.id, isStart, $0.location) }
                    .onEnded { onEndpointEnded(arrow.id, isStart, $0.location) }
            )
            .accessibilityLabel(isStart ? "Start endpoint" : "End endpoint")
            .accessibilityHint("Drag to connect this arrow")
    }

    private func previewPoint(isStart: Bool) -> CanvasPoint? {
        guard let endpointPreview,
              endpointPreview.arrowID == arrow.id,
              endpointPreview.isStart == isStart else { return nil }
        return endpointPreview.point
    }

    private func local(_ point: CanvasPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
    }

    private func resolved(_ endpoint: ArrowEndpoint) -> CanvasPoint {
        endpoint.attachment.flatMap(scene.attachmentPoint(for:)) ?? endpoint.point
    }
}

private struct MobileMarkdownText: UIViewRepresentable {
    let markdown: String
    let fontSize: CGFloat
    let textColor: UIColor
    let alignment: CanvasTextAlignment
    let maximumWidth: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.isAccessibilityElement = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = MobileMarkdownRenderer.attributedString(
            markdown: markdown,
            fontSize: fontSize,
            color: textColor,
            alignment: alignment,
            maximumWidth: maximumWidth
        )
        view.accessibilityLabel = view.attributedText.string
    }
}

enum MobileMarkdownRenderer {
    private enum Segment {
        case markdown(String)
        case math(String, display: Bool)
    }

    static func attributedString(
        markdown: String,
        fontSize: CGFloat,
        color: UIColor,
        alignment: CanvasTextAlignment,
        maximumWidth: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in segments(in: markdown) {
            switch segment {
            case let .markdown(source):
                result.append(nativeMarkdown(source, fontSize: fontSize, color: color))
            case let .math(source, display):
                if display, result.length > 0, result.string.last != "\n" {
                    result.append(NSAttributedString(string: "\n"))
                }
                if let image = mathImage(latex: source, fontSize: fontSize, color: color, display: display) {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    let scale = min(1, maximumWidth / max(1, image.size.width))
                    attachment.bounds = CGRect(
                        x: 0,
                        y: display ? 0 : -image.size.height * scale * 0.18,
                        width: image.size.width * scale,
                        height: image.size.height * scale
                    )
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    result.append(NSAttributedString(string: source))
                }
                if display { result.append(NSAttributedString(string: "\n")) }
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        if result.length > 0 {
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    private static func nativeMarkdown(_ source: String, fontSize: CGFloat, color: UIColor) -> NSAttributedString {
        let converted: NSAttributedString
        if let value = try? AttributedString(markdown: source) {
            converted = NSAttributedString(value)
        } else {
            converted = NSAttributedString(string: source)
        }
        let mutable = NSMutableAttributedString(attributedString: converted)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.foregroundColor, value: color, range: range)
        mutable.enumerateAttribute(.font, in: range) { value, subrange, _ in
            var traits = (value as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            traits.formIntersection([.traitBold, .traitItalic])
            let descriptor = UIFont.systemFont(ofSize: fontSize).fontDescriptor.withSymbolicTraits(traits)
                ?? UIFont.systemFont(ofSize: fontSize).fontDescriptor
            mutable.addAttribute(.font, value: UIFont(descriptor: descriptor, size: fontSize), range: subrange)
        }
        return mutable
    }

    private static func mathImage(latex: String, fontSize: CGFloat, color: UIColor, display: Bool) -> UIImage? {
        var math = MathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: color,
            labelMode: display ? .display : .text
        )
        guard let source = math.asImage().1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 4
        return UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: source.size))
        }
    }

    private static func segments(in source: String) -> [Segment] {
        var result: [Segment] = []
        var cursor = source.startIndex
        var plainStart = cursor
        while cursor < source.endIndex {
            if startsBracketDisplayDelimiter(at: cursor, in: source),
               let close = closingBracketDisplayDelimiter(in: source, from: source.index(cursor, offsetBy: 2)) {
                if plainStart < cursor { result.append(.markdown(String(source[plainStart..<cursor]))) }
                let contentStart = source.index(cursor, offsetBy: 2)
                let latex = String(source[contentStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(.math(latex, display: true))
                cursor = source.index(close, offsetBy: 2)
                plainStart = cursor
                continue
            }
            guard source[cursor] == "$", !isEscaped(cursor, in: source) else {
                cursor = source.index(after: cursor)
                continue
            }
            let second = source.index(after: cursor)
            let display = second < source.endIndex && source[second] == "$"
            let delimiterLength = display ? 2 : 1
            let contentStart = source.index(cursor, offsetBy: delimiterLength)
            guard let close = closingDollarDelimiter(in: source, from: contentStart, display: display) else {
                cursor = source.index(after: cursor)
                continue
            }
            if plainStart < cursor { result.append(.markdown(String(source[plainStart..<cursor]))) }
            result.append(.math(String(source[contentStart..<close]), display: display))
            cursor = source.index(close, offsetBy: delimiterLength)
            plainStart = cursor
        }
        if plainStart < source.endIndex { result.append(.markdown(String(source[plainStart...]))) }
        return result.isEmpty ? [.markdown(source)] : result
    }

    private static func startsBracketDisplayDelimiter(at index: String.Index, in source: String) -> Bool {
        guard source[index] == "\\", !isEscaped(index, in: source) else { return false }
        let next = source.index(after: index)
        return next < source.endIndex && source[next] == "["
    }

    private static func closingBracketDisplayDelimiter(in source: String, from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "\\" {
                let next = source.index(after: cursor)
                if next < source.endIndex, source[next] == "]" { return cursor }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func closingDollarDelimiter(in source: String, from start: String.Index, display: Bool) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "$", !isEscaped(cursor, in: source) {
                if !display { return cursor }
                let next = source.index(after: cursor)
                if next < source.endIndex, source[next] == "$" { return cursor }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func isEscaped(_ index: String.Index, in source: String) -> Bool {
        guard index > source.startIndex else { return false }
        var cursor = index
        var slashCount = 0
        while cursor > source.startIndex {
            let previous = source.index(before: cursor)
            guard source[previous] == "\\" else { break }
            slashCount += 1
            cursor = previous
        }
        return !slashCount.isMultiple(of: 2)
    }
}

enum MobileCanvasConnectionGeometry {
    static func attachmentPoint(_ attachment: ArrowAttachment, in scene: CanvasSceneDocument) -> CanvasPoint? {
        scene.attachmentPoint(for: attachment)
    }

    static func attachment(
        to point: CanvasPoint,
        in scene: CanvasSceneDocument,
        excluding excludedID: String? = nil,
        maximumDistance: Double = 18
    ) -> ArrowAttachment? {
        if let named = nearestAttachment(
            to: point,
            in: scene,
            excluding: excludedID,
            maximumDistance: maximumDistance
        ) {
            return named
        }

        for element in scene.elements.reversed()
        where element.acceptsArrowAttachment && element.id != excludedID {
            let frame = element.geometry.frame.cgRect
            guard frame.width > 0, frame.height > 0 else { continue }
            let local = rotated(point.cgPoint, around: CGPoint(x: frame.midX, y: frame.midY), degrees: -element.geometry.rotation)
            guard frame.contains(local) else { continue }
            return ArrowAttachment(
                elementID: element.id,
                edge: .center,
                position: 0.5,
                normalizedPoint: CanvasPoint(
                    x: (local.x - frame.minX) / frame.width,
                    y: (local.y - frame.minY) / frame.height
                )
            )
        }
        return nil
    }

    private static func nearestAttachment(
        to point: CanvasPoint,
        in scene: CanvasSceneDocument,
        excluding excludedID: String?,
        maximumDistance: Double
    ) -> ArrowAttachment? {
        var best: (ArrowAttachment, Double)?
        for element in scene.elements where element.acceptsArrowAttachment && element.id != excludedID {
            let frame = element.geometry.frame.cgRect
            let candidates: [(ArrowAnchorEdge, CGPoint)] = [
                (.center, CGPoint(x: frame.midX, y: frame.midY)),
                (.top, CGPoint(x: frame.midX, y: frame.minY)),
                (.right, CGPoint(x: frame.maxX, y: frame.midY)),
                (.bottom, CGPoint(x: frame.midX, y: frame.maxY)),
                (.left, CGPoint(x: frame.minX, y: frame.midY)),
            ]
            for (edge, candidate) in candidates {
                let rotatedPoint = rotated(candidate, around: CGPoint(x: frame.midX, y: frame.midY), degrees: element.geometry.rotation)
                let distance = hypot(rotatedPoint.x - point.x, rotatedPoint.y - point.y)
                if distance <= maximumDistance, distance < (best?.1 ?? .greatestFiniteMagnitude) {
                    best = (ArrowAttachment(elementID: element.id, edge: edge, position: 0.5), distance)
                }
            }
        }
        return best?.0
    }

    private static func rotated(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let radians = CGFloat(degrees * .pi / 180)
        let translated = CGPoint(x: point.x - center.x, y: point.y - center.y)
        return CGPoint(
            x: center.x + translated.x * cos(radians) - translated.y * sin(radians),
            y: center.y + translated.x * sin(radians) + translated.y * cos(radians)
        )
    }
}
