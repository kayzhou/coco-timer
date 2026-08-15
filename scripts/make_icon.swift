import AppKit
import Foundation

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext
let xuan = NSColor(red: 0.078, green: 0.067, blue: 0.055, alpha: 1).cgColor
let xuanDeep = NSColor(red: 0.047, green: 0.039, blue: 0.031, alpha: 1).cgColor
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [xuan, xuanDeep] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
)

func fillYin(rect: NSRect) {
    NSColor(red: 0.929, green: 0.910, blue: 0.863, alpha: 1).setFill()
    let gap = rect.width * 0.26
    let seg = (rect.width - gap) / 2
    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: seg, height: rect.height)).fill()
    NSBezierPath(rect: NSRect(x: rect.maxX - seg, y: rect.minY, width: seg, height: rect.height)).fill()
}

// 坤卦䷁：六阴。AppKit 原点在左下，自下而上画初爻至上爻。
let lineH: CGFloat = 58
let gap: CGFloat = 62
let count: CGFloat = 6
let totalH = lineH * count + gap * (count - 1)
let width: CGFloat = lineH * 7.4
let originX = (size - width) / 2
let originY = (size - totalH) / 2

for i in 0..<6 {
    let y = originY + CGFloat(i) * (lineH + gap)
    fillYin(rect: NSRect(x: originX, y: y, width: width, height: lineH))
}

image.unlockFocus()

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath
let pngURL = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.png")
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode icon\n", stderr)
    exit(1)
}
try png.write(to: pngURL)
print(pngURL.path)
