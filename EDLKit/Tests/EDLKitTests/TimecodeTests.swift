import Testing
@testable import EDLKit

struct TimecodeTests {
    @Test(arguments: ["01:02:03:04", "01:02:03;04", "01.02.03.04", "01:02:03,04"])
    func parsesSeparators(_ text: String) throws {
        let tc = try #require(Timecode(text))
        #expect([tc.hours, tc.minutes, tc.seconds, tc.frames] == [1, 2, 3, 4])
        #expect(tc.dropFrame == (text.contains(";") || text.contains(",")))
    }

    @Test(arguments: ["", "01:02:03", "01:02:03:04:05", "01:60:00:00", "01:00:60:00", "aa:00:00:00", "01:00:00:0x", "01::00:00"])
    func rejectsInvalid(_ text: String) {
        #expect(Timecode(text) == nil)
    }

    @Test func defaultDropFrameApplies() throws {
        #expect(try #require(Timecode("01:00:00:00", defaultDropFrame: true)).dropFrame)
        #expect(try #require(Timecode("01:00:00:00", defaultDropFrame: false)).dropFrame == false)
    }

    @Test func nonDropFrameCounts() throws {
        #expect(try #require(Timecode("01:00:00:00")).frameCount(timebase: 24) == 86_400)
        #expect(try #require(Timecode("00:00:01:12")).frameCount(timebase: 25) == 37)
        #expect(try #require(Timecode("10:00:00:00")).frameCount(timebase: 30) == 1_080_000)
    }

    @Test func dropFrameCounts() throws {
        #expect(try #require(Timecode("00:01:00;02")).frameCount(timebase: 30) == 1_800)
        #expect(try #require(Timecode("00:10:00;00")).frameCount(timebase: 30) == 17_982)
        #expect(try #require(Timecode("01:00:00;00")).frameCount(timebase: 30) == 107_892)
        #expect(try #require(Timecode("00:01:00;04")).frameCount(timebase: 60) == 3_600)
    }

    @Test(arguments: [(30, true), (60, true), (24, false), (25, false), (30, false)])
    func roundTrips(timebase: Int, dropFrame: Bool) throws {
        for count in stride(from: 0, to: timebase * 60 * 60 * 25, by: 997) {
            let text = Timecode.string(fromFrameCount: count, timebase: timebase, dropFrame: dropFrame)
            let tc = try #require(Timecode(text))
            #expect(tc.dropFrame == dropFrame)
            #expect(tc.frameCount(timebase: timebase) == count, "\(text)")
        }
    }

    @Test func dropFrameSkipsFrameNumbers() {
        #expect(Timecode.string(fromFrameCount: 1_799, timebase: 30, dropFrame: true) == "00:00:59;29")
        #expect(Timecode.string(fromFrameCount: 1_800, timebase: 30, dropFrame: true) == "00:01:00;02")
        #expect(Timecode.string(fromFrameCount: 17_982, timebase: 30, dropFrame: true) == "00:10:00;00")
    }

    @Test func formatsNegativeAndLongDurations() {
        #expect(Timecode.string(fromFrameCount: -25, timebase: 25, dropFrame: false) == "-00:00:01:00")
        #expect(Timecode.string(fromFrameCount: 24 * 3600 * 30, timebase: 24, dropFrame: false) == "30:00:00:00")
    }

    @Test(arguments: [
        (0, false, 24), (23, false, 24), (24, false, 25), (29, false, 30), (49, false, 50), (59, false, 60), (99, false, 60),
        (0, true, 30), (29, true, 30), (59, true, 60),
    ])
    func infersFrameRate(maxFrame: Int, dropFrame: Bool, expected: Int) {
        let rate = FrameRate.infer(maxFrameValue: maxFrame, dropFrame: dropFrame)
        #expect(rate.timebase == expected)
        #expect(rate.dropFrame == dropFrame)
    }

    @Test func frameRateNames() {
        #expect(FrameRate(timebase: 30, dropFrame: true).displayName == "29.97 DF")
        #expect(FrameRate(timebase: 60, dropFrame: true).displayName == "59.94 DF")
        #expect(FrameRate(timebase: 25, dropFrame: true).dropFrame == false)
        #expect(FrameRate(timebase: 25, dropFrame: false).displayName == "25")
    }
}
