import SwiftUI
import UIKit

/// Design tokens. Mirrors replica/design/tokens.json (light) and tokens.dark.json (dark).
/// Change values there first, re-run contrast.py, then copy here. Views never use raw hex or sizes.
enum Theme {
    enum Colors {
        static let bg          = Color(light: 0xF2F3F5, dark: 0x000000)
        static let surface     = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
        static let track       = Color(light: 0xE6E8EC, dark: 0x2C2C2E)
        static let border      = Color(light: 0xE3E6EA, dark: 0x38383A)
        static let borderInput = Color(light: 0x7D8590, dark: 0x8E8E93)
        static let text        = Color(light: 0x14171C, dark: 0xF2F2F7)
        static let textMuted   = Color(light: 0x5B6470, dark: 0xA1A1AA)
        static let accent      = Color(light: 0x2F5BEA, dark: 0x7B93FF)
        static let onAccent    = Color(light: 0xFFFFFF, dark: 0x0B1020)
        static let danger      = Color(light: 0xC62F2F, dark: 0xFF6B6B)
        static let success     = Color(light: 0x1F7A4D, dark: 0x4ADE80)
        static let warning     = Color(light: 0x8A5A00, dark: 0xF5C542)
        static let gold        = Color(light: 0xF2C14E, dark: 0xF2C14E)
        static let onGold      = Color(light: 0x3A2A00, dark: 0x2A1F00)
        static let energy      = Color(light: 0x2F5BEA, dark: 0x7B93FF)
        static let protein     = Color(light: 0x1F8A5B, dark: 0x4ADE80)
        static let carbs       = Color(light: 0x2F6FD6, dark: 0x60A5FA)
        static let fat         = Color(light: 0xC2410C, dark: 0xFB923C)
    }

    /// Dynamic Type text styles, so every size scales with the user's setting.
    enum Fonts {
        static let caption  = Font.caption
        static let footnote = Font.footnote
        static let label    = Font.subheadline.weight(.medium)
        static let body     = Font.body
        static let heading  = Font.headline
        static let title    = Font.title3.weight(.semibold)
        static let metric   = Font.title.weight(.bold).monospacedDigit()
        static let display  = Font.largeTitle.weight(.bold)
    }

    enum Space {
        static let xxs: CGFloat = 4, xs: CGFloat = 8, sm: CGFloat = 12, md: CGFloat = 16
        static let lg: CGFloat = 24, xl: CGFloat = 32, xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 6, md: CGFloat = 10, lg: CGFloat = 16
    }

    enum Layout {
        static let tapTarget: CGFloat = 44
        static let barHeight: CGFloat = 8
        static let ringSize: CGFloat = 160
        static let ringLine: CGFloat = 14
    }

    enum Motion {
        static let fast = Animation.easeOut(duration: 0.12)
        static let base = Animation.snappy(duration: 0.2)
    }
}

extension Color {
    /// A colour that follows light/dark mode. Hex as 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension View {
    /// Card surface used for diary groups, summaries and charts.
    func card() -> some View {
        padding(Theme.Space.md)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}
