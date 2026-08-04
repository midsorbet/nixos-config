---
title: 'nixpkgs#android-tools 36.0.1 on Darwin exposes `adb mdns` syntax but both `adb mdns services`'
severity: 'minor'
---

nixpkgs#android-tools 36.0.1 on Darwin exposes `adb mdns` syntax but both `adb mdns services` and `adb mdns check` fail with `unknown host service`, so wireless discovery needs macOS `dns-sd` or an explicit IP:port.

---
Migrated from PAPERCUTS.md; originally captured 2026-07-18T19:10:31-07:00 by `openai-codex/gpt-5.6-sol`.
