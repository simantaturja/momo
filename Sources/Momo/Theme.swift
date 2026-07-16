import AppKit

/// Accent + role colors, defined once. `accent` is chili-oil red-orange and is used ONLY on
/// the selection pill, the search focus ring, and the selected row's icon tint. Everything
/// else stays neutral so the panel reads clean. Colors are dynamic (light/dark) so they track
/// the system appearance without any per-render work.
enum Theme {
    /// #E8542B (light) / #FF6B43 (dark).
    static let accent = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.00, green: 0.420, blue: 0.263, alpha: 1)
            : NSColor(srgbRed: 0.910, green: 0.329, blue: 0.169, alpha: 1)
    }

    /// Soft accent fill for the selection pill (~18% alpha).
    static let selectionFill = accent.withAlphaComponent(0.18)

    /// Subtle neutral container behind a kind badge's SF Symbol.
    static let badgeFill = NSColor.quaternaryLabelColor

    /// Neutral (unselected) badge symbol tint.
    static let badgeSymbol = NSColor.secondaryLabelColor

    /// Dimmed right-aligned relative-time label + footer hint text.
    static let dimText = NSColor.tertiaryLabelColor

    /// Fill behind the search capsule.
    static let searchFill = NSColor.quaternaryLabelColor
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
