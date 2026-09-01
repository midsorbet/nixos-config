---
name: walmart-sparky
description: "Use Walmart's Sparky assistant on the dedicated Galaxy S20 for reviewed grocery searches, cart handoffs, conversation-history inspection, and exact post-action reconciliation."
---

# Walmart Sparky

Use this skill for Walmart shopping workflows that are best handled through the Sparky assistant instead of brittle item-by-item app automation. Follow `skill://android-app-automation` for device authorization, serialized UIAutomator reads, selector priority, privacy, and recovery.

## App route

- Device transport: the exact current value of `ANDROID_DEVICE_SERIAL`; native Wireless Debugging ports can change after reboot.
- Package: `com.walmart.android`.
- Launch activity: `com.walmart.glass.integration.splash.SplashActivity`.
- Foreground activity after launch: `com.walmart.glass.integration.root.RootActivity`.
- Use Kitchen Flow's `android:readiness:walmart` command and versioned manifests for stable navigation and assertions. Use raw ADB only for selector discovery, recovery, or an unmodeled screen, then migrate repeated behavior into a manifest.
- Main bottom navigation exposes `Shop`, `Sparky`, `Services`, and `Account`.
- Open Sparky through the bottom navigation node with content description `Sparky` and resource ID `com.walmart.android:id/navigation_tab_3`.
- Confirm the `Ask Sparky` toolbar before reading or acting.

Always read fresh bounds from the current hierarchy. Do not reuse the measured coordinates in this skill.

## Side-effect model

Opening Sparky, opening Chat History, opening an existing conversation, scrolling, reading messages, and reading product cards are read-only.

Treat all of these as mutations or request-sending actions:

- tapping a home suggestion such as `Shop for my usual items`;
- focusing or typing into `Ask me anything` during a read-only task;
- submitting any Sparky message, including search-only messages;
- tapping `Add`, `Add to cart`, `Buy now`, quantity steppers, or replacement controls;
- asking Sparky to add, remove, swap, replace, or change the quantity of an item;
- changing fulfillment, store, delivery address, reservation, substitutions, or cart contents.

A message that says `add to cart` can mutate the cart immediately. Sparky does not always require a separate confirmation. A search or recommendation message can return actionable product cards without changing the cart, but sending it is still an external request.

Do not send a message unless the active user request authorizes the message and its likely side effects. Never send a test prompt merely to inspect behavior.

## Read conversation history

1. Open Sparky and verify the `Ask Sparky` toolbar.
2. Select the toolbar button with content description `Chat History` and resource ID `com.walmart.android:id/converse_unified_chat_ui_sparky_chat_toolbar_history`.
3. Verify the `Chat history` header.
4. Read period headers from `com.walmart.android:id/timeHeader`.
5. Read conversation titles from `com.walmart.android:id/converse_source_name`.
6. Open only the intended title by its fresh text and bounds.
7. Read the conversation through the `com.walmart.android:id/sparky_recycler_view` hierarchy.
8. Scroll toward earlier messages with a downward swipe inside the recycler. Long product groups can require many sequential scroll-and-dump cycles.
9. Stop when the oldest sent message and its first response are visible or when a repeated fresh dump proves the list no longer moves.

Conversation titles are generated summaries. They can be stale or unrelated to later turns in the same thread. Never infer the conversation's purpose from the title alone.

## Conversation semantics

Use these observed selectors on Walmart 26.32.2:

- Sent message wrapper: resource ID `com.walmart.android:id/background`, with content description beginning `Sent message:`.
- Sent and received text: resource ID `com.walmart.android:id/text_message`.
- Received message: `text_message` content description beginning `Received message:`.
- Product-group heading: resource ID `com.walmart.android:id/unified_carousel_title`.
- Product card: resource ID `com.walmart.android:id/horizontal_item_card_root`.
- Add control: resource ID `com.walmart.android:id/stepper_textview`, commonly labeled `Add` or `Add to cart ...`.
- Buy-now control: resource ID `com.walmart.android:id/horizontal_item_card_buy_now_button` or a button labeled `Buy now`.
- Input field: resource ID `com.walmart.android:id/unified_ui_input_field`, text `Ask me anything`.
- Camera input: resource ID `com.walmart.android:id/unified_input_field_camera_icon`.
- Cart summary: resource IDs `com.walmart.android:id/cart_summary_icon`, `cart_summary_count`, and `cart_summary_subtotal`.

Product-card content descriptions can expose:

- product name and package size;
- price;
- purchase-history hints such as `Bought 1 time`;
- stock or popularity hints;
- AI-generated rationale;
- rating and review count.

Treat AI-generated rationale as selection context, not proof that the product satisfies the requested size, variety, dietary constraint, or unit count.

## Grocery handoff blueprint

Prepare the complete handoff outside Walmart before sending anything. Each item must specify, when relevant:

- exact quantity;
- product category or product name;
- desired package size or acceptable range;
- unit form, such as individual, bunch, bag, tub, box, or jar;
- brand preference or `any suitable brand`;
- must-have qualifiers;
- allowed substitutions;
- forbidden substitutions;
- optional-item condition, such as `only if inexpensive`;
- skip rule when only oversized, unsuitable, or expensive options exist.

Also define:

- fulfillment target: delivery, pickup, or unspecified;
- selection policy: normal-size, good-value, conventional, organic, store brand, or another explicit preference;
- whether the task is discovery-only or cart mutation;
- response contract, such as `report only added, substituted, and not found`.

Never let Sparky decide a material ambiguity that the blueprint can resolve first.

## Preferred two-stage workflow

Use two stages when product identity or substitution quality matters.

### Discovery stage

1. Record the visible cart count and subtotal as a baseline.
2. Prepare a find-only prompt that explicitly says not to add or remove anything.
3. Send it only when the user authorized a Sparky request.
4. Wait for Sparky to finish.
5. Read the response, group headings, product-card descriptions, package sizes, prices, and rationales.
6. Compare every proposed product with the blueprint.
7. Resolve missing items, package mismatches, and substitutions before cart mutation.

### Cart stage

1. Prepare one final exact add-to-cart prompt from reviewed product choices.
2. State quantities, package sizes, substitutions, exclusions, and the response contract again.
3. Re-read the input field before typing. Confirm that no stale draft exists.
4. Enter and submit the prompt once.
5. Wait for the complete response. Do not send a duplicate because the first response is slow.
6. Read the sent message back from the conversation to prove the submitted payload.
7. Read Sparky's result and classify each requested item as exact, substituted, not found, out of stock, or unresolved.
8. Verify the cart count and subtotal changed consistently with the result.
9. Open the cart only when item-level verification is required. Do not alter fulfillment or checkout state during verification.

A direct one-stage add prompt is acceptable only when the user already approved exact item rules and the possible substitutions are low risk.

## Reconciliation rules

- Sparky can return candidates first and wait for a follow-up such as `Add these to cart`.
- Sparky can also add found items immediately from a batch add prompt and report misses.
- Quantity can apply to an individual item or to a package. Verify which unit the product card represents.
- Sparky can substitute a different brand or package after a follow-up instruction.
- A product-verification follow-up can fail transiently. Do not infer that the prior cart mutation was reverted.
- `Not found`, `out of stock`, and an unsuitable near-match are different results. Preserve the distinction.
- Do not accept broth, sauce, seasoning, or another related product as a substitute for a required paste, base ingredient, or product form unless the blueprint allows it.
- Do not silently replace a missing item. Return unresolved choices to the user or planner.
- Reconcile the final cart against the grocery blueprint, not only against Sparky's prose summary.

## Checkout and human gates

Stop before:

- checkout;
- payment or gift-card actions;
- delivery or pickup reservation confirmation;
- address or store changes;
- substitution-policy changes that affect the whole order;
- CAPTCHA, identity verification, or account recovery;
- Walmart+ enrollment, trial, subscription, or paid upsell;
- destructive cart clearing or order cancellation.

The user must review these actions directly.

## Privacy and cleanup

Conversation history can contain the user's name, shopping history, dietary preferences, delivery context, cart contents, and prices. Product cards can reveal prior purchases.

- Keep screenshots and hierarchy XML in temporary host and device paths.
- Do not store raw conversation captures in the vault or skill source.
- Summarize reusable behavior without copying personal shopping history.
- Delete all host and device captures after the workflow.
- Park Walmart on a non-sensitive main screen when practical.

## Measured behavior

Read-only exploration on 2026-08-29 used Walmart 26.32.2 on the dedicated Galaxy S20:

- the app was authenticated and exposed Sparky through the main navigation;
- Chat History exposed two recent conversation titles;
- 22 sequential UIAutomator dumps completed successfully;
- message direction, product groups, product metadata, action controls, input, and cart summary were semantically readable;
- long conversations restored at an interior scroll position and required repeated fresh downward swipes to reach earlier messages;
- the observed history included discovery, product recommendation, exact batch grocery addition, follow-up substitution, package verification, not-found, out-of-stock, and transient-error behavior;
- no message was sent and no cart action was taken during the exploration;
- the visible cart baseline remained unchanged during the read-only review.
