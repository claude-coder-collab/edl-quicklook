public struct FrameRate: Hashable, Sendable {
    public let timebase: Int
    public let dropFrame: Bool

    public init(timebase: Int, dropFrame: Bool) {
        self.timebase = timebase
        self.dropFrame = dropFrame && timebase % 30 == 0
    }

    public var framesPerSecond: Double {
        dropFrame ? Double(timebase) * 1000 / 1001 : Double(timebase)
    }

    public var displayName: String {
        switch (timebase, dropFrame) {
        case (30, true): "29.97 DF"
        case (60, true): "59.94 DF"
        default: "\(timebase)"
        }
    }

    public static let candidateTimebases = [24, 25, 30, 48, 50, 60]

    public static func infer(maxFrameValue: Int, dropFrame: Bool) -> FrameRate {
        if dropFrame {
            return FrameRate(timebase: maxFrameValue >= 30 ? 60 : 30, dropFrame: true)
        }
        let timebase = candidateTimebases.first { maxFrameValue < $0 } ?? candidateTimebases[candidateTimebases.count - 1]
        return FrameRate(timebase: timebase, dropFrame: false)
    }
}
