---
description: Do not create standalone terminal windows to obtain a command or sudo session.
condition:
  - >-
    \bopen[ \t]+[^\r\n;]{0,160}(?:[Gg]hostty|[Tt]erminal|i[Tt]erm2?|[Aa]lacritty|[Kk]itty|[Ww]ez[Tt]erm)\.app\b
  - >-
    \bopen[ \t]+[^\r\n;]{0,120}-[A-Za-z]*a[ \t]+["'\\]*(?:[Gg]hostty|[Tt]erminal|i[Tt]erm2?|[Aa]lacritty|[Kk]itty|[Ww]ez[Tt]erm)\b
  - >-
    \bghostty[ \t]+[^\r\n;]{0,120}(?:-e\b|--command\b|\+new-window\b)
  - >-
    tell[ \t]+application[^\r\n]{0,60}(?:[Gg]hostty|[Tt]erminal|i[Tt]erm2?)[^\r\n]{0,120}do[ \t]+script
scope:
  - tool:bash
  - tool:eval
  - tool:hub
interruptMode: always
---

Do not create standalone terminal or Ghostty windows. Use OMP's foreground
console TTY for `nh` switches and one-off sudo. For repeated sudo administration,
use an agent-created Herdr tab and clean it up when the work ends.

Do not evade this restriction through application executables, AppleScript,
GUI automation, code execution, or a different shell wrapper. Inspection of an
existing terminal is not permission to create another window. An explicit user
request for a standalone window requires a deliberate user-approved policy
exception; do not weaken the managed command policy yourself.

TTSR is a stream-time reminder, not a sandbox. Managed `bash.patterns` separately
denies common shell launch routes. Neither mechanism makes arbitrary code
execution an OS-level security boundary.
