# Work Laptop Windows Profile

Microsoft-first native Windows setup for a corporate work laptop. This profile
intentionally avoids third-party window managers, hotkey daemons, and keyboard
remappers. Nix remains the WSL developer-environment layer; native Windows state
is configured with Microsoft-supported tools.

## Scope

Managed here:

- Microsoft packages through WinGet Configuration.
- PowerToys settings through Microsoft DSC v3 resources.
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
- `powertoys.dsc.yaml`: conservative PowerToys DSC v3 settings.
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
.\bootstrap.ps1 -InstallTerminalFragment
```

Add `-AcceptAgreements` to the WinGet steps only after reviewing the YAML.
The Terminal fragment merge creates a timestamped backup next to the existing
Windows Terminal settings file and rewrites the settings as plain JSON. Do not
use it if the company manages Terminal settings through policy.
The managed fragment also sets Windows Terminal itself to follow the Windows
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

## Developer Workflow

Use Windows Terminal plus WSL/NixOS-WSL as the main shell path. The Terminal
fragment maps pane focus and resize to the same `alt-h/j/k/l` and
`alt-shift-h/j/k/l` muscle memory used by AeroSpace on `mini-darwin`, but only
inside Terminal. System-wide window management remains Windows-native:

- `Win+Arrow` for snap.
- `Win+Shift+Arrow` for monitor moves.
- `Win+Ctrl+Left/Right` for virtual desktops.
- PowerToys FancyZones for reusable zones.
