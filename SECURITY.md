# Security

Please report security issues privately through GitHub Security Advisories for
this repository. Do not include passwords, access tokens, device serial numbers,
or personal logs in a public issue.

The application is local-only: it has no networking code, analytics, updater,
or remote-control interface.

Local automation acts only on this Mac. AppleScript from other apps is gated by
macOS Automation permission. Shortcuts actions run in the app. The Control
Center extension is sandboxed and signals the app with Darwin notifications
(`org.windholm.iScreenBarMenu.control.*`); any local process can post these, and
they can only toggle the lamp, set or step its brightness and color temperature,
toggle Keep Awake (which still asks for an administrator password), apply the
saved rotation preset, or open the panel. The app publishes the lamp's on/off,
brightness, and color temperature as the state of
`org.windholm.iScreenBarMenu.state` for the widget; any local process can read it.

