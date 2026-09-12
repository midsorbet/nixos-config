# Diagram workflow

Use this reference only when the diagram form, renderer, or interaction needs design.

## Match grammar to the question

- components and connections: topology or system map
- ordered messages or causality: sequence or request trace
- decisions and transformations: process flow
- transitions and conditions: state diagram
- containment or ownership: hierarchy or boundary map
- alternatives: matrix or aligned comparison
- change over time: timeline
- magnitude or distribution: quantitative chart; also read [charts and data](../../html/references/charts-and-data.md)

Split overloaded questions into coordinated views or selectable layers. Decide what must remain visible together and what may appear on demand.

## Choose the renderer

Use HTML/CSS for labeled regions and reflowing text, SVG for crisp relationships and paths, Canvas for dense or frequently changing scenes, and WebGL only when scale or spatial depth earns its complexity. Mixed media is valid.

Establish hierarchy through position, grouping, boundaries, scale, and whitespace before color. Keep node positions stable when readers compare steps or states. Use legends only when notation is not self-explanatory.

## Interaction

Sequence must expose causality. For anything beyond a brief self-explanatory animation, provide durable step labels and suitable play, pause, restart, step, or path controls. Preserve meaning when motion stops and respect `prefers-reduced-motion`.

Use filtering or layer toggles only to reduce genuine complexity. Make selections obvious and floating panels dismissible and reopenable from their trigger.

Add pan and zoom only when the information materially exceeds the viewport. Transform one containing SVG group, keep pointer and transform math in one coordinate system, preserve the point under the cursor while zooming, suppress click after drag with a movement threshold, expose scale and reset controls, and set useful zoom limits.
