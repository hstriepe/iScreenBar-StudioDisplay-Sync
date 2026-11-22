import AppIntents
import SwiftUI
import WidgetKit

// Control Center / menu bar controls and a desktop widget (macOS 26+). The extension is
// sandboxed and shares no data with the app: actions are Darwin notifications, and the
// lamp state comes from the app's published notify state (Shared/LampState.swift).

/// Signals the app, then waits briefly for its published state to change so the widget
/// reload that follows an intent shows the new values.
@MainActor
func performControlAction(_ action: ControlAction) async {
    let before = LampState.current()
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center, CFNotificationName(action.notificationName as CFString), nil, nil, true)
    guard before.isAppRunning else { return }
    for _ in 0..<10 {
        try? await Task.sleep(for: .milliseconds(100))
        if LampState.current() != before { return }
    }
}

@main
struct IScreenBarMenuControls: WidgetBundle {
    var body: some Widget {
        LampLevelsWidget()
        LightControl()
        KeepAwakeControl()
        RotationPresetControl()
        ControlPanelControl()
        BrightnessDownControl()
        BrightnessUpControl()
        WarmerControl()
        CoolerControl()
    }
}

// MARK: - Control Center

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

struct BrightnessDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.brightnessDown") {
            ControlWidgetButton(action: StepBrightnessControlIntent(.down)) {
                Label("Dimmer", systemImage: "sun.min")
            }
        }
        .displayName("Lamp Dimmer")
        .description("Lowers the iScreenBar brightness by 10%.")
    }
}

struct BrightnessUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.brightnessUp") {
            ControlWidgetButton(action: StepBrightnessControlIntent(.up)) {
                Label("Brighter", systemImage: "sun.max.fill")
            }
        }
        .displayName("Lamp Brighter")
        .description("Raises the iScreenBar brightness by 10%.")
    }
}

struct WarmerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.warmer") {
            ControlWidgetButton(action: StepTemperatureControlIntent(.down)) {
                Label("Warmer", systemImage: "thermometer.low")
            }
        }
        .displayName("Lamp Warmer")
        .description("Lowers the iScreenBar color temperature by 500 K.")
    }
}

struct CoolerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "org.windholm.iScreenBarMenu.Controls.cooler") {
            ControlWidgetButton(action: StepTemperatureControlIntent(.up)) {
                Label("Cooler", systemImage: "thermometer.high")
            }
        }
        .displayName("Lamp Cooler")
        .description("Raises the iScreenBar color temperature by 500 K.")
    }
}

// MARK: - Desktop / Notification Center widget

struct LampEntry: TimelineEntry {
    let date: Date
    let state: LampState
}

struct LampProvider: TimelineProvider {
    func placeholder(in context: Context) -> LampEntry {
        LampEntry(date: .now, state: LampState(isAppRunning: true, isConnected: true, isPowerOn: true,
                                               brightness: 60, temperature: 4400))
    }

    func getSnapshot(in context: Context, completion: @escaping (LampEntry) -> Void) {
        let state = LampState.current()
        completion(context.isPreview && !state.isAppRunning ? placeholder(in: context) : LampEntry(date: .now, state: state))
    }

    // The app reloads this widget whenever it publishes a new state.
    func getTimeline(in context: Context, completion: @escaping (Timeline<LampEntry>) -> Void) {
        completion(Timeline(entries: [LampEntry(date: .now, state: LampState.current())], policy: .never))
    }
}

struct LampLevelsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LampState.widgetKind, provider: LampProvider()) { entry in
            LampLevelsView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Lamp Levels")
        .description("Sets the iScreenBar brightness and color temperature.")
        .supportedFamilies([.systemMedium])
    }
}

struct LampLevelsView: View {
    let state: LampState

    private var lampAvailable: Bool { state.isAppRunning && state.isConnected }

    private var statusText: Text {
        if !state.isAppRunning { return Text("iScreenBar Menu isn't running") }
        if !state.isConnected { return Text("iScreenBar not connected") }
        let brightness = state.brightness.map { "\($0)%" } ?? "--%"
        let temperature = state.temperature.map { "\($0)K" } ?? "----K"
        return Text(verbatim: "\(brightness) · \(temperature)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("iScreenBar")
                    .font(.headline)
                statusText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(intent: ToggleLightControlIntent()) {
                    Image(systemName: "power")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(state.isPowerOn && lampAvailable ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!lampAvailable)
                .accessibilityLabel(Text("Light"))
            }
            levelRow(symbol: "sun.max", label: Text("Brightness")) { brightnessSegments }
                .disabled(!lampAvailable)
            levelRow(symbol: "thermometer.medium", label: Text("Color Temp")) { temperatureSegments }
                .disabled(!lampAvailable || state.isAutoTemperatureOn)
            if lampAvailable, state.isAutoTemperatureOn {
                Text("Auto Temp is on")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(lampAvailable ? 1 : 0.6)
    }

    private func levelRow<Content: View>(symbol: String, label: Text, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityLabel(label)
            HStack(spacing: 3) { content() }
        }
    }

    private var brightnessSegments: some View {
        ForEach(LampState.brightnessSteps, id: \.self) { step in
            let filled = (state.brightness ?? 0) >= step - LampState.brightnessStep / 2
            Button(intent: SetBrightnessControlIntent(step)) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(filled ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(step)%"))
        }
    }

    private var temperatureSegments: some View {
        let selected = state.temperature.flatMap { current in
            LampState.temperatureSteps.min { abs($0 - current) < abs($1 - current) }
        }
        return ForEach(Array(LampState.temperatureSteps.enumerated()), id: \.element) { index, step in
            let fraction = Double(index) / Double(LampState.temperatureSteps.count - 1)
            let color = Color(hue: 0.09 + 0.5 * fraction, saturation: 0.75 - 0.45 * fraction, brightness: 1)
            Button(intent: SetTemperatureControlIntent(step)) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(step == selected ? 1 : 0.35))
                    .overlay {
                        if step == selected {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                        }
                    }
                    .frame(height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(step)K"))
        }
    }
}
