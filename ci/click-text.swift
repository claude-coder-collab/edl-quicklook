import AppKit
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else { fail("usage: click-text <screenshot.png> <text> click|scroll") }
let (imagePath, target, action) = (arguments[1], arguments[2], arguments[3])

guard let image = NSImage(contentsOfFile: imagePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("cannot read \(imagePath)")
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image).perform([request])

func normalise(_ text: String) -> String {
    text.lowercased().replacingOccurrences(of: "×", with: "x")
}

let wanted = normalise(target)
var found: CGRect?
for observation in request.results ?? [] {
    guard let candidate = observation.topCandidates(1).first else { continue }
    print("ocr: \(candidate.string) \(observation.boundingBox)")
    let text = normalise(candidate.string)
    guard found == nil, let range = text.range(of: wanted) else { continue }
    let lower = candidate.string.index(candidate.string.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound))
    let upper = candidate.string.index(lower, offsetBy: text.distance(from: range.lowerBound, to: range.upperBound))
    found = (try? candidate.boundingBox(for: lower..<upper))?.boundingBox ?? observation.boundingBox
}
guard let box = found else { fail("text '\(target)' not found") }

let scale = NSScreen.main?.backingScaleFactor ?? 1
let point = CGPoint(
    x: box.midX * Double(image.width) / scale,
    y: (1 - box.midY) * Double(image.height) / scale
)
print("target \(target) at \(point) (scale \(scale))")

let source = CGEventSource(stateID: .hidSystemState)
func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(150_000)
}

switch action {
case "click":
    post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
    post(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left))
case "scroll":
    let over = CGPoint(x: point.x - 250, y: point.y + 60)
    post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: over, mouseButton: .left))
    for _ in 0..<10 {
        post(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: -120, wheel3: 0))
    }
default:
    fail("unknown action \(action)")
}
print("\(action) posted")
