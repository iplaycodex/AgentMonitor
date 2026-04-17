#!/usr/bin/env swift

import Cocoa

let sizes: [Int] = [16, 32, 64, 128, 256, 512]

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else { return image }

    // Rounded rect background (macOS icon shape)
    let radius = s * 0.2236 // Standard macOS icon corner radius
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.clip()

    // Gradient background: dark navy → deep blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 0.11, green: 0.14, blue: 0.22, alpha: 1.0),
        CGColor(red: 0.16, green: 0.22, blue: 0.36, alpha: 1.0),
    ] as CFArray, locations: [0.0, 1.0])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Terminal window body
    let termX = s * 0.18
    let termY = s * 0.15
    let termW = s * 0.64
    let termH = s * 0.70
    let termRadius = s * 0.06
    let termPath = CGPath(roundedRect: CGRect(x: termX, y: termY, width: termW, height: termH),
                          cornerWidth: termRadius, cornerHeight: termRadius, transform: nil)
    context.addPath(termPath)
    context.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.9))
    context.fillPath()

    // Terminal title bar
    let barH = s * 0.10
    let barPath = CGPath(roundedRect: CGRect(x: termX, y: termY + termH - barH, width: termW, height: barH),
                         cornerWidth: termRadius, cornerHeight: termRadius, transform: nil)
    context.addPath(barPath)
    context.setFillColor(CGColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1.0))
    context.fillPath()

    // Traffic lights (3 circles)
    let dotR = s * 0.022
    let dotY = termY + termH - barH * 0.5
    let dotColors: [CGColor] = [
        CGColor(red: 1.0, green: 0.38, blue: 0.36, alpha: 1.0), // red
        CGColor(red: 1.0, green: 0.78, blue: 0.26, alpha: 1.0), // yellow
        CGColor(red: 0.35, green: 0.85, blue: 0.42, alpha: 1.0), // green
    ]
    for (i, color) in dotColors.enumerated() {
        let dotX = termX + s * 0.08 + CGFloat(i) * s * 0.05
        context.addEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
        context.setFillColor(color)
        context.fillPath()
    }

    // Terminal text lines (chevrons > representing CLI)
    let lineHeight = s * 0.08
    let startY = termY + termH - barH - s * 0.12
    let textLines = [
        (startX: termX + s * 0.08, width: s * 0.40, color: CGColor(red: 0.30, green: 0.80, blue: 1.0, alpha: 1.0)),
        (startX: termX + s * 0.08, width: s * 0.30, color: CGColor(red: 0.30, green: 0.80, blue: 1.0, alpha: 0.7)),
        (startX: termX + s * 0.08, width: s * 0.35, color: CGColor(red: 0.30, green: 0.80, blue: 1.0, alpha: 0.5)),
    ]
    for (i, line) in textLines.enumerated() {
        let ly = startY - CGFloat(i) * (lineHeight + s * 0.03)
        // ">" prompt character
        let promptPath = CGPath(roundedRect: CGRect(x: line.startX, y: ly, width: s * 0.04, height: lineHeight * 0.5),
                                cornerWidth: s * 0.01, cornerHeight: s * 0.01, transform: nil)
        context.addPath(promptPath)
        context.setFillColor(CGColor(red: 0.50, green: 0.55, blue: 0.65, alpha: 1.0))
        context.fillPath()

        // Text line
        let textPath = CGPath(roundedRect: CGRect(x: line.startX + s * 0.06, y: ly + lineHeight * 0.15,
                                                    width: line.width, height: lineHeight * 0.3),
                               cornerWidth: s * 0.015, cornerHeight: s * 0.015, transform: nil)
        context.addPath(textPath)
        context.setFillColor(line.color)
        context.fillPath()
    }

    // Pulse/heartbeat line at bottom of terminal
    let pulseY = termY + s * 0.10
    context.setStrokeColor(CGColor(red: 0.20, green: 0.90, blue: 0.55, alpha: 0.9))
    context.setLineWidth(s * 0.015)
    context.move(to: CGPoint(x: termX + s * 0.08, y: pulseY))
    context.addLine(to: CGPoint(x: termX + s * 0.22, y: pulseY))
    context.addLine(to: CGPoint(x: termX + s * 0.28, y: pulseY + s * 0.08))
    context.addLine(to: CGPoint(x: termX + s * 0.34, y: pulseY - s * 0.05))
    context.addLine(to: CGPoint(x: termX + s * 0.40, y: pulseY + s * 0.03))
    context.addLine(to: CGPoint(x: termX + s * 0.50, y: pulseY))
    context.addLine(to: CGPoint(x: termX + s * 0.56, y: pulseY))
    context.strokePath()

    // Status dot (green, pulsing indicator)
    let dotSize = s * 0.06
    let statusDotX = termX + termW - s * 0.12
    let statusDotY = termY + termH - barH * 0.5
    context.addEllipse(in: CGRect(x: statusDotX, y: statusDotY - dotSize / 2, width: dotSize, height: dotSize))
    context.setFillColor(CGColor(red: 0.20, green: 0.90, blue: 0.55, alpha: 1.0))
    context.fillPath()

    image.unlockFocus()
    return image
}

// Generate iconset
let iconsetPath = "AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// Standard macOS icon sizes
let iconSizes: [(size: Int, scale: Int, filename: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

for item in iconSizes {
    let pixelSize = item.size * item.scale
    let image = drawIcon(size: pixelSize)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(item.filename)"))
    print("Generated \(item.filename) (\(pixelSize)x\(pixelSize))")
}

// Generate Contents.json
let contentsJson = """
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try? contentsJson.write(toFile: "\(iconsetPath)/Contents.json", atomically: true, encoding: .utf8)
print("Generated Contents.json")

// Convert to icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", "AppIcon.icns", iconsetPath]
try? task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✅ Generated AppIcon.icns")
} else {
    print("❌ iconutil failed")
}
