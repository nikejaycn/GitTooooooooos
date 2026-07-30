#!/usr/bin/env swift

import AppKit
import Foundation

private struct IconOutput {
  let pixels: Int
  let filename: String
}

private let outputs = [
  IconOutput(pixels: 16, filename: "AppIcon-16.png"),
  IconOutput(pixels: 32, filename: "AppIcon-16@2x.png"),
  IconOutput(pixels: 32, filename: "AppIcon-32.png"),
  IconOutput(pixels: 64, filename: "AppIcon-32@2x.png"),
  IconOutput(pixels: 128, filename: "AppIcon-128.png"),
  IconOutput(pixels: 256, filename: "AppIcon-128@2x.png"),
  IconOutput(pixels: 256, filename: "AppIcon-256.png"),
  IconOutput(pixels: 512, filename: "AppIcon-256@2x.png"),
  IconOutput(pixels: 512, filename: "AppIcon-512.png"),
  IconOutput(pixels: 1024, filename: "AppIcon-512@2x.png"),
]

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("usage: generate-app-icon-assets.swift <source.png> <appiconset>\n".utf8)
  )
  exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
  FileHandle.standardError.write(Data("error: unable to read \(sourceURL.path)\n".utf8))
  exit(66)
}

try FileManager.default.createDirectory(
  at: outputDirectory,
  withIntermediateDirectories: true
)

for output in outputs {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: output.pixels,
      pixelsHigh: output.pixels,
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
    throw CocoaError(.fileWriteUnknown)
  }

  let canvas = NSRect(x: 0, y: 0, width: output.pixels, height: output.pixels)
  let destination = canvas.insetBy(
    dx: CGFloat(output.pixels) * 0.035,
    dy: CGFloat(output.pixels) * 0.035
  )
  let sourceCrop = NSRect(
    x: sourceImage.size.width * 0.045,
    y: sourceImage.size.height * 0.045,
    width: sourceImage.size.width * 0.91,
    height: sourceImage.size.height * 0.91
  )

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = output.pixels <= 64 ? .high : .high
  NSColor.clear.setFill()
  canvas.fill()
  NSBezierPath(
    roundedRect: destination,
    xRadius: CGFloat(output.pixels) * 0.22,
    yRadius: CGFloat(output.pixels) * 0.22
  ).addClip()
  sourceImage.draw(
    in: destination,
    from: sourceCrop,
    operation: .copy,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
  )
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }
  try png.write(to: outputDirectory.appendingPathComponent(output.filename), options: .atomic)
}
