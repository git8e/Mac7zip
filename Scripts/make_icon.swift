// Generates Mac7Zip's .icns from an official 7-Zip logo image.
//
// Usage:
//   swift Scripts/make_icon.swift <logo.png> <output.icns> [background-hex]
//
// The logo is cropped to its visible bounds and centred on a rounded "app
// tile" so the result reads as a proper macOS application icon at every size.
//
// The bundled artwork comes from the official 7-Zip program icon (7-Zip is
// LGPL); see THIRD_PARTY/7-Zip-License.txt.

import AppKit
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: make_icon <logo.png> <out.icns> [bg-hex]") }
let logoURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

func color(fromHex hex: String) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = Int(s, radix: 16) else {
        return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
    return CGColor(
        red: CGFloat((value >> 16) & 0xff) / 255,
        green: CGFloat((value >> 8) & 0xff) / 255,
        blue: CGFloat(value & 0xff) / 255,
        alpha: 1
    )
}
let background = color(fromHex: args.count > 3 ? args[3] : "FFFFFF")

guard let logoImage = NSImage(contentsOf: logoURL),
      let logo = logoImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("cannot read logo at \(logoURL.path)")
}

// Crop to the non-transparent bounding box.
guard let provider = logo.dataProvider, let raw = provider.data,
      let bytes = CFDataGetBytePtr(raw) else { fail("logo has no pixel data") }
let width = logo.width
let height = logo.height
let bytesPerRow = logo.bytesPerRow
let bytesPerPixel = logo.bitsPerPixel / 8
guard bytesPerPixel >= 1 else { fail("unexpected pixel format") }

var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width {
        let alpha = bytes[y * bytesPerRow + x * bytesPerPixel + (bytesPerPixel - 1)]
        if alpha > 8 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}
guard maxX >= minX, maxY >= minY else { fail("logo appears to be empty") }
let cropWidth = maxX - minX + 1
let cropHeight = maxY - minY + 1
guard let cropped = logo.cropping(to: CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)) else {
    fail("crop failed")
}

func makeIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create context") }

    ctx.interpolationQuality = .high

    // Rounded background tile.
    let margin = s * 0.06
    let tile = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = tile.width * 0.225
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(tilePath)
    ctx.setFillColor(background)
    ctx.fillPath()

    // Hairline border for definition on light backgrounds.
    ctx.addPath(tilePath)
    ctx.setStrokeColor(CGColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()

    // Centred logo, sized to the tile width.
    let targetWidth = tile.width * 0.70
    let scale = targetWidth / CGFloat(cropWidth)
    let targetHeight = CGFloat(cropHeight) * scale
    let logoRect = CGRect(
        x: (s - targetWidth) / 2,
        y: (s - targetHeight) / 2,
        width: targetWidth,
        height: targetHeight
    )
    ctx.draw(cropped, in: logoRect)
    guard let image = ctx.makeImage() else { fail("cannot render icon") }
    return image
}

let fileManager = FileManager.default
let iconset = fileManager.temporaryDirectory
    .appendingPathComponent("Mac7Zip-\(UUID().uuidString).iconset")
try? fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

let variants: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

for variant in variants {
    let pixels = variant.base * variant.scale
    let image = makeIcon(size: pixels)
    let name = variant.scale == 1
        ? "icon_\(variant.base)x\(variant.base).png"
        : "icon_\(variant.base)x\(variant.base)@2x.png"
    let url = iconset.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("cannot write \(name)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot finalize \(name)") }
}

// Write a 1024px PNG next to the output for previews, then build the .icns.
if let preview = Optional(makeIcon(size: 1024)),
   let dest = CGImageDestinationCreateWithURL(
        outURL.deletingPathExtension().appendingPathExtension("png") as CFURL,
        "public.png" as CFString, 1, nil) {
    CGImageDestinationAddImage(dest, preview, nil)
    CGImageDestinationFinalize(dest)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fail("iconutil failed") }
print("wrote \(outURL.path)")
