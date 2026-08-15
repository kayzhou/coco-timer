import AppKit

enum Theme {
    /// 影青：瓷色，不是宣纸暖白
    static let paper = NSColor(red: 0.886, green: 0.902, blue: 0.863, alpha: 1)
    /// 墨
    static let ink = NSColor(red: 0.110, green: 0.094, blue: 0.078, alpha: 1)
    /// 茶褐
    static let muted = NSColor(red: 0.420, green: 0.369, blue: 0.306, alpha: 1)
    /// 朱砂：阳、主按钮
    static let cinnabar = NSColor(red: 0.604, green: 0.231, blue: 0.184, alpha: 1)
    /// 石青：爻画
    static let mineral = NSColor(red: 0.247, green: 0.361, blue: 0.333, alpha: 1)
    static let line = NSColor(red: 0.773, green: 0.784, blue: 0.737, alpha: 1)
    static let chip = NSColor(red: 0.827, green: 0.843, blue: 0.800, alpha: 1)
    /// 玄：天
    static let xuan = NSColor(red: 0.078, green: 0.067, blue: 0.055, alpha: 1)
    static let xuanDeep = NSColor(red: 0.047, green: 0.039, blue: 0.031, alpha: 1)
    /// 月白
    static let silk = NSColor(red: 0.929, green: 0.910, blue: 0.863, alpha: 1)
    static let haze = NSColor(red: 0.640, green: 0.604, blue: 0.533, alpha: 1)
    static let skip = NSColor(red: 0.478, green: 0.447, blue: 0.408, alpha: 1)

    static func kaiti(size: CGFloat) -> NSFont {
        NSFont(name: "Kaiti SC", size: size)
            ?? NSFont(name: "STKaiti", size: size)
            ?? NSFont(name: "KaiTi", size: size)
            ?? serif(size: size)
    }

    static func songti(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name: String
        switch weight {
        case .ultraLight, .thin, .light:
            name = "Songti SC Light"
        default:
            name = "Songti SC"
        }
        return NSFont(name: name, size: size)
            ?? NSFont(name: "STSong", size: size)
            ?? serif(size: size, weight: weight)
    }

    static func serif(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func statusIcon(yaos: [Bool]) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 18), flipped: true) { rect in
            YaoPainter.draw(
                in: rect.insetBy(dx: 1, dy: 0.5),
                yaos: yaos,
                progress: 1,
                yang: .black,
                dim: .black
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum YaoPainter {
    private static let gapRatio: CGFloat = 1.05
    private static let widthToLine: CGFloat = 7.4
    private static let yinBreak: CGFloat = 0.26

    /// `yaos[0]` 是初爻，画在卦象最下方。
    static func draw(
        in rect: NSRect,
        yaos: [Bool],
        progress: Double = 1,
        yang: NSColor,
        dim: NSColor
    ) {
        let n = yaos.count
        guard n > 0, rect.width > 1, rect.height > 1 else { return }
        let glyph = fittedGlyph(in: rect, count: n)
        let lineHeight = glyph.height / (CGFloat(n) + CGFloat(n - 1) * gapRatio)
        let stride = lineHeight * (1 + gapRatio)
        let gapW = glyph.width * yinBreak

        for i in 0..<n {
            let rowFromTop = n - 1 - i
            let y = glyph.minY + CGFloat(rowFromTop) * stride
            let lit = min(1, max(0, progress * Double(n) - Double(i)))
            dim.setFill()
            fillYao(
                x: glyph.minX,
                y: y,
                width: glyph.width,
                height: lineHeight,
                yangLine: yaos[i],
                gap: gapW
            )
            if lit > 0.02 {
                (yang.withAlphaComponent(CGFloat(0.35 + 0.65 * lit))).setFill()
                fillYao(
                    x: glyph.minX,
                    y: y,
                    width: glyph.width,
                    height: lineHeight,
                    yangLine: yaos[i],
                    gap: gapW
                )
            }
        }
    }

    private static func fittedGlyph(in bounds: NSRect, count: Int) -> NSRect {
        let n = CGFloat(count)
        let units = n + (n - 1) * gapRatio
        var lineH = bounds.height / units
        var width = lineH * widthToLine
        if width > bounds.width {
            width = bounds.width
            lineH = width / widthToLine
        }
        let height = lineH * units
        return NSRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func fillYao(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, yangLine: Bool, gap: CGFloat) {
        if yangLine {
            NSBezierPath(rect: NSRect(x: x, y: y, width: width, height: height)).fill()
        } else {
            let seg = (width - gap) / 2
            NSBezierPath(rect: NSRect(x: x, y: y, width: seg, height: height)).fill()
            NSBezierPath(rect: NSRect(x: x + width - seg, y: y, width: seg, height: height)).fill()
        }
    }
}
