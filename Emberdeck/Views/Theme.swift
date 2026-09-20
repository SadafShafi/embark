//
//  Theme.swift
//  Emberdeck
//
//  The palette, defined once as dynamic colours so light and dark both resolve
//  without a second set of call sites.
//

import SwiftUI
import UIKit

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let edPaper     = Color.dynamic(light: 0xF6F4F8, dark: 0x110E18)
    static let edSurface   = Color.dynamic(light: 0xFFFFFF, dark: 0x1A1624)
    static let edSurface2  = Color.dynamic(light: 0xEDE9F2, dark: 0x231E30)
    static let edSurface3  = Color.dynamic(light: 0xE3DDEC, dark: 0x2E2740)
    static let edLine      = Color.dynamic(light: 0xDFD8E9, dark: 0x332B45)
    static let edInk       = Color.dynamic(light: 0x1A1526, dark: 0xF1EDF7)
    static let edInk2      = Color.dynamic(light: 0x463D57, dark: 0xCEC6DC)
    static let edMuted     = Color.dynamic(light: 0x756C85, dark: 0x958CA6)

    static let edEmber     = Color.dynamic(light: 0xEE5A24, dark: 0xFF7A4D)
    static let edEmberSoft = Color.dynamic(light: 0xFDEBE4, dark: 0x3A2018)
    static let edGold      = Color.dynamic(light: 0xC98A17, dark: 0xF0BC5C)
    static let edGoldSoft  = Color.dynamic(light: 0xFBF0DC, dark: 0x372B14)
    static let edMint      = Color.dynamic(light: 0x0F8A72, dark: 0x3ECBA4)
    static let edMintSoft  = Color.dynamic(light: 0xE1F3EE, dark: 0x0F2F28)
    static let edViolet    = Color.dynamic(light: 0x6B4BC4, dark: 0xA98BF5)
    static let edVioletSoft = Color.dynamic(light: 0xEDE7FB, dark: 0x241B3D)
    static let edDanger    = Color.dynamic(light: 0xC93A52, dark: 0xF4697F)
    static let edDangerSoft = Color.dynamic(light: 0xFBE6EA, dark: 0x3A1720)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Grade {
    var tint: Color {
        switch self {
        case .again: return .edDanger
        case .hard: return .edGold
        case .good: return .edMint
        case .easy: return .edViolet
        }
    }
}

// MARK: - Type

extension Font {
    /// Big tabular figures for counters and intervals.
    static func edNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
    }
    static func edDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
    static func edMono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}

// MARK: - Shared building blocks

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .kerning(1.4)
            .foregroundStyle(Color.edMuted)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.edSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.edLine, lineWidth: 1)
            )
    }
}

struct CountPill: View {
    let value: Int
    let tint: Color
    let soft: Color

    var body: some View {
        Text("\(value)")
            .font(.edMono(11.5))
            .foregroundStyle(value > 0 ? tint : Color.edMuted)
            .frame(minWidth: 26)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(value > 0 ? soft : Color.edSurface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The chunky pressable button the whole app uses, with the shadow that sinks on press.
struct ChunkyButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color = .white
    var depth: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .offset(y: configuration.isPressed ? depth : 0)
            .shadow(color: background.opacity(0.55),
                    radius: 0, x: 0, y: configuration.isPressed ? 0 : depth)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = .edInk2
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.edLine, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
