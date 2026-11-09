// What the user sets for each receiver slot. The app sends it to the driver in the driver's layout (App/DriverSettings.swift); the driver applies it
// (Driver/X360Settings.h).

public struct StickSettings: Codable, Equatable, Sendable {
    /// Deflection (fraction of full) below which the stick reads as centred: the cure for drift.
    public var innerDeadZone: Double
    /// Deflection past which the stick reads as fully deflected (old sticks may no longer reach their edge).
    public var outerDeadZone: Double
    public var invertY: Bool

    public init(innerDeadZone: Double, outerDeadZone: Double = 0.98, invertY: Bool = false) {
        self.innerDeadZone = innerDeadZone; self.outerDeadZone = outerDeadZone; self.invertY = invertY
    }
}

public struct TriggerSettings: Codable, Equatable, Sendable {
    /// Travel (fraction) below which the trigger reads as released.
    public var deadZone: Double
    /// Travel past which the trigger also presses its digital button (DualSense L2 / R2).
    public var clickPoint: Double

    public init(deadZone: Double = 0.03, clickPoint: Double = 0.12) { self.deadZone = deadZone; self.clickPoint = clickPoint }
}

public struct PadSettings: Codable, Equatable, Sendable {
    public var leftStick: StickSettings
    public var rightStick: StickSettings
    public var triggers: TriggerSettings
    /// Source button -> the button it presses instead; a button missing from the map presses itself.
    public var remap: [X360Button: X360Button]
    /// Buttons that do nothing (checked before `remap`).
    public var disabled: Set<X360Button>
    /// 0 silent .. 2 twice the game's strength (clipped at the motors' maximum).
    public var rumbleGain: Double
    public var swapMotors: Bool
    /// 0..254: a game's motor level 1..255 is spread over this..255 (a 360 controller's motors do not turn below about 130)
    public var motorFloor: Int = 130
    /// Once on, the motors stay on at least this long (games' rumble effects can be shorter than the motors' spin-up)
    public var motorHoldMs: Int = 200

    /// XInput's own dead zones for this controller (XINPUT_GAMEPAD_LEFT / RIGHT_THUMB_DEADZONE, 7849 and 8689 of 32767).
    public static let defaults = PadSettings(
        leftStick: StickSettings(innerDeadZone: 7849.0 / 32767.0),
        rightStick: StickSettings(innerDeadZone: 8689.0 / 32767.0),
        triggers: TriggerSettings(),
        remap: [:],
        disabled: [],
        rumbleGain: 1,
        swapMotors: false
    )

    public init(leftStick: StickSettings, rightStick: StickSettings, triggers: TriggerSettings, remap: [X360Button: X360Button], disabled: Set<X360Button>, rumbleGain: Double, swapMotors: Bool) {
        self.leftStick = leftStick; self.rightStick = rightStick; self.triggers = triggers
        self.remap = remap; self.disabled = disabled; self.rumbleGain = rumbleGain; self.swapMotors = swapMotors
    }

    /// The button a press of `b` produces (nil: none).
    public func target(of b: X360Button) -> X360Button? {
        if disabled.contains(b) { return nil }
        return remap[b] ?? b
    }
}

/// The state the virtual pad reports: sticks in -1...1 with y up, triggers in 0...1.
public struct PadOutput: Equatable, Sendable {
    public var buttons: X360Buttons = []
    public var leftX = 0.0, leftY = 0.0, rightX = 0.0, rightY = 0.0
    public var leftTrigger = 0.0, rightTrigger = 0.0
    public var leftTriggerClick = false, rightTriggerClick = false
    public init() {}
}

public enum PadProcessing {
    /// A stick axis from the wire report's signed 16 bits to -1...1.
    public static func axis(_ v: Int16) -> Double { v == Int16.min ? -1 : Double(v) / 32767.0 }
}
