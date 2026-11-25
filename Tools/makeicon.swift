import AppKit

let pixelSize = 1024
let canvasSize = CGFloat(pixelSize)

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fatalError("failed to initialize 1024x1024 bitmap context")
}

bitmap.size = NSSize(width: canvasSize, height: canvasSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
context.imageInterpolation = .high

let inset: CGFloat = 100
let background = NSBezierPath(
    roundedRect: NSRect(x: inset, y: inset, width: canvasSize - inset * 2, height: canvasSize - inset * 2),
    xRadius: 190,
    yRadius: 190
)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.22, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
])
gradient?.draw(in: background, angle: -90)

let discRect = NSRect(x: 262, y: 272, width: 500, height: 500)
let disc = NSBezierPath(ovalIn: discRect)
NSColor(srgbRed: 0.95, green: 0.93, blue: 0.87, alpha: 1).setFill()
disc.fill()

NSGraphicsContext.saveGraphicsState()
disc.addClip()
NSColor.black.withAlphaComponent(0.48).setFill()
NSRect(x: 240, y: 240, width: 544, height: 282).fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("icon render failed")
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
