// The receiver's four slots, through the driver (Driver/): each slot's settings are kept here (the receiver tells controllers apart only by slot),
// sent to the driver when its slot service appears and whenever they change, and the driver's live state is read for the window. The driver
// applies the settings to every report and every rumble request, so they hold in every game while the driver runs, app or not (until the next
// replug or restart, when the driver starts from its defaults again until the app sends them).
import Combine
import Foundation
import os
import X360PadCore

let log = Logger(subsystem: "com.hectorviov.x360pad", category: "pad")

@MainActor
final class SlotModel: ObservableObject, Identifiable {
    let index: Int
    nonisolated var id: Int { index }

    @Published private(set) var attached = false    // the driver's service for this slot is open
    @Published private(set) var connected = false   // a controller is on in this slot
    @Published var settings: PadSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            push()
        }
    }
    /// The latest raw and processed state (not published: the window samples them on its own clock).
    private(set) var raw = X360State()
    private(set) var output = PadOutput()
    private(set) var motors: (strong: UInt8, weak: UInt8) = (0, 0)

    fileprivate weak var manager: PadManager?

    init(index: Int) {
        self.index = index
        if let data = UserDefaults.standard.data(forKey: Self.key(index)), let s = try? JSONDecoder().decode(PadSettings.self, from: data) {
            settings = s
        } else {
            settings = .defaults
        }
    }

    private static func key(_ i: Int) -> String { "slot\(i + 1).settings" }
    private func save() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.key(index)) }
    }

    /// Sends the settings to the driver.
    fileprivate func push() {
        guard attached, let manager else { return }
        let r = manager.driver.setSettings(settings.driverSettingsData, forSlot: index)
        if r != 0 { log.error("slot \(self.index + 1, privacy: .public): settings not sent (0x\(String(UInt32(bitPattern: r), radix: 16), privacy: .public))") }
    }

    fileprivate func setAttached(_ on: Bool) {
        attached = on
        if on { push() } else { update(nil) }
    }

    fileprivate func update(_ state: x360_state?) {
        guard var st = state, st.connected != 0 else {
            if connected { connected = false }
            raw = X360State(); output = PadOutput(); motors = (0, 0)
            return
        }
        if !connected { connected = true }
        let bytes = withUnsafeBytes(of: &st.raw) { [UInt8]($0) }
        raw = DriverState.state(bytes)
        output = DriverState.output(bytes, settings)
        motors = (st.motors.0, st.motors.1)
    }

    /// Turns this slot's controller off (no need to take its batteries out).
    func powerOff() {
        guard let manager else { return }
        let r = manager.driver.powerOffSlot(index)
        if r != 0 { log.error("slot \(self.index + 1, privacy: .public): power off not sent (0x\(String(UInt32(bitPattern: r), radix: 16), privacy: .public))") }
    }

    /// Half a second of both motors as a game's strong request would get them (the slot's gain, swap and floor), to feel the setting.
    func testRumble() {
        guard let manager else { return }
        let (a, b) = settings.motorLevels(strong: 200, weak: 200)
        let r = manager.driver.testRumbleStrong(a, weak: b, milliseconds: 500, forSlot: index)
        if r != 0 { log.error("slot \(self.index + 1, privacy: .public): test rumble not sent (0x\(String(UInt32(bitPattern: r), radix: 16), privacy: .public))") }
    }
}

@MainActor
final class PadManager: NSObject, ObservableObject, X360DriverDelegate {
    let slots = (0..<4).map { SlotModel(index: $0) }
    @Published private(set) var attachedSlots: Set<Int> = []
    @Published private(set) var problem: String?

    let driver = X360Driver()
    private var timer: Timer?

    override init() {
        super.init()
        for s in slots { s.manager = self }
        driver.delegate = self
    }

    /// Follows the driver's slot services (they exist while the driver runs and the receiver is plugged in).
    func start() {
        driver.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    var receiverConnected: Bool { !attachedSlots.isEmpty }

    private func poll() {
        for s in slots where s.attached {
            if let data = driver.state(forSlot: s.index), data.count == MemoryLayout<x360_state>.size {
                s.update(data.withUnsafeBytes { $0.loadUnaligned(as: x360_state.self) })
            }
        }
    }

    // X360DriverDelegate (main queue)
    nonisolated func x360DriverSlotAppeared(_ slot: Int) {
        MainActor.assumeIsolated {
            guard slots.indices.contains(slot) else { return }
            attachedSlots.insert(slot)
            problem = nil
            slots[slot].setAttached(true)
            log.info("driver slot \(slot + 1, privacy: .public) open")
        }
    }
    nonisolated func x360DriverSlotGone(_ slot: Int) {
        MainActor.assumeIsolated {
            guard slots.indices.contains(slot) else { return }
            attachedSlots.remove(slot)
            slots[slot].setAttached(false)
            log.info("driver slot \(slot + 1, privacy: .public) gone")
        }
    }
    nonisolated func x360DriverOpenFailed(_ slot: Int, result: Int32) {
        MainActor.assumeIsolated {
            problem = "The driver refused the connection for controller \(slot + 1) (0x\(String(UInt32(bitPattern: result), radix: 16)))."
            log.error("driver slot \(slot + 1, privacy: .public): open failed 0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)")
        }
    }
}
