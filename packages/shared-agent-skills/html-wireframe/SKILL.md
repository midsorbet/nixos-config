---
name: html-wireframe
description: Create a low-fidelity, self-contained HTML wireframe that tests information hierarchy, content, navigation, task flow, and responsive structure. Invoke only by explicit request for html-wireframe or routing from the html skill.
---

# HTML Wireframe

Create a visibly low-fidelity artifact for deciding what belongs on screen and how a bounded task should work. Reuse the project's vocabulary, content model, and accepted constraints; do not make it look finished.

Use html-prototype instead for polished mockups or production-like interaction.

## Route the wireframe work

Read [wireframe workflow](references/wireframe-workflow.md) when structure remains unsettled, comparison directions would aid review, or a short click path is needed. If the user already chose a structure, build that direction only.

## Contract

- Use real labels and representative content where wording affects layout. Do not use lorem ipsum or invent product scope to fill space.
- Keep styling intentionally unfinished: restrained grayscale, system type, plain borders, simple blocks, limited radius, and no brand treatment, gradients, shadows, decorative imagery, or polished component styling.
- Deliver one responsive, self-contained HTML file with essential CSS and JavaScript inline and no build tooling or external service.
- Use semantic landmarks and native controls, visible keyboard focus, useful wide and narrow layouts, and no accidental page-level horizontal overflow.
- Add only behavior needed to review navigation, disclosure, or a short task flow. Remove unrelated controls or label them out of scope.

Inspect the actual file at desktop and mobile widths. Exercise every implemented click path and check reading order, wrapping, overflow, and focus visibility. When comparing directions, confirm that they remain structurally distinct at both sizes. Return the absolute path, direction names and tradeoffs, and visual decisions deferred to a later mockup or prototype.
