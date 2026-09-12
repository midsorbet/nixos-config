---
name: html-prototype
description: Create a polished, responsive, self-contained HTML mockup or interactive prototype. Invoke only by explicit request for html-prototype or routing from the html skill.
---

# HTML Prototype

Build the smallest credible product experience that makes the important visual or behavioral question testable. Match the user's context and established design language rather than applying a recurring house style.

## Choose a mode

- **Mockup:** polished and mostly static; tests hierarchy, layout, typography, color, or product fit.
- **Prototype:** working bounded flow; tests navigation, input, state change, feedback, recovery, or transition.

Do not add behavior merely to make a mockup look complete. If both modes are requested, preserve content and structure so the fidelity change is comparable.

Read [prototype workflow](references/prototype-workflow.md) when modeling a flow, form, dialog, asynchronous action, or multiple states. This skill remains authoritative for fidelity, state, and interaction completeness.

## Contract

- Use realistic, internally consistent content. Implement one important path deeply rather than a broad fake product.
- Deliver one responsive, self-contained HTML file with essential CSS and JavaScript inline; require no build tooling, authentication, live API, or external service.
- Remove dead controls. Clearly mark where the real product would take over instead of pretending an external action completed.
- Use semantic native controls, accessible contrast, visible focus, keyboard operation, and more than color alone for state. Respect `prefers-reduced-motion`.
- In mockup mode, retain semantic structure and visible focus while making the static review boundary clear.

Inspect the actual file at wide desktop and narrow mobile widths. Exercise every modeled state and control; check keyboard paths, console errors, overflow, long content, disabled behavior, focus transitions, surface contrast, and reduced-motion behavior. If browser tooling is unavailable, name the checks left unverified. Return the absolute path, fidelity mode, modeled scenario and states, and production behavior deliberately excluded.
