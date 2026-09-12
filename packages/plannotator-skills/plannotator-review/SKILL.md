---
name: plannotator-review
description: Open Plannotator's code-review UI when the user explicitly wants to review the current worktree or a pull request URL in Plannotator instead of inspecting a diff inline.
disable-model-invocation: true
---

# Plannotator Review

Run the command yourself and wait for review to finish:

```bash
plannotator review [optional-pr-url]
```

Without a URL, the target is the current worktree. Address returned feedback or annotations in the same conversation. If the result is an approval or LGTM-style message, acknowledge that review passed and continue.
