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

The no-argument run prints checks only. Applying these files requires WinGet 1.11 or later
because they use the DSC v3 processor. WinGet supplies the DSC v3 processor package
when configuration is applied; this profile does not install the obsolete WinGet
PowerShell DSC module. Apply explicit pieces after reviewing the YAML:

```powershell
.\bootstrap.ps1 -ApplyPackages
.\bootstrap.ps1 -ApplyPowerToys
.\bootstrap.ps1 -InstallCommandPaletteFragment
.\bootstrap.ps1 -InstallTerminalFragment
```

Add `-AcceptAgreements` to the WinGet steps only after reviewing the YAML.
The Terminal merge parses and validates both JSON documents before changing the
settings file. If the merged content differs, it creates a timestamped backup next
to the existing Windows Terminal settings file and then writes the merged JSON.
If it already matches, it does not rewrite the file or create another backup. Do
not use it if the company manages Terminal settings through policy.

The Terminal merge applies the fragment's top-level `theme`, merges profile
defaults by property, replaces managed color schemes by their `name`, and merges
actions by their `keys`. Unrelated schemes, actions, profile properties, and
other top-level settings remain untouched. It is safe to run repeatedly: managed
schemes and actions are not duplicated. A malformed fragment fails before backup
or write.

Command Palette stores its settings outside the PowerToys DSC surface. Start
Command Palette once, close it, and then apply the managed fragment. The merge
creates a timestamped backup and preserves settings not owned by the fragment.

The managed Terminal fragment sets Windows Terminal itself to follow the system
theme, with `Everforest Light Hard` for light mode and `Kanagawa Wave` for dark
mode.

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

Use Windows Terminal plus WSL/NixOS-WSL as the main shell path. When Herdr runs
inside Terminal, Herdr owns the terminal tabs and panes, so one Terminal window
is enough. The Terminal fragment maps pane focus to `Alt+h/j/k/l` and pane
resize to `Alt+Shift+h/j/k/l`. The focus layer matches Paneru. The shifted layer
is Terminal-specific because Paneru uses those chords to swap windows.

### Desk layout

The work desk has two Dell P2225H monitors side by side. FancyZones spans both
monitors (`fancyzones_span_zones_across_monitors`), so one layout covers both
screens and a window can cover both monitors. Keyboard snapping uses relative
position (`fancyzones_moveWindowsBasedOnPosition`), which enables keyboard
spanning.

Windows switching addresses apps by taskbar position. Pin the apps in this
order: Outlook, Teams, Windows Terminal, IntelliJ IDEA, Chrome, Remote Desktop
Connection. Positions 1 to 5 are on the left half of the keyboard, so the right
index finger can hold `Win` while the left hand selects the app. Remote Desktop
has no comfortable `Win+number` chord; reach it through Command Palette or the
desktop switch.

Default placement on the three virtual desktops:

1. Teams in the left zone and Outlook in the right zone.
2. Terminal and IntelliJ share the left zone. Chrome uses the right zone.
3. Remote Desktop Connection to the build PC.

One-time Windows setup:

1. In Settings > System > Display, give both monitors the same scale and align
   their top edges. Spanning requires equal DPI scaling.
2. In Settings > Personalization > Taskbar > Taskbar behaviors, turn on
   **Show my taskbar on all displays**. The spanned layout uses the bounding
   rectangle of both work areas. Matching taskbars keep zones off the taskbar.
3. In Settings > System > Multitasking > Desktops, set **On the taskbar, show
   all the open windows** to **On all desktops**. Then `Win+number` reaches an
   app on another virtual desktop.
4. On each virtual desktop, open the FancyZones editor with ``Win+Shift+` `` and
   select the **Columns** template with 2 zones. FancyZones keeps a separate
   layout for each virtual desktop.
5. In Remote Desktop Connection, open **Show Options > Local Resources**, set
   **Apply Windows key combinations** to **On this computer**, and save the
   connection. The `.rdp` equivalent is `keyboardhook:i:0`. Windows shortcuts
   then stay on the laptop, including desktop switching from the remote window.
   They no longer reach the build PC.
6. In PowerToys Settings > Window Hopper, set the shortcut to ``Win+Alt+` ``.
   The default ``Alt+` `` takes IntelliJ's VCS Operations Popup. The DSC profile
   does not manage Window Hopper.

### Go60 key positions

The shortcuts target the MoErgo Go60 default layout. Position names follow
MoErgo's `C(column)R(row)` and `T(thumb)` convention; `T1` is the innermost
thumb key.

| Key | Go60 default position | Finger |
| --- | --- | --- |
| `Win` | `RH C2R5`, the bottom-row key below `M` | Right index |
| `Alt` | `RH T3`, outer right thumb key | Right thumb |
| `Ctrl` | `LH T3`, outer left thumb key | Left thumb |
| `Shift` | `LH T2`, middle left thumb key | Left thumb |
| SymbolNav (hold) | `LH T1`, inner left thumb key | Left thumb |
| `Ctrl` inside SymbolNav | `RH C6R4`, the `Keypad` key position | Right pinky |
| Left / Right arrow | SymbolNav `S` / `F` (left) or `J` / `L` (right) | Left ring / left index, or right index / right ring |
| `` ` `` | `LH C4R5`, the bottom-row key below `X` | Left ring |

Custom shortcuts use `Win+Alt+<left-hand key>`: the right hand holds `Win` and
`Alt`, and the left hand taps the action key. Fixed Windows and FancyZones
arrow chords need SymbolNav, so the left thumb cannot also press `Ctrl`; use
the SymbolNav `Ctrl` under the right pinky. Press `Win` as the last modifier in
layered chords. Shortcut Guide opens after `Win` is held for 900 ms.

### Keys

| Keys | Go60 fingering | Action |
| --- | --- | --- |
| `Win+1` to `Win+5` | Right index `Win`, left hand on the number | Open or focus Outlook, Teams, Terminal, IntelliJ, or Chrome. Press again to cycle its windows. |
| `Win+Ctrl+1` to `Win+Ctrl+5` | Add left thumb `Ctrl` | Go to the last active window of that app. |
| `Win+Alt+F` | Right index `Win`, right thumb `Alt`, left index `F` | Next window in the current zone, such as Terminal to IntelliJ. |
| `Win+Alt+Shift+F` | Add left thumb `Shift` | Previous window in the current zone. |
| `Win+Alt+S` | Right index `Win`, right thumb `Alt`, left ring `S` | Command Palette. Type a window title to switch to that window. |
| ``Win+Alt+` `` | Right index `Win`, right thumb `Alt`, left ring `` ` `` | Next window of the same app (Window Hopper). |
| `Win+Alt+W` | Right index `Win`, right thumb `Alt`, left ring `W` | Open Workspaces. |
| ``Win+` `` | Right index `Win`, left ring `` ` `` | Toggle the Terminal quake window on the current desktop. |
| `Win+Left` / `Win+Right` | Hold SymbolNav, right index `Win`, left ring `S` / left index `F` | Move the active window to the left or right zone. |
| `Win+Ctrl+Alt+Right` / `Win+Ctrl+Alt+Left` | Hold SymbolNav, right pinky `Ctrl`, right thumb `Alt`, right index `Win`, left index `F` / left ring `S` | Extend the window across both monitors, or shrink it back. |
| `Win+Ctrl+Left` / `Win+Ctrl+Right` | Hold SymbolNav, right pinky `Ctrl`, right index `Win`, left ring `S` / left index `F` | Previous or next virtual desktop. |
| Hold `Alt+X`, then Left or Right | Right thumb `Alt` and left ring `X`, then hold SymbolNav and tap right `J` / `L` | Rotate open windows across monitors. |
| `Win+Ctrl+T` | Right index `Win`, left thumb `Ctrl`, left index `T` | Toggle Always On Top. |
| `Win+Shift+/` | Right index `Win`, left thumb `Shift`, right pinky `/` | Open Shortcut Guide. Holding `Win` for 900 ms also opens it. |

With relative position, FancyZones handles `Win+Up` and `Win+Down` for every
window it can snap, so these keys no longer maximize or minimize. Each zone
already fills one monitor. The window menu (`Alt+Space`, then `X` or `N`) needs
two right-thumb keys on the Go60 default layout.

Command Palette is the only launcher; PowerToys Run is disabled. Keyboard
Manager is explicitly disabled. The profile does not assign system-wide Paneru
chords to Windows commands with different behavior. PowerToys does not provide
spatial focus, window swaps, direct numbered desktops, per-monitor desktops, or
automatic tiling.

After applying the profile, check these behaviors on the laptop:

- PowerToys Settings reports no shortcut conflicts for `Win+Alt+F`,
  `Win+Alt+Shift+F`, `Win+Alt+S`, ``Win+Alt+` ``, or `Win+Alt+W`.
- `Win+Ctrl+Alt+Right` extends IntelliJ or Terminal across both monitors, and
  `Win+Ctrl+Alt+Left` shrinks it back.
- `Win+Alt+F` switches between Terminal and IntelliJ in the left zone.
- `Win+2` reaches Teams from desktop 2.
- `Alt+X` rotation still works while zones span both monitors.
