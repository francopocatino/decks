import AppKit

let size = 1024.0
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let background = NSBezierPath(roundedRect: bounds, xRadius: size * 0.2237, yRadius: size * 0.2237)
background.addClip()

let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.31, green: 0.42, blue: 0.96, alpha: 1),
    ending: NSColor(srgbRed: 0.35, green: 0.30, blue: 0.82, alpha: 1)
)!
gradient.draw(in: bounds, angle: -90)

func card(_ rect: NSRect, color: NSColor) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 38,
                  color: NSColor.black.withAlphaComponent(0.22).cgColor)
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 46, yRadius: 46).fill()
    ctx.restoreGState()
}

let cardWidth = 460.0
let cardHeight = 320.0
let originX = (size - cardWidth) / 2
let originY = (size - cardHeight) / 2
let step = 50.0

card(NSRect(x: originX - step, y: originY - step, width: cardWidth, height: cardHeight),
     color: NSColor.white.withAlphaComponent(0.85))
card(NSRect(x: originX, y: originY, width: cardWidth, height: cardHeight),
     color: NSColor.white.withAlphaComponent(0.92))
card(NSRect(x: originX + step, y: originY + step, width: cardWidth, height: cardHeight),
     color: NSColor(srgbRed: 0.99, green: 0.74, blue: 0.18, alpha: 1))

NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: output))
