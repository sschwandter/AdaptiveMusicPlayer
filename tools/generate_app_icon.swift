import AppKit
import Foundation

struct IconSpec {
    let pointSize: Int
    let scale: Int
    let filename: String

    var pixelSize: Int { pointSize * scale }
}

let specs: [IconSpec] = [
    .init(pointSize: 16, scale: 1, filename: "icon_16x16.png"),
    .init(pointSize: 16, scale: 2, filename: "icon_16x16@2x.png"),
    .init(pointSize: 32, scale: 1, filename: "icon_32x32.png"),
    .init(pointSize: 32, scale: 2, filename: "icon_32x32@2x.png"),
    .init(pointSize: 128, scale: 1, filename: "icon_128x128.png"),
    .init(pointSize: 128, scale: 2, filename: "icon_128x128@2x.png"),
    .init(pointSize: 256, scale: 1, filename: "icon_256x256.png"),
    .init(pointSize: 256, scale: 2, filename: "icon_256x256@2x.png"),
    .init(pointSize: 512, scale: 1, filename: "icon_512x512.png"),
    .init(pointSize: 512, scale: 2, filename: "icon_512x512@2x.png"),
]

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func makeBitmap(size: Int, draw: (_ rect: CGRect) -> Void) -> NSBitmapImageRep {
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
    )!

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    draw(rect)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func roundedSquarePath(in rect: CGRect, inset: CGFloat) -> NSBezierPath {
    let inner = rect.insetBy(dx: inset, dy: inset)
    let radius = inner.width * 0.225
    return NSBezierPath(roundedRect: inner, xRadius: radius, yRadius: radius)
}

func drawIcon(in rect: CGRect) {
    let inset = rect.width * 0.035
    let iconPath = roundedSquarePath(in: rect, inset: inset)

    NSGraphicsContext.current?.imageInterpolation = .high

    iconPath.addClip()

    let background = NSGradient(
        colors: [
            color(37, 118, 255),
            color(27, 52, 134),
            color(18, 27, 58)
        ]
    )!
    background.draw(in: iconPath, angle: -55)

    let warmGlow = NSBezierPath(ovalIn: CGRect(
        x: rect.midX - rect.width * 0.18,
        y: rect.minY - rect.height * 0.10,
        width: rect.width * 0.72,
        height: rect.height * 0.72
    ))
    color(255, 146, 92, 0.22).setFill()
    warmGlow.fill()

    let coolGlow = NSBezierPath(ovalIn: CGRect(
        x: rect.minX - rect.width * 0.10,
        y: rect.midY - rect.height * 0.08,
        width: rect.width * 0.62,
        height: rect.height * 0.62
    ))
    color(114, 255, 236, 0.12).setFill()
    coolGlow.fill()

    let barWidth = rect.width * 0.09
    let barSpacing = rect.width * 0.038
    let barHeights: [CGFloat] = [0.22, 0.40, 0.58, 0.40, 0.22]
    let totalWidth = (CGFloat(barHeights.count) * barWidth) + (CGFloat(barHeights.count - 1) * barSpacing)
    let barsOriginX = rect.midX - totalWidth / 2

    for (index, heightFactor) in barHeights.enumerated() {
        let x = barsOriginX + CGFloat(index) * (barWidth + barSpacing)
        let barHeight = rect.height * heightFactor
        let barRect = CGRect(
            x: x,
            y: rect.midY - barHeight / 2,
            width: barWidth,
            height: barHeight
        )
        let bar = NSBezierPath(
            roundedRect: barRect,
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )

        if rect.width >= 128 {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = color(10, 18, 44, 0.24)
            shadow.shadowBlurRadius = rect.width * 0.03
            shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.012)
            shadow.set()
            color(255, 255, 255, 0.96).setFill()
            bar.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        color(255, 255, 255, 0.96).setFill()
        bar.fill()
    }

    let border = roundedSquarePath(in: rect, inset: inset)
    border.lineWidth = rect.width * 0.012
    color(255, 255, 255, 0.10).setStroke()
    border.stroke()
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for spec in specs {
    let rep = makeBitmap(size: spec.pixelSize) { rect in
        drawIcon(in: rect)
    }

    let destination = outputDirectory.appendingPathComponent(spec.filename)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(spec.filename)")
    }
    try data.write(to: destination)
    print("Wrote \(destination.path)")
}
