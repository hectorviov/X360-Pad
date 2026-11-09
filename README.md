# X360 Pad

A macOS driver and menu-bar app for the original **Xbox 360 wireless controller** with Microsoft's
**Wireless Gaming Receiver** (USB `045e:0291` / `0719` / `02a9`). Each controller that turns on
appears to macOS and games as a **DualShock 4**: GameController, System Settings, Steam, SDL and
nxnative take it like a real one, rumble included. No kernel extension, no boot arguments.

Per controller (by receiver slot, the ring quadrant it lights), applied by the driver in every game:

- stick dead zone and full-deflection point, each stick on its own, with a live view of the raw and
  corrected position (to tune away drift); invert Y
- trigger dead zone and the point where L2 / R2 click
- rumble strength, the level a game's faintest rumble starts at (a 360 controller's motors do not
  turn below about 130 of 255), its minimum length (games' effects can be shorter than the motors
  take to spin up), motor swap, a test button
- button remapping (any button to another, or to nothing)
- turning the controller off

Buttons reach games by position: A is ✕, B ○, X □, Y △, Back is Share, Start Options, Guide PS.

## Why a DualShock 4

GameController accepts a gamepad that a driver publishes only under the identities Apple marks for
virtual devices (`GCIOMatchVirtual` in AppleGameControllerPersonality.kext: DualSense, DualShock 4,
the Bluetooth Xbox and Switch controllers). The wired Xbox 360 identity is not one of them. A
DualSense's haptics go to its audio interface, which a driver-made gamepad does not have, so it
never rumbles; a DualShock 4's rumble comes as a HID output report the driver receives. (A CoreHID
virtual device, x360w's route, is refused by the kernel on macOS 27: `IOServiceOpen(IOHIDResource)`
returns `kIOReturnNotPermitted` even with `com.apple.developer.hid.virtual.device`.)

## Layout

| Path | What |
|---|---|
| `Driver/X360PadDevice` | matches the receiver and sets its USB configuration (macOS sets none for a vendor-class device, so its slots would not exist) |
| `Driver/X360PadSlot` | one receiver slot: reads it, publishes the gamepad while a controller is on, queues commands to the receiver (one in flight, the latest rumble / LED replacing a waiting one), the motors' minimum time on, the slot's settings |
| `Driver/X360PadGamepad` | the DualShock 4 the slot publishes (`DualShock4Wire.h`) |
| `Driver/X360PadUserClient` | the app's connection to a slot: settings, live state, test rumble, power off |
| `Driver/X360Settings.h` | the settings and how they apply (shared C: the driver applies them, the app draws with them) |
| `Driver/X360Wire.h` | the receiver's reports and commands |
| `App/` | the menu-bar app: installs the driver, keeps each slot's settings, sends them, shows live state |
| `Sources/X360PadCore` | the settings model (Swift) |
| `Design/` | the app icon's source (`AppIcon.figcraft`, FigCraft) and its 1024 px export; `App/Assets.xcassets` holds the sizes |
| `tools/` | `test_settings.c` (unit tests), `gccheck.swift` (what GameController sees), `ds4rumble.c` (rumble straight to the driver) |

## Requirements

- macOS 15 or later on Apple silicon, the app in `/Applications`.
- A paid developer account with these development capabilities, which Xcode's automatic signing
  enables: on the driver's App ID, DriverKit, DriverKit USB Transport, DriverKit Family HID Device and
  DriverKit Allow Any UserClient; on the app's, System Extension. The development DriverKit profile
  grants `idVendor = *`, so the driver's entitlement says `*` too. Distribution needs Apple's approval
  of the same capabilities.
- The driver is allowed once in System Settings > General > Login Items & Extensions > Driver
  Extensions. While it runs it owns the receiver: nxnative's built-in receiver support and x360w
  cannot open it (they see the DualShock 4 instead).

## Build and install

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then set your DEVELOPMENT_TEAM in it
xcodegen generate
xcodebuild -project X360Pad.xcodeproj -scheme X360Pad -configuration Debug \
  -derivedDataPath build/dd -allowProvisioningUpdates build
ditto "build/dd/Build/Products/Debug/X360 Pad.app" "/Applications/X360 Pad.app"
open "/Applications/X360 Pad.app"     # then Install driver (or launch with X360PAD_INSTALL_DRIVER=1)
```

A new driver version (raise `CURRENT_PROJECT_VERSION` in `project.yml`) replaces the old one once the
old one stops: unplug and replug the receiver with games closed. When the old one stays in
"terminating for upgrade" (`systemextensionsctl list`), a restart clears it.

Tests: `scripts/test.sh`. Driver diagnostics: `ioreg -l | grep X360Pad` (each service's last step and
result; the driver's os_log lines are not always kept). App log:
`/usr/bin/log stream --predicate 'subsystem == "com.hectorviov.x360pad"' --info`.

MIT License; see NOTICE for attributions.
