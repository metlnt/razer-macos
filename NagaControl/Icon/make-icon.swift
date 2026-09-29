// Renders the app icon: swift make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt rounded square centered in 1024
let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
NSColor.black.setFill(); shape.fill()
ctx.restoreGState()
shape.addClip()
NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.17, alpha: 1),
                    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.06, alpha: 1)])!.draw(in: rect, angle: -90)

let green = NSColor(calibratedRed: 0.27, green: 0.84, blue: 0.17, alpha: 1)

// Soft glow behind the mouse
NSGradient(colors: [green.withAlphaComponent(0.35), green.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: 512, y: 500), radius: 0, toCenter: NSPoint(x: 512, y: 500), radius: 380, options: [])

// Mouse glyph
let cfg = NSImage.SymbolConfiguration(pointSize: 520, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [green]))
if let sym = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let s = sym.size
    let scale = 560 / s.height
    let w = s.width * scale, h = s.height * scale
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: green.withAlphaComponent(0.8).cgColor)
    sym.draw(in: NSRect(x: 512 - w / 2, y: 480 - h / 2, width: w, height: h))
    ctx.restoreGState()
}

// Three lighting-zone dots
for (i, x) in [412.0, 512.0, 612.0].enumerated() {
    let d: CGFloat = i == 1 ? 34 : 26
    green.withAlphaComponent(i == 1 ? 1 : 0.7).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - d / 2, y: 175 - d / 2, width: d, height: d)).fill()
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
