// The Orbit mark: a roof that turns into a tick (one ribbon) with a spark orbiting the house.
// Geometry is the 120 × 120 drawing from the design canvas ("Final mark" board), so the app icon,
// the sign-in hero and the in-app loading indicator are all the same shape.
import SwiftUI

nonisolated enum BrandMarkGeometry {
    static let size: CGFloat = 120
    /// Roof 22,70 → 60,34 → 98,70 and tick 34,76 → 52,94 → 92,54 (full mark).
    static func roof(in r: CGRect) -> Path { polyline([(22, 70), (60, 34), (98, 70)], in: r) }
    static func tick(in r: CGRect) -> Path { polyline([(34, 76), (52, 94), (92, 54)], in: r) }
    /// Orbit ellipse 54 × 22 centred 60,64, rotated −18°.
    static let orbitCenter = CGPoint(x: 60, y: 64)
    static let orbitRadii = CGSize(width: 54, height: 22)
    static let orbitAngle = -18.0 * .pi / 180
    /// Spark centre at parameter t ∈ [0, 1) along the orbit (t = 0 is the resting position, 109,47).
    static func orbitPoint(_ t: Double, in r: CGRect) -> CGPoint {
        let a = t * 2 * .pi
        let x = orbitRadii.width * cos(a), y = orbitRadii.height * sin(a)
        let px = orbitCenter.x + x * cos(orbitAngle) - y * sin(orbitAngle)
        let py = orbitCenter.y + x * sin(orbitAngle) + y * cos(orbitAngle)
        return CGPoint(x: r.minX + px / size * r.width, y: r.minY + py / size * r.height)
    }
    static func orbit(in r: CGRect) -> Path {
        var p = Path(ellipseIn: CGRect(x: -orbitRadii.width, y: -orbitRadii.height, width: orbitRadii.width * 2, height: orbitRadii.height * 2))
        let s = r.width / size
        p = p.applying(CGAffineTransform(rotationAngle: orbitAngle))
        p = p.applying(CGAffineTransform(translationX: orbitCenter.x, y: orbitCenter.y))
        return p.applying(CGAffineTransform(scaleX: s, y: s).translatedBy(x: r.minX / s, y: r.minY / s))
    }
    /// Four-point star, `outer` wide, centred at `c`.
    static func spark(at c: CGPoint, outer: CGFloat, inner: CGFloat) -> Path {
        var p = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2
            let rad = i.isMultiple(of: 2) ? outer : inner
            let pt = CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    private static func polyline(_ pts: [(CGFloat, CGFloat)], in r: CGRect) -> Path {
        var p = Path()
        for (i, (x, y)) in pts.enumerated() {
            let pt = CGPoint(x: r.minX + x / size * r.width, y: r.minY + y / size * r.height)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

/// The mark on a dark tile (sign-in hero) or bare (loading). `spinning` sends the spark around the
/// orbit once every 1.6 s with its trail; with reduce-motion the spark pulses in place instead.
struct BrandMark: View {
    enum Style { case darkTile, bare }
    var style: Style = .darkTile
    var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { ctx in
            let t = spinning ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 : 0
            Canvas { g, size in
                let r = CGRect(origin: .zero, size: size)
                let s = size.width / BrandMarkGeometry.size
                let mint = Brand.mintBright
                if style == .darkTile {
                    g.fill(Path(roundedRect: r, cornerRadius: size.width * 0.27, style: .continuous), with: .color(Brand.ink))
                }
                let inset = style == .darkTile ? r.insetBy(dx: size.width * 0.08, dy: size.width * 0.08) : r
                let stroke = StrokeStyle(lineWidth: 12 * (inset.width / BrandMarkGeometry.size), lineCap: .round, lineJoin: .round)
                g.stroke(BrandMarkGeometry.orbit(in: inset), with: .color(mint.opacity(0.42)), lineWidth: 3.5 * s)
                g.stroke(BrandMarkGeometry.roof(in: inset), with: .linearGradient(Gradient(colors: [mint, Brand.primary]), startPoint: inset.origin, endPoint: CGPoint(x: inset.maxX, y: inset.maxY)), style: stroke)
                g.stroke(BrandMarkGeometry.tick(in: inset), with: .color(.white), style: stroke)
                // Spark with two trailing dots behind it along the ring.
                let pulse = reduceMotion && spinning ? 1 + 0.15 * sin(ctx.date.timeIntervalSinceReferenceDate * 4) : 1
                let tt = reduceMotion ? 0 : t
                for (lag, radius, alpha) in [(0.06, 1.8, 0.4), (0.03, 2.5, 0.7)] {
                    let c = BrandMarkGeometry.orbitPoint(tt - lag, in: inset)
                    g.fill(Path(ellipseIn: CGRect(x: c.x - radius * s, y: c.y - radius * s, width: radius * 2 * s, height: radius * 2 * s)), with: .color(mint.opacity(alpha)))
                }
                let c = BrandMarkGeometry.orbitPoint(tt, in: inset)
                g.fill(BrandMarkGeometry.spark(at: c, outer: 8.5 * s * pulse, inner: 2.8 * s * pulse), with: .color(mint))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The spark alone: the "smart" glyph for suggestions and assistant hints.
struct SparkGlyph: View {
    var size: CGFloat = 18
    var tint: Color = Brand.primary

    var body: some View {
        Canvas { g, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            g.fill(BrandMarkGeometry.spark(at: c, outer: sz.width / 2, inner: sz.width / 6), with: .color(tint))
            let small = CGPoint(x: sz.width * 0.86, y: sz.height * 0.18)
            g.fill(BrandMarkGeometry.spark(at: small, outer: sz.width * 0.14, inner: sz.width * 0.05), with: .color(tint.opacity(0.7)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
