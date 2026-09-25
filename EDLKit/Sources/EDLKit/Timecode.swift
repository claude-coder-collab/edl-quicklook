public struct Timecode: Hashable, Sendable, CustomStringConvertible {
    public let hours: Int
    public let minutes: Int
    public let seconds: Int
    public let frames: Int
    public let dropFrame: Bool

    public init(hours: Int, minutes: Int, seconds: Int, frames: Int, dropFrame: Bool = false) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.dropFrame = dropFrame
    }

    public init?<S: StringProtocol>(_ text: S, defaultDropFrame: Bool = false) {
        var fields = [0, 0, 0, 0]
        var index = 0
        var digits = 0
        var explicitDrop = false
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                guard digits < 9 else { return nil }
                fields[index] = fields[index] * 10 + Int(byte - UInt8(ascii: "0"))
                digits += 1
            case UInt8(ascii: ":"), UInt8(ascii: "."), UInt8(ascii: ";"), UInt8(ascii: ","):
                guard digits > 0, index < 3 else { return nil }
                if byte == UInt8(ascii: ";") || byte == UInt8(ascii: ",") { explicitDrop = true }
                index += 1
                digits = 0
            default:
                return nil
            }
        }
        guard index == 3, digits > 0, fields[1] < 60, fields[2] < 60 else { return nil }
        self.init(hours: fields[0], minutes: fields[1], seconds: fields[2], frames: fields[3], dropFrame: explicitDrop || defaultDropFrame)
    }

    public func frameCount(timebase: Int) -> Int {
        let nominal = ((hours * 60 + minutes) * 60 + seconds) * timebase + frames
        guard dropFrame, timebase % 30 == 0 else { return nominal }
        let dropPerMinute = timebase / 15
        let totalMinutes = hours * 60 + minutes
        return nominal - dropPerMinute * (totalMinutes - totalMinutes / 10)
    }

    public static func string(fromFrameCount count: Int, timebase: Int, dropFrame: Bool) -> String {
        guard count >= 0 else {
            return "-" + string(fromFrameCount: -count, timebase: timebase, dropFrame: dropFrame)
        }
        let useDrop = dropFrame && timebase % 30 == 0
        var adjusted = count
        if useDrop {
            let drop = timebase / 15
            let framesPerMinute = timebase * 60 - drop
            let framesPerTenMinutes = framesPerMinute * 10 + drop
            let tens = count / framesPerTenMinutes
            let remainder = count % framesPerTenMinutes
            adjusted += 9 * drop * tens
            if remainder > drop {
                adjusted += drop * ((remainder - drop) / framesPerMinute)
            }
        }
        let f = adjusted % timebase
        let totalSeconds = adjusted / timebase
        let s = totalSeconds % 60
        let m = (totalSeconds / 60) % 60
        let h = totalSeconds / 3600
        return "\(pad(h)):\(pad(m)):\(pad(s))\(useDrop ? ";" : ":")\(pad(f))"
    }

    public var description: String {
        "\(Self.pad(hours)):\(Self.pad(minutes)):\(Self.pad(seconds))\(dropFrame ? ";" : ":")\(Self.pad(frames))"
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
