---
name: android-app-automation
description: "Control the dedicated connected Galaxy S20 through ADB for stable, verified Cook Well, MacroFactor, and other visible Android app workflows."
---

# Android App Automation

Use this skill for visible app workflows on the dedicated Galaxy S20 automation phone.

## Device and host command

- Target serial: `RFCN80KARNX`.
- Device: Samsung Galaxy S20 `SM-G981U1`, Android 13.
- Always select the serial explicitly. Never act on the first device in an unscoped list.
- The host does not have a permanent `adb` command. Use:

```sh
nix shell nixpkgs#android-tools -c adb -s RFCN80KARNX <command>
```

## Preconditions

1. Run `nix shell nixpkgs#android-tools -c adb devices -l`.
2. Continue only when `RFCN80KARNX` has state `device`.
3. If the state is `unauthorized`, ask the user to unlock the phone and approve the RSA prompt. Retry after approval.
4. Keep the phone connected by USB for unattended work. The configured stay-awake setting applies while it is plugged in.

## Control loop

1. Launch the exact activity with `am start -W -n PACKAGE/ACTIVITY`.
2. Check `mCurrentFocus` and `mFocusedApp` before reading or acting.
3. Dump the current hierarchy with `uiautomator dump /sdcard/omp-window.xml`.
4. Pull or inspect that hierarchy. Prefer selectors in this order:
   - exact `content-desc`;
   - exact visible `text`;
   - stable `resource-id`;
   - class plus a verified parent label;
   - fresh bounds from the current hierarchy.
5. Capture a screenshot when the hierarchy is ambiguous or a control is unlabeled.
6. Tap the center of the fresh bounds. Use `input swipe` for scrolling and `input keyevent BACK` for safe exits.
7. Dump the hierarchy again and verify the expected state before the next action.

Never run two `uiautomator dump` processes concurrently. Concurrent dumps can kill one another or return incomplete output. Sequential dumps were stable in the initial device probe.

Do not reuse coordinates after a screen transition, density change, rotation change, keyboard transition, or app relaunch. Re-read the hierarchy first.

For text input, focus the verified `EditText`, use `input text`, and read the field back. Encode a space as `%s`. Treat visible text as uncommitted until the app recalculates or shows the expected result.

Use `am start`, not `monkey`, for normal launches. `monkey` can generate an unintended event after launch.

## Intentional device baseline

The device is configured for agentic app automation:

- native display density: 480 dpi;
- fixed portrait rotation;
- window, transition, and animator scales: 0;
- screen timeout: 30 minutes when unplugged;
- stay awake while plugged into AC, USB, or wireless power;
- three-button navigation;
- pointer coordinates and show-touches enabled;
- ADB authorization timeout disabled.

The native density exposes more app content and reduces scrolling. Pointer overlays are intentional. They can cover a small strip at the top of screenshots, so do not use that strip as the only evidence for app content.

## Cook Well

- Package/activity: `com.cookwell.app/.MainActivity`.
- Main navigation: `Explore`, `Planner`, `Grocery`, `Chat`, and `Profile`.
- Weekly plan route: `Explore` → horizontal `Meal Plans` tab → current meal-plan card.
- Read the plan by scrolling through the rationale, daily recipe/framework rows, reusable components, leftovers, and the final action row.
- Current plan actions are labeled `Add Groceries` and `Add to Planner`. Treat both as mutations.
- Recipe pages expose ingredients, quantities, instructions, FAQ text, tags, and inline guidance through the hierarchy.
- Cook Well uses React Native. Most useful buttons have `content-desc`, but some close and plus controls are unlabeled `Button` nodes. Derive their bounds from the current card or row and verify visually.
- First-use `COOK WELL TIP` cards can be dismissed. A screen can contain more than one tip, including a second tip below the first visible viewport. Re-dump and repeat until no tip label remains.

## MacroFactor

- Package/activity: `com.sbs.diet/.MainActivityAlias`.
- Main navigation: `Dashboard`, `Food Log`, central `Tab 3 of 5`, `Strategy`, and `More`.
- The central tab opens `Shortcuts` with `Weight`, `Search`, `Barcode`, `Describe`, `Recipes`, `Edit Day`, `New Recipe`, and `New Food`.
- `Recipes` opens the add-food Library. Recipe rows expose name, calories, macros, serving unit, and serving weight through `content-desc`.
- `New Recipe` offers `Build from scratch`, `Import from Link`, and `Import with AI`.
- MacroFactor uses Flutter semantics. Read-only rows usually have rich `content-desc` labels. Recipe-form `EditText` nodes can be unlabeled and have no resource ID. Select them only by a fresh parent label, verified order, class, and bounds. Verify every field after entry.
- Search text injection and result reading work through ADB. Never tap a row plus button or `Log Foods` during a read-only check.
- The Android app exposes Health Connect permissions for body fat, hydration, nutrition, steps, and weight. Health Connect is currently disabled. Enabling it requires an explicit workflow and permission review.

## Side-effect gates

Navigation, hierarchy reads, screenshots, search queries, and opening detail pages are read-only.

Stop before these actions unless the active user request requires them:

- Cook Well: add a plan, recipe, note, grocery list, grocery template, or grocery items; send a chat message; save/favorite; mark cooked.
- MacroFactor: add food to the plate; press `Log Foods`; save/edit/delete a recipe or food; change goals, strategy, account, subscription, integrations, or units.
- Android: install an APK, grant a permission, change an account, clear app data, uninstall, factory reset, or enable network ADB.

For a write workflow, prepare the full payload first. Perform the mutation once. Then reopen the destination screen and verify the saved or logged result. Confirm that MacroFactor's plate is empty unless logging is the active task.

## Manual intervention

Ask the user only when Android requires a human-only gate, such as:

- RSA authorization;
- device unlock or secure lock-screen input;
- Cook Well email verification;
- MacroFactor password or account recovery;
- a permission or Health Connect consent screen that needs user review;
- CAPTCHA, payment, subscription, or destructive confirmation.

## Privacy and cleanup

Screenshots and UI hierarchies can contain account names, email addresses, meal history, weight, and nutrition data. Keep captures in temporary paths. Do not put raw captures in the vault. Delete temporary host and device captures after the workflow.

## Stability evidence and recovery

Initial probe on 2026-08-29:

- Cook Well 1.0.8 and MacroFactor 5.8.3 were authenticated.
- Five sequential hierarchy dumps succeeded.
- Three Cook Well/MacroFactor foreground-switch cycles per app completed with zero launch or dump failures.
- Cook Well showed no app crash. Android recorded only a normal WebView sandbox cleanup.
- MacroFactor had no recorded application exit.

If state becomes stale:

1. Re-check device authorization and current focus.
2. Relaunch the exact activity.
3. Wait for the visible screen to settle.
4. Create one fresh hierarchy dump.
5. Capture a screenshot only if the hierarchy remains ambiguous.
6. Stop before a mutation when the current state cannot be proved.
