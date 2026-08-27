#!/usr/bin/env swift
import AppKit
import Foundation

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("set-file-icon: \(message)\n".utf8))
  exit(1)
}

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 5 else {
  FileHandle.standardError.write(
    Data("usage: set-file-icon.swift TARGET SOURCE.png [VISIBLE_SIZE FINDER_ICON_SIZE]\n".utf8)
  )
  exit(2)
}

let targetPath = CommandLine.arguments[1]
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[2])
let visibleSize = CommandLine.arguments.count == 5 ? CGFloat(Double(CommandLine.arguments[3]) ?? 0) : 70
let finderIconSize = CommandLine.arguments.count == 5 ? CGFloat(Double(CommandLine.arguments[4]) ?? 0) : 104
guard visibleSize > 0, finderIconSize > 0, visibleSize <= finderIconSize else {
  fail("invalid visible/Finder icon sizes")
}
guard FileManager.default.fileExists(atPath: targetPath) else {
  fail("target does not exist: \(targetPath)")
}
guard let source = NSImage(contentsOf: sourceURL) else {
  fail("cannot load icon source: \(sourceURL.path)")
}

// Finder applies one icon-size setting to every item in the window. Render the website artwork
// inside a transparent 1024 px canvas so its visible mark is intentionally smaller than the app
// and Applications icons while retaining a sharp Retina resource fork.
let canvasSize = NSSize(width: 1024, height: 1024)
let visibleScale = visibleSize / finderIconSize
let drawingSize = NSSize(
  width: canvasSize.width * visibleScale,
  height: canvasSize.height * visibleScale
)
let drawingRect = NSRect(
  x: (canvasSize.width - drawingSize.width) / 2,
  // Anchor the visible mark low in Finder's fixed icon cell. This keeps the approved size while
  // removing the artificial gap that a vertically centered transparent canvas creates above
  // the filename label.
  y: 0,
  width: drawingSize.width,
  height: drawingSize.height
)

let paddedIcon = NSImage(size: canvasSize)
paddedIcon.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(
  in: drawingRect,
  from: .zero,
  operation: .sourceOver,
  fraction: 1,
  respectFlipped: false,
  hints: [.interpolation: NSImageInterpolation.high]
)
paddedIcon.unlockFocus()

guard NSWorkspace.shared.setIcon(paddedIcon, forFile: targetPath, options: []) else {
  fail("Finder rejected the custom icon for \(targetPath)")
}
