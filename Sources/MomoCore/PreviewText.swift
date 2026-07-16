public enum PreviewText {
    /// Collapse every run of whitespace (spaces, tabs, newlines) to a single space and
    /// trim the ends, so a multi-line clipboard snippet renders as one tidy row without
    /// overflowing its fixed height. Used at display time; the stored preview is untouched.
    public static func singleLine(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
