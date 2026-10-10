// Generates Mac7Zip's .icns from the authentic 7-Zip program icon.
//
// Usage:
//   swift Scripts/make_icon.swift <icon.svg> <output.icns>
//
// The source (`Resources/7-Zip-Icon.svg`) is the official 7-Zip program icon
// as vector artwork — the very same mark that the Windows File Manager
// (`7zFM.exe`, `CPP/7zip/UI/FileManager/FM.ico`) uses: a black-outlined
// landscape rounded rectangle containing the black "7z" logo.
//
// To match the original 48x48 icon exactly, the artwork is drawn into the same
// region the original uses (x 2...46, y 7...41 inside a 48x48 canvas). Because
// the source is vector, every size is rendered crisply.
//
// The bundled artwork comes from the official 7-Zip program icon (7-Zip is
// LGPL); see THIRD_PARTY/7-Zip-Icon-License.txt.

import AppKit
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: make_icon <icon.svg> <out.icns>") }
let logoURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

guard let logo = NSImage(contentsOf: logoURL) else {
    fail("cannot read icon at \(logoURL.path)")
}

/// Renders the official 7-Zip icon at `size` x `size` pixels.
func makeIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let scale = s / 48.0
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot create context") }

    ctx.interpolationQuality = .high

    // The original 48x48 program icon places its landscape artwork at
    // x 2...46, y 7...41 (a 44x34 rounded rectangle). Reproduce that layout.
    let artwork = CGRect(x: 2 * scale, y: 7 * scale, width: 44 * scale, height: 34 * scale)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    logo.draw(in: artwork, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

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
