# Security

Please report security issues privately through GitHub Security Advisories for
this repository. Do not include passwords, access tokens, device serial numbers,
or personal logs in a public issue.

The application is local-only: it has no networking code, analytics, updater,
or remote-control interface.

Local automation acts only on this Mac. AppleScript from other apps is gated by
macOS Automation permission. Shortcuts actions run in the app. The Control
Center extension is sandboxed and signals the app with Darwin notifications
(`org.windholm.iScreenMenu.control.*`); any local process can post these, and
they can only toggle the lamp, toggle Keep Awake (which still asks for an
administrator password), apply the saved rotation preset, or open the panel.

