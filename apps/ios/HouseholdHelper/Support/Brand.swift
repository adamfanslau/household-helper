// The app's visual language: one brand green, a stable colour + symbol per shop (same hash on
// Android so a shop looks the same on both phones), and the soft gradient hero behind big titles.
import SwiftUI

nonisolated enum Brand {
    static let primary = Color(red: 0.09, green: 0.63, blue: 0.42)        // #17A06A
    static let primaryDeep = Color(red: 0.05, green: 0.42, blue: 0.28)    // #0E6B47
    static let mint = Color(red: 0.78, green: 0.95, blue: 0.87)           // #C8F2DD
    static let basket = Color(red: 0.13, green: 0.72, blue: 0.45)         // tick green
    static let leaf = Color(red: 0.12, green: 0.71, blue: 0.48)           // #1FB57A, light end of the Leaf gradient
    static let mintBright = Color(red: 0.44, green: 0.85, blue: 0.65)     // #6FD9A6, the mark's roof/spark on dark
    static let ink = Color(red: 0.06, green: 0.13, blue: 0.10)            // #10201A, the mark's dark tile
    static let inkSoft = Color(red: 0.12, green: 0.23, blue: 0.17)        // #1E3A2C

    static let gradient = LinearGradient(colors: [primary, primaryDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let inkGradient = LinearGradient(colors: [ink, inkSoft], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Eight vivid-but-soft hues; a shop keeps its colour as long as it keeps its name.
    static let shopPalette: [Color] = [
        Color(red: 0.95, green: 0.42, blue: 0.36),  // coral
        Color(red: 0.95, green: 0.64, blue: 0.23),  // amber
        Color(red: 0.55, green: 0.76, blue: 0.29),  // lime
        Color(red: 0.12, green: 0.71, blue: 0.64),  // teal
        Color(red: 0.23, green: 0.62, blue: 0.91),  // sky
        Color(red: 0.56, green: 0.42, blue: 0.91),  // violet
        Color(red: 0.93, green: 0.37, blue: 0.64),  // pink
        Color(red: 0.42, green: 0.48, blue: 0.56),  // slate
    ]

    /// Same arithmetic as Android's Brand.shopColor: sum of the lower-cased code points mod 8.
    static func shopColor(_ name: String) -> Color {
        let sum = name.lowercased().unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 100_000 }
        return shopPalette[sum % shopPalette.count]
    }

    static func shopSymbol(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("pharm") || n.contains("drug") || n.contains("apothe") || n.contains("boots") { return "cross.case.fill" }
        if n.contains("costco") || n.contains("wholesale") || n.contains("bulk") || n.contains("warehouse") { return "shippingbox.fill" }
        if n.contains("bak") || n.contains("bread") { return "birthday.cake.fill" }
        if n.contains("hardware") || n.contains("diy") || n.contains("depot") || n.contains("ikea") { return "wrench.and.screwdriver.fill" }
        if n.contains("pet") { return "pawprint.fill" }
        if n.contains("farm") || n.contains("market") || n.contains("veg") || n.contains("fruit") { return "leaf.fill" }
        if n.contains("butcher") || n.contains("meat") { return "fork.knife" }
        if n.contains("wine") || n.contains("off licence") || n.contains("liquor") { return "wineglass.fill" }
        return "basket.fill"
    }

    static let unsortedColor = Color.secondary

    /// The screens' ground: a green-grey instead of the system grouped grey (#F2F5F3 / #101513).
    static let ground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.063, green: 0.082, blue: 0.075, alpha: 1) : UIColor(red: 0.949, green: 0.961, blue: 0.953, alpha: 1)
    })
}

/// Soft brand glow that sits behind a large navigation title and fades into the ground
/// (design canvas: 26 % → 6 % at 60 % → 0 over the top 320 pt; a shop's own colour at 42 %).
struct HeroGlow: View {
    var tint: Color = Brand.primary
    var strength: Double = 0.26
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: tint.opacity(scheme == .dark ? strength * 1.4 : strength), location: 0),
                .init(color: tint.opacity(strength * 0.23), location: 0.6),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 340)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The floating call to action: Leaf gradient, a light catch on the top edge so it reads convex,
/// a deep-green soft shadow, and a press squash (design canvas: 135° #1FB57A→#0E6B47,
/// shadow 0 10 24 at 38 %, inset top highlight at 35 %).
struct ConvexButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background {
                Circle().fill(LinearGradient(colors: [Brand.leaf, Brand.primaryDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(RadialGradient(colors: [.white.opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: 26))
                    .frame(width: 46, height: 26)
                    .offset(y: 3)
            }
            .overlay {
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            }
            .clipShape(Circle())
            .shadow(color: Brand.primaryDeep.opacity(0.38), radius: 12, y: 10)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Ground + glow for a whole screen. Use as one `.background { ScreenGround() }`: two stacked
/// `.background` modifiers would put the glow *behind* the opaque ground and hide it.
struct ScreenGround: View {
    var tint: Color = Brand.primary
    var strength: Double = 0.26

    var body: some View {
        ZStack(alignment: .top) {
            Brand.ground
            HeroGlow(tint: tint, strength: strength)
        }
        .ignoresSafeArea()
    }
}

/// Round coloured badge with a symbol: the shop's identity, used in headers, rows and cards.
struct ShopGlyph: View {
    let name: String?
    var size: CGFloat = 32

    var body: some View {
        let color = name.map(Brand.shopColor) ?? Brand.unsortedColor
        Image(systemName: name.map(Brand.shopSymbol) ?? "tray.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .shadow(color: color.opacity(0.35), radius: 4, y: 2)
    }
}

/// Small rounded chip for quantities and counts.
struct Chip: View {
    let text: String
    var tint: Color = Brand.primary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Thin progress capsule (basket / open) under a shop header.
struct ProgressCapsule: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint).frame(width: max(6, geo.size.width * value))
            }
        }
        .frame(height: 4)
        .animation(.snappy, value: value)
    }
}
