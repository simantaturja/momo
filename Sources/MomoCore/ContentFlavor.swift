import Foundation

/// What a text clip looks like, so the list can pick a badge and the preview a layout.
/// Detected from the stored preview (≤200 characters), so the cost is bounded.
public enum ContentFlavor: Equatable, Sendable {
    case plain, link, color, code

    /// Checked in order on the trimmed text: a hex color; a lone http(s) URL with a host;
    /// code (a `{…}` block, or several lines where a later one is indented or any one ends
    /// with `{`, `}` or `;`); otherwise plain.
    public static func detect(_ text: String) -> ContentFlavor {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if HexColor(t) != nil { return .color }
        if isLink(t) { return .link }
        if isCode(t) { return .code }
        return .plain
    }

    /// Whether `text` (surrounding whitespace allowed) is a lone http(s) URL with a host. Also
    /// run on a clip's full, unbounded text, so only the scheme is lowercased and the scans stop
    /// at the first whitespace and at the first non-whitespace after it.
    static func isLink(_ text: String) -> Bool {
        let t = text.drop(while: { $0.isWhitespace })
        let scheme = t.prefix(8).lowercased()
        guard scheme.hasPrefix("http://") || scheme.hasPrefix("https://") else { return false }
        let end = t.firstIndex(where: { $0.isWhitespace }) ?? t.endIndex
        guard t[end...].allSatisfy({ $0.isWhitespace }),
              let host = URL(string: String(t[..<end]))?.host else { return false }
        return !host.isEmpty
    }

    private static func isCode(_ t: String) -> Bool {
        if t.hasPrefix("{") && t.hasSuffix("}") { return true }
        let lines = t.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        guard lines.count >= 2 else { return false }
        if lines.dropFirst().contains(where: { $0.hasPrefix(" ") || $0.hasPrefix("\t") }) { return true }
        return lines.contains { line in
            guard let last = line.last(where: { !$0.isWhitespace }) else { return false }
            return last == "{" || last == "}" || last == ";"
        }
    }
}

/// A `#RGB`, `#RRGGBB` or `#RRGGBBAA` color (case-insensitive, surrounding whitespace allowed).
public struct HexColor: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int
    /// 255 when the text had no alpha digits.
    public let alpha: Int

    public init?(_ string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        let digits = s.dropFirst()
        // ASCII only: `hexDigitValue` also accepts fullwidth digits.
        let values = digits.compactMap { $0.isASCII ? $0.hexDigitValue : nil }
        guard values.count == digits.count, [3, 6, 8].contains(values.count) else { return nil }
        let full = values.count == 3 ? values.flatMap { [$0, $0] } : values
        let bytes = stride(from: 0, to: full.count, by: 2).map { full[$0] * 16 + full[$0 + 1] }
        red = bytes[0]
        green = bytes[1]
        blue = bytes[2]
        alpha = bytes.count == 4 ? bytes[3] : 255
    }

    /// Uppercase `#RRGGBB`, plus `AA` only when not fully opaque.
    public var hex: String {
        let parts = alpha == 255 ? [red, green, blue] : [red, green, blue, alpha]
        return "#" + parts.map { ($0 < 16 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined()
    }

    /// Hue in degrees, saturation and lightness in percent, each rounded.
    public var hsl: (hue: Int, saturation: Int, lightness: Int) {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        let l = (hi + lo) / 2
        var h = 0.0, s = 0.0
        if d > 0 {
            s = d / (1 - abs(2 * l - 1))
            if hi == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if hi == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
        }
        return (hue: Int(h.rounded()) % 360, saturation: Int((s * 100).rounded()), lightness: Int((l * 100).rounded()))
    }
}
