# OMP Global Instructions

## Ownership

This file owns global instructions for Oh My Pi (OMP). `nixos-config/modules/omp/AGENTS.md` is the source; Hjem installs it at `~/.omp/agent/AGENTS.md`. Edit the managed source, not the installed file. Keep Codex-specific instructions in `~/.codex/AGENTS.md`; do not use that file as OMP's policy source.

Keep project `AGENTS.md` files agent-neutral. Do not put OMP model roles, reasoning levels, tool names, or execution policy in project instructions.

## Model And Execution Settings

OMP's managed settings in `nixos-config/modules/omp/config.yml` are authoritative for model roles and execution settings. Inherit those settings instead of pinning models or repeating model-specific limits in project notes.

- A role's reasoning suffix applies to that role. `defaultThinkingLevel` is a separate fallback for selections without an explicit level. Do not change that fallback for a role-specific request.
- Specialized roles are deliberate overrides, not required stages for ordinary work. Changing the main default does not mean replacing every specialized role.
- Hjem installs `~/.omp/agent/config.yml` as a writable copy. Activation replaces it from the managed source. Persist deliberate changes in that source.
- Check effective settings with `omp config list --json`; do not expose secrets. Build the generated Hjem config and smoke-test it in a temporary agent directory. Never use the checked-in module directory as `PI_CODING_AGENT_DIR`.
- The YAML template's `@OMP_USER_HOME@` is resolved by the Nix module. Mnemopi does not expand literal `~` paths.
- Memory uses a reviewed namespace with automatic transcript retention disabled. Retain selected stable context explicitly; keep old stores out of active recall.

## Tool Use

Use OMP's language-server `references` action before changing exported symbols. Use `generate_image` when a task calls for generated imagery. Use the `bash` tool with an interactive PTY for approved deployments. Use `hub` process supervision only when a long-running command needs it, and `eval` for quick scripted checks. Follow the repository's deployment approval boundaries.
