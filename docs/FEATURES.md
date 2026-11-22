# iScreenBar Menu Feature List

English · [简体中文](FEATURES.zh-CN.md)

> Reflects the version currently installed from the `main` branch. This is an unofficial macOS menu-bar utility that runs locally.

## 1. Menu bar and status

- Left-click the menu-bar icon for a standard menu with submenus; right-click (or Control-click) it to open or close the control panel.
- The menu has Launch at Login (user LaunchAgent), Help… (a Help window), and Quit; the panel has a Quit button at the bottom right.
- The icon is yellow when the lamp is on and gray when it is off.
- It turns red when the USB connection or a lamp power command fails.
- Hovering over the icon shows the iScreenBar's current brightness and color temperature.
- Opening the panel reads the lamp state, so the UI matches the actual lamp.
- Starts at login through a user-level LaunchAgent (`org.windholm.iScreenBarMenu`); no administrator rights needed. Quit stays quit until the next login; launchd restarts the app only after a crash.
- The interface is in English and Simplified Chinese and follows the macOS language (including the per-app language setting).

## 2. Basic iScreenBar control

- **Light on/off**: turn the iScreenBar on or off directly.
- **Brightness**: 1%–100%, from the panel slider.
- **Color temperature**: 2700K–6500K in 100K steps.
- **Status readback**: reads power, brightness, main/back light color temperature, auto-light, presence detection, and video mode.
- **Manual changes**: after you change the lamp with its physical buttons, the app reads the state again and refreshes the UI.

## 3. Studio Display sleep sync

- When the Studio Display turns off or sleeps, the iScreenBar turns off.
- When the Studio Display wakes, the lamp turns back on if this app turned it off.
- While the screen is off, sleep sync has top priority: lamp auto-light, presence detection, or other logic must not turn the lamp back on.
- The **Sleep Sync** button turns this feature on or off.
- During lock and wake, all built-in display topology changes are paused to avoid conflicts with WindowServer's unlock transition.

## 4. iScreenBar brightness follows the Studio Display

- Turning on **Match Screen** records the current brightness difference between the iScreenBar and the Studio Display.
- After that, changing the Studio Display brightness changes the iScreenBar by the same difference.
- The iScreenBar's 1% minimum is kept.
- When turned off, the lamp keeps its current brightness instead of returning to an old value.
- Lamp auto-light and this feature are mutually exclusive: turning one on turns the other off, so two brightness sources never control the lamp at once.

## 5. MacBook and Studio Display brightness lock

- Turning on **Link Screens** records the current brightness difference between the MacBook display and the Studio Display.
- Works both ways: change either display and the other follows by the same difference.
- Uses a 0.6-second write debounce and source tracking so the two displays don't write back to each other in a loop.
- Pauses automatically when the lid is closed, the built-in display is unavailable, the Studio Display is asleep, or macOS is locked.
- Resumes with the recorded difference once both displays are back.
- With **Match Screen** also on, this links all three: `MacBook ↔ Studio Display → iScreenBar`.

## 6. Lamp auto-light

- Turn the iScreenBar's built-in ambient light sensor on or off from the panel.
- On uses the lamp's official auto-light state; off writes the current manual brightness to exit auto mode.
- The UI shows the state read back from the lamp, including a short transition while the command is confirmed.
- Known firmware behavior: the physical auto-light button can enter or recalibrate auto mode but doesn't always exit it reliably; the panel runs a verifiable turn-off sequence.

## 7. Studio Display ambient calibration and automatic on/off

- Reads the Studio Display's ambient light sensor directly; the lamp's sensor is not used for these rules.
- Uses the median of the last 10 seconds of samples as the "ambient score", to smooth out brief changes in light.
- **Bright: Off point**: click to capture the current value; above it for 30 seconds turns the lamp off.
- **Dim: On point**: click to capture the current value; below it for about 30 seconds turns the lamp on.
- After an ambient turn-off there is also a gradual turn-on path of about 45 seconds that tolerates small fluctuations, avoiding flicker or the lamp staying off too long.
- The two points are independent; you don't have to set both.
- The calibration buttons light up briefly only when a capture succeeds; the saved value stays next to them.
- A separate **Enable** switch decides whether the saved thresholds are used; turning it off does not delete them.
- If the on point is at or above the off point, the UI warns that the thresholds overlap.
- While the ambient off-lock is active, lamp auto-light and presence detection cannot turn the lamp back on.
- If presence detection was on before the turn-off, it is paused temporarily and restored when the ambient off-lock is released.
- Sleep sync takes priority over ambient rules: while the screen is off, a darker room does not turn the lamp on.

## 8. Presence / away detection

- Turn the lamp's presence detection on or off from the panel.
- Away delay: 3, 5, or 10 minutes.
- Sensitivity: Low, Medium, or High.
- Settings are sent to the lamp when it supports them; if sending fails, the local choice is kept and logged.
- Works with the ambient off-lock so the lamp doesn't turn back on as soon as you move after it switched off.

## 9. Video mode

- Turn the iScreenBar's video mode on or off from the panel.
- Video mode is read back from the lamp and can be saved as part of a light preset.

## 10. Auto color temperature

- **Auto Temp** adjusts the lamp's color temperature smoothly by time of day.
- 00:00–06:00: 3000K.
- 06:00–10:00: gradually from 3000K to 5500K.
- 10:00–16:00: 5500K.
- 16:00–21:00: gradually from 5500K to 3500K.
- 21:00–24:00: gradually from 3500K to 3000K.
- Transitions use 50K internal steps and write to the lamp at most once a minute.
- No color temperature is written while the lamp is off or the Studio Display is asleep.
- Turning Auto Temp off keeps the current color temperature.

## 11. Light presets

- Built-in **Favorite** default: 47% / 5500K / video mode off.
- Built-in **Night Work**: 30% / 4000K / video mode off.
- Built-in **Wind Down**: 20% / 3000K / video mode off.
- Save the current brightness, color temperature, and video mode as a custom scene.
- **Mode Center** lists the available modes for quick use.
- Applying a preset turns the lamp on, writes brightness and color temperature, sets video mode, and turns off iScreenBar Match Screen.
- Bind the current light mode to a macOS app; the matching mode is applied when that app comes to the front.

## 12. MacBook built-in display on/off and rotation

- Enable or disable the MacBook's built-in display from the panel.
- The rotate button cycles `0° → 90° → 270° → 0°`.
- Save a rotation preset that records built-in on/off, rotation, and whether it is the main display.
- Optionally apply the rotation preset automatically when the Studio Display connects.
- Turning the auto preset off returns to 0° landscape and also requests 0° when the Studio Display reconnects; the old 270° baseline is no longer applied.
- Manual rotation must be confirmed within 5 seconds, or the previous rotation is requested again.
- After the Studio Display disconnects, the app waits to confirm the connection state, then restores the built-in display on, at 0°, with the default main display layout.
- Normal operations pause during lock, display sleep, and the settle period after wake; forcing the built-in display back on after an external disconnect is the safety exception.
- Quitting the app no longer forces a built-in display state.

## 13. USB disconnect, reconnect, and fault tolerance

- Checks the iScreenBar USB HID connection every 2 seconds.
- When the lamp is unplugged, loses power, or HID commands fail, the icon turns red and the event is logged.
- After the lamp is plugged back in, the app rebuilds the HID manager, reads the state again, and restores sleep sync and the Match Screen lock.
- When the Studio Display disconnects, the app keeps running and rebuilds display monitoring and the ambient light sensor connection when it returns.
- All key states and errors are written to `~/Library/Logs/iScreenBarMenu.log`.

## 14. Interface and interaction

- Native AppKit menu-bar popover; no Dock icon.
- Quick controls use a compact button grid: system gray when off, accent color with SF Symbols when on.
- The brightness and color temperature sliders show a colored highlight while dragging and return to a static style on release.
- The color temperature slider has 5 common tick marks.
- Unavailable features gray out their buttons to avoid mistakes when the lid is closed, the Mac is locked, or a device is offline.
- The Help window (Help… in the menu) is localized (English / Simplified Chinese). It follows the system light/dark Appearance, including a switch while it's open.
- ⌘W closes the app's windows, ⌘C / ⌘A work in Help, and ⌘Q quits.

## 15. Local storage, privacy, and installation

- All switches, thresholds, presets, app bindings, and brightness lock states are stored locally in `UserDefaults`.
- No account, cloud service, network API, or analytics.
- The install script builds the Xcode project locally with an ad-hoc signature, installs to `~/Applications`, and creates a user-level LaunchAgent. Full Xcode is required.
- The uninstall script stops the service and moves the installed app and LaunchAgent to the Trash; logs are kept for troubleshooting.

## 16. Implementation limits and risks

- Verified on an Apple Silicon Mac with macOS 26, Apple Studio Display, and BenQ iScreenBar `VID 0x04A5 / PID 0x2501`.
- iScreenBar control uses device-specific 33-byte HID reports; other models are not guaranteed to work.
- Display brightness uses DisplayServices; built-in display on/off, rotation, and main display settings use the private macOS SkyLight/MonitorPanel interfaces.
- macOS updates can change private interface behavior, so display topology features need retesting on real hardware.
- The Studio Display is identified by Apple vendor ID 0x0610 and a known model number (0xAE46 or 0xAE3A), not by picking the largest external display.
- Some details of lamp auto-light and presence detection depend on the lamp firmware version.

## 17. Feature priority

1. macOS lock / display sleep safety: normal display configuration writes are paused, except restoring the built-in display after an external disconnect.
2. Studio Display sleep sync: the lamp stays off while the screen is off.
3. Studio Display ambient off-lock: after the bright threshold is reached, presence detection and auto-light cannot turn the lamp back on.
4. Lamp auto-light and iScreenBar Match Screen are mutually exclusive.
5. Link Screens only adjusts the MacBook display and the Studio Display; to have the lamp follow too, also turn on iScreenBar **Match Screen**.

## 18. Differences from BenQ's official iScreenBar app

> Based on BenQ's official iScreenBar product page, quick start guide, and published feature descriptions. The official app changes by region and version; this comparison reflects public information as of August 2026 and the official app on the author's Mac.

### 18.1 Features both have

| Feature | BenQ official app | This utility | Main difference |
| --- | --- | --- | --- |
| Light on/off | Yes | Yes | This utility adds a red USB-offline state and reconnect recovery. |
| Brightness and color temperature | Yes | Yes | Official: stepless 0–100% brightness, 2700K–6500K; this utility writes the levels the lamp's HID interface can verify. |
| Auto-light | Yes | Yes | Both use the lamp's ambient light sensor; this utility also handles exclusion with Match Screen. |
| Presence detection | Yes | Yes | Official uses a 24 GHz mmWave sensor with adjustable detection range; this utility offers away delay and sensitivity. |
| Video mode | Yes | Yes | Official can enable it automatically with the iMac camera; this utility relies on the manual switch and presets. |
| Light modes | Yes | Yes | Both save combinations of brightness, color temperature, and more. |
| Per-app modes | Yes | Yes | Both apply the matching light mode when the frontmost app changes. |
| Light follows display power | Yes | Yes | Official targets compatible iMacs; this utility covers the standalone Studio Display sleep case. |

### 18.2 What this utility adds

- **Studio Display support**: the official compatibility list covers 2021 and later iMacs, not the Apple Studio Display; this utility watches the Studio Display's sleep, screen-off, wake, and reconnect events.
- **Lamp follows Studio Display brightness**: keeps the current difference between lamp and display, so adjusting the Studio Display changes the iScreenBar too.
- **Two-way MacBook / Studio Display brightness lock**: change either display and the other follows by the same difference, optionally driving the lamp as well.
- **Studio Display ambient thresholds**: capture a "bright: off" point and a "dim: on" point separately; the lamp switches automatically using a median, duration, and priority rules.
- **Auto color temperature**: changes smoothly between 3000K and 5500K over the day instead of relying only on manual levels or fixed modes.
- **MacBook built-in display management**: on/off, 0°/90°/270° rotation, main display setting, layout presets, and safe recovery after the external display disconnects.
- **Visible health status**: the menu-bar icon shows lamp on, off, and error as yellow, gray, and red, and shows brightness and color temperature on hover.
- **Clear rule priority**: explicit exclusion and restore rules between lock/screen-off, ambient off-lock, presence detection, auto-light, and Match Screen.
- **USB fault tolerance and logs**: rebuilds the HID manager after the lamp is unplugged and replugged, and keeps a local log for troubleshooting.
- **Local and auditable**: settings stay on the Mac, with no account, cloud, or analytics; the source for the latest enhancements is public in the original project.

### 18.3 Where the official app is currently stronger

- **Official signing, releases, and firmware support**: BenQ maintains the official app, with formal support for firmware updates, regional versions, and lamp protocol changes.
- **Native iMac compatibility**: designed for the hardware, power, camera, and wake flow of 2021 and later iMacs, with clearer compatibility limits.
- **Automatic video mode with the camera**: official documentation says camera mode can turn on automatically when connected over iMac USB-C; this utility does not yet detect camera use reliably.
- **Official lamp memory**: the lamp's own "favorite/memory" is managed by firmware; this utility's presets are mainly stored in the Mac's `UserDefaults`, which is not the same hardware memory.
- **Polish and support channels**: onboarding, updates, signing, notarization, customer service, and warranty support are more complete in the official app.
- **Lower OS-update risk**: this utility's display rotation, built-in display on/off, and some display controls rely on private macOS interfaces and need retesting after system updates.

### 18.4 Not yet matched or still to verify

- Switching to video mode automatically when the camera turns on.
- The protocol for reading, overwriting, and recalling the lamp's "favorite" hardware memory from the official app.
- All official presence-detection time options and the sensitivity mapping across firmware versions.
- Exact behavior of official per-app modes when apps quit, go full screen, across multiple Spaces, and with multiple user sessions.
- Developer ID signing, notarization, automatic updates, and a one-click install for regular users.

### 18.5 In one sentence

**The official app is BenQ's complete control software for compatible iMacs; this utility keeps the main lamp controls and adds what Studio Display and MacBook multi-display setups need: sleep sync, brightness linking, ambient light rules, built-in display rotation, and fault recovery.**

### 18.6 Official references

- [BenQ iScreenBar product page](https://www.benq.com/en-us/lighting/monitor-light/iscreenbar.html)
- [BenQ iScreenBar quick start guide](https://www.benq.com/en-us/qsg/iscreenbar/guide.html)
- [BenQ iScreenBar specifications and compatible models](https://www.benq.com/en-us/lighting/monitor-light/iscreenbar/spec.html)

## 19. Automation

- **AppleScript:** scripting dictionary `iScreenBarMenu.sdef`. Properties for Light, Brightness, Color Temperature, Auto Temp, Auto Light, Presence, Video Mode, Match Screen, Link Screens, Sleep Sync, Keep Awake, and the built-in display, plus read-only lamp connection, status, favorites, and rotation preset name. Commands: `toggle light`, `apply favorite`, `apply rotation preset`, `show control panel`. Failures return a script error with the reason (for example, lamp not connected).
- **Shortcuts (App Intents, macOS 14+):** Set Light, Turn Setting On or Off, Get Setting, Set Lamp Brightness, Set Color Temperature, Apply Favorite, Apply Rotation Preset, Show Control Panel, Get Lamp Status. Five ready-made shortcuts for Spotlight and Siri. Localized in English and Simplified Chinese.
- **Control Center (macOS 26):** a sandboxed widget extension with four buttons: Lamp Light (toggle), Keep Awake (toggle), Rotation Preset, Control Panel. They don't show state and only work while the app is running.
- Every path sets the panel control and runs its own action, so automation has the same side effects, saving, and limits as clicking the button.
