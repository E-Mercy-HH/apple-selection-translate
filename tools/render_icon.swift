import AppKit
import Foundation

private let canvasSize = 1024

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

private func speechBubble() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 330, y: 266))
    path.line(to: NSPoint(x: 340, y: 266))
    path.line(to: NSPoint(x: 262, y: 160))
    path.curve(to: NSPoint(x: 482, y: 266),
               controlPoint1: NSPoint(x: 333, y: 182),
               controlPoint2: NSPoint(x: 408, y: 240))
    path.line(to: NSPoint(x: 690, y: 266))
    path.curve(to: NSPoint(x: 840, y: 416),
               controlPoint1: NSPoint(x: 774, y: 266),
               controlPoint2: NSPoint(x: 840, y: 332))
    path.line(to: NSPoint(x: 840, y: 653))
    path.curve(to: NSPoint(x: 690, y: 803),
               controlPoint1: NSPoint(x: 840, y: 737),
               controlPoint2: NSPoint(x: 774, y: 803))
    path.line(to: NSPoint(x: 330, y: 803))
    path.curve(to: NSPoint(x: 180, y: 653),
               controlPoint1: NSPoint(x: 246, y: 803),
               controlPoint2: NSPoint(x: 180, y: 737))
    path.line(to: NSPoint(x: 180, y: 416))
    path.curve(to: NSPoint(x: 330, y: 266),
               controlPoint1: NSPoint(x: 180, y: 332),
               controlPoint2: NSPoint(x: 246, y: 266))
    path.close()
    return path
}

private func drawGlyph(_ glyph: String, font: NSFont, ink: NSColor, center: NSPoint) {
    let text = NSAttributedString(string: glyph, attributes: [
        .font: font,
        .foregroundColor: ink,
    ])
    let textSize = text.size()
    text.draw(at: NSPoint(x: center.x - textSize.width / 2,
                          y: center.y - textSize.height / 2))
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift render_icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                    pixelsWide: canvasSize,
                                    pixelsHigh: canvasSize,
                                    bitsPerSample: 8,
                                    samplesPerPixel: 4,
                                    hasAlpha: true,
                                    isPlanar: false,
                                    colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0,
                                    bitsPerPixel: 0),
      let drawingContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create icon bitmap.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = drawingContext
drawingContext.imageInterpolation = .high
drawingContext.shouldAntialias = true

let tile = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928),
                        xRadius: 215,
                        yRadius: 215)
NSGradient(starting: color(14, 19, 49), ending: color(16, 68, 83))?
    .draw(in: tile, angle: 35)

// A gentle surface highlight keeps the tile readable against light Finder backgrounds.
NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(starting: color(150, 190, 255, alpha: 0.11),
           ending: color(255, 255, 255, alpha: 0))?
    .draw(in: NSRect(x: 48, y: 48, width: 928, height: 928), angle: 90)
NSGraphicsContext.restoreGraphicsState()

let bubble = speechBubble()
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(1, 6, 20, alpha: 0.52)
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -24)
shadow.set()
NSGradient(starting: color(25, 43, 71), ending: color(34, 57, 85))?
    .draw(in: bubble, angle: 90)
NSGraphicsContext.restoreGraphicsState()

bubble.lineWidth = 8
color(74, 116, 148, alpha: 0.7).setStroke()
bubble.stroke()

// Opposing arrows show translation in both directions, even at Finder icon sizes.
let forward = NSBezierPath()
forward.move(to: NSPoint(x: 425, y: 561))
forward.line(to: NSPoint(x: 537, y: 561))
forward.line(to: NSPoint(x: 537, y: 588))
forward.line(to: NSPoint(x: 588, y: 548))
forward.line(to: NSPoint(x: 537, y: 508))
forward.line(to: NSPoint(x: 537, y: 535))
forward.line(to: NSPoint(x: 425, y: 535))
forward.close()
color(80, 224, 219).setFill()
forward.fill()

let backward = NSBezierPath()
backward.move(to: NSPoint(x: 582, y: 464))
backward.line(to: NSPoint(x: 470, y: 464))
backward.line(to: NSPoint(x: 470, y: 491))
backward.line(to: NSPoint(x: 419, y: 451))
backward.line(to: NSPoint(x: 470, y: 411))
backward.line(to: NSPoint(x: 470, y: 438))
backward.line(to: NSPoint(x: 582, y: 438))
backward.close()
color(166, 176, 255).setFill()
backward.fill()

drawGlyph("A",
          font: NSFont.systemFont(ofSize: 250, weight: .bold),
          ink: color(245, 250, 255),
          center: NSPoint(x: 328, y: 516))
drawGlyph("文",
          font: NSFont(name: "PingFangSC-Semibold", size: 232)
              ?? NSFont.systemFont(ofSize: 232, weight: .semibold),
          ink: color(158, 244, 232),
          center: NSPoint(x: 694, y: 516))

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode icon PNG.\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
