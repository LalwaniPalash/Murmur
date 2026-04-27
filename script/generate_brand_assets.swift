#!/usr/bin/env swift

import AppKit
import Foundation

struct CubicCurve {
    let end: CGPoint
    let control1: CGPoint
    let control2: CGPoint
}

struct Palette {
    let stroke: NSColor
    let background: NSColor?
}

private let canvasSize = CGSize(width: 1024, height: 1024)
private let iconRect = CGRect(x: 64, y: 64, width: 896, height: 896)
private let iconCornerRadius: CGFloat = 216
private let strokeWidth: CGFloat = 108
private let strokeStart = CGPoint(x: 202, y: 726)
private let curves = [
    CubicCurve(
        end: CGPoint(x: 348, y: 306),
        control1: CGPoint(x: 252, y: 726),
        control2: CGPoint(x: 292, y: 306)
    ),
    CubicCurve(
        end: CGPoint(x: 512, y: 592),
        control1: CGPoint(x: 404, y: 306),
        control2: CGPoint(x: 456, y: 592)
    ),
    CubicCurve(
        end: CGPoint(x: 676, y: 306),
        control1: CGPoint(x: 568, y: 592),
        control2: CGPoint(x: 620, y: 306)
    ),
    CubicCurve(
        end: CGPoint(x: 822, y: 726),
        control1: CGPoint(x: 732, y: 306),
        control2: CGPoint(x: 772, y: 726)
    ),
]

private let darkPalette = Palette(
    stroke: NSColor(hex: "#F5F3EE"),
    background: NSColor(hex: "#0F1318")
)

private let lightPalette = Palette(
    stroke: NSColor(hex: "#15191E"),
    background: nil
)

private let inversePalette = Palette(
    stroke: NSColor(hex: "#F5F3EE"),
    background: nil
)

let scriptURL = URL(fileURLWithPath: #filePath)
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let brandURL = rootURL.appendingPathComponent("Assets/Brand", isDirectory: true)
let iconsetURL = brandURL.appendingPathComponent("Murmur.iconset", isDirectory: true)
let icnsURL = brandURL.appendingPathComponent("Murmur.icns")

try FileManager.default.createDirectory(at: brandURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func brandPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: strokeStart)
    for curve in curves {
        path.curve(to: curve.end, controlPoint1: curve.control1, controlPoint2: curve.control2)
    }
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = strokeWidth
    return path
}

func svgPathDescription() -> String {
    let header = "M \(strokeStart.x) \(svgY(strokeStart.y))"
    let segments = curves.map { curve in
        "C \(curve.control1.x) \(svgY(curve.control1.y)) \(curve.control2.x) \(svgY(curve.control2.y)) \(curve.end.x) \(svgY(curve.end.y))"
    }
    return ([header] + segments).joined(separator: " ")
}

func svgDocument(palette: Palette, includeRoundedBackground: Bool) -> String {
    let path = svgPathDescription()
    let background = includeRoundedBackground && palette.background != nil
        ? #"<rect x="64" y="64" width="896" height="896" rx="216" fill="\#(palette.background!.hexString)"/>"#
        : ""

    return """
    <svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
      \(background)
      <path d="\(path)" stroke="\(palette.stroke.hexString)" stroke-width="108" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    """
}

func renderPNG(at destination: URL, size: Int, palette: Palette, includeRoundedBackground: Bool) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let rep else {
        throw NSError(domain: "Murmur.Brand", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap context."])
    }

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "Murmur.Brand", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create graphics context."])
    }

    NSGraphicsContext.current = context
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    let scale = CGFloat(size) / canvasSize.width
    context.cgContext.scaleBy(x: scale, y: scale)

    NSColor.clear.setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

    if includeRoundedBackground, let background = palette.background {
        background.setFill()
        NSBezierPath(
            roundedRect: iconRect,
            xRadius: iconCornerRadius,
            yRadius: iconCornerRadius
        ).fill()
    }

    palette.stroke.setStroke()
    brandPath().stroke()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Murmur.Brand", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG."])
    }

    try data.write(to: destination)
}

func writeText(_ string: String, to destination: URL) throws {
    try Data(string.utf8).write(to: destination)
}

func svgY(_ y: CGFloat) -> CGFloat {
    canvasSize.height - y
}

func runIconutil(iconsetURL: URL, destination: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", destination.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(domain: "Murmur.Brand", code: 4, userInfo: [NSLocalizedDescriptionKey: "iconutil failed with exit code \(process.terminationStatus)."])
    }
}

try writeText(svgDocument(palette: lightPalette, includeRoundedBackground: false), to: brandURL.appendingPathComponent("murmur-mark.svg"))
try writeText(svgDocument(palette: inversePalette, includeRoundedBackground: false), to: brandURL.appendingPathComponent("murmur-mark-light.svg"))
try writeText(svgDocument(palette: darkPalette, includeRoundedBackground: true), to: brandURL.appendingPathComponent("murmur-icon-dark.svg"))

try renderPNG(
    at: brandURL.appendingPathComponent("murmur-mark-1024.png"),
    size: 1024,
    palette: lightPalette,
    includeRoundedBackground: false
)

try renderPNG(
    at: brandURL.appendingPathComponent("murmur-mark-light-1024.png"),
    size: 1024,
    palette: inversePalette,
    includeRoundedBackground: false
)

try renderPNG(
    at: brandURL.appendingPathComponent("murmur-icon-dark-1024.png"),
    size: 1024,
    palette: darkPalette,
    includeRoundedBackground: true
)

let iconSizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, filename) in iconSizes {
    try renderPNG(
        at: iconsetURL.appendingPathComponent(filename),
        size: size,
        palette: darkPalette,
        includeRoundedBackground: true
    )
}

try? FileManager.default.removeItem(at: icnsURL)
try runIconutil(iconsetURL: iconsetURL, destination: icnsURL)

print("Generated brand assets in \(brandURL.path)")

private extension NSColor {
    convenience init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return "#000000"
        }

        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
