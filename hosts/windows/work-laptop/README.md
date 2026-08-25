# Work Laptop Windows Profile

Microsoft-first native Windows setup for a corporate work laptop. This profile
intentionally avoids third-party window managers, hotkey daemons, and keyboard
remappers. Nix remains the WSL developer-environment layer; native Windows state
is configured with Microsoft-supported tools.

## Scope

Managed here:

- Microsoft packages through WinGet Configuration.
- PowerToys settings through Microsoft DSC v3 resources.
- Command Palette compact-mode settings through a reviewed JSON fragment.
- Windows Terminal keyboard-oriented settings through a reviewed JSON fragment.

Not managed here:

- `komorebi`, `whkd`, `GlazeWM`, `kanata`, AutoHotkey scripts, or other
  third-party desktop-control tools.
- WSL/NixOS-WSL internals. Use the existing `hosts/delcatty` or `hosts/porygon`
  NixOS-WSL host profiles for the Linux development environment.
- Corporate policy, endpoint management, or software approval. If a command is
  blocked by policy, stop and use the approved company path.

## Files

- `configuration.dsc.yaml`: WinGet DSC package baseline for Microsoft tools.
- `powertoys.dsc.yaml`: PowerToys DSC v3 module settings.
- `command-palette.settings.fragment.json`: compact Command Palette settings.
- `terminal-settings.fragment.json`: Windows Terminal settings fragment.
- `bootstrap.ps1`: Windows-side helper for applying and exporting state.

## First Run

From PowerShell on the Windows laptop:

```powershell
cd <path-to-this-directory>
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap.ps1
```

The no-argument run prints checks only. Apply explicit pieces after review:

```powershell
.\bootstrap.ps1 -ApplyPackages
.\bootstrap.ps1 -ApplyPowerToys
.\bootstrap.ps1 -InstallCommandPaletteFragment
.\bootstrap.ps1 -InstallTerminalFragment
```

Add `-AcceptAgreements` to the WinGet steps only after reviewing the YAML.
The Terminal fragment merge creates a timestamped backup next to the existing
Windows Terminal settings file and rewrites the settings as plain JSON. Do not
use it if the company manages Terminal settings through policy.

Command Palette stores its settings outside the PowerToys DSC surface. Start
Command Palette once, close it, and then apply the managed fragment. The merge
creates a timestamped backup and preserves settings not owned by the fragment.

The managed Terminal fragment also sets Windows Terminal itself to follow the
system theme, with `Everforest Light Hard` for light mode and `Kanagawa Wave`
for dark mode.

`Microsoft.WSL` is included in the package baseline because WSL is the intended
developer substrate, but enabling the underlying Windows optional features may
still require admin rights, a reboot, or the company's approved endpoint flow.

## PowerToys Schema Refresh

PowerToys DSC schemas can drift between releases. After PowerToys is installed,
export local schema evidence before adding more settings:

```powershell
.\bootstrap.ps1 -ExportPowerToysSchemas
```

This writes a local `schemas/` directory so future edits can be based on the
actual installed PowerToys version rather than guessed property names.

## Keyboard-Driven Workflow

Use Windows Terminal plus WSL/NixOS-WSL as the main shell path. The Terminal
fragment maps pane focus to `Alt+h/j/k/l` and pane resize to
`Alt+Shift+h/j/k/l`. The focus layer matches Paneru. The shifted layer is
Terminal-specific because Paneru uses those chords to swap windows.

PowerToys and native Windows provide the system-wide layer:

- `Win+Alt+Space` opens Command Palette as a compact search box. PowerToys Run
  is disabled so the profile has one launcher.
- `Alt+backtick` selects the next window from the focused application, and
  `Alt+Shift+backtick` selects the previous one through Window Hopper.
- `Win+Arrow` moves the active window through FancyZones.
- Hold `Alt+X`, then press Left or Right, to rotate open windows across monitors.
- `Win+PgUp/PgDn` cycles windows that occupy the same FancyZone.
- `Win+Ctrl+T` toggles Always On Top for the active window.
- `Win+Shift+;` opens Workspaces. Workspace definitions and captured application
  positions remain user-created.
- `Win+Shift+/` opens Shortcut Guide. Holding either Windows key for 900 ms also
  opens it, and releasing the key closes it.
- `Win+Ctrl+Left/Right` changes the native Windows virtual desktop.

Keyboard Manager is explicitly disabled. The profile does not assign
system-wide Paneru chords to Windows commands with different behavior.
FancyZones provides keyboard placement, but it does not provide spatial focus,
window swaps, direct numbered desktops, or automatic tiling.
