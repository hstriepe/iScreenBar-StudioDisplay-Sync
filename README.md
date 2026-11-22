# iScreenBar Menu

English · [简体中文](README.zh-CN.md)

**Screen and Light Controller: Lighting, dual-display synchronization, and Mac auxiliary control—all centralized in the menu bar.**

Originally created to add "screen-off synchronization" for the iScreenBar when used with a Studio Display, this tool has evolved to include brightness synchronization, ambient light rules, automatic color temperature adjustment, and internal display management. This is an independent, unofficial project with no affiliation to BenQ or Apple. The source code for the latest version remains publicly available in this repository under the MIT License.

## Interface and Features

See the [UI Guide](docs/UI-GUIDE.md) and the [Full Feature List](docs/FEATURES.md) for details.

| Module                      | Features                                                     |
| --------------------------- | ------------------------------------------------------------ |
| Quick Controls              | Lighting, ambient light sensing, presence detection, video mode, brightness synchronization, screen-off sync, auto color temperature, dual-display brightness, and "prevent sleep" mode. |
| Light Adjustment            | Control brightness and color temperature (2700–6500K); supports state feedback after physical adjustments. |
| Brightness Sync             | Maintains relative brightness differences across devices (MacBook ↔ Studio Display → iScreenBar). |
| Ambient Light Calibration   | Uses the Studio Display’s built-in sensors to define thresholds for "bright (lights off)" and "dim (lights on)" conditions. |
| Auto Color Temp             | Adjusts color temperature based on the time of day (cooler during the day, warmer at night); does not measure actual ambient color temperature. |
| Internal Display Management | Toggle internal display on/off, rotate (0°/90°/270°), auto-revert after 5 seconds if not confirmed, and restore settings upon external display disconnection. |
| Studio Display "Off"        | Applies a black overlay while preserving window layout; **does not turn off the backlight** (not equivalent to hardware power-saving). |
| Presets                     | Save lighting modes, switch modes based on the active foreground application, and store display rotation presets. |

The icon appears yellow when the light is on, gray when it is off, and red to indicate an issue. Hovering over the icon displays the current brightness and color temperature. The app does not occupy a space in the Dock.

- **Left-click** the icon for a standard menu: Light, Brightness, Color Temperature, Lamp modes, Ambient Rules, Displays (built-in on/off, rotation 0°/90°/180°/270°, Studio Display, rotation preset), Favorites, Keep Awake, Control Panel…, Launch at Login, Help… (a Help window that follows the system light/dark Appearance), and Quit.
- **Right-click** (or Control-click) the icon for the full control panel, which has a **Quit** button at the bottom right.

The interface is in English and Simplified Chinese and follows the macOS language. To use Chinese for this app only, choose it under System Settings › General › Language & Region › Applications, then restart the app.

## Installation

Tested on: Apple Silicon MacBook Pro, macOS 26, Studio Display, and BenQ iScreenBar (USB VID 0x04A5 / PID 0x2501). Other systems and devices have not been fully verified.

Requires full Xcode 26 or later (the Command Line Tools alone are not enough). Install Xcode from the App Store, then run:

```bash
sudo xcode-select -s /Applications/Xcode.app
git clone https://github.com/rogerbush007-a11y/iScreenBar-StudioDisplay-Sync.git
cd iScreenBar-StudioDisplay-Sync
./scripts/install.sh
```

The script builds the Xcode project with an ad-hoc (local) signature, installing the application to `~/Applications/iScreenBar Menu.app`. It also creates a user-level LaunchAgent so the app runs automatically at login. **Launch at Login** in the menu turns that LaunchAgent on or off. Quitting the app keeps it quit until the next login; launchd only restarts it after a crash. If you installed an earlier version, run `./scripts/install.sh` again (or log out and back in) so Quit is not undone by an automatic relaunch. No administrator password is required for the installation; however, the optional "prevent sleep" feature requires administrator authorization.

### Installing without the script

1. Build the app, either in Xcode or with `./scripts/build.sh`, which produces `build/iScreenBar Menu.app`.
2. Drag `iScreenBar Menu.app` into `/Applications` or `~/Applications`.
3. Open it once from Finder. This also lets Shortcuts and Control Center find it.
4. Left-click the menu bar icon and choose **Launch at Login**. This writes the same LaunchAgent the script creates, pointing at the app's current location.

Unlike the script, this doesn't start the LaunchAgent right away. It takes effect at the next login, and until then nothing is written to `~/Library/Logs/iScreenBarMenu.log`. If you move the app afterward, turn Launch at Login off and on again. Don't turn on Launch at Login while running the copy in `build/`, or that copy will start at every login. If an older version with the `local.qiu.iScreenBarStudioSync` agent is still running, log out and back in once.

### Upgrading from iScreen Menu (0.4 and earlier)

Version 0.5 renamed the app from **iScreen Menu** to **iScreenBar Menu** (bundle ID `org.windholm.iScreenBarMenu`). Running `./scripts/install.sh` stops the old app, moves `~/Applications/iScreen Menu.app` to the Trash, and removes its `org.windholm.iScreenMenu` LaunchAgent. On first launch, the app copies your settings (favorites, rotation preset, thresholds) from the old name and replaces the old Launch at Login entry. Some things need updating by hand:

- Control Center: remove the old iScreen Menu controls and add them again from iScreenBar Menu.
- AppleScript: change `tell application "iScreen Menu"` to `tell application "iScreenBar Menu"`.
- Shortcuts: actions from iScreen Menu must be replaced with the iScreenBar Menu actions.
- The log moves to `~/Library/Logs/iScreenBarMenu.log`; the old `iScreenMenu.log` can be deleted.

Daily light control is handled directly via USB HID, independent of the official application. It is recommended to avoid running both this software and the official application simultaneously, as both may attempt to write light settings automatically. Please note that the automatic video mode (linked to the camera) and the hardware-based memory of the light bar are not yet fully synchronized; therefore, this software is not intended as a complete replacement for all official features.

## Usage Guidelines

- Brightness synchronization and the light bar’s built-in ambient light sensor are mutually exclusive; if synchronization is disabled, the current brightness level is maintained.
- Ambient light readings are calculated using the median value over the preceding 10 seconds. It takes approximately 30 seconds to trigger the light to turn off in bright conditions, and about 30 seconds to turn it on when the environment becomes dim. A gradual reactivation after the light has been turned off due to ambient brightness takes approximately 45 seconds. The system employs hysteresis and duration-based logic, meaning state changes do not occur immediately upon crossing a specific threshold.
- When "Rotation Preset" is enabled, the saved angle is applied whenever the Studio Display is connected. When disabled, the angle resets to 0°, and the system will request that it remain at 0° upon reconnection.
- If an external display is disconnected, the system will attempt to force the internal display to resume. While general display configuration operations are designed to avoid interference during screen locking or waking, the restoration process upon disconnection is an exception.
- The "prevent sleep" feature utilizes `caffeinate` and an administrator-authorized `pmset disablesleep` command; the software attempts to release these settings upon closure or exit. Please verify the behavior on your specific machine regarding lid closure, screen locking, and system wake-up.

## Automation

iScreenBar Menu can be controlled from AppleScript, Shortcuts, and (on macOS 26) Control Center. Each setting works exactly like its control panel button, including the same limits: lamp settings need a connected iScreenBar, display settings are unavailable while the Mac is locked, and turning on Keep Awake asks for an administrator password. The app must be running; Shortcuts and AppleScript launch it if it isn't.

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

**Control Center (macOS 26).** Add controls from Control Center › Edit Controls › iScreenBar Menu: Lamp Light, Keep Awake, Rotation Preset, and Control Panel. They're buttons, not switches, and don't show the current state. A control signals the running app, so it does nothing while iScreenBar Menu is quit.

## Verification and Limitations

```bash
./scripts/check.sh
tail -f ~/Library/Logs/iScreenBarMenu.log
launchctl print gui/$(id -u)/org.windholm.iScreenBarMenu
```

Restoring the internal display when the external display is unplugged while the internal display is turned off (2026-10-05) has been confirmed by a user on real hardware. Returning to 0° when the rotation preset is turned off (2026-10-06) has been built and deployed, but still needs another round of plug/unplug testing. Note that a successful build or a successful read-back of system state does not guarantee that the light panel is actually emitting light.

Display control relies on private macOS APIs—SkyLight, MonitorPanel, and DisplayServices—which may require re-testing following system updates. USB command packets are specific to certain light models; compatibility with other ScreenBar models is not guaranteed. The virtual split-screen feature is experimental and not part of the official, production-ready functionality.

## Uninstallation and Development

```bash
./scripts/uninstall.sh
# Build only (without installation):
./scripts/build.sh
```

Uninstallation moves the app and the `LaunchAgent` to the Trash, while preserving log files. Build artifacts are located in `build/iScreenBar Menu.app`.

For development, open `iScreenBarMenu.xcodeproj` in Xcode. The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); after changing `project.yml`, run `xcodegen generate` and commit both. UI text is localized through `iScreenBarMenu/Localizable.xcstrings` (English source, Simplified Chinese translation). Builds are signed ad-hoc by default; to sign with your own certificate, put your settings in a git-ignored `Config/Signing.local.xcconfig` (see `Config/Signing.xcconfig`).

Currently, the app uses a local, temporary signature; it lacks a Developer ID notarization and does not support automatic updates.

The source code contains no network requests, analytics, or cloud-based dependencies. Please refer to the [Security Notice](SECURITY.md), [Trademark Notice](NOTICE.md), and the [MIT License](LICENSE).
