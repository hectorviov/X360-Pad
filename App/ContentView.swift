import SwiftUI
import X360PadCore

struct ContentView: View {
    @ObservedObject var manager: PadManager
    @ObservedObject var driver: DriverInstaller
    @State private var selected = 0
    @State private var openAtLogin = LoginItem.isOn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if driver.state != .installed { DriverSection(driver: driver, advanced: false) }   // installed: under Advanced instead
            Picker("Controller", selection: $selected) {
                ForEach(manager.slots) { s in
                    Text("\(s.index + 1)").tag(s.index)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            SlotView(slot: manager.slots[selected], driver: driver)

            Divider()
            HStack {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in LoginItem.set(on); openAtLogin = LoginItem.isOn }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text("X360 Pad").font(.headline)
            Spacer()
            ForEach(manager.slots) { s in SlotDot(slot: s) }
        }
        if let problem = manager.problem {
            VStack(alignment: .leading, spacing: 6) {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
        } else if driver.state != .installed {
            Label("Install the driver below, then plug in the Xbox 360 Wireless Gaming Receiver.", systemImage: "cable.connector").font(.callout).foregroundStyle(.secondary)
        } else if !manager.receiverConnected {
            Label("Plug in the Xbox 360 Wireless Gaming Receiver.", systemImage: "cable.connector").font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct DriverSection: View {
    @ObservedObject var driver: DriverInstaller
    let advanced: Bool   // installed, under Advanced: no install button

    var body: some View {
        GroupBox("Driver") {
            VStack(alignment: .leading, spacing: 6) {
                switch driver.state {
                case .unknown: Text("The driver presents each controller to macOS and games as a DualShock 4, with these settings applied.").font(.caption)
                case .installing: Text("Installing…").font(.caption)
                case .needsApproval: Text("Allow it in System Settings > General > Login Items & Extensions > Driver Extensions.").font(.caption).foregroundStyle(.orange)
                case .installed: Label("Installed", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
                case .failed(let m): Text(m).font(.caption).foregroundStyle(.red)
                }
                if !driver.inApplications {
                    Text("Move X360 Pad to /Applications first: macOS installs drivers only from there.").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    if !advanced { Button("Install driver") { driver.install() }.disabled(!driver.inApplications) }
                    Button("Remove") { driver.uninstall() }.disabled(!driver.inApplications)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SlotDot: View {
    @ObservedObject var slot: SlotModel
    var body: some View {
        Circle()
            .fill(slot.connected ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
            .help("Controller \(slot.index + 1): \(slot.connected ? "on" : "off")")
    }
}

private struct SlotView: View {
    @ObservedObject var slot: SlotModel
    @ObservedObject var driver: DriverInstaller
    @State private var showRemap = false
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if slot.attached && !slot.connected {
                Text("Turn on a controller: it takes quadrant \(slot.index + 1) on its ring.").font(.callout).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                StickColumn(title: "Left stick", slot: slot, left: true, settings: $slot.settings.leftStick)
                StickColumn(title: "Right stick", slot: slot, left: false, settings: $slot.settings.rightStick)
            }

            GroupBox("Triggers") {
                VStack(alignment: .leading, spacing: 4) {
                    TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                        HStack {
                            TriggerBar(label: "LT", raw: Double(slot.raw.leftTrigger) / 255, out: slot.output.leftTrigger, settings: slot.settings.triggers)
                            TriggerBar(label: "RT", raw: Double(slot.raw.rightTrigger) / 255, out: slot.output.rightTrigger, settings: slot.settings.triggers)
                        }
                    }
                    PercentSlider(label: "Dead zone", value: $slot.settings.triggers.deadZone, range: 0...0.5)
                    PercentSlider(label: "Full press at", value: $slot.settings.triggers.clickPoint, range: 0.02...0.95)
                }
            }

            GroupBox("Rumble") {
                VStack(alignment: .leading, spacing: 4) {
                    PercentSlider(label: "Strength", value: $slot.settings.rumbleGain, range: 0...2)
                    IntSlider(label: "Motor start", value: $slot.settings.motorFloor, range: 0...220, unit: "",
                              help: "The level a game's faintest rumble starts at (0-255): a 360 controller's motors do not turn below about 130")
                    IntSlider(label: "Min length", value: $slot.settings.motorHoldMs, range: 0...500, unit: " ms",
                              help: "Once on, the motors stay on at least this long: games' rumble can be shorter than the motors take to spin up")
                    HStack {
                        Toggle("Swap motors", isOn: $slot.settings.swapMotors)
                        Spacer()
                        Button("Test") { slot.testRumble() }.disabled(!slot.connected)
                    }
                }
            }

            DisclosureGroup("Remap buttons", isExpanded: $showRemap) {
                RemapView(slot: slot)
            }

            if driver.state == .installed {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    DriverSection(driver: driver, advanced: true).padding(.top, 4)
                }
            }

            HStack {
                Button { slot.powerOff() } label: { Label("Turn off", systemImage: "power") }
                    .disabled(!slot.connected)
                    .help("Turns this controller off, as holding its Guide button does on a console")
                Button("Reset this controller") { slot.settings = .defaults }
                Spacer()
            }
        }
    }
}

private struct StickColumn: View {
    let title: String
    @ObservedObject var slot: SlotModel
    let left: Bool
    @Binding var settings: StickSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                let r = slot.raw, o = slot.output
                StickPlot(
                    raw: left ? (PadProcessing.axis(r.leftX), PadProcessing.axis(r.leftY)) : (PadProcessing.axis(r.rightX), PadProcessing.axis(r.rightY)),
                    out: left ? (o.leftX, o.leftY) : (o.rightX, o.rightY),
                    inner: settings.innerDeadZone, outer: settings.outerDeadZone)
            }
            .frame(width: 120, height: 120)
            PercentSlider(label: "Dead zone", value: $settings.innerDeadZone, range: 0...0.6)
            PercentSlider(label: "Full at", value: $settings.outerDeadZone, range: 0.5...1)
            Toggle("Invert Y", isOn: $settings.invertY)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The stick's raw position (grey) and what the game receives (accent), inside the dead zone (filled) and the full-deflection ring.
private struct StickPlot: View {
    let raw: (Double, Double)
    let out: (Double, Double)
    let inner: Double
    let outer: Double

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 4
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ f: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r * f, y: c.y - r * f, width: 2 * r * f, height: 2 * r * f)) }
            func point(_ p: (Double, Double)) -> CGPoint { CGPoint(x: c.x + r * p.0, y: c.y - r * p.1) }
            func dot(_ p: CGPoint, _ size: Double) -> Path { Path(ellipseIn: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)) }
            ctx.stroke(circle(1), with: .color(.secondary.opacity(0.5)))
            ctx.fill(circle(inner), with: .color(.orange.opacity(0.2)))
            ctx.stroke(circle(outer), with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(dot(point(raw), 7), with: .color(.secondary))
            ctx.fill(dot(point(out), 9), with: .color(.accentColor))
        }
    }
}

private struct TriggerBar: View {
    let label: String
    let raw: Double
    let out: Double
    let settings: TriggerSettings

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption.monospaced()).frame(width: 20, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(Color.secondary.opacity(0.5)).frame(width: g.size.width * raw)
                    Capsule().fill(Color.accentColor).frame(width: g.size.width * out, height: 4)
                    Rectangle().fill(Color.orange).frame(width: 1).offset(x: g.size.width * settings.clickPoint)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct PercentSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 72, alignment: .leading)
            Slider(value: $value, in: range).controlSize(.small)
            Text("\(Int((value * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
        }
    }
}

private struct IntSlider: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    let help: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 72, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound)).controlSize(.small)
            Text("\(value)\(unit)").font(.caption.monospacedDigit()).frame(width: 52, alignment: .trailing)
        }
        .help(help)
    }
}

private struct RemapView: View {
    @ObservedObject var slot: SlotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(X360Button.allCases) { b in
                HStack {
                    TimelineView(.periodic(from: .now, by: 1.0 / 15)) { _ in
                        Circle().fill(slot.raw.buttons.contains(b.mask) ? Color.accentColor : Color.secondary.opacity(0.25)).frame(width: 7, height: 7)
                    }
                    .frame(width: 10)
                    Text(b.label).font(.caption).frame(width: 100, alignment: .leading)
                    Picker("", selection: binding(for: b)) {
                        Text("Itself").tag(Optional(b))
                        Text("Nothing").tag(X360Button?.none)
                        Divider()
                        ForEach(X360Button.allCases.filter { $0 != b }) { t in Text(t.label).tag(Optional(t)) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 170)   // every row the same width, whatever its label
                }
            }
            Text("Games see the controller as a DualShock 4, buttons by position: A is ✕, B ○, X □, Y △, Back is Share, Start Options, Guide PS.")
                .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private func binding(for b: X360Button) -> Binding<X360Button?> {
        Binding(
            get: { slot.settings.target(of: b) },
            set: { t in
                var s = slot.settings
                s.disabled.remove(b); s.remap[b] = nil
                if let t { if t != b { s.remap[b] = t } } else { s.disabled.insert(b) }
                slot.settings = s
            })
    }
}
