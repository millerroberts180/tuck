// Renders the Tuck logo SVGs to PNG, builds Support/AppIcon.icns and the web icons.
// Run from the repository root after generate.py: swift design/logo/render.swift
// Uses only AppKit's SVG support and ImageIO, so it needs no third-party tools or browser.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let logo = root.appendingPathComponent("design/logo")
let fm = FileManager.default

func load(_ relative: String) -> NSImage {
    let url = logo.appendingPathComponent(relative)
    guard let image = NSImage(contentsOf: url) else { fatalError("cannot read \(url.path)") }
    return image
}

/// Draws an SVG into an sRGB bitmap of exactly `width` pixels (height follows the artwork's aspect).
func png(_ svg: String, width: Int, to out: URL) -> Data {
    let image = load(svg)
    let height = Int((CGFloat(width) * image.size.height / image.size.width).rounded())
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no bitmap context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! (data as Data).write(to: out)
    return data as Data
}

// MARK: - macOS app icon (16 and 32 px use the small cut, whose bolder line keeps the dip open)

let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let source = pixels <= 32 ? "source/appicon-small.svg" : "source/appicon.svg"
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    _ = png(source, width: pixels, to: iconset.appendingPathComponent(name))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Support/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
try? fm.removeItem(at: iconset)

// MARK: - Web icons

let web = logo.appendingPathComponent("web")
_ = png("source/web-touch.svg", width: 180, to: web.appendingPathComponent("apple-touch-icon.png"))
_ = png("source/web-touch.svg", width: 192, to: web.appendingPathComponent("icon-192.png"))
_ = png("source/web-touch.svg", width: 512, to: web.appendingPathComponent("icon-512.png"))
_ = png("source/web-maskable.svg", width: 512, to: web.appendingPathComponent("icon-maskable-512.png"))

// favicon.ico: 16, 32 and 48 px PNG entries of the small cut
let scratch = fm.temporaryDirectory
let entries = [16, 32, 48].map { ($0, png("svg/tuck-symbol-small.svg", width: $0,
                                          to: scratch.appendingPathComponent("tuck-fav-\($0).png"))) }
var ico = Data()
func le16(_ v: Int) { ico.append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]) }
func le32(_ v: Int) { le16(v & 0xffff); le16(v >> 16) }
le16(0); le16(1); le16(entries.count)
var offset = 6 + 16 * entries.count
for (size, data) in entries {
    ico.append(contentsOf: [UInt8(size), UInt8(size), 0, 0])
    le16(1); le16(32); le32(data.count); le32(offset)
    offset += data.count
}
entries.forEach { ico.append($0.1) }
try! ico.write(to: web.appendingPathComponent("favicon.ico"))

// MARK: - PNG exports for documents, press and social

let pngDir = logo.appendingPathComponent("png")
for (svg, width) in [("svg/tuck-symbol.svg", 1024), ("svg/tuck-symbol-white.svg", 1024),
                     ("svg/tuck-logo-horizontal.svg", 1600), ("svg/tuck-logo-horizontal-reversed.svg", 1600),
                     ("svg/tuck-logo-stacked.svg", 1200), ("svg/tuck-logo-stacked-reversed.svg", 1200),
                     ("source/appicon.svg", 1024)] {
    let base = (svg as NSString).lastPathComponent.replacingOccurrences(of: ".svg", with: "")
    let name = base == "appicon" ? "tuck-appicon" : base
    _ = png(svg, width: width, to: pngDir.appendingPathComponent("\(name)-\(width).png"))
}
print("Rendered PNGs, Support/AppIcon.icns and web icons")
