// The settings model (the processing itself is the driver's C, tested by tools/test_settings.c).
import Foundation
import Testing
@testable import X360PadCore

@Suite struct Settings {
    @Test func remapAndDisable() {
        var p = PadSettings.defaults
        p.remap = [.a: .b, .b: .a]
        p.disabled = [.guide]
        #expect(p.target(of: .a) == .b)
        #expect(p.target(of: .b) == .a)
        #expect(p.target(of: .guide) == nil)
        #expect(p.target(of: .x) == .x)
    }

    @Test func roundTrip() throws {
        var p = PadSettings.defaults
        p.remap = [.lb: .rb]; p.disabled = [.back]; p.motorFloor = 140; p.motorHoldMs = 250
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(PadSettings.self, from: data) == p)
    }

    @Test func buttonBits() {
        // the wire report's bits, which the driver's remap table is indexed by
        #expect(X360Button.dpadUp.mask.rawValue == 1 << 0 && X360Button.rightStick.mask.rawValue == 1 << 7)
        #expect(X360Button.lb.mask.rawValue == 1 << 8 && X360Button.guide.mask.rawValue == 1 << 10)
        #expect(X360Button.a.mask.rawValue == 1 << 12 && X360Button.y.mask.rawValue == 1 << 15)
    }

    @Test func axis() {
        #expect(PadProcessing.axis(0) == 0 && PadProcessing.axis(32767) == 1 && PadProcessing.axis(-32768) == -1)
    }
}
