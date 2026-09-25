import Foundation

public struct HTMLRenderer: Sendable {
    public var laneHeight = 22
    public var maxTicks = 10

    public init() {}

    public func render(_ document: EDLDocument, fileName: String? = nil) -> String {
        let title = document.title ?? fileName ?? "Untitled EDL"
        var html: [String] = []
        html.append("<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(escape(title))</title>")
        html.append("<style>\(Self.stylesheet)</style></head><body>")
        html.append("<header><h1>\(escape(title))</h1>\(summary(document))</header>")
        html.append(timeline(document))
        html.append(eventTable(document))
        html.append(markerTable(document))
        html.append(unparsedSection(document))
        html.append("</body></html>")
        return html.joined(separator: "\n")
    }

    func summary(_ document: EDLDocument) -> String {
        var items: [(String, String)] = []
        if let fcm = document.frameCodeMode { items.append(("FCM", fcm)) }
        items.append(("Frame rate", "\(document.frameRate.displayName) (assumed)"))
        items.append(("Events", String(document.events.count)))
        if let extent = document.recordExtent {
            items.append(("Record", "\(document.string(extent.lowerBound)) – \(document.string(extent.upperBound))"))
            items.append(("Duration", document.durationString(extent.count)))
        }
        let lanes = document.lanes
        if !lanes.isEmpty { items.append(("Tracks", lanes.map(\.description).joined(separator: " "))) }
        if !document.markers.isEmpty { items.append(("Markers", String(document.markers.count))) }
        let list = items.map { "<div><dt>\(escape($0.0))</dt><dd>\(escape($0.1))</dd></div>" }.joined()
        let notes = document.notes.isEmpty ? "" :
            "<ul class=\"notes\">" + document.notes.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
        return "<dl class=\"summary\">\(list)</dl>\(notes)"
    }

    func timeline(_ document: EDLDocument) -> String {
        guard let extent = document.recordExtent else { return "" }
        let lanes = document.lanes
        guard !lanes.isEmpty else { return "" }
        let total = Double(extent.count)
        func percent(_ frame: Int) -> String {
            Self.percentString(Double(frame - extent.lowerBound) / total * 100)
        }
        func width(_ frames: Int) -> String {
            Self.percentString(Double(frames) / total * 100)
        }
        let markerPositions = document.markers
            .map { (document.recordPosition($0.timecode), $0) }
            .filter { extent.contains($0.0) || $0.0 == extent.upperBound }

        var rows: [String] = []
        rows.append("<div class=\"label\"></div><svg class=\"ruler\" height=\"20\">\(ruler(document, extent: extent, percent: percent))</svg>")

        for lane in lanes {
            var shapes: [String] = []
            for event in document.events {
                for line in event.lines where line.lanes.contains(lane) {
                    let range = document.recordRange(of: line)
                    guard !range.isEmpty else { continue }
                    let tooltip = [
                        "#\(event.number) \(line.reel)",
                        "\(line.recordIn) – \(line.recordOut)",
                        line.transition == .cut ? nil : line.transition.code,
                        line.clipName,
                    ].compactMap { $0 }.joined(separator: " · ")
                    shapes.append(
                        "<rect class=\"seg\" x=\"\(percent(range.lowerBound))\" y=\"2\" width=\"\(width(range.count))\" "
                            + "height=\"\(laneHeight - 4)\" fill=\"\(Self.colour(for: line.reel))\"><title>\(escape(tooltip))</title></rect>"
                    )
                    let transitionFrames = min(line.transition.durationFrames, range.count)
                    if transitionFrames > 0 {
                        shapes.append(
                            "<rect class=\"trans\" x=\"\(percent(range.lowerBound))\" y=\"2\" width=\"\(width(transitionFrames))\" height=\"\(laneHeight - 4)\"/>"
                        )
                    }
                }
            }
            for (position, _) in markerPositions {
                shapes.append("<line class=\"mline\" x1=\"\(percent(position))\" x2=\"\(percent(position))\" y1=\"0\" y2=\"\(laneHeight)\"/>")
            }
            rows.append("<div class=\"label\">\(escape(lane.description))</div><svg class=\"lane\" height=\"\(laneHeight)\">\(shapes.joined())</svg>")
        }

        if !markerPositions.isEmpty {
            let pins = markerPositions.map { position, marker in
                "<circle cx=\"\(percent(position))\" cy=\"7\" r=\"5\" fill=\"\(MarkerColor.css(marker.color))\">"
                    + "<title>\(escape("\(marker.timecode) \(marker.note)"))</title></circle>"
            }.joined()
            rows.append("<div class=\"label\">M</div><svg class=\"markers\" height=\"14\">\(pins)</svg>")
        }
        return "<section class=\"timeline\">\(rows.joined())</section>"
    }

    func ruler(_ document: EDLDocument, extent: Range<Int>, percent: (Int) -> String) -> String {
        let rate = document.frameRate.timebase
        let totalSeconds = Double(extent.count) / Double(rate)
        let steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 14400]
        let stepSeconds = steps.first { totalSeconds / Double($0) <= Double(maxTicks) } ?? steps[steps.count - 1]
        let stepFrames = stepSeconds * rate
        var tick = (extent.lowerBound + stepFrames - 1) / stepFrames * stepFrames
        var marks: [String] = []
        while tick <= extent.upperBound {
            let fraction = Double(tick - extent.lowerBound) / Double(max(extent.count, 1))
            let anchor = fraction < 0.05 ? "start" : fraction > 0.95 ? "end" : "middle"
            let x = percent(tick)
            marks.append("<line x1=\"\(x)\" x2=\"\(x)\" y1=\"14\" y2=\"20\"/>")
            marks.append("<text x=\"\(x)\" y=\"11\" text-anchor=\"\(anchor)\">\(document.string(tick))</text>")
            tick += stepFrames
        }
        return marks.joined()
    }

    func eventTable(_ document: EDLDocument) -> String {
        guard !document.events.isEmpty else { return "<p class=\"empty\">No events found.</p>" }
        let headers = ["#", "Reel", "Track", "Trans", "Src In", "Src Out", "Rec In", "Rec Out", "Duration", "Speed", "Clip"]
        var html = "<section><h2>Events</h2><div class=\"scroll\"><table class=\"events\"><thead><tr>"
        html += headers.map { "<th>\($0)</th>" }.joined()
        html += "</tr></thead>"
        for event in document.events {
            html += "<tbody class=\"event\">"
            for (index, line) in event.lines.enumerated() {
                let duration = document.recordRange(of: line).count
                let speed = line.speed.map { speed -> String in
                    let percentage = speed / document.frameRate.framesPerSecond * 100
                    return String(format: "%.1f fps (%.0f%%)", speed, percentage)
                } ?? ""
                let cells = [
                    index == 0 ? String(event.number) : "",
                    line.reel, line.track, line.transition.code,
                    line.sourceIn.description, line.sourceOut.description,
                    line.recordIn.description, line.recordOut.description,
                    document.durationString(duration), speed, line.clipName ?? "",
                ]
                let classes = ["num", "reel", "", "", "tc", "tc", "tc", "tc", "tc", "", "clip"]
                html += "<tr>" + zip(cells, classes).map { cell, cls in
                    "<td\(cls.isEmpty ? "" : " class=\"\(cls)\"")>\(escape(cell))</td>"
                }.joined() + "</tr>"
                let details = (line.sourceFile.map { ["Source file: \($0)"] } ?? []) + line.comments
                if !details.isEmpty {
                    html += "<tr class=\"detail\"><td></td><td colspan=\"\(headers.count - 1)\">"
                        + details.map(escape).joined(separator: "<br>") + "</td></tr>"
                }
            }
            html += "</tbody>"
        }
        return html + "</table></div></section>"
    }

    func markerTable(_ document: EDLDocument) -> String {
        guard !document.markers.isEmpty else { return "" }
        let rows = document.markers.map { marker in
            "<tr><td class=\"tc\">\(escape(marker.timecode.description))</td>"
                + "<td><span class=\"swatch\" style=\"background:\(MarkerColor.css(marker.color))\"></span>\(escape(marker.color?.capitalized ?? ""))</td>"
                + "<td>\(escape(marker.note))</td></tr>"
        }.joined()
        return "<section><h2>Markers</h2><table class=\"markers\"><thead><tr><th>Timecode</th><th>Colour</th><th>Note</th></tr></thead><tbody>\(rows)</tbody></table></section>"
    }

    func unparsedSection(_ document: EDLDocument) -> String {
        guard !document.unparsed.isEmpty else { return "" }
        let lines = document.unparsed.map { "<span class=\"ln\">\($0.lineNumber)</span>\(escape($0.text))" }.joined(separator: "\n")
        return "<section><h2>Unparsed lines</h2><pre class=\"unparsed\">\(lines)</pre></section>"
    }

    static func percentString(_ value: Double) -> String {
        let scaled = Int((value * 10_000).rounded())
        let sign = scaled < 0 ? "-" : ""
        let magnitude = abs(scaled)
        let fraction = String(magnitude % 10_000)
        return "\(sign)\(magnitude / 10_000).\(String(repeating: "0", count: 4 - fraction.count))\(fraction)%"
    }

    public static func colour(for reel: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in reel.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return "hsl(\(hash % 360) 55% 55%)"
    }

    func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    static let stylesheet = """
    :root{color-scheme:light dark;--bg:#fff;--fg:#1d1d1f;--muted:#6e6e73;--line:#d2d2d7;--lane:#f2f2f5;--head:#fafafa}
    @media (prefers-color-scheme:dark){:root{--bg:#1e1e1e;--fg:#f5f5f7;--muted:#98989d;--line:#3a3a3c;--lane:#2a2a2c;--head:#252525}}
    *{box-sizing:border-box}
    body{margin:0;padding:16px 20px;background:var(--bg);color:var(--fg);font:12px -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    h1{font-size:18px;margin:0 0 8px;overflow-wrap:anywhere}
    h2{font-size:13px;margin:20px 0 6px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
    .summary{display:flex;flex-wrap:wrap;gap:6px 24px;margin:0}
    .summary dt{color:var(--muted);font-size:11px}
    .summary dd{margin:0;font-variant-numeric:tabular-nums}
    .notes{color:var(--muted);margin:8px 0 0;padding-left:18px}
    .timeline{display:grid;grid-template-columns:2.5em 1fr;row-gap:2px;margin-top:16px}
    .timeline svg{width:100%;display:block;overflow:visible}
    .label{color:var(--muted);font-size:11px;align-self:center}
    .lane{background:var(--lane);border-radius:3px}
    .seg{stroke:var(--bg);stroke-width:.5}
    .trans{fill:#fff;opacity:.45}
    .mline{stroke:var(--fg);stroke-width:1;opacity:.35}
    .ruler text{fill:var(--muted);font-size:10px;font-variant-numeric:tabular-nums}
    .ruler line{stroke:var(--muted)}
    .scroll{overflow-x:auto}
    table{border-collapse:collapse;width:100%}
    th{position:sticky;top:0;background:var(--head);text-align:left;font-weight:600;color:var(--muted);border-bottom:1px solid var(--line)}
    th,td{padding:3px 8px;white-space:nowrap}
    tbody{border-bottom:1px solid var(--line)}
    .tc,.num{font-family:ui-monospace,Menlo,monospace;font-variant-numeric:tabular-nums}
    .reel,.clip{white-space:normal;overflow-wrap:anywhere;min-width:8em}
    .detail td{color:var(--muted);white-space:normal;padding-top:0;overflow-wrap:anywhere}
    .swatch{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:-1px}
    .unparsed{font-family:ui-monospace,Menlo,monospace;background:var(--lane);padding:8px;border-radius:4px;overflow-x:auto}
    .ln{display:inline-block;min-width:3em;color:var(--muted)}
    .empty{color:var(--muted)}
    """
}
