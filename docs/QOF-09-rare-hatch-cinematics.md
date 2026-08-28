# QOF-09 – Rare Hatch Cinematics

## Status

**Source/code implemented; generated place regenerated and source parity verified; Roblox Studio validation pending.** The shared policy, Schema-V7 persistence contract, full client cinematic, failure-safe FIFO integration, tests, source registration, and generated `BATTLE_PETS.rbxlx` parity are complete. The generated-place verifier currently confirms 62 ModuleScripts, 1 Script, and 1 LocalScript. Device/layout, camera, input, and timing behavior still require Studio validation on desktop, phone, tablet, and portrait viewports.

## Deterministic presentation policy

Rare-result presentation is client-side only. `ReplicatedStorage.Shared.HatchCinematicPolicy` classifies already-authoritative result DTOs in this order:

1. `Shiny`
2. `Rainbow`
3. `Golden`
4. `Legendary`
5. `Epic`
6. `Rare`

Common and Uncommon are normal. Every non-empty batch designates exactly one Hero index for deterministic card ownership, but Hero classification priority is strictly `Shiny > Rainbow > Golden > Legendary > Epic > Rare > Normal`. Equal classifications always keep the first batch index: there is no Rainbow-Shiny or Golden-Shiny sub-priority. `buildPlan(pets)` returns the stable `heroIndex`, `hasRare` (`false` when that Hero classifies as `Normal`), entries, classification, exact `PopStagger = 0.12`, and a duration capped at 3.00 seconds. Normal batches use `StandardHoldDuration` and do not receive rare title, FOV, or Hero-hold treatment. Classification never changes pet identity, rarity, variant, damage, inventory, discovery, currency, entitlement, probability, or transaction outcome.

## Client choreography

`EffectsController` owns the lossless FIFO presentation queue. `Main.client` forwards `EggHatchStart` to `handleHatchStart`, normalizes the complete QOF-08 `EggHatchResult` DTO, and enqueues it through `enqueueHatchBatch`. A bounded 128-entry seen cache deduplicates non-empty `batchId` values; rolling QOF-07 single-pet payloads without `batchId` remain accepted.

Each accepted x1/x2/x5/x10 batch uses one `ScreenGui` (`DisplayOrder = 50`, `IgnoreGuiInset = false`, `DeviceSafeInsets` when available):

- Start feedback wobbles all expected eggs. A start without a result self-cleans after 2.25 seconds; a result without a start creates its presentation normally.
- Intro lasts 0.18 seconds. Egg `index` is bound to `pets[index]`, and pops form a policy-driven chain at exactly 0.12-second offsets.
- Every popped card immediately exposes a compact pet name, rarity, and variant accent.
- A rare batch has exactly one policy-selected Hero. Other cards dim briefly, while the Hero gets a local seven-degree-equivalent FOV emphasis (FOV only; no camera `CFrame`, gameplay state, or server time changes) for at most the policy `HeroHoldDuration`, provided the direct `UpgradeTreeGui` overlay is not visible. If that overlay becomes visible or is remounted during Hero/restore, the Hatch scope permanently yields FOV ownership to the Upgrade Tree for the remainder of the scope.
- Additional rare results receive a short accent only. Normal and rare plans remain within the policy's three-second ceiling.
- Outro lasts 0.30 seconds. While Hatch retains FOV ownership it restores the exact captured snapshot before the scope is destroyed; after ownership is yielded, the Upgrade Tree remains responsible for restoring its own camera state.

The layout reflows from the active overlay's `AbsoluteSize`: x1 is centered, wide layouts use at most five columns and two rows, and narrow/mobile/portrait layouts use two columns. Dedicated title and SKIP reservations are removed from the card-height budget, so short portrait x10 layouts fit without control overlap while retaining the maximum available readable size. One scope owns its reflow and variant-animation connections separately from every other presentation.

## Variants and resource limits

All cinematic visuals are procedural UI:

- **Golden:** gold glow/stroke and bounded gold stars.
- **Rainbow:** animated rainbow `UIGradient` accent.
- **Shiny:** white/cyan stars and a moving light strip.
- **Rainbow Shiny / Golden Shiny:** combines the applicable base-variant and Shiny treatments.

A batch can create at most 24 temporary UI particles. The idempotent presentation scope owns all tweens, connections, sounds, its conditional camera snapshot, and GUI instances. Completion, SKIP, CharacterRemoving, controller cleanup, external GUI destruction, timeout, and runtime errors converge on the same exactly-once finalizer. While Hatch retains FOV ownership, its exact snapshot is restored before the committed result callback runs. If the Upgrade Tree opens or remounts, Hatch cancels its active FOV tween, permanently yields ownership for that scope, and never writes the snapshot from its finalizer; the Tree remains the camera owner and restores its own state. The result callback (including result-grid display and discovery queueing) runs failure-safely while the presentation gate remains held. Only after that callback completes is the gate released and FIFO processing advanced exactly once. Late finalizer tasks cannot release a newer scope's gate, and placeholder/error/timeout/cleanup paths continue without wedging the queue.

The visible `SKIP` button is 132×52 pixels, meeting the mobile touch-target requirement. During the `EggHatchStart` waiting-for-result scope it remains visible as `WAITING` but is explicitly disabled (`Active = false`, `AutoButtonColor = false`), and direct skip calls do not finalize that scope. Binding the authoritative result changes it to active `SKIP`; skip then affects only the current cinematic. No skip tombstone is retained. Its `onPresented` callback still opens the existing `UIController:showEggBatch` result grid before the presentation gate is released and the queue advances. No stacked single-pet result modals or duplicate grid implementation exist; `showEggHatchAnimation` and `completeEggHatch` remain compatibility adapters into the same FIFO.

Discovery toasts (`DisplayOrder = 100`) are enqueued only from `onPresented`, after the rare cinematic has finalized. `showEggBatch` is called exactly once per accepted presentation, including skip/error/cleanup paths. Onboarding still commits immediately on a valid authoritative result rather than waiting for presentation.

## Roblox Studio validation scenarios

Effects/UI lifecycle behavior has no repository Roblox runtime harness, so it is intentionally covered by Studio scenarios rather than fake pure-Lua tests:

1. Delay `EggHatchResult` after `EggHatchStart`: verify the visible control reads `WAITING`, cannot be activated, and does not dismiss the start scope. Deliver the result, verify it changes to `SKIP`, then skip and confirm the result grid/discovery toasts appear exactly once.
2. Enqueue batch B while batch A is tearing down: pause A inside `onPresented` and verify B cannot create/start its cinematic until A's result grid and discovery enqueueing complete; then verify FIFO advances once.
3. Exercise `start_timeout`, `start_replaced`, surface-creation error, external GUI destruction, CharacterRemoving, and controller cleanup. In every case verify FOV/GUI resources restore, retained callbacks run once in FIFO order, and later accepted batches do not wedge.
4. Hatch an all-Common/Uncommon batch and verify normal title, no Hero FOV/dimming/hold treatment, and standard hold timing despite its designated policy Hero index. Repeat Shiny ties in Normal/Golden/Rainbow base variants and verify the first Shiny remains Hero.
5. After persisted selector hydration, downgrade Multi-Open while x10 or x5 is selected and verify selection reconciles to the highest allowed fixed tier; upgrades that still permit the current tier must preserve it.
6. During a rare Hero FOV tween/hold, open and close the Upgrade Tree first with `Q`, then repeat through the on-screen Open Upgrade Tree button (which remounts `UpgradeTreeGui`). Verify Hatch immediately stops writing FOV and never overwrites the Tree during closing/finalization. For each entry path, test both end states: when the Tree remains open past Hatch finalization, FOV stays at the Tree's open value and returns to its captured base only when the Tree closes; when it is closed during Hero/outro, the Tree completes that same base-FOV restore. Repeat cycles to confirm no stale tween or duplicate observer survives the Hatch scope.

## Audio

Audio infrastructure has `Pop`, `RareAccent`, and `Hero` cues, but all QOF-09 Sound IDs are intentionally empty. Empty IDs create no `Sound` instance, so the feature is silent by default and imports no unapproved asset.

## Persistent batch preference (Schema V7)

Profiles contain:

```lua
hatchPreferences = {
    preferredBatchCount = 1,
}
```

Only x1, x2, x5, and x10 are structurally valid; malformed or unsupported values normalize to x1. Migration and persistence cloning are idempotent. `DataService.getClientData` returns a deep copy without private session metadata. Every read, write, and hatch re-resolves effective Multi-Open entitlement; entitlement loss repairs the saved tier to the highest allowed fixed tier. Player removal clears transient hatch locks without deleting this preference. Client hydration remains entitlement-aware and occurs after controller initialization.

## Boundaries

- The server remains authoritative; no cinematic metadata is added to the hatch DTO.
- The QOF-08 preflight, total debit, all-or-nothing inventory commit, rollback, discovery, quest, and notification behavior is unchanged.
- Permanent in-world Shiny pet rendering remains `PetController` responsibility.
- `UIController` remains the only result-grid owner.
- `upgradeTree.lua`, `upgradeTreeSettings.lua`, and vendored Vide are unchanged.
- The generated `BATTLE_PETS.rbxlx` is regenerated and source-parity verified; Studio runtime/device validation remains pending.
