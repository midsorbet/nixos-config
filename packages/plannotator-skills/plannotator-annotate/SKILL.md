---
name: plannotator-annotate
description: Open Plannotator for a file, supported plain-text config, HTML file, URL, or folder when the user explicitly wants annotation or approval in Plannotator rather than inline chat review.
disable-model-invocation: true
---

# Plannotator Annotate

Run the command yourself and wait for the browser session to finish.

For annotation or feedback:

```bash
plannotator annotate <path-or-url>
```

For an explicit review, approval, acceptance, or gate of a generated plan, spec, or document:

```bash
plannotator annotate <path-or-url> --gate --json
```

Plain `annotate` has no **Approve** action. `--json` changes output format; only `--gate` enables approval.

Address returned annotations directly. If the session closes without feedback, say so briefly and continue. In a gated JSON result, `"decision": "approved"` may include `"feedback"`; carry those notes into later work as guidance, but do not revise the approved document as though they were change requests.

If Plannotator cannot resolve the argument to a file, URL, or folder, determine the intended concrete target and rerun it rather than asking the user to invoke shell syntax.
