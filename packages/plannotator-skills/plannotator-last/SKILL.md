---
name: plannotator-last
description: Open Plannotator on the latest rendered assistant message when the user explicitly wants to annotate that response, then apply returned feedback.
disable-model-invocation: true
---

# Plannotator Last

Do not send commentary or a status preamble first: it could become the latest rendered assistant message and therefore the wrong review target.

Run the command yourself and wait for the annotation session to finish:

```bash
plannotator last
```

Incorporate returned feedback into the follow-up response. If the session closes without feedback, mention that briefly and continue. An approved result may still include a `"feedback"` field; carry those notes into later work as guidance, but do not redo the approved message as though they were change requests.
