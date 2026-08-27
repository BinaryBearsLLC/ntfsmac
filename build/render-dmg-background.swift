#!/usr/bin/env swift
import AppKit
import Foundation

struct Layout: Decodable {
  struct Canvas: Decodable { let width: CGFloat; let height: CGFloat }
  struct Card: Decodable {
    let x: CGFloat; let y: CGFloat; let width: CGFloat; let height: CGFloat
    let radius: CGFloat; let opacity: CGFloat
  }
  struct Watermark: Decodable {
    let centerX: CGFloat; let centerY: CGFloat; let size: CGFloat; let opacity: CGFloat
  }
  struct TextElement: Decodable {
    let text: String; let centerX: CGFloat; let centerY: CGFloat
    let fontSize: CGFloat; let boxHeight: CGFloat
  }
  struct Arrow: Decodable {
    let centerX: CGFloat; let centerY: CGFloat; let width: CGFloat
    let rotationDegrees: CGFloat; let opacity: CGFloat; let removeWhite: Bool
    let whiteThreshold: CGFloat; let edgeSoftness: CGFloat
  }

  let schemaVersion: Int
  let canvas: Canvas
  let card: Card
  let watermark: Watermark
  let title: TextElement
  let subtitle: TextElement
  let arrow: Arrow
}

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("render-dmg-background: \(message)\n".utf8))
  exit(1)
}

private func drawText(
  _ element: Layout.TextElement,
  canvas: NSSize,
  weight: NSFont.Weight,
  color: NSColor
) {
  let style = NSMutableParagraphStyle()
  style.alignment = .center
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: element.fontSize, weight: weight),
    .foregroundColor: color,
    .paragraphStyle: style,
  ]
  let rect = NSRect(
    x: 0,
    y: canvas.height - element.centerY - element.boxHeight / 2,
    width: canvas.width,
    height: element.boxHeight
  )
  element.text.draw(in: rect, withAttributes: attributes)
}

private func preparedArrow(from url: URL, settings: Layout.Arrow) -> NSImage {
  guard let source = NSImage(contentsOf: url) else {
    fail("failed to load arrow artwork: \(url.path)")
  }
  var proposed = NSRect(origin: .zero, size: source.size)
  guard let sourceCG = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
    fail("failed to decode arrow artwork: \(url.path)")
  }

  let width = sourceCG.width
  let height = sourceCG.height
  let bytesPerRow = width * 4
  var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
    CGImageAlphaInfo.premultipliedLast.rawValue
  guard let context = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
  ) else {
    fail("failed to allocate arrow bitmap")
  }
  context.translateBy(x: 0, y: CGFloat(height))
  context.scaleBy(x: 1, y: -1)
  context.draw(sourceCG, in: CGRect(x: 0, y: 0, width: width, height: height))

  var minX = width
  var minY = height
  var maxX = -1
  var maxY = -1
  let thresholdFloor = 255.0 - settings.whiteThreshold
  let softness = max(1.0, settings.edgeSoftness)

  for y in 0..<height {
    for x in 0..<width {
      let index = y * bytesPerRow + x * 4
      let originalAlpha = CGFloat(pixels[index + 3])
      if settings.removeWhite {
        let minimumChannel = CGFloat(min(pixels[index], min(pixels[index + 1], pixels[index + 2])))
        let darkness = 255.0 - minimumChannel
        let normalized = max(0.0, min(1.0, (darkness - thresholdFloor) / softness))
        let newAlpha = min(originalAlpha, normalized * 255.0)
        let alphaScale = originalAlpha > 0 ? newAlpha / originalAlpha : 0
        pixels[index] = UInt8((CGFloat(pixels[index]) * alphaScale).rounded())
        pixels[index + 1] = UInt8((CGFloat(pixels[index + 1]) * alphaScale).rounded())
        pixels[index + 2] = UInt8((CGFloat(pixels[index + 2]) * alphaScale).rounded())
        pixels[index + 3] = UInt8(newAlpha.rounded())
      }
      if pixels[index + 3] > 3 {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
      }
    }
  }
  guard maxX >= minX, maxY >= minY else {
    fail("arrow processing removed every visible pixel")
  }

  let padding = 4
  let cropX = max(0, minX - padding)
  let cropY = max(0, minY - padding)
  let cropMaxX = min(width - 1, maxX + padding)
  let cropMaxY = min(height - 1, maxY + padding)
  let cropWidth = cropMaxX - cropX + 1
  let cropHeight = cropMaxY - cropY + 1
  let cropBytesPerRow = cropWidth * 4
  var croppedPixels = [UInt8](repeating: 0, count: cropHeight * cropBytesPerRow)
  for y in 0..<cropHeight {
    let sourceStart = (cropY + y) * bytesPerRow + cropX * 4
    let destinationStart = y * cropBytesPerRow
    croppedPixels[destinationStart..<(destinationStart + cropBytesPerRow)] =
      pixels[sourceStart..<(sourceStart + cropBytesPerRow)]
  }

  guard let provider = CGDataProvider(data: Data(croppedPixels) as CFData),
    let croppedCG = CGImage(
      width: cropWidth,
      height: cropHeight,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: cropBytesPerRow,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    )
  else {
    fail("failed to create processed arrow image")
  }
  return NSImage(cgImage: croppedCG, size: NSSize(width: cropWidth, height: cropHeight))
}

guard CommandLine.arguments.count == 5 else {
  FileHandle.standardError.write(
    Data("usage: render-dmg-background.swift OUTPUT.png BRAND_BACKGROUND.png ARROW_IMAGE LAYOUT.json\n".utf8)
  )
  exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let brandBackgroundURL = URL(fileURLWithPath: CommandLine.arguments[2])
let arrowURL = URL(fileURLWithPath: CommandLine.arguments[3])
let layoutURL = URL(fileURLWithPath: CommandLine.arguments[4])
guard let brandBackground = NSImage(contentsOf: brandBackgroundURL) else {
  fail("failed to load approved brand background: \(brandBackgroundURL.path)")
}
let layout: Layout
do {
  layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
} catch {
  fail("invalid layout configuration: \(error)")
}
guard layout.schemaVersion == 1 else {
  fail("unsupported layout schema: \(layout.schemaVersion)")
}

let canvas = NSSize(width: layout.canvas.width, height: layout.canvas.height)
guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width),
    pixelsHigh: Int(canvas.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fail("failed to create canvas")
}
bitmap.size = canvas

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let bounds = NSRect(origin: .zero, size: canvas)
let top = NSColor(calibratedWhite: 0.985, alpha: 1)
let bottom = NSColor(calibratedRed: 0.91, green: 0.95, blue: 0.93, alpha: 1)
NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)

let cardRect = NSRect(
  x: layout.card.x,
  y: canvas.height - layout.card.y - layout.card.height,
  width: layout.card.width,
  height: layout.card.height
)
let halo = NSBezierPath(roundedRect: cardRect, xRadius: layout.card.radius, yRadius: layout.card.radius)
NSColor(calibratedWhite: 1, alpha: layout.card.opacity).setFill()
halo.fill()

let watermarkRect = NSRect(
  x: layout.watermark.centerX - layout.watermark.size / 2,
  y: canvas.height - layout.watermark.centerY - layout.watermark.size / 2,
  width: layout.watermark.size,
  height: layout.watermark.size
)
brandBackground.draw(
  in: watermarkRect,
  from: .zero,
  operation: .sourceOver,
  fraction: layout.watermark.opacity,
  respectFlipped: false,
  hints: [.interpolation: NSImageInterpolation.high]
)

let border = NSBezierPath(
  roundedRect: cardRect.insetBy(dx: 0.5, dy: 0.5),
  xRadius: layout.card.radius,
  yRadius: layout.card.radius
)
border.lineWidth = 1
NSColor(calibratedWhite: 0.62, alpha: 0.18).setStroke()
border.stroke()

drawText(
  layout.title,
  canvas: canvas,
  weight: .semibold,
  color: NSColor(calibratedWhite: 0.16, alpha: 1)
)
drawText(
  layout.subtitle,
  canvas: canvas,
  weight: .regular,
  color: NSColor(calibratedWhite: 0.34, alpha: 1)
)

let arrow = preparedArrow(from: arrowURL, settings: layout.arrow)
let arrowHeight = layout.arrow.width * arrow.size.height / arrow.size.width
NSGraphicsContext.saveGraphicsState()
let transform = NSAffineTransform()
transform.translateX(by: layout.arrow.centerX, yBy: canvas.height - layout.arrow.centerY)
transform.rotate(byDegrees: -layout.arrow.rotationDegrees)
// The processed raster rows use top-left image order; flip once for AppKit's bottom-left canvas.
transform.scaleX(by: 1, yBy: -1)
transform.concat()
arrow.draw(
  in: NSRect(
    x: -layout.arrow.width / 2,
    y: -arrowHeight / 2,
    width: layout.arrow.width,
    height: arrowHeight
  ),
  from: .zero,
  operation: .sourceOver,
  fraction: layout.arrow.opacity,
  respectFlipped: false,
  hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fail("failed to encode PNG")
}
do {
  try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try png.write(to: output, options: .atomic)
} catch {
  fail("failed to write output: \(error)")
}
