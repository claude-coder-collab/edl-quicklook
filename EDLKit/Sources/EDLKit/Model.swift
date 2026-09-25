public enum Transition: Hashable, Sendable {
    case cut
    case dissolve(frames: Int)
    case wipe(code: String, frames: Int)
    case key(kind: String?, frames: Int?)

    public var code: String {
        switch self {
        case .cut: "C"
        case .dissolve(let frames): "D \(Self.pad(frames))"
        case .wipe(let code, let frames): "\(code) \(Self.pad(frames))"
        case .key(let kind, let frames):
            ["K", kind, frames.map(Self.pad)].compactMap { $0 }.joined(separator: " ")
        }
    }

    public var durationFrames: Int {
        switch self {
        case .cut: 0
        case .dissolve(let frames), .wipe(_, let frames): frames
        case .key(_, let frames): frames ?? 0
        }
    }

    private static func pad(_ value: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, 3 - text.count)) + text
    }
}

public enum Lane: Hashable, Comparable, Sendable, CustomStringConvertible {
    case video(Int)
    case audio(Int)

    public var description: String {
        switch self {
        case .video(1): "V"
        case .video(let n): "V\(n)"
        case .audio(let n): "A\(n)"
        }
    }

    public static func < (lhs: Lane, rhs: Lane) -> Bool {
        switch (lhs, rhs) {
        case (.video(let a), .video(let b)): a > b
        case (.audio(let a), .audio(let b)): a < b
        case (.video, .audio): true
        case (.audio, .video): false
        }
    }

    public static func lanes(forTrack track: String) -> [Lane] {
        let upper = track.uppercased()
        if upper == "NONE" { return [] }
        let lanes = upper.split(separator: "/").flatMap { part -> [Lane] in
            switch part {
            case "B": return [.video(1), .audio(1)]
            case "AA": return [.audio(1), .audio(2)]
            case "A": return [.audio(1)]
            case "V": return [.video(1)]
            default:
                guard let kind = part.first, let n = Int(part.dropFirst()), n > 0 else { return [] }
                switch kind {
                case "A": return [.audio(n)]
                case "V": return [.video(n)]
                default: return []
                }
            }
        }
        return Array(Set(lanes)).sorted()
    }
}

public struct EventLine: Hashable, Sendable {
    public var lineNumber: Int
    public var reel: String
    public var track: String
    public var transition: Transition
    public var sourceIn: Timecode
    public var sourceOut: Timecode
    public var recordIn: Timecode
    public var recordOut: Timecode
    public var clipName: String?
    public var sourceFile: String?
    public var speed: Double?
    public var comments: [String] = []

    public var lanes: [Lane] { Lane.lanes(forTrack: track) }
}

public struct Event: Hashable, Sendable {
    public var number: Int
    public var label: String
    public var lines: [EventLine]

    public init(number: Int, label: String? = nil, lines: [EventLine]) {
        self.number = number
        self.label = label ?? String(number)
        self.lines = lines
    }
}

public struct Marker: Hashable, Sendable {
    public var lineNumber: Int
    public var timecode: Timecode
    public var color: String?
    public var note: String
}

public struct UnparsedLine: Hashable, Sendable {
    public var lineNumber: Int
    public var text: String
}

public struct EDLDocument: Hashable, Sendable {
    public var title: String?
    public var frameCodeMode: String?
    public var notes: [String] = []
    public var events: [Event] = []
    public var markers: [Marker] = []
    public var unparsed: [UnparsedLine] = []
    public var frameRate = FrameRate(timebase: 24, dropFrame: false)

    public init() {}

    public var lines: [EventLine] { events.flatMap(\.lines) }

    public var lanes: [Lane] { Array(Set(lines.flatMap(\.lanes))).sorted() }

    public func frames(_ timecode: Timecode) -> Int {
        timecode.frameCount(timebase: frameRate.timebase)
    }

    public func string(_ frameCount: Int) -> String {
        Timecode.string(fromFrameCount: frameCount, timebase: frameRate.timebase, dropFrame: frameRate.dropFrame)
    }

    public func durationString(_ frameCount: Int) -> String {
        Timecode.string(fromFrameCount: frameCount, timebase: frameRate.timebase, dropFrame: false)
    }

    public var framesPerDay: Int {
        Timecode(hours: 24, minutes: 0, seconds: 0, frames: 0, dropFrame: frameRate.dropFrame)
            .frameCount(timebase: frameRate.timebase)
    }

    private var anchorFrame: Int? {
        events.first?.lines.first.map { frames($0.recordIn) }
    }

    public func recordPosition(_ timecode: Timecode) -> Int {
        let value = frames(timecode)
        guard let anchor = anchorFrame, value < anchor - framesPerDay / 2 else { return value }
        return value + framesPerDay
    }

    public func recordRange(of line: EventLine) -> Range<Int> {
        let start = recordPosition(line.recordIn)
        var end = recordPosition(line.recordOut)
        if end < start { end += framesPerDay }
        return start..<end
    }

    public var recordExtent: Range<Int>? {
        let ranges = lines.map(recordRange(of:)).filter { !$0.isEmpty }
        guard let lower = ranges.map(\.lowerBound).min(), let upper = ranges.map(\.upperBound).max() else { return nil }
        return lower..<upper
    }
}
