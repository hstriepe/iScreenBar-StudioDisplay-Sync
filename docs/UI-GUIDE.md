# iScreen Menu UI Guide

English · [简体中文](UI-GUIDE.zh-CN.md)

This page walks through the control panel from top to bottom. Screenshots of the current panel are still to come; the green-dot and log images in the repository are from an early version and do not show the current interface.

Button names below are the English UI labels. With the app in Chinese, see the Chinese guide for the matching labels.

## 1. Quick Controls

A highlighted button is on; gray means off or unavailable.

| Button | Use |
| --- | --- |
| Light | Turn the lamp on or off manually |
| Auto Light | Let the lamp's own sensor adjust the light; mutually exclusive with Match Screen |
| Presence | Use the lamp's presence detection; set the away delay and sensitivity below |
| Video Mode | Turn on the video lighting mode manually |
| Match Screen | Set the lamp and Studio Display to comfortable brightness first, then turn this on to record the difference |
| Sleep Sync | Turn the lamp off when the Studio Display sleeps and restore it by the rules on wake |
| Auto Temp | Adjust color temperature gradually by local time; the manual color temperature slider is limited while on |
| Link Screens | Sync brightness changes between the MacBook display and Studio Display, keeping the initial difference |
| Keep Awake | Asks for administrator authorization, then enables the forced layer; the display can still sleep normally. Turn it off when done |

## 2. Light Adjustment

The brightness and color temperature sliders show the values read back from the lamp. 1% is the lowest control level, not fully off; to turn the lamp off, use **Light**. Auto Temp follows the time of day; it does not measure ambient color temperature with a sensor.

## 3. Ambient Light Calibration

Click **Bright: Off** when the room is bright enough, and **Dim: On** when you need extra light; each records the current sensor value. The button only highlights briefly on capture, and the saved value stays on the right. **Enable** next to the heading reuses the saved thresholds, so you don't need to recalibrate every day.

"Ambient" is a filtered, relative value from the Studio Display sensor, not a calibrated light meter. Turning off and fast turning on each need about 30 seconds of sustained readings; the gradual turn-on takes about 45 seconds. Between the two points the lamp may keep its current state. Sleep Sync has priority: a darker room cannot turn the lamp on while the display is asleep.

## 4. Presence Detection

On the left is the away delay (3/5/10 minutes); on the right is the sensitivity (Low/Medium/High). While the ambient off-lock is active or the screen is off, the app temporarily pauses presence detection and restores the previous state afterward.

## 5. Displays & Rotation

**Built-in** controls the MacBook's built-in display. It can only be turned off while an external display is connected; unplugging the Studio Display forces the built-in display back on. **Rotate** cycles through 0°, 90°, and 270°, and reverts if you don't confirm within 5 seconds.

**Studio Display** covers the screen with a pure black overlay. Windows don't move, but the backlight stays powered. Double-click the black screen or click the button again to restore.

## 6. Light Presets and Rotation Preset

A light preset saves brightness, color temperature, and video mode, and can be bound to a frontmost app. This is separate from the lamp's own hardware memory.

The rotation preset controls display configuration on its own. With **Enable Preset** on, the saved rotation is applied when the Studio Display connects; with it off, the built-in display returns to 0° landscape and stays there on reconnect. Turning it off does not delete the saved preset.

## Verification status

Restoring the built-in display when the external display is unplugged was confirmed by a user on 2026-10-05. The change that returns to 0° when the rotation auto preset is turned off has been deployed but still needs plug/unplug retesting. Behavior may differ across firmware and macOS versions; when reporting a problem, include the macOS version, device models, steps, and a redacted log.
