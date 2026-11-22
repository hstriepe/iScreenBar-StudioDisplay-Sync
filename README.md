# iScreenBar Menu

English · [简体中文](README.zh-CN.md)

**A menu bar app that keeps a BenQ iScreenBar in step with an Apple Studio Display, and manages the MacBook's built-in display.**

iScreenBar Menu turns the lamp off when the Studio Display sleeps and back on when it wakes. It can also follow the display's brightness, switch the lamp by room light from the Studio Display's sensor, and shift color temperature with the time of day. It also handles the built-in display (on/off, rotation, restore on unplug) and keep-awake. The lamp is driven directly over USB, so the BenQ app isn't needed.

This is an independent, unofficial project with no affiliation to BenQ or Apple. It started as a fork of [iScreenBar-StudioDisplay-Sync](https://github.com/rogerbush007-a11y/iScreenBar-StudioDisplay-Sync) by rogerbush007-a11y and is released under the MIT License.

## Features

See the [UI Guide](docs/UI-GUIDE.md) and the [Full Feature List](docs/FEATURES.md) for details.

| Area | What it does |
| --- | --- |
| Quick Controls | Light, Auto Light, Presence, Video Mode, Match Screen, Sleep Sync, Auto Temp, Link Screens, Keep Awake |
| Light | Brightness and color temperature (2700–6500 K); reads back changes made on the lamp itself |
| Sleep Sync | Lamp off when the Studio Display sleeps, restored on wake |
| Match Screen / Link Screens | Lamp follows the Studio Display's brightness; MacBook and Studio Display brightness stay linked, keeping the offsets you set |
| Ambient Rules | Turns the lamp **off** when the room is bright and **on** when it's dark, using the Studio Display's light sensor and two thresholds you capture. It switches the lamp; it doesn't dim it |
| Auto Temp | Cooler by day, warmer at night, by local time; it doesn't measure the room's color temperature |
| Built-in Display | On/off, rotation (panel button cycles 0°/90°/270°, menu offers 0°/90°/180°/270°) with a 5-second confirm, forced back on when the external display is unplugged |
| Studio Display button | Black overlay that keeps windows in place; **the backlight stays on** |
| Favorites and Mode Center | Saved light settings, optionally switched by the frontmost app; separate rotation preset applied when the Studio Display connects |
| Keep Awake | Prevents system sleep until you turn it off or quit (asks for an administrator password) |
| Automation | AppleScript, Shortcuts, and Control Center (macOS 26 and later) |

The menu bar icon is yellow when the lamp is on, gray when it's off, and red when something needs attention. Hover over it to see brightness and color temperature. The app has no Dock icon.

- **Left-click** the icon for a standard menu: Light, Brightness, Color Temperature, Lamp, Ambient Rules, Displays, Favorites, Keep Awake, Control Panel…, Launch at Login, Help…, and Quit.
- **Right-click** (or Control-click) for the full control panel. Its **Quit** button is at the bottom right.

The interface is in English and Simplified Chinese and follows the macOS language. To use Chinese for this app only, choose it under System Settings › General › Language & Region › Applications, then restart the app.

## Requirements

- Mac with macOS 14 or later; Control Center controls need macOS 26 or later
- Apple Studio Display
- BenQ iScreenBar (USB VID 0x04A5 / PID 0x2501). Other ScreenBar models aren't supported

Tested on an Apple Silicon MacBook Pro with macOS 26 and 27, a Studio Display (including firmware 17.0), and the iScreenBar. Other setups haven't been fully verified.

## Installation

### Download (recommended)

1. Download the latest DMG from [Releases](https://github.com/hstriepe/iScreenBar-StudioDisplay-Sync/releases). Release builds are signed with a Developer ID and notarized by Apple.
2. Open the DMG and drag **iScreenBar Menu** to `/Applications`.
3. Open the app once from Finder. This also lets Shortcuts and Control Center find it.
4. Left-click the menu bar icon and choose **Launch at Login**.

Launch at Login adds a user LaunchAgent pointing at the app's current location. It takes effect at the next login, and until then nothing is written to `~/Library/Logs/iScreenBarMenu.log`. If you move the app later, turn Launch at Login off and on again. Quitting keeps the app closed until the next login; launchd only restarts it after a crash.

There's no automatic update. To update, quit the app and replace it with the new version.

### Build from source

Requires full Xcode 26 or later (the Command Line Tools alone aren't enough).

```bash
sudo xcode-select -s /Applications/Xcode.app
git clone https://github.com/hstriepe/iScreenBar-StudioDisplay-Sync.git
cd iScreenBar-StudioDisplay-Sync
./scripts/install.sh
```

The script builds the app with an ad-hoc (local) signature, installs it to `~/Applications/iScreenBar Menu.app`, and creates and starts the LaunchAgent right away. No administrator password is needed.

To build without installing, run `./scripts/build.sh` (output: `build/iScreenBar Menu.app`) or build in Xcode, then follow steps 2–4 above. Don't turn on Launch at Login while running the copy in `build/`, or that copy will start at every login.

### Upgrading from iScreen Menu (0.4 and earlier)

Version 0.5 renamed the app from **iScreen Menu** to **iScreenBar Menu** (bundle ID `org.windholm.iScreenBarMenu`). On first launch, the new app copies your settings (favorites, rotation preset, thresholds) from the old name and replaces the old Launch at Login entry. `./scripts/install.sh` also quits the old app and moves `~/Applications/iScreen Menu.app` to the Trash; if you install from the DMG, quit and delete the old app yourself. Then:

- Control Center: remove the old iScreen Menu controls and add them again from iScreenBar Menu.
- AppleScript: change `tell application "iScreen Menu"` to `tell application "iScreenBar Menu"`.
- Shortcuts: replace iScreen Menu actions with the iScreenBar Menu actions.
- The log moves to `~/Library/Logs/iScreenBarMenu.log`; the old `iScreenMenu.log` can be deleted.

If a much older version using the `local.qiu.iScreenBarStudioSync` agent is still running, log out and back in once.

## Using it

### Ambient Rules

1. Open the control panel (right-click the icon).
2. With the room as bright as it gets when you don't need the lamp, click **Bright: Off**.
3. With the room as dark as it gets when you do need the lamp, click **Dim: On**.
4. Turn on **Enable** next to the heading. It stays disabled until at least one threshold is saved.

The "Ambient" value is a 10-second median from the Studio Display's sensor, a relative score rather than lux. The lamp turns off after about 30 seconds above the Bright point and on after about 30 seconds below the Dim point. After a bright turn-off, it also comes back on after about 45 seconds once the room dims a little below the Bright point. Between the two points nothing changes.

Ambient Rules only switch the lamp on and off. To have the lamp **dim** with the room, use **Match Screen** together with automatic brightness for the Studio Display (System Settings › Displays), or use the lamp's own **Auto Light**. Match Screen and Auto Light can't be on at the same time.

### Other notes

- Sleep Sync has priority: a dark room can't turn the lamp on while the display is asleep.
- When Match Screen is turned off, the lamp keeps its current brightness.
- With the rotation preset on, the saved angle is applied whenever the Studio Display connects. With it off, the built-in display returns to 0° and stays there on reconnect.
- When the external display is unplugged, the built-in display is forced back on. Apart from that, the app doesn't reconfigure displays during lock, sleep, or wake.
- Keep Awake uses `caffeinate` and an administrator-authorized `pmset disablesleep`, both released when you turn it off or quit. Check how it behaves with lid closing and locking on your Mac.
- Daily lamp control doesn't need the BenQ app. Avoid running both at once, since both write lamp settings. The camera-linked video mode and the lamp's hardware memory aren't fully mirrored, so this app doesn't replace every official feature.

## Automation

iScreenBar Menu can be controlled from AppleScript, Shortcuts, and (on macOS 26 and later) Control Center. Each setting works exactly like its control panel button, with the same limits: lamp settings need a connected iScreenBar, display settings are unavailable while the Mac is locked, and turning on Keep Awake asks for an administrator password. Shortcuts and AppleScript launch the app if it isn't running.

**AppleScript.** Open the dictionary in Script Editor (File › Open Dictionary… › iScreenBar Menu). Properties: `light`, `brightness` (1–100), `color temperature` (2700–6500 K; Auto Temp must be off), `auto temperature`, `auto light`, `presence`, `video mode`, `match screen`, `link screens`, `sleep sync`, `keep awake`, `builtin display`, and read-only `lamp connected`, `lamp status`, `favorites`, `rotation preset`. Commands: `toggle light`, `apply favorite "Name"`, `apply rotation preset`, `show control panel`. The first time another app sends commands, macOS asks for Automation permission.

```applescript
tell application "iScreenBar Menu"
    set brightness to 60
    set color temperature to 4000
    apply favorite "Night Work"
    get lamp status -- "Light on · 60% · 4000K"
end tell
```

**Shortcuts.** Actions: Set Light, Turn Setting On or Off, Get Setting, Set Lamp Brightness, Set Color Temperature, Apply Favorite, Apply Rotation Preset, Show Control Panel, and Get Lamp Status. Toggle Light, Apply Favorite, Lamp Status, Rotation Preset, and Control Panel are also offered as ready-made shortcuts for Spotlight and Siri.

**Control Center (macOS 26 and later).** Add controls from Control Center › Edit Controls › iScreenBar Menu: Lamp Light, Keep Awake, Rotation Preset, and Control Panel. They're buttons, not switches, and don't show the current state. They do nothing while iScreenBar Menu is quit.

## Troubleshooting and limitations

```bash
tail -f ~/Library/Logs/iScreenBarMenu.log
launchctl print gui/$(id -u)/org.windholm.iScreenBarMenu
```

The log is written only when the app runs from its LaunchAgent; a copy opened from Finder or Xcode logs to its own console.

- Display control uses private macOS frameworks (SkyLight, MonitorPanel, DisplayServices). These can change with macOS updates; the app fails safe and logs when a function is missing.
- Studio Display firmware 17.0 changed the USB ID of the display's light sensor. Version 0.5 (39) and later handle both IDs; older versions show Ambient Light Calibration as disabled.
- The lamp's USB commands are specific to the iScreenBar; other ScreenBar models aren't supported.
- A successful command or status read-back doesn't prove the lamp physically changed.

## Uninstalling

```bash
./scripts/uninstall.sh
```

This moves the app and its LaunchAgent to the Trash and keeps the log. If you installed from the DMG without the repository, turn off Launch at Login, quit the app, and move it to the Trash.

## Development

Open `iScreenBarMenu.xcodeproj` in Xcode. The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); after changing `project.yml`, run `xcodegen generate` and commit both. Run `./scripts/check.sh` before committing; CI runs the same script. UI text is localized through `iScreenBarMenu/Localizable.xcstrings` (English source, Simplified Chinese translation).

Source builds are signed ad-hoc by default. To sign with your own certificate, put your settings in a git-ignored `Config/Signing.local.xcconfig` (see `Config/Signing.xcconfig`).

The app makes no network requests and has no analytics or cloud dependencies. See the [Security Notice](SECURITY.md), [Trademark Notice](NOTICE.md), [Contributing](CONTRIBUTING.md), and the [MIT License](LICENSE).
