---
name: android-app-automation
description: "Run deterministic Kitchen Flow Appium workflows on the dedicated Galaxy S20, with raw ADB reserved for exploration and recovery."
---

# Android App Automation

Use this skill for visible app workflows on the dedicated Galaxy S20 automation phone.

## Canonical deterministic runner

- Project: `/Users/me/vault/projects/kitchen-flow`.
- Device: Samsung Galaxy S20 `SM-G981U1`, Android 13.
- The active transport comes from `ANDROID_DEVICE_SERIAL`. Always scope Appium and ADB to that exact value.
- Native Wireless Debugging uses an IP and dynamic port. The port can change after every reboot. Read the current `IP address & Port` from the main Wireless debugging screen instead of reusing an old endpoint.
- USB fallback serial: `RFCN80KARNX`. Do not assume it is connected.

Start the localhost-only Appium server in one terminal:

```sh
cd /Users/me/vault/projects/kitchen-flow
nix develop -c npm run android:server
```

Set the current device endpoint and run a named readiness workflow in another terminal:

```sh
cd /Users/me/vault/projects/kitchen-flow
export ANDROID_DEVICE_SERIAL="<current adb serial or wireless IP:port>"
nix develop -c npm run android:readiness:cookwell
nix develop -c npm run android:readiness:macrofactor
nix develop -c npm run android:readiness:walmart
```

These commands create isolated UTC-stamped run directories with parser-clean JSONL evidence and failure artifacts. For a write workflow, use a reviewed versioned manifest and the SHA-256 approval procedure in `docs/android-automation-operator.md`. Never bypass the mutation digest gate.

## Preconditions

1. Set `ANDROID_DEVICE_SERIAL` explicitly from the current transport.
2. Run `nix shell nixpkgs#android-tools -c adb -s "$ANDROID_DEVICE_SERIAL" get-state`.
3. Continue only when that exact transport reports `device`.
4. The dedicated Galaxy S20 has a nonsecure swipe-only lock. Let Kitchen Flow's Appium session wake the phone and dismiss that lock.
5. If Android instead requires a secure credential, RSA authorization, or Wireless Debugging pairing, stop for the user.
6. Run Appium only on `127.0.0.1:4723`.

## Routing rule

Use an existing Kitchen Flow manifest whenever it covers the task. Add a reviewed manifest for stable repeated navigation, assertions, extraction, recipe creation, logging, or cart staging. Use raw ADB only to explore an unmodeled screen, recover transport, or collect selectors for a new manifest. After exploration, encode repeated behavior in Kitchen Flow instead of preserving an ad-hoc coordinate script.

## Raw ADB exploratory fallback

The host does not have a permanent `adb` command. Scope every fallback command explicitly:

```sh
nix shell nixpkgs#android-tools -c adb -s "$ANDROID_DEVICE_SERIAL" <command>
```

1. Launch the exact activity with `am start -W -n PACKAGE/ACTIVITY`.
2. Check `mCurrentFocus` and `mFocusedApp` before reading or acting.
3. Dump the current hierarchy with `uiautomator dump /sdcard/omp-window.xml`.
4. Prefer exact `content-desc`, exact text, stable resource ID, verified parent context, then fresh bounds.
5. Capture a screenshot only when the hierarchy is ambiguous or a control is unlabeled.
6. Tap only fresh verified bounds. Re-dump and verify the expected state before the next action.

Never run two `uiautomator dump` processes concurrently. Do not reuse coordinates after a screen transition, density change, rotation change, keyboard transition, or app relaunch. For text input, read the field back and verify the app recalculates. Use `am start`, not `monkey`, for normal launches.

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
- secure lock-screen input, or a nonsecure swipe-only lock that Appium cannot dismiss;
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
