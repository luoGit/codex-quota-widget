import AppKit

// 以 1024x1024 绘制应用图标：深色圆角底 + 胶囊轮廓 + 两条配额条。
let canvas: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create bitmap")
}
bitmap.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let background = NSBezierPath(
    roundedRect: NSRect(x: 72, y: 72, width: canvas - 144, height: canvas - 144),
    xRadius: 196,
    yRadius: 196
)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.14, green: 0.19, blue: 0.27, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.10, alpha: 1),
])!
gradient.draw(in: background, angle: -90)

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

NSColor.white.withAlphaComponent(0.10).setStroke()
background.lineWidth = 4
background.stroke()

let pill = NSBezierPath(
    roundedRect: NSRect(x: 160, y: 356, width: 704, height: 312),
    xRadius: 156,
    yRadius: 156
)
NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.15, alpha: 1).setFill()
pill.fill()
NSColor.white.withAlphaComponent(0.14).setStroke()
pill.lineWidth = 6
pill.stroke()

func drawDot(atX x: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: 476, width: 72, height: 72)).fill()
}

func drawBar(atX x: CGFloat, width: CGFloat) {
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: x, y: 478, width: width, height: 68),
        xRadius: 34,
        yRadius: 34
    ).fill()
}

drawDot(atX: 250, color: NSColor(calibratedRed: 0.96, green: 0.40, blue: 0.36, alpha: 1))
drawBar(atX: 356, width: 150)
drawDot(atX: 556, color: NSColor(calibratedRed: 0.23, green: 0.79, blue: 0.39, alpha: 1))
drawBar(atX: 662, width: 130)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
