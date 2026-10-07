import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Pass the output PNG path")
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(x: 112, y: 72, width: 800, height: 880), xRadius: 132, yRadius: 132)
NSColor(calibratedRed: 0.93, green: 0.97, blue: 1, alpha: 1).setFill()
background.fill()
NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.94, alpha: 1).setStroke()
background.lineWidth = 32
background.stroke()

let fold = NSBezierPath()
fold.move(to: NSPoint(x: 672, y: 952))
fold.line(to: NSPoint(x: 912, y: 712))
fold.line(to: NSPoint(x: 672, y: 712))
fold.close()
NSColor(calibratedRed: 0.32, green: 0.65, blue: 1, alpha: 1).setFill()
fold.fill()

let colors: [NSColor] = [
    NSColor(calibratedRed: 0.18, green: 0.47, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.25, green: 0.69, blue: 0.54, alpha: 1),
    NSColor(calibratedRed: 1, green: 0.58, blue: 0.18, alpha: 1),
]
for (index, color) in colors.enumerated() {
    let y = 570 - CGFloat(index * 170)
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 230, y: y, width: 82, height: 82)).fill()
    NSColor(calibratedWhite: 0.28, alpha: 0.72).setFill()
    NSBezierPath(roundedRect: NSRect(x: 356, y: y + 19, width: 410, height: 42), xRadius: 21, yRadius: 21).fill()
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
