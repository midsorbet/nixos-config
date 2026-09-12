---
name: write-discoverable-code
description: |
  Guidance for designing names, diagnostics, types, and source placement when
  discoverability is an explicit concern. Helps agents and humans find code
  through search without overriding established repository conventions.
license: MIT
---

# Write Discoverable Code

Apply this guidance when designing names or diagnostics, or when a task
explicitly asks to improve code discoverability. Do not load it automatically
for every code edit. Start with the repository's established vocabulary,
naming, and layout. Improve the specific search path at issue without renaming
stable public APIs or reorganizing unrelated code solely to satisfy this skill.

For naming, type, documentation, string, module, and test-placement guidance,
read [discoverability-rules.md](references/discoverability-rules.md) and apply
only the sections relevant to the task.
