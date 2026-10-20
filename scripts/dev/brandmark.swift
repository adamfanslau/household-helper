#!/usr/bin/env swift
// Renders the Orbit mark (design canvas "Final mark" board, 120 × 120 geometry) to PNG app icons.
// Usage: scripts/dev/brandmark.swift <out-dir>      → icon.png, icon-dark.png, icon-tinted.png (1024²)
// Vector copies for Android live in apps/android/app/src/main/res/drawable/ic_launcher_*.xml.
import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let px = 1024
let unit = CGFloat(px) / 120

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func polyline(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath()
    for (i, (x, y)) in pts.enumerated() {
        let pt = CGPoint(x: x * unit, y: y * unit)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    return p
}

func spark(_ c: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<8 {
        let a = Double(i) * .pi / 4 - .pi / 2
        let r = i.isMultiple(of: 2) ? outer : inner
        let pt = CGPoint(x: (c.x + r * cos(a)) * unit, y: (c.y + r * sin(a)) * unit)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

struct Variant { let name: String; let bg: (CGContext) -> Void; let orbit: CGColor; let roof: [CGColor]; let tick: CGColor; let spark: CGColor }

let leaf = { (ctx: CGContext) in
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x1FB57A), color(0x0E6B47)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: px, y: px), options: [])
}
let variants = [
    Variant(name: "icon", bg: leaf, orbit: color(0xFFFFFF, 0.4), roof: [color(0xFFFFFF, 0.55), color(0xFFFFFF, 0.55)], tick: color(0xFFFFFF), spark: color(0xFFFFFF)),
    Variant(name: "icon-dark", bg: { $0.setFillColor(color(0x10201A)); $0.fill(CGRect(x: 0, y: 0, width: px, height: px)) },
            orbit: color(0x6FD9A6, 0.42), roof: [color(0x6FD9A6), color(0x17A06A)], tick: color(0xFFFFFF), spark: color(0x6FD9A6)),
    // Tinted source art is greyscale; the system applies the user's tint.
    Variant(name: "icon-tinted", bg: { $0.setFillColor(color(0x2A2F2C)); $0.fill(CGRect(x: 0, y: 0, width: px, height: px)) },
            orbit: color(0xFFFFFF, 0.38), roof: [color(0xFFFFFF, 0.6), color(0xFFFFFF, 0.6)], tick: color(0xFFFFFF), spark: color(0xFFFFFF)),
]

for v in variants {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip so the 120-unit coordinates read top-down like the SVG.
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: 1, y: -1)
    v.bg(ctx)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    // Icon geometry (inset so every mask keeps the spark): roof 28,72→60,42→92,72; tick 38,77→53,92→87,58;
    // orbit 46 × 19 at 60,66 rotated −18°; spark centred 100,50.
    ctx.saveGState()
    ctx.translateBy(x: 60 * unit, y: 66 * unit); ctx.rotate(by: -18 * .pi / 180)
    ctx.setStrokeColor(v.orbit); ctx.setLineWidth(3.5 * unit)
    ctx.strokeEllipse(in: CGRect(x: -46 * unit, y: -19 * unit, width: 92 * unit, height: 38 * unit))
    ctx.restoreGState()
    ctx.setLineWidth(11 * unit)
    ctx.saveGState()
    ctx.addPath(polyline([(28, 72), (60, 42), (92, 72)])); ctx.replacePathWithStrokedPath(); ctx.clip()
    let rg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: v.roof as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(rg, start: CGPoint(x: 28 * unit, y: 42 * unit), end: CGPoint(x: 92 * unit, y: 72 * unit), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(v.tick); ctx.addPath(polyline([(38, 77), (53, 92), (87, 58)])); ctx.strokePath()
    ctx.setFillColor(v.spark); ctx.addPath(spark(CGPoint(x: 100, y: 50), outer: 7.5, inner: 2.3)); ctx.fillPath()
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    let path = "\(out)/\(v.name).png"
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
