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
        #expect(!html.contains("<th>Speed</th>"))
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
        #expect(html.contains("<td title=\"59.9 fps\">200%</td>"))
        #expect(html.contains("<th>Speed</th>"))
        #expect(html.contains("K O 010"))
        #expect(occurrences(of: "<rect class=\"seg\"", in: html) == 5)
    }

    @Test func keepsEventNumbersAsWrittenAndShowsLongRollNames() throws {
        let doc = try fixture("six_digit_long_reels")
        let html = HTMLRenderer().render(doc)
        for label in ["000001", "000003", "010000", "123456", "999999"] {
            #expect(html.contains("<td class=\"num\">\(label)</td>"))
        }
        #expect(occurrences(of: "<td class=\"num\">000003</td>", in: html) == 1)
        let longest = try #require(doc.lines.map(\.reel).max { $0.count < $1.count })
        #expect(longest.count == 200)
        #expect(html.contains("<td class=\"reel\">\(longest)</td>"))
        #expect(html.contains("#999999 \(longest)"))
        #expect(html.contains("<th>Speed</th>"))
        #expect(html.contains("<colgroup><col style=\"width:4.8em\"><col>"))
    }

    @Test func columnWidthsFitTheirContent() {
        #expect(HTMLRenderer.columnWidth(longest: 3, header: "#") == 2.9)
        #expect(HTMLRenderer.columnWidth(longest: 6, header: "#") == 4.8)
        #expect(HTMLRenderer.columnWidth(longest: 11, header: "Duration") == 7.9)
        #expect(HTMLRenderer.columnWidth(longest: 1, header: "Track") == 4.1)
        #expect(HTMLRenderer.em(7.9) == "7.9em")
        #expect(HTMLRenderer.em(7.91) == "8.0em")
    }

    func ruler(_ html: String, zoom: Int) throws -> String {
        try #require(html.components(separatedBy: "<svg class=\"ruler z\(zoom)\"").dropFirst().first?.components(separatedBy: "</svg>").first)
    }

    @Test func rulerTicksStayReadable() throws {
        let html = HTMLRenderer().render(try fixture("six_digit_long_reels"))
        #expect(occurrences(of: "<text", in: try ruler(html, zoom: 1)) <= 7)
    }

    @Test func timelineHasZoomLevelsWithDenserRulers() throws {
        let html = HTMLRenderer().render(try fixture("six_digit_long_reels"))
        #expect(occurrences(of: "<input type=\"radio\" name=\"zoom\"", in: html) == HTMLRenderer.zoomLevels.count)
        #expect(html.contains("<input type=\"radio\" name=\"zoom\" id=\"z1\" checked>"))
        #expect(occurrences(of: " checked>", in: html) == 1)
        for zoom in HTMLRenderer.zoomLevels {
            #expect(html.contains("<label for=\"z\(zoom)\">\(zoom)×</label>"))
            #expect(html.contains("#z\(zoom):checked~.tl .tl-inner{width:\(zoom * 100)%}"))
        }
        let ticks = try HTMLRenderer.zoomLevels.map { occurrences(of: "<text", in: try ruler(html, zoom: $0)) }
        #expect(ticks == ticks.sorted())
        #expect(ticks.last! > ticks.first!)
    }

    @Test func laneLabelsLineUpWithLanes() throws {
        let html = HTMLRenderer().render(try fixture("resolve_cuts"))
        #expect(occurrences(of: "<div class=\"lbl-lane\">", in: html) == occurrences(of: "<svg class=\"lane\"", in: html))
        #expect(occurrences(of: "<div class=\"lbl-markers\">", in: html) == occurrences(of: "<svg class=\"markers\"", in: html))
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
