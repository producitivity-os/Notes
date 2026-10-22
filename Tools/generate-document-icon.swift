import AppKit
import Foundation

guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
    fatalError("Pass the output PNG path and, optionally, the Notebook app icon path")
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSGraphicsContext.current?.imageInterpolation = .high

let paper = NSBezierPath()
paper.move(to: NSPoint(x: 192, y: 92))
paper.line(to: NSPoint(x: 192, y: 932))
paper.line(to: NSPoint(x: 620, y: 932))
paper.line(to: NSPoint(x: 832, y: 720))
paper.line(to: NSPoint(x: 832, y: 92))
paper.close()

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0.08, alpha: 0.26)
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
paper.fill()
NSGraphicsContext.restoreGraphicsState()

NSColor(calibratedWhite: 0.84, alpha: 1).setStroke()
paper.lineWidth = 7
paper.stroke()

let fold = NSBezierPath()
fold.move(to: NSPoint(x: 620, y: 932))
fold.line(to: NSPoint(x: 832, y: 720))
fold.line(to: NSPoint(x: 620, y: 720))
fold.close()
NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
fold.fill()
NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
fold.lineWidth = 6
fold.stroke()

NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.31, alpha: 0.72).setStroke()
let margin = NSBezierPath()
margin.move(to: NSPoint(x: 304, y: 224))
margin.line(to: NSPoint(x: 304, y: 782))
margin.lineWidth = 8
margin.stroke()

NSColor(calibratedRed: 0.39, green: 0.68, blue: 0.94, alpha: 0.66).setStroke()
for y in stride(from: CGFloat(276), through: CGFloat(760), by: 82) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 242, y: y))
    line.line(to: NSPoint(x: 752, y: y))
    line.lineWidth = 7
    line.stroke()
}

let badgeRect = NSRect(x: 580, y: 54, width: 330, height: 330)
let badgeBackground = NSBezierPath(roundedRect: badgeRect.insetBy(dx: -14, dy: -14), xRadius: 86, yRadius: 86)
NSColor.white.setFill()
badgeBackground.fill()

if CommandLine.arguments.count == 3,
   let badge = NSImage(contentsOfFile: CommandLine.arguments[2]) {
    let clip = NSBezierPath(roundedRect: badgeRect, xRadius: 72, yRadius: 72)
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
} else {
    NSColor(calibratedRed: 1, green: 0.61, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(roundedRect: badgeRect, xRadius: 72, yRadius: 72).fill()
    let book = NSBezierPath()
    book.move(to: NSPoint(x: 642, y: 178))
    book.curve(to: NSPoint(x: 744, y: 142), controlPoint1: NSPoint(x: 682, y: 214), controlPoint2: NSPoint(x: 720, y: 208))
    book.curve(to: NSPoint(x: 846, y: 178), controlPoint1: NSPoint(x: 768, y: 208), controlPoint2: NSPoint(x: 806, y: 214))
    book.line(to: NSPoint(x: 846, y: 306))
    book.curve(to: NSPoint(x: 744, y: 270), controlPoint1: NSPoint(x: 806, y: 342), controlPoint2: NSPoint(x: 768, y: 336))
    book.curve(to: NSPoint(x: 642, y: 306), controlPoint1: NSPoint(x: 720, y: 336), controlPoint2: NSPoint(x: 682, y: 342))
    book.close()
    NSColor(calibratedWhite: 1, alpha: 0.9).setFill()
    book.fill()
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
