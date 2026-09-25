import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: mouse <x> <y> click|scroll-left|scroll-right\n".utf8))
    exit(2)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(150_000)
}

post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
switch arguments[3] {
case "click":
    post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
    post(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left))
case "scroll-left", "scroll-right":
    let delta: Int32 = arguments[3] == "scroll-left" ? 120 : -120
    for _ in 0..<10 {
        post(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: delta, wheel3: 0))
    }
default:
    FileHandle.standardError.write(Data("unknown action\n".utf8))
    exit(2)
}
print("\(arguments[3]) at \(point)")
