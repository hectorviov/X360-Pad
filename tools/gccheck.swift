// Lists the controllers GameController sees; with "rumble" as argument, plays a 1 s rumble on each.
import CoreHaptics
import Foundation
import GameController

GCController.shouldMonitorBackgroundEvents = true
let wantRumble = CommandLine.arguments.contains("rumble")
let locality: GCHapticsLocality = CommandLine.arguments.contains("handles") ? .handles : CommandLine.arguments.contains("left") ? .leftHandle : CommandLine.arguments.contains("right") ? .rightHandle : CommandLine.arguments.contains("all") ? .all : .default
var engines: [CHHapticEngine] = []

func describe(_ c: GCController) {
    let gp = c.extendedGamepad
    print("controller: '\(c.vendorName ?? "?")' category=\(c.productCategory) extended=\(gp != nil) haptics=\(c.haptics != nil)")
    if let gp {
        print("  A=\(gp.buttonA.isPressed) LX=\(gp.leftThumbstick.xAxis.value) LY=\(gp.leftThumbstick.yAxis.value) LT=\(gp.leftTrigger.value) symbolA=\(gp.buttonA.sfSymbolsName ?? "-")")
    }
    if wantRumble, let h = c.haptics, let e = h.createEngine(withLocality: locality) {
        do {
            try e.start()
            let ev = CHHapticEvent(eventType: .hapticContinuous, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)], relativeTime: 0, duration: 1)
            try e.makePlayer(with: CHHapticPattern(events: [ev], parameters: [])).start(atTime: 0)
            engines.append(e)
            print("  rumble started (\(locality.rawValue)); localities: \(h.supportedLocalities.map { $0.rawValue }.sorted())")
        } catch { print("  rumble failed: \(error)") }
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    print("controllers now: \(GCController.controllers().count)")
    for c in GCController.controllers() { describe(c) }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
RunLoop.main.run()
