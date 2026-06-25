import XCTest
@testable import SpinTouch

final class MarkupTests: XCTestCase {

    func testStripsScriptAndEventHandlers() {
        let dirty = "<p onclick=\"steal()\">Hi</p><script>alert(1)</script>"
        let out = Markup.html(from: dirty)
        XCTAssertFalse(out.contains("<script"))
        XCTAssertFalse(out.lowercased().contains("onclick"))
        XCTAssertFalse(out.contains("alert(1)"))
        XCTAssertTrue(out.contains("Hi"))   // text content is preserved
    }

    func testDropsDisallowedTagsButKeepsText() {
        let out = Markup.html(from: "<iframe src=\"http://evil\"></iframe><div>kept</div>")
        XCTAssertFalse(out.contains("<iframe"))
        XCTAssertFalse(out.contains("<div"))
        XCTAssertTrue(out.contains("kept"))
    }

    func testRejectsJavascriptHrefButKeepsHTTPS() {
        let out = Markup.html(from: "<a href=\"javascript:evil()\">x</a> <a href=\"https://ok.example\">ok</a>")
        XCTAssertFalse(out.lowercased().contains("javascript:"))
        XCTAssertTrue(out.contains("https://ok.example"))
    }

    func testKeepsAllowlistedFormatting() {
        let out = Markup.html(from: "<h2>Title</h2><ul><li><strong>bold</strong></li></ul>")
        XCTAssertTrue(out.contains("<h2>"))
        XCTAssertTrue(out.contains("<li>"))
        XCTAssertTrue(out.contains("<strong>"))
    }

    func testConvertsMarkdownFallback() {
        let out = Markup.html(from: "# Heading\n\n- one\n- two")
        XCTAssertTrue(out.contains("<h1>"))
        XCTAssertTrue(out.contains("<li>"))
    }
}
