---
name: macrofactor-cookwell
description: Turn Cook Well meal plans and framework recipes into concrete groceries, servings, day-by-day vault planner entries, and MacroFactor-style calorie/protein sanity checks. Use when the user asks for Cook Well grocery quantities, recipe scaling, meal-prep portions, app planner alignment, or whether a plan fits a calorie target such as MacroFactor logging.
---

# MacroFactor Cook Well

## Overview

Use this skill to bridge Cook Well's flexible recipe language with a concrete one-person meal-prep plan. Ground the work in the actual Cook Well app text, then translate it into buyable quantities, realistic servings, and planner notes in `/Users/me/vault`.

## Workflow

1. Read `/Users/me/vault/AGENTS.md` and the smallest relevant planner or area notes before changing files.
2. If Cook Well app context matters, prefer the dedicated attached Android device and follow `skill://android-app-automation`. Use Computer Use on the macOS iOS/iPad wrapper only as a fallback. For that fallback, first run `list_apps` and target the live wrapper path under `/var/folders/.../Wrapper/CookWell.app` with no trailing slash. Do not target the ambiguous `com.cookwell.app` bundle ID or `/Applications/Cook Well.app` while the wrapper is running.
3. Open the current Meal Plans tab and read the plan description, rationale, recipe list, day-by-day plan, and nutrition/serving guidance when present. Do not infer quantities from recipe titles alone.
4. Usually use the current platform's plan action for the weekly plan: `Add to Planner` on Android or `Add Plan to Week` in the macOS wrapper. Then verify the app Planner placement against the user's intended real dates. If the app schedule and real schedule diverge, record the difference and move meals only with explicit intent.
5. Open each relevant framework or recipe page. Scroll/read through the end, including FAQ, meal ideas, tags, substitutions, nutrition, and serving guidance when visible.
6. Tap component headers or `?` icons when the page says more guidance exists. In frameworks, section headers often expand inline guidance that turns vague parts into usable starting points. Tooltips usually appear as `Cook Well Tip` with Q&A-like text; capture useful guidance and close the tooltip before continuing.
7. Interpret Cook Well "parts" as flexible ratios by weight when possible, or rough volume when eyeballing. Convert ratios into actual quantities only after checking the user's pantry, target servings, purchased items, and cooking vessel.
8. Translate the plan into a one-person serving model, prep allocation, grocery list, and MacroFactor blueprint. Keep quantities realistic for one adult and correct obviously excessive package assumptions.
9. Estimate MacroFactor-style nutrition at the plan level: use Cook Well nutrition as a sanity-check target when available, but treat actual pantry/Walmart items, package labels, and cooked yields as the MacroFactor source of truth.
10. Update vault planner files with exact dates and state markers. Use Google Calendar only for real time-bound blocks, not ordinary recipe sequencing.
11. When checking Cook Well's Planner tab, use the highlighted date in the horizontal date strip plus the visible meal row as the primary evidence for the meal's planner placement. The action sheet's `Planned for ...` line can be offset/misleading in the iPad app wrapper.

When improving this skill rather than executing a time-sensitive weekly plan, it is useful to inspect several historical Cook Well meal plans to identify repeated patterns: exact recipes versus frameworks, explicit base-component prep, how often nutrition/serving guidance appears, and common FAQ substitution guidance. During a live Sunday planning/shopping run, do not wander into historical plans unless the current plan is ambiguous and the extra examples directly unblock it.

## Android App Route

Use the Android route as the primary live app surface when serial `RFCN80KARNX` is connected and authorized.

- Cook Well: launch `com.cookwell.app/.MainActivity`. Open `Explore`, select the horizontal `Meal Plans` tab, and open the current meal-plan card. On Android, the current mutation controls are labeled `Add Groceries` and `Add to Planner` rather than `Add Plan to Week`.
- MacroFactor: launch `com.sbs.diet/.MainActivityAlias`. The bottom navigation and central `Shortcuts` flow match the state machine below. The recipe Library exposes recipe names, calories, macros, serving units, and serving weights through Android semantics.
- Prefer fresh `content-desc` or text selectors from a serialized `uiautomator` dump. Do not reuse coordinates across screen transitions.
- Cook Well recipe and plan pages expose enough semantic text to capture rationale, daily rows, ingredients, quantities, instructions, FAQ content, and tags.
- MacroFactor read-only rows have strong semantics. MacroFactor recipe-form fields are less stable because the `EditText` nodes can be unlabeled. Verify each field by its fresh parent context, order, bounds, visible value, and recalculated totals.
- Treat `Add Groceries`, `Add to Planner`, row plus buttons, `Log Foods`, recipe save/edit, and integration changes as explicit mutation gates.
- Dismiss first-use tooltips when they obstruct the task. A Cook Well screen can contain more than one tooltip at different scroll positions.
- Keep screenshots and hierarchy XML in temporary paths because they can contain account, nutrition, and weight data.


## Weekly Sunday State Machine

Use this as the default route for recurring Cook Well weekly meal planning.

1. `plan_detected`: Open Cook Well Meal Plans, identify the newest weekly plan, and read the plan page all the way through. Exit when the plan name, intended week, serving model, meals, and high-level prep concept are captured.
2. `plan_added_or_scheduled`: If the user wants the in-app planner aligned, tap `Add to Planner` on Android or `Add Plan to Week` in the macOS wrapper, then verify Cook Well Planner dates. Exit when app dates match the intended week or an explicit reschedule action is recorded.
3. `recipes_read`: Open every listed meal plus any base framework. Read recipes/frameworks through FAQ and tips. Distinguish exact recipes from flexible frameworks before converting quantities.
4. `component_graph_ready`: Map reusable bases, shared ingredients, planned leftovers, optional toppings, and cleanup meals across the whole plan before scaling. Exit when each meal is classified as fixed recipe, reusable component, remix of earlier components, cleanup/flexible assembly, or individually logged items.
5. `serving_model_scaled`: Convert the plan to the user's real schedule, usually one person with dinner plus next-day lunch. Exit when each eating occasion has a target serving, each reusable component has an allocation, and the plan has a fallback if prep slips.
6. `grocery_blueprint_ready`: Combine recipe requirements, pantry/on-hand decisions, package-size reality, and likely substitutions into a buy list. Exit with a markdown grocery checklist plus any "buy if low" items.
7. `shopping_handoff_ready`: For Walmart, follow `skill://walmart-sparky`. Prepare the full grocery blueprint before opening the app. Prefer one reviewed Sparky batch handoff over high-speed item-by-item automation. Exit only when every requested item is classified as exact, substituted, not found, out of stock, or unresolved and the cart result is reconciled. Stop at checkout, payment, reservation, CAPTCHA, or human-check gates. If Walmart is unavailable or the user will shop manually, keep the grocery state in the vault or iCloud Groceries and reconcile from the receipt later.
8. `macrofactor_blueprint_ready`: Before opening MacroFactor, write copy-ready recipe specs: recipe name, servings, total weight, icon target, each ingredient row/search term, quantity, unit, brand/source, expected macros or Cook Well nutrition sanity check, and unresolved unknowns.
9. `macrofactor_entered`: Create/edit MacroFactor entries only from the blueprint. Prefer `Build from scratch` for controlled meal-prep recipes. Use AI/Describe only for rough casual logging, not reusable Cook Well components.
10. `library_verified`: Search or view MacroFactor Library rows after saving. Verify recipe name, icon, serving weight, macros, and that the plate is empty or exactly intended. Do not press `Log Foods` unless the user asked for logging.
11. `cooked_yield_updated`: For cooked base components, update the recipe `Total Weight` only after final edible cooked yield is weighed. Exit when the base component and dependent meal recipes still line up.
12. `ready_to_log`: Log meals or copy/move logged foods only after the user has confirmed actual portions, meal time, and day.

## Recipe State Model

- `planned`: Cook Well recipe/framework text has been read, including FAQ/tips/nutrition where available.
- `component_graphed`: The recipe has been placed in the weekly dependency graph: standalone meal, base component, remix, cleanup assembly, side/sauce, or individually logged topping.
- `scaled`: Servings and schedule are adjusted for the user rather than blindly following Cook Well's default week.
- `ingredients_resolved`: Pantry decisions, Walmart cart/order/receipt items, and substitutions are known enough to choose MacroFactor rows.
- `choices_pending`: The page is readable but still has unresolved choices such as protein option, filling, sauce, starch, toppings, or whether leftovers are being reused. Do not create a fixed MacroFactor recipe from this state unless the draft is clearly labeled.
- `macrofactor_ready`: Exact recipe fields and ingredient rows are copy-ready in the planner. Unknown cooked yield is explicitly marked as placeholder.
- `entered`: The recipe exists in MacroFactor, but may still need row/icon/library verification.
- `verified`: MacroFactor Library/search confirms the expected name, icon, serving weight, macros, and ingredients.
- `yield_pending`: A base component uses an estimated total weight until cooking is finished. This is acceptable only when clearly labeled.
- `yield_updated`: Final edible cooked weight has replaced the placeholder and downstream recipes are still coherent.
- `logged`: Food has been intentionally logged for a specific date/time. Never treat recipe creation as logging.

## Data Source Priority

1. User-stated pantry decisions, substitutions, serving goals, and schedule.
2. Cook Well plan page, recipe pages, frameworks, FAQs, tooltips, and nutrition/serving guidance.
3. Actual Walmart cart/order/receipt items and package labels, especially variable-weight meat and brand-specific serving sizes.
4. MacroFactor library/barcode entries that match the actual purchased item.
5. Close generic MacroFactor entries only when the brand/label match is unavailable and the macro difference is acceptable.
6. Custom MacroFactor foods from package labels when catalog entries materially disagree with the purchased item.
7. Final cooked edible yield for cooked base recipe `Total Weight`.

## MacroFactor Automation Playbook

Before app entry:

- Put MacroFactor on a stable, visible, low-traffic monitor/workspace. AeroSpace can move or tile the iOS wrapper unpredictably; re-read app state after every workspace/display change.
- Keep the Mac awake during long app-entry sessions. If the display sleeps or the screensaver locks, Computer Use may see a live `Runner.app` process with no usable scene until the user wakes the screen.
- Find the live iOS wrapper path from `list_apps`; do not rely on bundle ID or `/Applications/MacroFactor.app` if a transient `/var/folders/.../Wrapper/Runner.app` is running.
- Do not assume iOS Simulator is a better control surface unless it has the real MacroFactor app, account data, and recipe library available. Prefer a semantic API/App Intent/Shortcut if MacroFactor exposes one; otherwise use the visible installed app plus the verification gates here.
- Verify the current task type: create recipe, edit recipe, verify recipe, log food, or copy/move logged foods. Each task has different side-effect risk.
- Confirm the add-food plate is empty before creation/verification work. If it is not empty and logging was not requested, close/clear the sheet before continuing.

During recipe entry:

- Use `Build from scratch` for reusable Cook Well meal-prep recipes, especially when one recipe depends on another custom base component.
- Fill recipe-level fields first, then ingredient rows, then icon, then save. Prefer direct `g`, `oz`, `lb`, `tsp`, or `tbsp` units on ingredient rows when MacroFactor supports them.
- Treat physical keyboard input, `set_value`, and visible numeric text as untrusted until MacroFactor recalculates the row macros/weight. If totals do not update, reopen the row and use the on-screen keypad.
- For spices, keep teaspoon-style amounts when that is how the recipe is specified. Do not convert every spice to grams unless the label/app requires it.
- For custom foods from labels, avoid reserved unit names such as `oz`; use a neutral custom serving name like `1 portion`, then switch recipe ingredient rows to direct weight units afterward.
- For icons, search normal MacroFactor foods for the plain meal name before creating/editing the recipe, note the best visual reference, then choose that icon manually. The `Choose Icon` picker is unlabeled and visually ambiguous.

Verification gates:

- After saving, verify the recipe in Library/search. Check name, icon, serving weight, calories/macros, and that the right custom base component is used.
- If an icon or row is wrong, reopen only that recipe through `Edit`, fix the narrow issue, and save with `Edit`, not `Edit & Add`.
- Return MacroFactor to the dashboard or an empty add-food sheet after verification. Do not leave staged food in the plate unless logging is the active task.

Bailout policy:

- If MacroFactor loses its visible scene, sleeps, stops accepting clicks, or field edits fail repeatedly, stop app automation. Write or update the copy-ready blueprint and exact resume point in the planner, then wait for the user to restore the app/window.
- Do not spend the whole session fighting the wrapper when a vault handoff plus later manual or assisted entry would preserve the meal plan accurately.

## Cook Well App Quirks

- The Planner meal action button may focus through accessibility without opening its menu. If that happens, use the current screenshot and click the visible three-dot control at the far right of the meal row.
- The meal action sheet includes `Move to Another Day`; use that to reschedule planner meals only when the highlighted date/visible row placement is wrong.
- If the visible highlighted date and action-sheet `Planned for ...` line disagree, do not trust the action sheet alone. Trust the highlighted date strip and visible row placement unless another app state clearly contradicts it.
- Observed on 2026-06-06: the highlighted Planner date showed the intended placement, while the action sheet reported one day earlier. `Simple Fried Rice` was visibly under highlighted `Wed, Jun 10`, while the action sheet said `Planned for Tuesday, Jun 9`. Do not move meals just to correct that action-sheet label if the highlighted date already matches the desired day.
- If the user changes the actual start day after the plan is added, shift both vault planner entries and Cook Well stored dates. In Cook Well, move meals through each meal action sheet's `Move to Another Day`; when shifting the full sequence, move the last meal first so it is easier to track what remains.
- If Planner state looks stale or contradictory, restart Cook Well and verify the highlighted date strip after relaunch. The app may reopen on Explore; refresh Computer Use state before actions, then use the bottom-nav Planner button exposed in the current accessibility tree.

## MacroFactor App Quirks

- MacroFactor on macOS may also run as an iOS/iPad wrapper. On 2026-06-06, `list_apps` showed the installed app at `/Applications/MacroFactor.app` and the running app as `/var/folders/.../Wrapper/Runner.app` with bundle ID `com.sbs.diet`. If the bundle ID is ambiguous, target the live wrapper path from `list_apps` and refresh app state before reading or acting.
- Computer Use may successfully read MacroFactor wrapper state while refusing follow-up clicks for the same wrapper path. If that happens, use the live accessibility tree or current window bounds rather than stale coordinates; keep actions limited to navigation unless the user explicitly asks to create, save, or log food.
- Observed MacroFactor version 5.7.9: bottom navigation exposed `Dashboard`, `Food Log`, a central add button described as `Tab 3 of 5`, `Strategy`, and `More`.
- The central add button opens a `Shortcuts` sheet with `Weight`, `Search`, `Barcode`, `Describe`, `Recipes`, `Edit Day`, `New Recipe`, and `New Food`. In the iOS wrapper, the central add control may require a coordinate click derived from current window bounds even when `AXPress` reports success.
- `New Recipe` starts with `Build from scratch`, `Import from Link`, and `Import with AI`. For Cook Well framework meals, prefer `Build from scratch` when the exact ingredients and cooked yields are known; treat imports as drafts that still need ingredient and yield verification.
- MacroFactor AI import/Describe does not reliably resolve existing custom recipes by name, and prompts for a preferred icon may be ignored. For Cook Well remix meals that depend on a custom base component, use `Build from scratch`, add the existing custom recipe from the library/search, verify the row displays that custom recipe name and expected macros, and set the icon manually on the recipe save screen.
- For custom recipe icons, search the plain meal name in MacroFactor's normal food search first and use the best matching library result's icon as the visual reference. After creating or editing the custom recipe, search the custom recipe and visually verify that its icon reads as the intended meal, not just any superficially similar shape.
- To edit an existing recipe icon, open the recipe detail from Library, use `Edit`, go `Next` to the preparation screen, choose `Edit Icon`, select the icon visually, then use `Edit` rather than `Edit & Add` to save without logging the recipe. The icon picker exposes unlabeled grid elements and may not scroll reliably through accessibility; a real mouse/trackpad scroll wheel can move the grid when `scroll` appears stuck. Verify the preview and the Library row afterward.
- The `Build from scratch` recipe form requires `Recipe Name`, `Serving Quantity`, `Total Weight` after preparation, and ingredients before it can be completed. Do not save placeholder recipes with fake weights; collect cooked edible yield and measured ingredient weights first.
- If MacroFactor relaunches with a window sliver offscreen, inspect display/window bounds before clicking. On 2026-06-07, the MacroFactor window was at the bottom edge of the portrait monitor and needed a drag from the visible sliver back to a normal display before Computer Use could read it.
- In the MacroFactor date/time picker, the hour wheel may not advance from `11` to `12` with `AXIncrement`. To select `12 PM`, use `AXDecrement` from `11` down through `1` and then to `12`, keep the AM/PM wheel on `PM`, and verify the header before adding or moving foods.
- Logged food detail views expose a time chip that opens hour/minute/AMPM wheels. Changing a logged item's time is possible there, but verify each item after saving; direct `set_value` calls on picker sliders can invalidate elements or send the app back to an add-food sheet.
- If an add-food sheet has an empty plate and the top-left `X` is unreliable, use the top-right plate arrow to expand/collapse the sheet and re-read app state. Do not press `Log Foods` unless the visible plate contents are exactly the intended items.
- For individual ingredients, prefer switching the item detail quantity unit to `g` when MacroFactor exposes it. Tap the unit button row (`g`, `oz`, `serving`, `lb`, etc.), select `g`, enter the gram weight, and verify the food-log row displays grams before moving on.
- In the iOS wrapper quantity editor, physical keyboard input can update the visible text field without committing the app's nutrition calculation. If the calories/macros do not recalculate immediately, use the on-screen numeric keypad and verify the top-line macros before tapping `Done`.
- `set_value` may focus MacroFactor recipe form fields without reliably replacing numeric values such as `Serving Quantity` or `Total Weight`. Prefer focusing the field, using select-all plus normal keyboard input, then re-reading the form before continuing.
- Changing units in a food or recipe quantity editor may preserve the numeric value rather than converting it. After selecting `g`, `tsp`, `tbsp`, or another unit, verify or replace the number with the intended amount before tapping `Done`.
- When creating a custom food from a package label, do not use reserved standard units such as `oz` as the custom serving name. MacroFactor shows a red validation warning and may refuse to save. Use the package serving weight, then set a neutral serving name such as `1 portion`; MacroFactor can still convert to ounces from the gram serving weight.
- After adding that custom food to a recipe, switch the recipe ingredient row to a direct unit such as `g`, `oz`, or `lb` when available. The neutral `portion` serving name is only a custom-food creation workaround; recipe rows should stay readable.
- For near-zero aromatics such as bay leaves, do not force a bad MacroFactor library entry just to make the ingredient list exhaustive. If search results use unrealistic units such as `100 g` servings or overstate the amount, record the aromatic in the cooking instructions/planner note and keep it out of recipe calories.
- Dashboard search/add-food sheets are useful for confirming that a custom recipe exists and shows the expected icon, macros, and serving weight. When verifying only, close the sheet after inspection and do not press `Log Foods`.
- For copying or moving a set of logged foods, use the Food Log selection mode instead of rebuilding the plate manually. Tap a logged item to enter/select the block, use the bottom selection bar (`Select`, `View`, `Copy`, `Move`, `Remove`) to select the intended foods, then use `Copy` or `Move` and choose the target date/time. Verify the destination day and time after the operation.
- If MacroFactor's wrapper process is running but `get_app_state` returns `cgWindowNotFound` and System Events reports zero windows for `Runner`, the app may be alive without an open iOS scene. Relaunching may preserve the same windowless state; ask the user to manually open/restore the MacroFactor window before continuing.
- Observed on 2026-06-28: MacroFactor can lose its scene mid-recipe after a quantity edit. `get_app_state` returned `cgWindowNotFound` or `remoteConnection`, System Events reported zero windows, and screenshots of both monitors showed only the desktop even though the `Runner` process was alive. Normal `open`, AppleScript `reopen`, and killing/reopening the stale `Runner` process still relaunched into a zero-window state. Stop app automation, record the exact recipe state in the planner, and wait for the user to manually restore/open the MacroFactor window.

## Quantity Heuristics

- Separate raw ingredient weight from edible cooked yield. Bone-in, skin-on chicken is not equivalent to boneless skinless chicken by weight.
- Prefer batch allocation over a single giant calorie number: first dinner, leftover lunches, reserved protein for each remix recipe, rice reserved for fried rice, and freezer/open-weekend buffer.
- For rice, distinguish dry cups from cooked cups. Note the rice type because jasmine, long grain, and Calrose behave differently for chicken rice and fried rice.
- Cooking-vessel constraints matter. If the user's pot or Instant Pot is close to full, split the protein batch rather than forcing unsafe fill levels.
- When replacing boxed broth with Better Than Bouillon or another concentrated base, use the label ratio as the starting point and reduce added salt. Better Than Bouillon commonly contributes meaningful sodium even when calories are negligible, so record teaspoons or grams if MacroFactor sodium accuracy matters.
- When breakfast/snack context exists, check whether the lunch/dinner plan plus breakfast/snacks plausibly fits the target calories.

## MacroFactor Logging Model

- Do not turn a reuse-heavy Cook Well plan into one giant MacroFactor recipe unless every meal portion is identical. Create reusable base components first, then build/log the remix meals from weighed component amounts.
- Do not assume Cook Well's `Recipe` label means MacroFactor-ready. Exact recipe pages can still contain flexible subcomponents, optional toppings, or "parts" that need real gram targets before entry.
- Do not assume Cook Well's `Framework` label means "no quantities." Framework headers, FAQs, and plan text often provide enough ratios and starting points to build a useful blueprint after the user chooses the options.
- For cleanup meals such as nacho bars, grain bowls, spring rolls, pasta salads, and fridge-cleanout wraps, default to component logging or a deliberately chosen fixed assembly. Do not save a catch-all recipe unless the user has fixed the protein, starch, sauce, toppings, and serving weights.
- For reusable dips/sauces such as hummus, white sauce, ginger-scallion sauce, or pickles, create or log the core component separately from optional plate toppings unless the meal plan fixes the full plated serving.
- For base frameworks with multiple edible outputs, create separate MacroFactor components for each output. For example, poached chicken and rice should become edible cooked chicken, cooked rice, and optionally measured sauce/fat/broth rather than one opaque weekly recipe.
- When Cook Well says a texture component should be kept separate for leftovers, such as chips, tortilla strips, crisp vegetables, or sauces, preserve that in the planner and MacroFactor blueprint instead of mixing it into a reheated recipe.
- Reconcile package labels with MacroFactor recipes by treating the label as a raw/as-purchased macro sanity check and the recipe as a cooked-yield converter. Ingredient macros feed the recipe; `Total Weight` is the cooked edible output. Do not assign bones, discarded skin, or discarded rendered fat to the edible chicken component.
- For bone-in, skin-on chicken, do not log the raw package weight as edible chicken. After cooking, weigh the edible cooked meat after bones and discarded skin/fat are removed. If skin is eaten consistently, use an appropriate cooked skin-on entry or include it deliberately; otherwise omit discarded skin and bones.
- For chicken rice, log dry rice plus measured fat/oil actually used. Broth can be treated as low-calorie unless fatty broth or rendered chicken fat is intentionally added; measure that fat separately.
- Best Cook Well-to-MacroFactor pattern: create or log `Base Shredded Chicken` from the cooked edible yield, `Chicken Rice` from dry rice plus measured fat/broth yield, then create/log finished meals such as `Taquitos`, `Chicken Noodle Soup`, and `Simple Fried Rice` from the amounts actually pulled from those containers.
- Prefer gram-based yields when MacroFactor allows them. Weigh the finished pot/pan or container, subtract tare, and set servings by grams or by clearly weighed portions. For leftover lunches, log the same recipe serving or weighed grams instead of creating a new entry.
- For MacroFactor accuracy, repeatability matters more than false precision. Use the same entries and weighing rules throughout the week, then adjust recipes next time if the batch yield or portions were off.

## Vault Output

- Put durable meal-prep context in `planner/YYYY-MM-DD.md` for the relevant days.
- Use Markdown checkbox grocery lists when the user is shopping or comparing quantities.
- Keep loose future ideas out of `INBOX.md` when they are already resolved into this project skill.
- After vault edits, commit promptly unless the user says not to.
