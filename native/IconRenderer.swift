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
        paper.setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 192, yRadius: 192).fill()

        ink.setStroke()
        let outer = NSBezierPath(rect: NSRect(x: 152, y: 152, width: 720, height: 720))
        outer.lineWidth = 18
        outer.stroke()

        let left = NSRect(x: 218, y: 310, width: 224, height: 404)
        let right = NSRect(x: 582, y: 310, width: 224, height: 404)
        ink.setFill()
        NSBezierPath(rect: left).fill()
        let rightPath = NSBezierPath(rect: right)
        rightPath.lineWidth = 18
        rightPath.stroke()

        draw("A", in: left, color: paper, size: 186)
        draw("РУ", in: right, color: ink, size: 104)

        let upper = NSBezierPath()
        upper.move(to: NSPoint(x: 460, y: 585))
        upper.line(to: NSPoint(x: 564, y: 585))
        upper.line(to: NSPoint(x: 530, y: 619))
        upper.move(to: NSPoint(x: 564, y: 585))
        upper.line(to: NSPoint(x: 530, y: 551))
        upper.lineWidth = 18
        upper.lineJoinStyle = .miter
        upper.stroke()

        let lower = NSBezierPath()
        lower.move(to: NSPoint(x: 564, y: 439))
        lower.line(to: NSPoint(x: 460, y: 439))
        lower.line(to: NSPoint(x: 494, y: 473))
        lower.move(to: NSPoint(x: 460, y: 439))
        lower.line(to: NSPoint(x: 494, y: 405))
        lower.lineWidth = 18
        lower.lineJoinStyle = .miter
        lower.stroke()

        let caption = "LAYOUT PILOT"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(
            string: caption,
            attributes: [
                .font: mono(size: 42, weight: .semibold),
                .foregroundColor: ink,
                .paragraphStyle: paragraph,
                .kern: 6,
            ]
        ).draw(in: NSRect(x: 190, y: 205, width: 644, height: 64))

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
