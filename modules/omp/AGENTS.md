# OMP global instructions

## Ownership

This file is the managed source for OMP global instructions; Hjem installs it at
`~/.omp/agent/AGENTS.md`. Edit this source, not the installed copy. Keep
Codex-specific instructions in `~/.codex/AGENTS.md` and project instructions
agent-neutral: no OMP model roles, reasoning levels, tool names, or execution
policy.

## Managed settings

`modules/omp/config.yml` owns OMP model roles and execution settings. Do not
duplicate or override them in project notes.

- A role's reasoning suffix applies only to that role;
  `defaultThinkingLevel` is the fallback for selections without one.
- Specialized roles are deliberate overrides, not mandatory stages. Changing
  the default does not imply replacing specialized roles.
- Hjem installs `~/.omp/agent/config.yml` as a writable copy but replaces it
  on activation. Persist deliberate changes in the managed source.
- Inspect effective settings with `omp config list --json` without exposing
  secrets. For configuration changes, build the generated Hjem config and smoke
  test it in a temporary agent directory; never use the checked-in module
  directory as `PI_CODING_AGENT_DIR`.
- Nix resolves `@OMP_USER_HOME@` in the YAML template. Mnemopi does not expand
  a literal `~` path.
- Memory uses a reviewed namespace with automatic transcript retention off.
  Retain only selected stable context and keep old stores out of active recall.

## Interactive terminals and sudo

Use OMP's foreground console TTY for `nh os switch` and `nh darwin switch`:
call `bash` with `pty: true`, without `async: true` or output pipes. The
console TTY is the interactive overlay in this OMP session, not a background
`hub` PTY. If no interactive UI is available, stop for user input; do not
silently fall back to a non-interactive command or a new terminal window.

When `HERDR_ENV=1`, immediately before starting or exposing any foreground
console TTY or Herdr-pane operation that will wait for user input, run
`herdr notification show "OMP needs input" --body "Return to the waiting prompt" --sound request`.
This notification is for attention only and must never carry secret content.

For repeated sudo administration, prefer a dedicated Herdr tab after reading
the Herdr skill and checking `HERDR_ENV=1`. Record the tab and pane IDs and
whether this agent created them. Use a temporary root shell only for the
approved work. One-off sudo commands can use the OMP console TTY. The `nh`
switch commands above always use the OMP console TTY.

Tell the user before a password prompt. Let the user type directly into the
visible TTY. Never request, relay, log, or script a password. On success,
failure, or abandonment, preserve verification output, exit temporary root
shells, invalidate sudo credentials locally and on each affected remote host,
and close the Herdr tab only if this agent created it. Do not leave privileged
sessions open while doing unrelated work.

Do not create standalone terminal or Ghostty windows. Do not work around this
rule with `open`, application executables, AppleScript, GUI automation, or
code execution. Use the existing OMP console or the dedicated Herdr tab.
An explicit request for a standalone window requires a deliberate user-approved
policy exception; do not weaken the managed command policy yourself.

Managed TTSR files under `modules/omp/rules/` reinforce this routing. They are
stream-time reminders, not an OS sandbox. `bash.patterns` in the managed
config separately denies common standalone-terminal shell launch commands.

Approved deployments remain subject to the repository's build-before-switch
and explicit approval boundaries.