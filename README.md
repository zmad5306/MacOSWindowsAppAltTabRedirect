# Windows Alt-Tab Redirect

A small macOS menu-bar utility that sends the familiar physical Windows
`Alt+Tab` gesture into a maximized Microsoft Windows App RDP session.

When an RDP session is focused and fills its display, the app maps:

- Left Command + Tab to Option + Tab
- Left Command + Shift + Tab to Option + Shift + Tab

Everywhere else, Command+Tab keeps its normal macOS behavior. The right
Command key and Option+Tab are never captured. While an eligible RDP session
is frontmost, the physical left Command key is mapped at the HID layer to left
Option because Windows App reads physical modifier state. This means other
left-Command combinations inside that session act as left-Option combinations;
right Command remains available for macOS shortcuts.

## Requirements

- macOS 14 or newer
- Microsoft Windows App (`com.microsoft.rdc.macos`)
- Swift command-line tools

## Build and install

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
cp -R "dist/Windows Alt-Tab Redirect.app" /Applications/
open "/Applications/Windows Alt-Tab Redirect.app"
```

On first launch, allow the app in **System Settings > Privacy & Security >
Accessibility**. If macOS does not recognize the newly granted permission,
quit and reopen the app. The utility appears in the menu bar rather than the
Dock.

Launch at Login can be enabled from the menu after the app has been copied to
`/Applications`.

## Session detection

Redirection is active only when Windows App is frontmost and its focused,
titled window looks like a remote session rather than the Windows App home or
settings window. Windows App reports inconsistent accessibility geometry for
maximized sessions, so session-window focus is used as the reliable gate.

The menu-bar item reports the current detection state. Choose **Enabled** to
pause or resume interception.

## Development

```sh
./scripts/test.sh
swift build
```

The build script produces a locally ad-hoc-signed app. Distribution to other
Macs without Gatekeeper warnings requires an Apple Developer ID signature and
notarization.
