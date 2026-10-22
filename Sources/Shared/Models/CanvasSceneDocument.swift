import CoreGraphics
import Foundation

struct CanvasSceneDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var schemaVersion: Int
    var elements: [CanvasElementRecord]

    static func blank() -> CanvasSceneDocument {
        CanvasSceneDocument(schemaVersion: currentVersion, elements: [])
    }

    func element(id: String) -> CanvasElementRecord? {
        elements.first { $0.id == id }
    }

    mutating func replace(_ element: CanvasElementRecord) {
        guard let index = elements.firstIndex(where: { $0.id == element.id }) else {
            elements.append(element)
            refreshArrowAttachments()
            return
        }
        elements[index] = element
        refreshArrowAttachments()
    }

    mutating func remove(ids: Set<String>) {
        // Preserve the currently rendered endpoint before its target disappears.
        refreshArrowAttachments()
        elements.removeAll { ids.contains($0.id) }
        for index in elements.indices {
            guard case var .arrow(arrow) = elements[index] else { continue }
            if let target = arrow.start.attachment?.elementID, ids.contains(target) { arrow.start.attachment = nil }
            if let target = arrow.end.attachment?.elementID, ids.contains(target) { arrow.end.attachment = nil }
            arrow.refreshBounds()
            elements[index] = .arrow(arrow)
        }
    }

    var contentBounds: CanvasRect? {
        let current = synchronizedArrowAttachments()
        guard let first = current.elements.first else { return nil }
        var bounds = first.geometry.frame.cgRect
        for element in current.elements.dropFirst() {
            bounds = bounds.union(element.geometry.frame.cgRect)
        }
        return CanvasRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height)
    }

    func contentSize(padding: Double, minimum: CanvasSize) -> CanvasSize {
        guard let bounds = contentBounds else { return minimum }
        return CanvasSize(
            width: max(minimum.width, bounds.width + padding * 2),
            height: max(minimum.height, bounds.height + padding * 2)
        )
    }

    func translatedBy(x: Double, y: Double) -> CanvasSceneDocument {
        var translated = synchronizedArrowAttachments()
        for index in translated.elements.indices {
            switch translated.elements[index] {
            case var .arrow(arrow):
                arrow.start.point.x += x
                arrow.start.point.y += y
                arrow.end.point.x += x
                arrow.end.point.y += y
                if var bend = arrow.bendPoint {
                    bend.x += x
                    bend.y += y
                    arrow.bendPoint = bend
                }
                arrow.geometry.frame.x += x
                arrow.geometry.frame.y += y
                translated.elements[index] = .arrow(arrow)
            default:
                var element = translated.elements[index]
                var geometry = element.geometry
                geometry.frame.x += x
                geometry.frame.y += y
                element.geometry = geometry
                translated.elements[index] = element
            }
        }
        translated.refreshArrowAttachments()
        return translated
    }

    /// Resolves an attachment against the target's latest frame and rotation.
    /// The endpoint's persisted point remains the fallback when the target no
    /// longer exists.
    func attachmentPoint(for attachment: ArrowAttachment) -> CanvasPoint? {
        guard let target = element(id: attachment.elementID) else { return nil }
        let frame = target.geometry.frame
        let unrotated: CanvasPoint
        if let normalizedPoint = attachment.normalizedPoint {
            let x = min(max(normalizedPoint.x, 0), 1)
            let y = min(max(normalizedPoint.y, 0), 1)
            unrotated = CanvasPoint(
                x: frame.x + frame.width * x,
                y: frame.y + frame.height * y
            )
        } else {
            let position = min(max(attachment.position, 0), 1)
            switch attachment.edge {
            case .center:
                unrotated = frame.center
            case .top:
                unrotated = CanvasPoint(x: frame.x + frame.width * position, y: frame.y)
            case .right:
                unrotated = CanvasPoint(x: frame.x + frame.width, y: frame.y + frame.height * position)
            case .bottom:
                unrotated = CanvasPoint(x: frame.x + frame.width * position, y: frame.y + frame.height)
            case .left:
                unrotated = CanvasPoint(x: frame.x, y: frame.y + frame.height * position)
            }
        }

        let radians = target.geometry.rotation * .pi / 180
        let center = frame.center
        let translatedX = unrotated.x - center.x
        let translatedY = unrotated.y - center.y
        return CanvasPoint(
            x: center.x + translatedX * cos(radians) - translatedY * sin(radians),
            y: center.y + translatedX * sin(radians) + translatedY * cos(radians)
        )
    }

    func resolvedArrow(_ arrow: ArrowElement) -> ArrowElement {
        var resolved = arrow
        if let attachment = resolved.start.attachment,
           let point = attachmentPoint(for: attachment) {
            resolved.start.point = point
        }
        if let attachment = resolved.end.attachment,
           let point = attachmentPoint(for: attachment) {
            resolved.end.point = point
        }
        resolved.refreshBounds()
        return resolved
    }

    mutating func refreshArrowAttachments() {
        let snapshot = self
        for index in elements.indices {
            guard case let .arrow(arrow) = elements[index] else { continue }
            elements[index] = .arrow(snapshot.resolvedArrow(arrow))
        }
    }

    func synchronizedArrowAttachments() -> CanvasSceneDocument {
        var result = self
        result.refreshArrowAttachments()
        return result
    }
}
