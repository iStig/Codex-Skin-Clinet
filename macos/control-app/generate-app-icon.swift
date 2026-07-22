import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(2) }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
  NSColor(
    red: CGFloat((hex >> 16) & 0xff) / 255,
    green: CGFloat((hex >> 8) & 0xff) / 255,
    blue: CGFloat(hex & 0xff) / 255,
    alpha: alpha
  )
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
  fill.setFill()
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawIcon(pixels: Int, filename: String) throws {
  let scale = CGFloat(pixels) / 1024
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    throw CocoaError(.fileWriteUnknown)
  }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  defer { NSGraphicsContext.restoreGraphicsState() }
  context.imageInterpolation = .high
  context.cgContext.scaleBy(x: scale, y: scale)

  let base = NSRect(x: 76, y: 76, width: 872, height: 872)
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
  shadow.shadowBlurRadius = 42
  shadow.shadowOffset = NSSize(width: 0, height: -18)
  shadow.set()
  roundedRect(base, radius: 204, fill: color(0x111418))
  NSShadow().set()

  let inner = NSBezierPath(roundedRect: base.insetBy(dx: 9, dy: 9), xRadius: 195, yRadius: 195)
  color(0xffffff, alpha: 0.12).setStroke()
  inner.lineWidth = 10
  inner.stroke()

  context.cgContext.saveGState()
  context.cgContext.translateBy(x: 512, y: 512)
  context.cgContext.rotate(by: -8 * .pi / 180)
  context.cgContext.translateBy(x: -512, y: -512)
  roundedRect(NSRect(x: 255, y: 250, width: 520, height: 500), radius: 116, fill: color(0x20c7c9))
  context.cgContext.restoreGState()

  context.cgContext.saveGState()
  context.cgContext.translateBy(x: 512, y: 512)
  context.cgContext.rotate(by: 7 * .pi / 180)
  context.cgContext.translateBy(x: -512, y: -512)
  roundedRect(NSRect(x: 272, y: 258, width: 500, height: 500), radius: 112, fill: color(0xff6b61))
  context.cgContext.restoreGState()

  roundedRect(NSRect(x: 275, y: 285, width: 474, height: 474), radius: 108, fill: color(0xf4f5f3))

  let center = NSPoint(x: 512, y: 535)
  for index in 0..<6 {
    context.cgContext.saveGState()
    context.cgContext.translateBy(x: center.x, y: center.y)
    context.cgContext.rotate(by: CGFloat(index) * .pi / 3)
    roundedRect(NSRect(x: 36, y: -38, width: 142, height: 76), radius: 38, fill: color(0x171a1f))
    context.cgContext.restoreGState()
  }
  color(0xf4f5f3).setFill()
  NSBezierPath(ovalIn: NSRect(x: 441, y: 464, width: 142, height: 142)).fill()

  for (hex, x) in [(UInt32(0x20c7c9), CGFloat(430)), (0xff6b61, 512), (0xf6c94c, 594)] {
    color(hex).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 26, y: 345, width: 52, height: 52)).fill()
  }

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  try png.write(to: output.appendingPathComponent(filename), options: .atomic)
}

let variants = [
  (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
  (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
  (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
  (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
  (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]
for (pixels, filename) in variants { try drawIcon(pixels: pixels, filename: filename) }
