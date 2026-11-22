import AppIntents
import SwiftUI
import WidgetKit

// Control Center / menu bar controls (macOS 26+). Stateless buttons: the extension is
// sandboxed and shares no data with the app, so it only signals the running app.

@MainActor
func performControlAction(_ action: ControlAction) {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center, CFNotificationName(action.notificationName as CFString), nil, nil, true)
}

@main
struct IScreenBarMenuControls: WidgetBundle {
    var body: some Widget {
        LightControl()
        KeepAwakeControl()
        RotationPresetControl()
        ControlPanelControl()
    }
}

struct LightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.light") {
            ControlWidgetButton(action: ToggleLightControlIntent()) {
                Label("Light", systemImage: "sun.min.fill")
            }
        }
        .displayName("Lamp Light")
        .description("Turns the iScreenBar on or off.")
    }
}

struct KeepAwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.keepAwake") {
            ControlWidgetButton(action: ToggleKeepAwakeControlIntent()) {
                Label("Keep Awake", systemImage: "cup.and.saucer")
            }
        }
        .displayName("Keep Awake")
        .description("Turns iScreenBar Menu's Keep Awake on or off.")
    }
}

struct RotationPresetControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.rotationPreset") {
            ControlWidgetButton(action: ApplyRotationPresetControlIntent()) {
                Label("Rotation Preset", systemImage: "rotate.right")
            }
        }
        .displayName("Rotation Preset")
        .description("Applies the saved built-in display rotation preset.")
    }
}

struct ControlPanelControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.controlPanel") {
            ControlWidgetButton(action: ShowControlPanelControlIntent()) {
                Label("Control Panel", systemImage: "slider.horizontal.3")
            }
        }
        .displayName("Control Panel")
        .description("Opens the iScreenBar Menu control panel.")
    }
}
