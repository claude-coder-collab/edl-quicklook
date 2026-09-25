import Foundation
import Testing
@testable import EDLKit

struct RendererTests {
    func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    @Test func rendersSummaryTimelineAndTable() throws {
        let html = HTMLRenderer().render(try fixture("resolve_cuts"))
        #expect(html.contains("<h1>Timeline 1</h1>"))
        #expect(html.contains("24 (assumed)"))
        #expect(html.contains("<dd>V A1 A2</dd>"))
        #expect(occurrences(of: "<rect class=\"seg\"", in: html) == 4)
        #expect(occurrences(of: "<tbody class=\"event\">", in: html) == 3)
        #expect(html.contains("B002_C011_0916CD_LONG_ROLL_NAME_EXCEEDING_EIGHT_CHARACTERS"))
        #expect(html.contains("Source file: /Volumes/Media/A001_C002_0915AB.mov"))
        #expect(html.contains("<h2>Markers</h2>"))
        #expect(html.contains("class=\"markers\""))
        #expect(!html.contains("Unparsed lines"))
    }

    @Test func escapesUserText() throws {
        let html = HTMLRenderer().render(try fixture("resolve_cuts"))
        #expect(html.contains("Music &amp; Effects &lt;final&gt;.wav"))
        #expect(!html.contains("<final>"))
    }

    @Test func rendersTransitionsAndSpeed() throws {
        let html = HTMLRenderer().render(try fixture("avid_transitions"))
        #expect(html.contains("29.97 DF (assumed)"))
        #expect(html.contains("<rect class=\"trans\""))
        #expect(html.contains("59.9 fps (200%)"))
        #expect(html.contains("K O 010"))
        #expect(occurrences(of: "<rect class=\"seg\"", in: html) == 5)
    }

    @Test func fallsBackToFileNameAndShowsUnparsed() {
        let html = HTMLRenderer().render(EDLParser.parse("nonsense <b>"), fileName: "cut.edl")
        #expect(html.contains("<h1>cut.edl</h1>"))
        #expect(html.contains("Unparsed lines"))
        #expect(html.contains("nonsense &lt;b&gt;"))
        #expect(html.contains("No events found."))
        #expect(!html.contains("class=\"timeline\""))
    }

    @Test(arguments: [(0.0, "0.0000%"), (12.5, "12.5000%"), (100.0, "100.0000%"), (0.00004, "0.0000%"), (3.14159, "3.1416%"), (-1.5, "-1.5000%")])
    func formatsPercentages(value: Double, expected: String) {
        #expect(HTMLRenderer.percentString(value) == expected)
    }

    @Test func reelColoursAreStable() {
        #expect(HTMLRenderer.colour(for: "A001") == HTMLRenderer.colour(for: "A001"))
        #expect(HTMLRenderer.colour(for: "A001") != HTMLRenderer.colour(for: "A002"))
    }

    @Test func largeListRendersQuickly() {
        let lines = (1...5_000).map { i -> String in
            let rec = Timecode.string(fromFrameCount: 86_400 + i * 48, timebase: 24, dropFrame: false)
            let out = Timecode.string(fromFrameCount: 86_400 + (i + 1) * 48, timebase: 24, dropFrame: false)
            return "\(i)  REEL\(i % 50)  V  C  00:00:00:00 00:00:02:00 \(rec) \(out)\n* FROM CLIP NAME: clip \(i)"
        }
        let start = Date()
        let doc = EDLParser.parse(lines.joined(separator: "\n"))
        let html = HTMLRenderer().render(doc)
        let elapsed = Date().timeIntervalSince(start)
        #expect(doc.events.count == 5_000)
        #expect(!html.isEmpty)
        #expect(elapsed < 2.0)
    }
}
