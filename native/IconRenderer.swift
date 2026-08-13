import AppKit
import Foundation

@main
private struct LayoutPilotIconRenderer {
    private struct Variant {
        let filename: String
        let pixels: Int
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: IconRenderer <iconset-directory>\n", stderr)
            exit(2)
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let variants = [
            Variant(filename: "icon_16x16.png", pixels: 16),
            Variant(filename: "icon_16x16@2x.png", pixels: 32),
            Variant(filename: "icon_32x32.png", pixels: 32),
            Variant(filename: "icon_32x32@2x.png", pixels: 64),
            Variant(filename: "icon_128x128.png", pixels: 128),
            Variant(filename: "icon_128x128@2x.png", pixels: 256),
            Variant(filename: "icon_256x256.png", pixels: 256),
            Variant(filename: "icon_256x256@2x.png", pixels: 512),
            Variant(filename: "icon_512x512.png", pixels: 512),
            Variant(filename: "icon_512x512@2x.png", pixels: 1024),
        ]

        for variant in variants {
            let data = try render(pixels: variant.pixels)
            try data.write(to: output.appendingPathComponent(variant.filename), options: .atomic)
        }
    }

    private static func render(pixels: Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "LayoutPilotIcon", code: 1)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let scale = CGFloat(pixels) / 1024
        context.cgContext.scaleBy(x: scale, y: scale)

        let paper = NSColor(srgbRed: 0.957, green: 0.949, blue: 0.925, alpha: 1)
        let ink = NSColor(srgbRed: 0.133, green: 0.125, blue: 0.098, alpha: 1)
        let signal = NSColor(srgbRed: 0.784, green: 1.0, blue: 0.094, alpha: 1)
        paper.setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 192, yRadius: 192).fill()

        // One relay core, readable from 16 px through 1024 px. The two
        // negative-space rails cross inside the diamond: source becomes target.
        ink.setFill()
        let core = NSBezierPath()
        core.move(to: NSPoint(x: 512, y: 232))
        core.line(to: NSPoint(x: 792, y: 512))
        core.line(to: NSPoint(x: 512, y: 792))
        core.line(to: NSPoint(x: 232, y: 512))
        core.close()
        core.fill()

        let railWidth: CGFloat = 54
        let upperRail = NSBezierPath()
        upperRail.move(to: NSPoint(x: 144, y: 650))
        upperRail.line(to: NSPoint(x: 394, y: 650))
        upperRail.line(to: NSPoint(x: 630, y: 374))
        upperRail.line(to: NSPoint(x: 880, y: 374))
        upperRail.lineWidth = railWidth
        upperRail.lineCapStyle = .butt

        let lowerRail = NSBezierPath()
        lowerRail.move(to: NSPoint(x: 144, y: 374))
        lowerRail.line(to: NSPoint(x: 394, y: 374))
        lowerRail.line(to: NSPoint(x: 630, y: 650))
        lowerRail.line(to: NSPoint(x: 880, y: 650))
        lowerRail.lineWidth = railWidth
        lowerRail.lineCapStyle = .butt

        paper.setStroke()
        upperRail.stroke()
        lowerRail.stroke()

        signal.setFill()
        let node = NSBezierPath()
        node.move(to: NSPoint(x: 512, y: 466))
        node.line(to: NSPoint(x: 558, y: 512))
        node.line(to: NSPoint(x: 512, y: 558))
        node.line(to: NSPoint(x: 466, y: 512))
        node.close()
        node.fill()

        if pixels >= 128 {
            draw("A", in: NSRect(x: 154, y: 690, width: 150, height: 96), color: ink, size: 72)
            draw("Я", in: NSRect(x: 720, y: 234, width: 150, height: 96), color: ink, size: 68)
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LayoutPilotIcon", code: 2)
        }
        return png
    }

    private static func draw(_ text: String, in rect: NSRect, color: NSColor, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let value = NSAttributedString(
            string: text,
            attributes: [
                .font: mono(size: size, weight: .semibold),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: text == "A" ? 0 : -4,
            ]
        )
        let measured = value.size()
        value.draw(in: NSRect(
            x: rect.minX,
            y: rect.midY - measured.height / 2 - 6,
            width: rect.width,
            height: measured.height + 16
        ))
    }

    private static func drawLabel(_ text: String, in rect: NSRect, size: CGFloat, kern: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(
            string: text,
            attributes: [
                .font: mono(size: size, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: 0.133, green: 0.125, blue: 0.098, alpha: 1),
                .paragraphStyle: paragraph,
                .kern: kern,
            ]
        ).draw(in: rect)
    }

    private static func mono(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let names = weight == .semibold
            ? ["JetBrainsMono-SemiBold", "JetBrains Mono SemiBold", "JetBrains Mono"]
            : ["JetBrainsMono-Regular", "JetBrains Mono"]
        for name in names {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}
