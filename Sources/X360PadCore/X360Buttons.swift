// A controller's buttons and state as the app shows and remaps them. The bits are the wire report's (Driver/X360Wire.h and X360Settings.h), which
// the driver reads; the driver applies the settings, the app only shows them.

public struct X360Buttons: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let dpadUp = X360Buttons(rawValue: 1 << 0)
    public static let dpadDown = X360Buttons(rawValue: 1 << 1)
    public static let dpadLeft = X360Buttons(rawValue: 1 << 2)
    public static let dpadRight = X360Buttons(rawValue: 1 << 3)
    public static let start = X360Buttons(rawValue: 1 << 4)
    public static let back = X360Buttons(rawValue: 1 << 5)
    public static let leftStick = X360Buttons(rawValue: 1 << 6)
    public static let rightStick = X360Buttons(rawValue: 1 << 7)
    public static let lb = X360Buttons(rawValue: 1 << 8)
    public static let rb = X360Buttons(rawValue: 1 << 9)
    public static let guide = X360Buttons(rawValue: 1 << 10)
    // bit 11 unused (as on the wire)
    public static let a = X360Buttons(rawValue: 1 << 12)
    public static let b = X360Buttons(rawValue: 1 << 13)
    public static let x = X360Buttons(rawValue: 1 << 14)
    public static let y = X360Buttons(rawValue: 1 << 15)
}

/// One button, for remapping and for the settings window.
public enum X360Button: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
    case a, b, x, y, lb, rb, back, start, guide, leftStick, rightStick, dpadUp, dpadDown, dpadLeft, dpadRight

    public var id: String { rawValue }
    public var mask: X360Buttons {
        switch self {
        case .a: .a
        case .b: .b
        case .x: .x
        case .y: .y
        case .lb: .lb
        case .rb: .rb
        case .back: .back
        case .start: .start
        case .guide: .guide
        case .leftStick: .leftStick
        case .rightStick: .rightStick
        case .dpadUp: .dpadUp
        case .dpadDown: .dpadDown
        case .dpadLeft: .dpadLeft
        case .dpadRight: .dpadRight
        }
    }
    public var label: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .lb: "LB"
        case .rb: "RB"
        case .back: "Back"
        case .start: "Start"
        case .guide: "Guide"
        case .leftStick: "Left stick click"
        case .rightStick: "Right stick click"
        case .dpadUp: "D-pad up"
        case .dpadDown: "D-pad down"
        case .dpadLeft: "D-pad left"
        case .dpadRight: "D-pad right"
        }
    }
}

/// A controller's raw state as the receiver reports it.
public struct X360State: Equatable, Sendable {
    public var buttons: X360Buttons = []
    public var leftTrigger: UInt8 = 0
    public var rightTrigger: UInt8 = 0
    public var leftX: Int16 = 0
    public var leftY: Int16 = 0     // up is positive
    public var rightX: Int16 = 0
    public var rightY: Int16 = 0
    public init() {}
}
