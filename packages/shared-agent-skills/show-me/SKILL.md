---
name: show-me
description: Use when the user asks to see, visualize, diagram, or sketch the current topic rather than receive prose alone.
---

# Show Me

Choose the smallest visual that makes the current point clear, and place it next to only the prose needed to interpret it.

- Use pseudocode for logic or algorithms.
- Use a call tree for runtime control flow.
- Use a component tree for UI ownership, state, props, or module boundaries.
- Use a shallow file tree for responsibilities or a broad refactor shape.
- Use Mermaid for relationships, sequence, topology, state, or data flow.
- Use a `diff` when the important point is how an existing shape changes; show the whole block when omitted context would hide ownership or order.

Keep only the calls, files, states, labels, and boundaries relevant to the question. Prefer an inline visual when it is sufficient.

When inline notation is insufficient for a visual UI, layout, state comparison, or dense concept, invoke the shared `html` skill as the router for one focused standalone HTML artifact. Use real labels and data, support desktop and mobile, and open the artifact for the user. Preserve its routing decision: `html-diagram`, `html-plan`, `html-prototype`, and `html-wireframe` are direct-invocation specialists and must be used only when the user explicitly invokes one or the `html` router delegates to it. Do not activate a specialist merely because its format could fit.
