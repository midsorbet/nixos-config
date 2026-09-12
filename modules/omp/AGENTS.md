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

Approved deployments require an interactive PTY and remain subject to the
repository's build-before-switch and explicit approval boundaries.
