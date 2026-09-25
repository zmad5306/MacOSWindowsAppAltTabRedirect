# Windows Alt-Tab Redirect

A native macOS menu-bar utility that makes physical **Left Command+Tab**
switch applications inside a maximized Microsoft Windows App RDP session.

When an eligible remote session is focused, the app maps:

- Left Command+Tab to Left Option+Tab
- Left Command+Shift+Tab to Left Option+Shift+Tab

Outside that session, macOS Command+Tab works normally. Right Command,
physical Option+Tab, and other Left Command shortcuts such as Command+C and
Command+V are unchanged.

## Why Karabiner-Elements is required

Microsoft Windows App reads modifier keys below the normal macOS event-tap
layer. Synthetic or rewritten Option events reach the remote desktop as plain
Tab, so the remap must happen through a virtual HID keyboard.

[Karabiner-Elements](https://karabiner-elements.pqrs.org/) provides that virtual
keyboard. This utility supplies the session detection and sets a Karabiner
variable only while the correct RDP window is focused and maximized. The
Karabiner rule itself also checks that Windows App is frontmost.

## Requirements

- macOS 14 or newer
- Microsoft Windows App (`com.microsoft.rdc.macos`)
- Karabiner-Elements 16 or newer
- Swift command-line tools or Xcode to build from source

## 1. Install and authorize Karabiner-Elements

Install Karabiner with Homebrew:

```sh
brew install --cask karabiner-elements
```

Alternatively, download its installer from the
[official installation page](https://karabiner-elements.pqrs.org/docs/getting-started/installation/).

Open **Karabiner-Elements** and complete every item under **Setup**:

1. In **System Settings > General > Login Items & Extensions**, enable:
   - Karabiner-Elements Non-Privileged Agents v2
   - Karabiner-Elements Privileged Daemons v2
2. In **System Settings > Privacy & Security > Accessibility** (called
   **Device Control and Data Access** on some macOS versions), enable
   **Karabiner-Core-Service**.
3. If Karabiner requests Input Monitoring or **Capture Input Events**, grant
   it. Newer Karabiner versions may satisfy this with Accessibility access.
4. In **System Settings > General > Login Items & Extensions > Extensions**,
   open **.Karabiner-VirtualHIDDevice-Manager**, turn on **Driver Extension**,
   authenticate, and click **Done**.

Karabiner's Setup page should no longer report a missing permission or driver.
Its background services and virtual keyboard start automatically with macOS.

## 2. Build and install the utility

From the repository root:

```sh
chmod +x scripts/build-app.sh scripts/test.sh
./scripts/test.sh
./scripts/build-app.sh
ditto "dist/Windows Alt-Tab Redirect.app" \
  "/Applications/Windows Alt-Tab Redirect.app"
open "/Applications/Windows Alt-Tab Redirect.app"
```

The app appears only in the menu bar. It does not have a Dock icon.

On first launch, enable **Windows Alt-Tab Redirect** in **System Settings >
Privacy & Security > Accessibility** (or **Device Control and Data Access**),
then quit and reopen the app if its menu still says permission is required.

The build is ad-hoc signed. Rebuilding changes its signature and can invalidate
the previous Accessibility approval. If that happens, remove and re-add the
app in Accessibility settings, or reset only its stale record before launching
the new build:

```sh
tccutil reset Accessibility com.local.WindowsAltTabRedirect
open "/Applications/Windows Alt-Tab Redirect.app"
```

Then turn its newly created Accessibility entry on.

## 3. Enable automatic startup

Open the utility's menu-bar menu and enable **Launch at Login**. This uses
macOS `SMAppService`; the app will appear under **System Settings > General >
Login Items**.

For automatic operation after a reboot, all of these must remain enabled:

- Windows Alt-Tab Redirect under Open at Login
- Both Karabiner background services
- Karabiner-Core-Service Accessibility access
- The Karabiner virtual HID Driver Extension

## How it works

The utility watches the frontmost application and the focused accessibility
window. Redirection becomes active only when:

- the utility is enabled;
- Microsoft Windows App is frontmost;
- the focused window looks like an RDP session rather than the Windows App
  home or settings window; and
- the window is native full screen or fills its display's frame/visible frame
  within a small geometry tolerance.

The app creates one rule named **Windows Alt-Tab Redirect (managed)** in the
selected Karabiner profile. It sets the variable
`windows_alt_tab_redirect_active` to `1` only while the session is eligible,
and resets it to `0` when focus leaves the session, the app is paused, or the
app quits.

On a fresh Karabiner installation, the app creates a default profile. If a
Karabiner configuration already exists, it preserves the selected profile and
adds/replaces only its managed rule. Before its first edit, it saves:

```text
~/.config/karabiner/karabiner.json.windows-alt-tab-redirect.backup
```

## Verify the installation

1. Open an RDP session in Windows App and maximize it or enter full screen.
2. Confirm the menu-bar status says **Redirecting Command+Tab**.
3. Press Left Command+Tab. Windows should switch applications inside the VM.
4. Press Left Command+Shift+Tab to switch in reverse.
5. Verify Left Command+C and Left Command+V still work normally.
6. Leave Windows App or make the RDP window non-maximized. Command+Tab should
   return to the macOS application switcher.

## Troubleshooting

- **Karabiner setup required:** Open Karabiner-Elements and finish every Setup
  item. Confirm its Driver Extension is on.
- **Accessibility permission required:** Enable Windows Alt-Tab Redirect in
  Privacy & Security, then relaunch it.
- **Command+Tab opens the macOS app switcher:** The helper is not running, is
  paused, or does not consider the current RDP window maximized.
- **Command+Tab only moves focus with Tab inside Windows:** The virtual HID
  driver or managed Karabiner rule is not active. Recheck Karabiner Setup and
  restart both apps.
- **A rebuild stops working:** Reset/re-add the helper's Accessibility entry as
  described above; ad-hoc signatures change with each build.
- **Inspect status:** Runtime diagnostics are written to
  `/tmp/windows-alt-tab-redirect-status.txt`.

## Development

```sh
./scripts/test.sh
swift build
```

The build script creates `dist/Windows Alt-Tab Redirect.app` and applies an
ad-hoc signature. Public distribution requires an Apple Developer ID
signature and notarization. Karabiner-Elements remains a runtime dependency.
