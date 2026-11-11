import AppKit

enum Theme {
    enum Style: String, CaseIterable {
        case classic, green
    }

    static var style: Style {
        get { Style(rawValue: UserDefaults.standard.string(forKey: "visualTheme") ?? "") ?? .classic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "visualTheme") }
    }

    private static var isGreen: Bool { style == .green }
    static var paper: NSColor { isGreen ? NSColor(red: 0.91, green: 0.94, blue: 0.89, alpha: 1) : NSColor(red: 0.886, green: 0.902, blue: 0.863, alpha: 1) }
    static var ink: NSColor { isGreen ? NSColor(red: 0.10, green: 0.19, blue: 0.14, alpha: 1) : NSColor(red: 0.110, green: 0.094, blue: 0.078, alpha: 1) }
    static var muted: NSColor { isGreen ? NSColor(red: 0.28, green: 0.37, blue: 0.30, alpha: 1) : NSColor(red: 0.420, green: 0.369, blue: 0.306, alpha: 1) }
    static var cinnabar: NSColor { isGreen ? NSColor(red: 0.20, green: 0.39, blue: 0.29, alpha: 1) : NSColor(red: 0.604, green: 0.231, blue: 0.184, alpha: 1) }
    static var mineral: NSColor { isGreen ? NSColor(red: 0.22, green: 0.42, blue: 0.31, alpha: 1) : NSColor(red: 0.247, green: 0.361, blue: 0.333, alpha: 1) }
    static var line: NSColor { isGreen ? NSColor(red: 0.72, green: 0.80, blue: 0.71, alpha: 1) : NSColor(red: 0.773, green: 0.784, blue: 0.737, alpha: 1) }
    static var chip: NSColor { isGreen ? NSColor(red: 0.79, green: 0.86, blue: 0.78, alpha: 1) : NSColor(red: 0.827, green: 0.843, blue: 0.800, alpha: 1) }
    static var xuan: NSColor { isGreen ? NSColor(red: 0.10, green: 0.21, blue: 0.15, alpha: 1) : NSColor(red: 0.078, green: 0.067, blue: 0.055, alpha: 1) }
    static var xuanDeep: NSColor { isGreen ? NSColor(red: 0.04, green: 0.12, blue: 0.08, alpha: 1) : NSColor(red: 0.047, green: 0.039, blue: 0.031, alpha: 1) }
    static var silk: NSColor { isGreen ? NSColor(red: 0.92, green: 0.95, blue: 0.88, alpha: 1) : NSColor(red: 0.929, green: 0.910, blue: 0.863, alpha: 1) }
    static var haze: NSColor { isGreen ? NSColor(red: 0.72, green: 0.80, blue: 0.70, alpha: 1) : NSColor(red: 0.640, green: 0.604, blue: 0.533, alpha: 1) }
    static var overlayAccent: NSColor { isGreen ? NSColor(red: 0.68, green: 0.82, blue: 0.65, alpha: 1) : cinnabar }

    /// 休息时的提醒，取古文口气
    static let standPrompt = "坐不可久，起而步之。"
    /// 连续四次仍行后，强制止息时的提示
    static let skipBlockedHint = "连仍四次，此番须止。"
    static let skipBlockedControl = "此番须止"

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

    static func statusBarTitle(phase: TimerPhase, time: String) -> NSAttributedString {
        let mark: String
        switch phase {
        case .work:
            mark = "行"
        case .rest:
            mark = "止"
        case .paused:
            mark = "静"
        }
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: mark, attributes: [
            .font: kaiti(size: 12)
        ]))
        text.append(NSAttributedString(string: " \(time)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ]))
        return text
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
