import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded-square background with a vertical gradient.
let inset = 100.0
let background = NSBezierPath(
    roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
    xRadius: 190,
    yRadius: 190
)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.17, green: 0.18, blue: 0.22, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
])
gradient?.draw(in: background, angle: -90)

// A pale disc, its lower half dimmed — the icon says "wallpaper, half brightness".
let discRect = NSRect(x: 262, y: 272, width: 500, height: 500)
let disc = NSBezierPath(ovalIn: discRect)
NSColor(srgbRed: 0.95, green: 0.93, blue: 0.87, alpha: 1).setFill()
disc.fill()

NSGraphicsContext.saveGraphicsState()
disc.addClip()
NSColor.black.withAlphaComponent(0.48).setFill()
NSRect(x: 240, y: 240, width: 544, height: 282).fill()
NSGraphicsContext.restoreGraphicsState()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("icon render failed")
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
