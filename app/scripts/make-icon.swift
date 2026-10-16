// Draws the 1024 × 1024 app icon: a 3 × 3 grid of coloured tiles on a dark rounded square,
// the centre tile "playing" (white ring and waveform bars).
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
// macOS icon template: 824 pt body centred in the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
  exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

guard
  let bitmap = NSBitmapImageRep(
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
  ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
else { fatalError("Couldn't create the drawing context") }

NSGraphicsContext.current = graphics
let context = graphics.cgContext

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

// Body: rounded square with a vertical gradient and a soft drop shadow.
context.saveGState()
context.setShadow(
  offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
let bodyPath = CGPath(
  roundedRect: body, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)
context.addPath(bodyPath)
context.setFillColor(color(0x231F3F))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(bodyPath)
context.clip()
let gradient = CGGradient(
  colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
  colors: [color(0x3B3170), color(0x17142B)] as CFArray,
  locations: [0, 1]
)!
context.drawLinearGradient(
  gradient,
  start: CGPoint(x: 0, y: body.maxY),
  end: CGPoint(x: 0, y: body.minY),
  options: []
)
context.restoreGState()

// Tiles: 3 × 3 grid, reading order from the top left.
let palette: [UInt32] = [
  0xAF52DE, 0xFF2D55, 0xFF3B30,
  0xFF9500, 0x3A3A3C, 0x34C759,
  0x32ADE6, 0x007AFF, 0xFFCC00,
]
let margin: CGFloat = 96
let gap: CGFloat = 40
let tileSize = (body.width - 2 * margin - 2 * gap) / 3
let tileRadius: CGFloat = 46

for index in 0..<9 {
  let column = CGFloat(index % 3)
  let row = CGFloat(index / 3)
  let tile = CGRect(
    x: body.minX + margin + column * (tileSize + gap),
    y: body.maxY - margin - tileSize - row * (tileSize + gap),
    width: tileSize,
    height: tileSize
  )
  let path = CGPath(
    roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
  context.addPath(path)
  context.setFillColor(color(palette[index]))
  context.fillPath()

  guard index == 4 else { continue }
  // The centre tile is the one playing.
  context.addPath(path)
  context.setStrokeColor(color(0xFFFFFF))
  context.setLineWidth(14)
  context.strokePath()

  let bars: [CGFloat] = [0.30, 0.62, 0.95, 0.55, 0.80, 0.40]
  let barWidth: CGFloat = 16
  let barGap: CGFloat = 12
  let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * barGap
  for (bar, height) in bars.enumerated() {
    let barHeight = (tileSize * 0.6) * height
    let barRect = CGRect(
      x: tile.midX - totalWidth / 2 + CGFloat(bar) * (barWidth + barGap),
      y: tile.midY - barHeight / 2,
      width: barWidth,
      height: barHeight
    )
    context.addPath(CGPath(roundedRect: barRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
  }
}

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("Couldn't encode the PNG")
}
try png.write(to: output)
