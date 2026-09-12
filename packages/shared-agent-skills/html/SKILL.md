---
name: html
description: Create or redesign a self-contained single-file HTML artifact. This is the collection's only implicit router for standalone HTML deliverables; do not use it for ordinary application implementation.
---

# HTML

Create one self-contained HTML file that makes the subject clearer or easier to use. Match the user's brief and the project's design language; do not reuse a house style from prior artifacts.

## Route by review question

Use the narrowest owner:

- [`html-wireframe`](../html-wireframe/SKILL.md): unsettled information hierarchy, navigation, task flow, or responsive structure.
- [`html-prototype`](../html-prototype/SKILL.md): a polished mockup or working interactive flow. Mockup is that skill's static fidelity mode.
- [`html-plan`](../html-plan/SKILL.md): a plan, roadmap, rollout, or implementation sequence whose commitments must remain traceable.
- [`html-diagram`](../html-diagram/SKILL.md): relationships, sequence, topology, state, hierarchy, or system behavior.
- Stay here for reports, explainers, presentations, landing pages, data stories, tools, and mixed artifacts without a clearer owner.

These specialists are direct-invocation skills; this router may invoke them. If one is unavailable, stay here and load the closest reference below rather than asking the user to install it.

## Load only relevant guidance

Honor explicit user direction first, then established project conventions, then the artifact's audience and purpose. When visual direction remains open, read [creative direction](references/creative-direction.md).

Read only references that materially apply:

- reports, briefs, explainers, and decks: [documents and presentations](references/documents-and-presentations.md)
- editors, calculators, and other operated tools: [interfaces](references/interfaces.md)
- architecture, process, sequence, state, hierarchy, or concept maps: [diagrams](references/diagrams.md)
- charts, tables, metrics, or data stories: [charts and data](references/charts-and-data.md)

## Contract

- Use real content; mark illustrative data and assumptions. Do not invent prominent claims, metrics, or product scope.
- Inline essential CSS and JavaScript. The file must open directly without a build step and must not require network access unless the user permits external dependencies.
- Use semantic HTML, responsive layout, accessible contrast, visible keyboard focus, keyboard-operable controls, and reduced-motion handling. Avoid accidental page-level horizontal overflow.
- Let structure and interaction serve the content. Do not add dead controls, decorative statistics, or motion that explains nothing.
- Write to the requested location, or use a clear filename in the current workspace.

Verify the actual file in a browser at wide and narrow widths when browser tooling is available. Exercise implemented controls and inspect the console, focus, clipping, overlap, legibility, states, and overflow; fix observed defects. If browser tooling is unavailable, identify the visual or interaction checks that remain unverified. Return the absolute path and a concise description of the result.
