// A slot's settings in the driver's layout (Driver/X360Settings.h), and the state the driver reports, read with the same C functions the driver
// applies (so the window shows what games get).
import Foundation
import X360PadCore

extension X360Button {
    /// The button's bit in the wire report (and in X360Buttons).
    var bit: Int { mask.rawValue.trailingZeroBitCount }
}

extension PadSettings {
    var driverSettings: x360_settings {
        var s = x360_settings()
        x360_settings_default(&s)
        s.stickInner = (Float(leftStick.innerDeadZone), Float(rightStick.innerDeadZone))
        s.stickOuter = (Float(leftStick.outerDeadZone), Float(rightStick.outerDeadZone))
        s.invertY = (leftStick.invertY ? 1 : 0, rightStick.invertY ? 1 : 0)
        s.swapMotors = swapMotors ? 1 : 0
        s.motorFloor = UInt8(min(max(motorFloor, 0), 254))
        s.triggerDead = Float(triggers.deadZone)
        s.triggerClick = Float(triggers.clickPoint)
        s.rumbleGain = Float(rumbleGain)
        s.motorHoldMs = UInt16(min(max(motorHoldMs, 0), 2000))
        withUnsafeMutableBytes(of: &s.remap) { map in
            for b in X360Button.allCases {
                map[b.bit] = target(of: b).map { UInt8($0.bit) } ?? UInt8(X360_REMAP_NONE)
            }
        }
        return s
    }

    var driverSettingsData: Data {
        var s = driverSettings
        return Data(bytes: &s, count: MemoryLayout<x360_settings>.size)
    }

    /// The motor levels the driver sends for a request (gain, swap, floor).
    func motorLevels(strong: UInt8, weak: UInt8) -> (UInt8, UInt8) {
        var s = driverSettings
        var a: UInt8 = 0, b: UInt8 = 0
        x360_motors(&s, strong, weak, &a, &b)
        return (a, b)
    }
}

/// A wire report (20 bytes) as the app's state types: the raw one, and the one after the settings as the driver applies them.
enum DriverState {
    static func state(_ w: [UInt8]) -> X360State {
        var st = X360State()
        guard w.count >= 14 else { return st }
        st.buttons = X360Buttons(rawValue: UInt16(w[2]) | UInt16(w[3]) << 8)
        st.leftTrigger = w[4]; st.rightTrigger = w[5]
        func le(_ i: Int) -> Int16 { Int16(bitPattern: UInt16(w[i]) | UInt16(w[i + 1]) << 8) }
        st.leftX = le(6); st.leftY = le(8); st.rightX = le(10); st.rightY = le(12)
        return st
    }

    static func output(_ raw: [UInt8], _ settings: PadSettings) -> PadOutput {
        var s = settings.driverSettings
        var w = raw
        guard w.count == 20 else { return PadOutput() }
        w.withUnsafeMutableBufferPointer { x360_apply(&s, $0.baseAddress!) }
        let st = state(w)
        var o = PadOutput()
        o.buttons = st.buttons
        o.leftX = PadProcessing.axis(st.leftX); o.leftY = PadProcessing.axis(st.leftY)
        o.rightX = PadProcessing.axis(st.rightX); o.rightY = PadProcessing.axis(st.rightY)
        o.leftTrigger = Double(st.leftTrigger) / 255; o.rightTrigger = Double(st.rightTrigger) / 255
        let click = x360_click_level(&s)
        o.leftTriggerClick = st.leftTrigger > click; o.rightTriggerClick = st.rightTrigger > click
        return o
    }
}
