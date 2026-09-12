---
name: html-plan
description: Create a self-contained HTML plan that preserves source material while clarifying hierarchy, sequence, ownership, dependencies, and reviewability. Invoke only by explicit request for html-plan or routing from the html skill.
---

# HTML Plan

Turn supplied material into a plan people can inspect and act on. Preserve the user's scope, ordering, commitments, and terminology unless broader synthesis is requested.

## Route the plan work

Read [plan structure](references/plan-structure.md) when the source includes phases, status, owners, dependencies, risks, acceptance checks, decisions, or unresolved questions. Use only the structures the source supports.

## Contract

- Keep source commitments recognizable and separate accepted decisions from assumptions and open questions.
- Show sequence, ownership, dependency, status, and progress only where supported. Do not invent dates, percentages, scope, or strategy.
- Deliver one responsive, accessible, self-contained HTML file with semantic headings, lists, tables, and landmarks; inline essential CSS and JavaScript and require no external service.
- Keep navigation and disclosure keyboard-operable, long prose readable, and wide content contained.

Inspect the actual file at wide and narrow widths. Confirm that every source commitment remains present, intended order is preserved, ownership and dependencies are legible, navigation works, and long content does not overflow. Return the absolute path and disclose material structural interpretations.
