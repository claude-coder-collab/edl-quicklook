import Foundation

public enum EDLParser {
    public static func parse(data: Data) -> EDLDocument {
        parse(decode(data))
    }

    public static func decode(_ data: Data) -> String {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        return String(data: bytes, encoding: .utf8)
            ?? String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }

    public static func parse(_ text: String) -> EDLDocument {
        var state = ParserState()
        for (index, rawLine) in splitLines(text).enumerated() {
            state.consume(rawLine, lineNumber: index + 1)
        }
        return state.finish()
    }

    static func splitLines(_ text: String) -> [Substring] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0 }
    }

    static func parseEventLine(_ line: Substring, lineNumber: Int, dropFrame: Bool) -> (number: Int, line: EventLine)? {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 8,
              tokens[0].allSatisfy(\.isASCIIDigit), let number = Int(tokens[0])
        else { return nil }
        let timecodes = tokens.suffix(4).compactMap { Timecode($0, defaultDropFrame: dropFrame) }
        guard timecodes.count == 4 else { return nil }
        let middle = Array(tokens[1..<(tokens.count - 4)])
        guard let (transition, consumed) = parseTransition(middle), middle.count - consumed >= 2 else { return nil }
        let remaining = middle.dropLast(consumed)
        let track = String(remaining[remaining.count - 1])
        let reel = remaining.dropLast().joined(separator: " ")
        return (number, EventLine(
            lineNumber: lineNumber,
            reel: reel,
            track: track,
            transition: transition,
            sourceIn: timecodes[0],
            sourceOut: timecodes[1],
            recordIn: timecodes[2],
            recordOut: timecodes[3]
        ))
    }

    static func parseTransition(_ tokens: [Substring]) -> (Transition, Int)? {
        let upper = tokens.map { $0.uppercased() }
        func token(_ offsetFromEnd: Int) -> String? {
            upper.count >= offsetFromEnd ? upper[upper.count - offsetFromEnd] : nil
        }
        func isWipe(_ text: String?) -> Bool {
            guard let text, text.first == "W" else { return false }
            return text.dropFirst().allSatisfy(\.isASCIIDigit) && text.count > 1
        }
        func isKeyKind(_ text: String?) -> Bool { text == "B" || text == "O" }

        guard let last = token(1) else { return nil }
        let duration = Int(last)

        if let duration {
            switch token(2) {
            case "D": return (.dissolve(frames: duration), 2)
            case let code? where isWipe(code): return (.wipe(code: code, frames: duration), 2)
            case "K": return (.key(kind: nil, frames: duration), 2)
            case let kind? where isKeyKind(kind) && token(3) == "K": return (.key(kind: kind, frames: duration), 3)
            default: return nil
            }
        }
        switch last {
        case "C": return (.cut, 1)
        case "D": return (.dissolve(frames: 0), 1)
        case "K": return (.key(kind: nil, frames: nil), 1)
        case let code where isWipe(code): return (.wipe(code: code, frames: 0), 1)
        case let kind where isKeyKind(kind) && token(2) == "K": return (.key(kind: kind, frames: nil), 2)
        default: return nil
        }
    }
}

private struct ParserState {
    var document = EDLDocument()
    var dropFrame = false
    var clipNameTarget: Int?

    mutating func consume(_ rawLine: Substring, lineNumber: Int) {
        let line = rawLine.trimmed
        guard !line.isEmpty else { return }
        let upper = line.prefix(24).uppercased()

        if upper.hasPrefix("TITLE:") {
            if document.title == nil { document.title = value(after: "TITLE:", in: line) }
        } else if upper.hasPrefix("FCM:") {
            let mode = value(after: "FCM:", in: line)
            if document.frameCodeMode == nil { document.frameCodeMode = mode }
            dropFrame = !mode.uppercased().contains("NON") && mode.uppercased().contains("DROP")
        } else if line.hasPrefix("*") {
            consumeComment(line.dropFirst().trimmed, lineNumber: lineNumber)
        } else if upper.hasPrefix("M2 ") || upper.hasPrefix("M2\t") {
            if !consumeSpeed(line) { unparsed(line, lineNumber) }
        } else if upper.hasPrefix("SPLIT:") || upper.hasPrefix("AUD ") {
            if !appendComment(line) { unparsed(line, lineNumber) }
        } else if let (number, eventLine) = EDLParser.parseEventLine(Substring(line), lineNumber: lineNumber, dropFrame: dropFrame) {
            if let last = document.events.indices.last, document.events[last].number == number {
                document.events[last].lines.append(eventLine)
            } else {
                document.events.append(Event(number: number, lines: [eventLine]))
            }
            clipNameTarget = nil
        } else {
            unparsed(line, lineNumber)
        }
    }

    mutating func consumeComment(_ body: String, lineNumber: Int) {
        let upper = body.prefix(24).uppercased()
        if upper.hasPrefix("FROM CLIP NAME:") {
            setClipName(value(after: "FROM CLIP NAME:", in: body), lineIndex: 0)
        } else if upper.hasPrefix("TO CLIP NAME:") {
            setClipName(value(after: "TO CLIP NAME:", in: body), lineIndex: nil)
        } else if upper.hasPrefix("SOURCE FILE:") {
            let path = value(after: "SOURCE FILE:", in: body)
            guard let e = document.events.indices.last else { return document.notes.append(body) }
            let l = clipNameTarget ?? document.events[e].lines.count - 1
            if document.events[e].lines[l].sourceFile == nil {
                document.events[e].lines[l].sourceFile = path
            } else {
                document.events[e].lines[l].comments.append(body)
            }
        } else if upper.hasPrefix("LOC:") {
            if !consumeMarker(value(after: "LOC:", in: body), lineNumber: lineNumber) {
                if !appendComment(body) { document.notes.append(body) }
            }
        } else if !appendComment(body) {
            document.notes.append(body)
        }
    }

    mutating func setClipName(_ name: String, lineIndex: Int?) {
        guard let e = document.events.indices.last else { return document.notes.append(name) }
        let l = lineIndex ?? document.events[e].lines.count - 1
        if document.events[e].lines[l].clipName == nil {
            document.events[e].lines[l].clipName = name
        } else {
            document.events[e].lines[l].comments.append("Clip name: \(name)")
        }
        clipNameTarget = l
    }

    mutating func consumeMarker(_ body: String, lineNumber: Int) -> Bool {
        let tokens = body.split(maxSplits: 2, whereSeparator: \.isWhitespace)
        guard let first = tokens.first, let timecode = Timecode(first, defaultDropFrame: dropFrame) else { return false }
        var color: String?
        var noteTokens = tokens.dropFirst()
        if let candidate = noteTokens.first, MarkerColor.isKnown(String(candidate)) {
            color = candidate.uppercased()
            noteTokens = noteTokens.dropFirst()
        }
        document.markers.append(Marker(
            lineNumber: lineNumber,
            timecode: timecode,
            color: color,
            note: noteTokens.joined(separator: " ").trimmed
        ))
        return true
    }

    mutating func consumeSpeed(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 4,
              Timecode(tokens[tokens.count - 1], defaultDropFrame: dropFrame) != nil,
              let speed = Double(tokens[tokens.count - 2]),
              let e = document.events.indices.last
        else { return false }
        let reel = tokens[1..<(tokens.count - 2)].joined(separator: " ")
        let lines = document.events[e].lines
        let l = lines.lastIndex { $0.reel == reel } ?? lines.count - 1
        document.events[e].lines[l].speed = speed
        return true
    }

    mutating func appendComment(_ text: String) -> Bool {
        guard let e = document.events.indices.last else { return false }
        let l = document.events[e].lines.count - 1
        document.events[e].lines[l].comments.append(text)
        return true
    }

    mutating func unparsed(_ line: String, _ lineNumber: Int) {
        document.unparsed.append(UnparsedLine(lineNumber: lineNumber, text: line))
    }

    func value(after prefix: String, in text: String) -> String {
        String(text.dropFirst(prefix.count)).trimmed
    }

    func finish() -> EDLDocument {
        var result = document
        let timecodes = result.lines.flatMap { [$0.sourceIn, $0.sourceOut, $0.recordIn, $0.recordOut] }
            + result.markers.map(\.timecode)
        let maxFrame = timecodes.map(\.frames).max() ?? 0
        let anyDrop = timecodes.contains(where: \.dropFrame)
        result.frameRate = FrameRate.infer(maxFrameValue: maxFrame, dropFrame: anyDrop)
        return result
    }
}

public enum MarkerColor {
    public static let known: [String: String] = [
        "RED": "#e5484d", "GREEN": "#30a46c", "BLUE": "#3e63dd", "CYAN": "#05a2c2",
        "MAGENTA": "#d6409f", "YELLOW": "#f5d90a", "WHITE": "#f0f0f0", "BLACK": "#202020",
        "ORANGE": "#f76b15", "PINK": "#e93d82", "PURPLE": "#8e4ec6", "FUCHSIA": "#c026d3",
        "ROSE": "#e11d48", "LAVENDER": "#a78bfa", "SKY": "#38bdf8", "MINT": "#34d399",
        "LEMON": "#facc15", "SAND": "#c2a878", "COCOA": "#7c4a2d", "CREAM": "#f5e6c8",
    ]

    public static func isKnown(_ name: String) -> Bool { known[name.uppercased()] != nil }

    public static func css(_ name: String?) -> String {
        name.flatMap { known[$0.uppercased()] } ?? "#8e8e93"
    }
}

extension StringProtocol {
    var trimmed: String {
        guard let first = firstIndex(where: { !$0.isWhitespace }),
              let last = lastIndex(where: { !$0.isWhitespace })
        else { return "" }
        return String(self[first...last])
    }
}
