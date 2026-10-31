import Foundation

public enum PreviewText {
    /// Collapse every run of whitespace (spaces, tabs, newlines) to a single space and
    /// trim the ends, so a multi-line clipboard snippet renders as one tidy row without
    /// overflowing its fixed height. Used at display time; the stored preview is untouched.
    public static func singleLine(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The first `limit` Characters of `text`, with "…" appended only if it was cut. Walks at
    /// most `limit` Characters, so a huge clip costs no more than a short one.
    public static func excerpt(_ text: String, limit: Int = 2_000) -> String {
        guard let end = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex),
              end < text.endIndex else { return text }
        return String(text[..<end]) + "…"
    }

    /// UTF-16 ranges (what attributed strings use) covering the given Character offsets of
    /// `text`, with consecutive offsets merged into one run. Offsets outside `text` are ignored.
    public static func highlightRanges(in text: String, positions: [Int]) -> [NSRange] {
        let wanted = Set(positions)
        guard let last = wanted.max() else { return [] }
        var ranges: [NSRange] = []
        var utf16Offset = 0
        for (i, ch) in text.enumerated() {
            if i > last { break }
            let width = ch.utf16.count
            if wanted.contains(i) {
                if let previous = ranges.last, NSMaxRange(previous) == utf16Offset {
                    ranges[ranges.count - 1].length += width   // continues the run before it
                } else {
                    ranges.append(NSRange(location: utf16Offset, length: width))
                }
            }
            utf16Offset += width
        }
        return ranges
    }

    /// Number of lines: "\n" count plus one ("\r\n" has a single "\n"), except that a trailing
    /// line break ends the last line rather than starting an empty one. "" has 0 lines.
    /// Scans UTF-8 bytes without building substrings.
    public static func lineCount(_ text: String) -> Int {
        guard let lastByte = text.utf8.last else { return 0 }
        let breaks = text.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        return lastByte == 0x0A ? breaks : breaks + 1
    }
}
