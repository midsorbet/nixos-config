---
name: meal-prep-runbook
description: "Create ADHD-friendly, mobile meal-prep runbooks from structured meal-plan JSON, with explicit ingredient destinations, retrieval cues, board release gates, dish budgets, quantities, and synchronized source data."
---

# Meal-Prep Runbook

Use this skill when creating or revising a mobile kitchen runbook from a structured weekly meal plan.

## Source of truth

1. Read the active meal-plan JSON, recipe quantities, scheduled cook session, inventory, appliance limits, and thaw reminders.
2. Derive the HTML task order from the JSON. If the runbook improves the workflow, write the same task IDs, order, quantities, destinations, and constraints back into the JSON in the same change.
3. Verify exact task-ID and task-order parity between JSON and HTML.

## Destination-first staging

- Every ingredient-prep action must say both `FOR` (recipe/component) and `PARK` (exact labeled container, jar, lid, plate, strainer, pan, or appliance).
- Show a parking map before the checklist begins.
- Use short labels such as `PEANUT SAUCE JAR`, `FILLINGS — DINNER`, `SATURDAY GREENS`, or `SHRIMP — SPLIT NEXT`.
- Put grated garlic, ginger, citrus juice, and other easy-to-forget aromatics directly into their final sauce jar or recipe container. Never use a generic aromatic pile.
- Later cook and assembly steps must repeat the same parking label when retrieving each staged ingredient.

## One-board and limited-dish rules

- Treat the sole cutting board as a constrained resource.
- Add a visible `Board release gate` listing every remaining knife and citrus-cutting task. Do not instruct the cook to wash or park the board before all listed tasks are complete.
- Declare a dish budget before prep. Prefer food-storage containers and their lids as prep trays.
- Do not consume an extra plate unless the runbook names its later use.
- State the exact cleanup list and when each tool can safely be washed.

## Quantities and working memory

- Put raw weights at wash/chop steps, not only in later recipe references.
- Put estimated cooked yields at the step where cooking completes.
- Put per-container or per-roll targets at the split/assembly step.
- Label estimates clearly and state that actual measured yield wins.
- Keep timer behavior manual unless the user asks for built-in timers; tell the cook when to set one.

## Appliance and storage gates

- Show which appliances are active, parked, and mutually exclusive due to electrical limits.
- State thaw timing and what remains frozen.
- Keep texture-sensitive leftovers separate, and name every storage destination.

## Verification

- Test wide desktop and the target Galaxy S20 Chrome viewport at its native 1440 × 3200 display and 480 dpi density. Keep an iPhone viewport test only when the runbook will also be used there.
- When the Android device is connected, follow `skill://android-app-automation` and verify the served runbook on the actual phone rather than relying only on browser emulation.
- Verify no horizontal overflow, visible focus, native keyboard controls, persisted checkmarks, reset recovery, reduced motion, and clean console output.
- For served copies, expose only the requested HTML files and verify unrelated paths return 404.
