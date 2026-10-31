import XCTest
@testable import MomoCore

final class ContentFlavorTests: XCTestCase {
    func testHexColorIsColor() {
        XCTAssertEqual(ContentFlavor.detect("#E8542B"), .color)
        XCTAssertEqual(ContentFlavor.detect("  #abc\n"), .color)
    }

    func testHttpUrlIsLink() {
        XCTAssertEqual(ContentFlavor.detect("https://github.com/simantaturja/momo"), .link)
        XCTAssertEqual(ContentFlavor.detect("HTTP://EXAMPLE.COM"), .link)
        XCTAssertEqual(ContentFlavor.detect(" https://x.com/a?b=1\n"), .link)
    }

    func testNotALink() {
        XCTAssertEqual(ContentFlavor.detect("https://a b"), .plain)          // whitespace
        XCTAssertEqual(ContentFlavor.detect("https://"), .plain)             // no host
        XCTAssertEqual(ContentFlavor.detect("ftp://x.com"), .plain)          // not http(s)
        XCTAssertEqual(ContentFlavor.detect("see https://x.com"), .plain)    // not just a URL
    }

    func testLinkCheckTakesUntrimmedFullText() {
        XCTAssertTrue(ContentFlavor.isLink("  https://x.com/a \n"))   // surrounding whitespace is fine
        XCTAssertTrue(ContentFlavor.isLink("HTTPS://X.COM"))
        XCTAssertFalse(ContentFlavor.isLink("https://x.com notes"))
        XCTAssertFalse(ContentFlavor.isLink("https://x.com\n\nmore"))
        XCTAssertFalse(ContentFlavor.isLink("http:/x.com"))
    }

    func testBracedTextIsCode() {
        XCTAssertEqual(ContentFlavor.detect("{\"a\": 1}"), .code)
    }

    func testMultiLineCodeByIndentOrLineEnding() {
        XCTAssertEqual(ContentFlavor.detect("if x:\n    return 1"), .code)     // indented later line
        XCTAssertEqual(ContentFlavor.detect("if x\n\treturn"), .code)          // tab indent
        XCTAssertEqual(ContentFlavor.detect("func f() {\nreturn 1\n}"), .code) // line ends with { / }
        XCTAssertEqual(ContentFlavor.detect("a = 1;  \nb = 2"), .code)         // ; before trailing spaces
    }

    func testEverythingElseIsPlain() {
        XCTAssertEqual(ContentFlavor.detect("Hello, world."), .plain)
        XCTAssertEqual(ContentFlavor.detect("SELECT * FROM items;"), .plain)   // one line: never code
        XCTAssertEqual(ContentFlavor.detect("first line\nsecond line"), .plain)
        XCTAssertEqual(ContentFlavor.detect("#12345"), .plain)
    }

    func testHexColorComponents() {
        let c = HexColor("#E8542B")
        XCTAssertEqual(c?.red, 232)
        XCTAssertEqual(c?.green, 84)
        XCTAssertEqual(c?.blue, 43)
        XCTAssertEqual(c?.alpha, 255)
        XCTAssertEqual(c?.hex, "#E8542B")
        XCTAssertEqual(c?.hsl.hue, 13)
        XCTAssertEqual(c?.hsl.saturation, 80)
        XCTAssertEqual(c?.hsl.lightness, 54)
    }

    func testHexColorShortFormLowercaseAndAlpha() {
        XCTAssertEqual(HexColor("#abc")?.hex, "#AABBCC")
        XCTAssertEqual(HexColor("#abc")?.red, 170)
        XCTAssertEqual(HexColor(" #e8542b \n")?.hex, "#E8542B")
        let translucent = HexColor("#11223344")
        XCTAssertEqual(translucent?.alpha, 68)
        XCTAssertEqual(translucent?.hex, "#11223344")
        XCTAssertEqual(HexColor("#112233FF")?.hex, "#112233")   // opaque alpha is dropped
    }

    func testHueForEachChannelBeingTheMax() {
        // Pure channels: lightness (1 + 0) / 2 = 50%, saturation 1 / (1 - |2·0.5 - 1|) = 100%.
        // #FF0080: (0 - 128/255) + 6 = 5.498 -> 329.9° -> 330. #FF0001: 5.996 -> 359.8° -> 360 -> 0.
        for (hex, hue) in [("#00FF00", 120), ("#0000FF", 240), ("#FF0080", 330), ("#FF0001", 0)] {
            let hsl = HexColor(hex)?.hsl
            XCTAssertEqual(hsl?.hue, hue, hex)
            XCTAssertEqual(hsl?.saturation, 100, hex)
            XCTAssertEqual(hsl?.lightness, 50, hex)
        }
    }

    func testGrayHasNoHueOrSaturation() {
        let gray = HexColor("#808080")
        XCTAssertEqual(gray?.hsl.hue, 0)
        XCTAssertEqual(gray?.hsl.saturation, 0)
        XCTAssertEqual(gray?.hsl.lightness, 50)
    }

    func testRejectsMalformedHex() {
        XCTAssertNil(HexColor("#12345"))      // wrong length
        XCTAssertNil(HexColor("#1234"))       // #RGBA isn't supported
        XCTAssertNil(HexColor("#GGGGGG"))     // not hex digits
        XCTAssertNil(HexColor("E8542B"))      // missing #
        XCTAssertNil(HexColor("#+12345"))     // a sign isn't a digit
        XCTAssertNil(HexColor("#E8542B is orange"))
    }
}
