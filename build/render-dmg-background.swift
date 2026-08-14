#!/usr/bin/env swift
import AppKit
import Foundation

private let canvas = NSSize(width: 720, height: 460)

private func drawText(
  _ text: String,
  y: CGFloat,
  font: NSFont,
  color: NSColor,
  height: CGFloat
) {
  let style = NSMutableParagraphStyle()
  style.alignment = .center

  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: color,
    .paragraphStyle: style,
  ]

  text.draw(
    in: NSRect(x: 40, y: y, width: canvas.width - 80, height: height),
    withAttributes: attributes
  )
}

private func drawArrow() {
  let accent = NSColor(calibratedRed: 0.16, green: 0.72, blue: 0.38, alpha: 0.82)
  let line = NSBezierPath()
  line.move(to: NSPoint(x: 292, y: 226))
  line.line(to: NSPoint(x: 428, y: 226))
  line.lineWidth = 4
  line.lineCapStyle = .round
  accent.setStroke()
  line.stroke()

  let head = NSBezierPath()
  head.move(to: NSPoint(x: 414, y: 238))
  head.line(to: NSPoint(x: 430, y: 226))
  head.line(to: NSPoint(x: 414, y: 214))
  head.lineWidth = 4
  head.lineCapStyle = .round
  head.lineJoinStyle = .round
  accent.setStroke()
  head.stroke()
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: render-dmg-background.swift OUTPUT.png\n".utf8))
  exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
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
  FileHandle.standardError.write(Data("render-dmg-background: failed to create canvas\n".utf8))
  exit(1)
}
bitmap.size = canvas

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let bounds = NSRect(origin: .zero, size: canvas)
let top = NSColor(calibratedWhite: 0.985, alpha: 1)
let bottom = NSColor(calibratedRed: 0.91, green: 0.95, blue: 0.93, alpha: 1)
NSGradient(starting: top, ending: bottom)?.draw(in: bounds, angle: -90)

let halo = NSBezierPath(
  roundedRect: NSRect(x: 48, y: 86, width: 624, height: 258), xRadius: 28, yRadius: 28)
NSColor(calibratedWhite: 1, alpha: 0.55).setFill()
halo.fill()

let border = NSBezierPath(
  roundedRect: NSRect(x: 48.5, y: 86.5, width: 623, height: 257), xRadius: 28, yRadius: 28)
border.lineWidth = 1
NSColor(calibratedWhite: 0.62, alpha: 0.18).setStroke()
border.stroke()

drawText(
  "Install ntfsmac",
  y: 381,
  font: .systemFont(ofSize: 28, weight: .semibold),
  color: NSColor(calibratedWhite: 0.16, alpha: 1),
  height: 40
)
drawText(
  "Drag ntfsmac to Applications",
  y: 351,
  font: .systemFont(ofSize: 15, weight: .regular),
  color: NSColor(calibratedWhite: 0.34, alpha: 1),
  height: 24
)
drawText(
  "DRAG TO INSTALL",
  y: 111,
  font: .systemFont(ofSize: 11, weight: .semibold),
  color: NSColor(calibratedWhite: 0.42, alpha: 0.78),
  height: 18
)
drawArrow()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  FileHandle.standardError.write(Data("render-dmg-background: failed to encode PNG\n".utf8))
  exit(1)
}

do {
  try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try png.write(to: output, options: .atomic)
} catch {
  FileHandle.standardError.write(Data("render-dmg-background: \(error)\n".utf8))
  exit(1)
}
