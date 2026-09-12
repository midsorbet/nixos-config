---
name: html-diagram
description: Create a self-contained HTML diagram that clarifies relationships, sequence, topology, state, hierarchy, or quantitative structure. Invoke only by explicit request for html-diagram or routing from the html skill.
---

# HTML Diagram

Build the smallest visual model that answers the reader's question more clearly than prose. Match notation and visual language to the subject rather than defaulting to generic boxes and arrows.

## Route the diagram work

Choose the form from the question: topology, sequence, process, state, hierarchy, timeline, matrix, or quantitative view. Read [diagram workflow](references/diagram-workflow.md) when choosing the grammar or renderer, or when the diagram needs sequencing, detail-on-demand, pan and zoom, or dense edge routing.

## Contract

- Deliver one self-contained HTML file with essential CSS and JavaScript inline, no build step, and no external service.
- Keep important meaning available without animation, hover, or color alone. Provide accessible text alternatives and keyboard access to controls and revealed details.
- Keep labels, grouping, direction, connectors, and arrowheads legible. Contain intentionally broad canvases in a pan or scroll region rather than causing page overflow.
- Add interaction only when it helps answer the stated question.

Inspect the actual file at wide and narrow widths. Exercise every interactive state and check label collisions, clipped nodes, edge routing, reading order, keyboard operation, overlays, sequence endpoints, and overflow. Return the absolute path, chosen diagram form, and material simplifications or assumptions.
