import Foundation
import Testing
@testable import EDLKit

func fixture(_ name: String) throws -> EDLDocument {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "edl", subdirectory: "Fixtures"))
    return EDLParser.parse(data: try Data(contentsOf: url))
}

struct ParserTests {
    @Test func resolveCutList() throws {
        let doc = try fixture("resolve_cuts")
        #expect(doc.title == "Timeline 1")
        #expect(doc.frameCodeMode == "NON-DROP FRAME")
        #expect(doc.frameRate == FrameRate(timebase: 24, dropFrame: false))
        #expect(doc.events.map(\.number) == [1, 2, 3])
        #expect(doc.unparsed.isEmpty)

        let first = doc.events[0].lines[0]
        #expect(first.reel == "A001_C002_0915AB")
        #expect(first.track == "V")
        #expect(first.transition == .cut)
        #expect(first.clipName == "A001_C002_0915AB.mov")
        #expect(first.sourceFile == "/Volumes/Media/A001_C002_0915AB.mov")
        #expect(first.recordIn.description == "01:00:00:00")

        #expect(doc.events[1].lines[0].lanes == [.audio(1), .audio(2)])
        #expect(doc.events[2].lines[0].reel == "B002_C011_0916CD_LONG_ROLL_NAME_EXCEEDING_EIGHT_CHARACTERS")
        #expect(doc.lanes == [.video(1), .audio(1), .audio(2)])

        #expect(doc.markers.count == 1)
        #expect(doc.markers[0].color == "RED")
        #expect(doc.markers[0].note == "Check focus")

        let extent = try #require(doc.recordExtent)
        #expect(doc.string(extent.lowerBound) == "01:00:00:00")
        #expect(doc.string(extent.upperBound) == "01:00:10:23")
    }

    @Test func avidTransitions() throws {
        let doc = try fixture("avid_transitions")
        #expect(doc.frameRate == FrameRate(timebase: 30, dropFrame: true))
        #expect(doc.events.map(\.number) == [1, 2, 3, 4, 5])
        #expect(doc.unparsed.isEmpty)

        let dissolve = doc.events[1]
        #expect(dissolve.lines.count == 2)
        #expect(dissolve.lines[0].clipName == "Shot A")
        #expect(dissolve.lines[1].clipName == "Shot B")
        #expect(dissolve.lines[1].transition == .dissolve(frames: 30))
        #expect(dissolve.lines[1].speed == 59.9)
        #expect(dissolve.lines[0].speed == nil)
        #expect(doc.recordRange(of: dissolve.lines[0]).isEmpty)

        #expect(doc.events[2].lines[0].transition == .wipe(code: "W001", frames: 15))
        #expect(doc.events[3].lines[0].transition == .key(kind: "B", frames: nil))
        #expect(doc.events[4].lines[0].transition == .key(kind: "O", frames: 10))
        #expect(doc.events[4].lines[0].transition.code == "K O 010")
        #expect(doc.events[0].lines[0].recordIn.dropFrame)
    }

    @Test func sixDigitEventsAndLongRollNames() throws {
        let doc = try fixture("six_digit_long_reels")
        #expect(doc.unparsed.isEmpty)
        #expect(doc.frameRate == FrameRate(timebase: 25, dropFrame: false))
        #expect(doc.events.map(\.number) == [1, 2, 3, 10_000, 123_456, 999_999])
        #expect(doc.events.map(\.label) == ["000001", "000002", "000003", "010000", "123456", "999999"])
        #expect(doc.events.flatMap(\.lines).map(\.reel.count) == [8, 64, 64, 100, 200, 2, 200])

        let dissolve = doc.events[2]
        #expect(dissolve.lines.count == 2)
        #expect(dissolve.lines[1].transition == .dissolve(frames: 25))
        #expect(dissolve.lines[1].clipName == "one-hundred.mov")
        #expect(dissolve.lines[1].speed == 50)
        #expect(dissolve.lines[0].speed == nil)

        #expect(doc.events[3].lines[0].lanes == [.audio(2)])
        #expect(doc.events[4].lines[0].lanes == [.video(1), .audio(1), .audio(2)])
        #expect(doc.markers.map(\.note) == ["Long roll marker"])
        #expect(doc.string(try #require(doc.recordExtent).upperBound) == "01:00:20:00")
    }

    @Test(arguments: ["1", "12", "123", "1234", "12345", "123456", "1234567", "0000000042"])
    func eventNumbersOfAnyLength(_ label: String) throws {
        let doc = EDLParser.parse("\(label)  R  V  C  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00")
        let event = try #require(doc.events.first)
        #expect(event.label == label)
        #expect(event.number == Int(label))
    }

    @Test func oversizedEventNumberIsUnparsedNotFatal() {
        let doc = EDLParser.parse("99999999999999999999999  R  V  C  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00")
        #expect(doc.events.isEmpty)
        #expect(doc.unparsed.count == 1)
    }

    @Test(arguments: [4, 8, 9, 32, 129, 1_000])
    func rollNamesOfAnyLength(_ length: Int) throws {
        let reel = String(repeating: "R", count: length - 1) + "9"
        let doc = EDLParser.parse("000001  \(reel)  V  D 030  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00\nM2   \(reel)   012.5   00:00:00:00")
        let line = try #require(doc.events.first?.lines.first)
        #expect(line.reel == reel)
        #expect(line.transition == .dissolve(frames: 30))
        #expect(line.speed == 12.5)
    }

    @Test(arguments: ["C", "V", "D", "K", "B", "AA", "W001", "030", "BL", "AX"])
    func rollNamesThatLookLikeOtherFields(_ reel: String) throws {
        let doc = EDLParser.parse("000001  \(reel)  V  C  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00")
        let line = try #require(doc.events.first?.lines.first)
        #expect(line.reel == reel)
        #expect(line.track == "V")
        #expect(line.transition == .cut)
    }

    @Test(arguments: [
        ("C", Transition.cut, 1), ("D 030", .dissolve(frames: 30), 2), ("W012 045", .wipe(code: "W012", frames: 45), 2),
        ("K", .key(kind: nil, frames: nil), 1), ("K B", .key(kind: "B", frames: nil), 2),
        ("K 010", .key(kind: nil, frames: 10), 2), ("K O 020", .key(kind: "O", frames: 20), 3), ("D", .dissolve(frames: 0), 1),
    ])
    func transitions(text: String, expected: Transition, consumed: Int) throws {
        let tokens = ("REEL V " + text).split(separator: " ")
        let (transition, count) = try #require(EDLParser.parseTransition(tokens))
        #expect(transition == expected)
        #expect(count == consumed)
    }

    @Test func reelNamesMayContainSpaces() throws {
        let doc = EDLParser.parse("001  My Camera Roll 7  V  C  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00")
        #expect(doc.events.first?.lines.first?.reel == "My Camera Roll 7")
    }

    @Test func handlesLineEndingsAndWhitespace() {
        let body = ["TITLE: X", "001\tR1\tV\tC\t00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00", "* FROM CLIP NAME: a"]
        for separator in ["\n", "\r\n", "\r"] {
            let doc = EDLParser.parse(body.joined(separator: separator) + separator)
            #expect(doc.title == "X")
            #expect(doc.events.count == 1)
            #expect(doc.events.first?.lines.first?.clipName == "a")
            #expect(doc.unparsed.isEmpty)
        }
        let lineNumbers = EDLParser.parse(["x", "y", "z"].joined(separator: "\r\n")).unparsed.map(\.lineNumber)
        #expect(lineNumbers == [1, 2, 3])
    }

    @Test func decodesLatin1AndUTF8WithBOM() {
        let latin1 = Data("TITLE: Caf".utf8) + Data([0xE9])
        #expect(EDLParser.parse(data: latin1).title == "Café")
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("TITLE: Café".utf8)
        #expect(EDLParser.parse(data: bom).title == "Café")
    }

    @Test func collectsUnparsedLinesAndHeaderNotes() {
        let text = """
        * Exported by Something
        TITLE: T
        garbage here
        001  R  V  C  00:00:00:00 00:00:01:00 01:00:00:00
        001  R  V  X  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00
        """
        let doc = EDLParser.parse(text)
        #expect(doc.notes == ["Exported by Something"])
        #expect(doc.events.isEmpty)
        #expect(doc.unparsed.map(\.lineNumber) == [3, 4, 5])
    }

    @Test func attachesOtherCommentsToCurrentLine() {
        let doc = EDLParser.parse("""
        001  R  V  C  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00
        * EFFECT NAME: BLUR
        SPLIT:    AUDIO DELAY=  00:00:00:05
        * FROM CLIP NAME: first
        * FROM CLIP NAME: duplicate
        """)
        let line = doc.events[0].lines[0]
        #expect(line.clipName == "first")
        #expect(line.comments == ["EFFECT NAME: BLUR", "SPLIT:    AUDIO DELAY=  00:00:00:05", "Clip name: duplicate"])
    }

    @Test func frameCodeModeCanChange() {
        let doc = EDLParser.parse("""
        FCM: NON-DROP FRAME
        001  R  V  C  00:00:00:00 00:00:01:00 01:00:00:00 01:00:01:00
        FCM: DROP FRAME
        002  R  V  C  00:00:00:00 00:00:01:00 01:00:01:00 01:00:02:00
        """)
        #expect(doc.frameCodeMode == "NON-DROP FRAME")
        #expect(doc.events[0].lines[0].recordIn.dropFrame == false)
        #expect(doc.events[1].lines[0].recordIn.dropFrame)
        #expect(doc.frameRate.dropFrame)
    }

    @Test func recordCrossingMidnight() throws {
        let doc = EDLParser.parse("""
        001  R  V  C  00:00:00:00 00:00:04:00 23:59:58:00 00:00:02:00
        002  R  V  C  00:00:04:00 00:00:05:00 00:00:02:00 00:00:03:00
        """)
        #expect(doc.recordRange(of: doc.events[0].lines[0]).count == 96)
        let extent = try #require(doc.recordExtent)
        #expect(extent.count == 120)
    }

    @Test func markerWithoutColour() {
        let doc = EDLParser.parse("* LOC: 01:00:00:00 Just a note")
        #expect(doc.markers.first?.color == nil)
        #expect(doc.markers.first?.note == "Just a note")
    }

    @Test(arguments: [
        ("V", [Lane.video(1)]), ("A", [.audio(1)]), ("A2", [.audio(2)]), ("AA", [.audio(1), .audio(2)]),
        ("B", [.video(1), .audio(1)]), ("A/V", [.video(1), .audio(1)]), ("AA/V", [.video(1), .audio(1), .audio(2)]),
        ("A2/V", [.video(1), .audio(2)]), ("V2", [.video(2)]), ("NONE", []), ("Q", []),
    ])
    func trackLanes(track: String, expected: [Lane]) {
        #expect(Lane.lanes(forTrack: track) == expected)
    }

    @Test func laneOrderingPutsHigherVideoFirst() {
        #expect([Lane.audio(2), .video(1), .audio(1), .video(2)].sorted() == [.video(2), .video(1), .audio(1), .audio(2)])
    }
}
