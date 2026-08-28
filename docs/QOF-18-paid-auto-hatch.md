# QOF-18 Paid Auto-Hatch

## Product and persistence contract

QOF-18 stacks on QOF-17 and activates one canonical `BalanceConfig.Shop.AutoHatch` definition:

| Contract | Value |
|---|---:|
| Access price | 500 Diamonds |
| Access duration | 600 seconds |
| Scheduler interval | 3 seconds |
| Network contract | V1 |
| Persisted fields | `autoHatchExpiresAt`, existing `hatchPreferences.preferredBatchCount` |

`autoHatchExpiresAt` is an absolute `os.time()` value, so offline time counts. DataSchema V9 accepts only a finite integer expiry strictly after `now` and no later than `now + 600`; expired, non-finite, malformed, negative, and impossibly distant values normalize to zero. A purchase grants exactly `now + 600`. Active access cannot be stacked, extended, or overwritten.

The access purchase uses `CurrencyService.beginSpendTransaction`: the exact 500-Diamond debit stays silent while the profile mutation and full DTO are prepared. Any technical failure restores the previous expiry and exact Diamond balance. Only the final currency commit publishes the purchase. Start target, running/paused state, generation, state revision, next tick, reason and in-flight state are transient.

## Concrete Egg-station authority

`ZoneService` owns a module-private registry for all eight runtime Egg stations. Every record retains:

- a stable bounded `stationId` and a unique per-server GUID capability;
- exact Workspace/Folder, pedestal, Egg Part, prompt, tag and interaction-Part references;
- canonical Egg type and zone;
- exact transforms, sizes, shape, anchored/collision/material/color state;
- exact prompt name, parent, enabled state, key, texts, hold duration, line-of-sight and 10-stud distance.

Start validates a real Player, Character and descendant HumanoidRootPart, unlocked station zone, exact capability and live proximity. Follow-up ticks use the same private validator with distance bypassed by the server call site only; station identity, ancestry, integrity, Egg type and zone remain mandatory. Clones, duplicate IDs, copied GUIDs, token swaps, replacement ancestry and property tampering fail closed. There is no highest-zone or other fallback.

Manual hatch quotes continue to use the same exact registry but always require proximity.

## Scheduler and transaction boundary

`AutoHatchService` owns one global 3-second loop. Duplicate starts return without creating another loop. A station session receives a monotonically changing generation and its first batch is eligible only at the next regular tick.

For each player/session:

- at most one batch can be in flight;
- an in-flight tick is skipped, not queued;
- stalls create no backlog and no catch-up batches;
- Stop, leave and station replacement invalidate old completion callbacks;
- `now >= expiresAt` admits no new batch;
- a batch admitted atomically before expiry may finish its existing `EggService` transaction.

Every tick revalidates access, target authority, zone and the exact selected tier. It calls the existing paid `EggService.purchaseAndHatch` path for the full x1/x2/x5/x10 batch and full Coin total. Capacity, entitlement, Hatch lock, pet/discovery/currency rollback, hatch events and quest progress remain EggService-owned. Auto batches explicitly set `consumeShinyCharges = false`; natural server-driven variant rolls remain unchanged.

A structurally invalid persisted tier repairs to x1. A valid x2/x5/x10 tier that later loses entitlement remains stored and pauses `BATCH_NOT_ENTITLED`; it is never mutated or executed as a smaller batch. New selection requests require current entitlement. Manual explicit x1/x3/Max confirmation remains independently revalidated and unchanged.

Stable pause codes include `REJOIN_REQUIRES_STATION`, `BATCH_NOT_ENTITLED`, `INSUFFICIENT_COINS`, `INVENTORY_FULL`, `HATCH_LOCKED`, `STATION_INVALID`, `ZONE_LOCKED`, `ACCESS_EXPIRED`, `TOO_FAR`, `CHARACTER_UNAVAILABLE` and `TECHNICAL_ERROR`. Resource and transient failures retry only at the next regular tick.

Stop removes the target/session without consuming the remaining absolute access. Leave invalidates Auto-Hatch before Egg/Data cleanup and saves the expiry. Rejoin with active remaining time never resumes an old station; the state is stopped with `REJOIN_REQUIRES_STATION` until the player starts again at one concrete station. Closing Shop, the prompt UI, or another screen invalidates local configuration only and never sends Stop.

## Contract V1 and rolling safety

The new RemoteFunctions are `PurchaseAutoHatch`, `GetAutoHatchState`, `SetAutoHatchBatch`, `StartAutoHatch` and `StopAutoHatch`; `AutoHatchStateUpdated` publishes committed/transient state. Every request is an exact plain table with `contractVersion = 1`, its exact action and only bounded action fields. Metatables, extra keys, malformed IDs/tokens and non-finite counts are rejected. Main applies per-action cooldown and burst limits, then AutoHatchService validates again.

The full state DTO includes contract version, monotone revision, server time, runtime/economy values, expiry/remaining time, selected/maximum/available counts, session generation/status, safe station DTO, next hatch time, pause reason and in-flight status. Every response/event is newly constructed or deep-copied.

`SetHatchBatchSize`, `PurchaseShopItem("AutoHatch")`, `_activeBuffs.autoHatch` and `_processAutoHatch` remain discoverable compatibility surfaces but fail closed. ShopService never starts its old highest-zone scheduler. New clients discover every QOF-18 remote/event with `FindFirstChild`, so they cannot wait forever on an older server.

## Client presentation

ShopData and ShopScreen show Auto-Hatch Access at 500 Diamonds for 10 minutes with authoritative active status and a server-time-adjusted countdown. The existing Egg prompt surface adds:

- exact local Egg/station target;
- x1/x2/x5/x10 tier controls;
- Buy, Start and Stop;
- status, remaining access, next tick and stable localized reason text.

`AutoHatchClientSession` owns prompt generation and in-flight response validity; `stateRevision` prevents older responses/events from replacing newer state. Prompt A→B, PromptHidden, close/reopen, navigation and delayed callbacks cannot regain local ownership. No client predicts currency, inventory or pet changes.

Committed auto batches use only the existing `EggHatchStart`/`EggHatchResult` route. `EffectsController` remains the sole cinematic FIFO and bounded `batchId` dedupe owner; QOF-18 creates no second modal or presentation queue.

## Automated verification

```bash
/projects/sandbox/.qof02-lua/lua tests/run_tests.lua
# compile every tracked and untracked .lua file:
/projects/sandbox/.qof10-luau/luau-compile <file>
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tools/generate_rbxlx.py
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/verify_generated_place.py
/usr/bin/python3 -m py_compile tools/generate_rbxlx.py tests/verify_generated_place.py
git diff --check origin/qof-17-rainbow-machine-e2e
```

The generator includes `AutoHatchService` and `AutoHatchClientSession`; the verifier requires byte-exact one-to-one parity for all 72 runtime sources.

## Required Roblox Studio/live checks

These engine/infrastructure boundaries remain manual:

1. **DataStore/offline:** buy access, leave for known wall time, rejoin and confirm remaining time; rejoin must show `REJOIN_REQUIRES_STATION` and no remote continuation.
2. **DataStore corruption:** inject expired, non-finite (where tooling permits), fractional and `now + 601` expiries in a test store; all invalid cases must load inactive.
3. **Atomic purchase:** with 500 and 499 Diamonds, verify exact success/failure; inject a server-side test fault before commit and confirm no CurrencyUpdated event or lost Diamonds.
4. **Station authority:** start at each Egg; test 10/10.001 studs, locked zones, respawn without HRP, cloned Eggs, copied attributes, swapped GUIDs, reparenting and prompt/property edits.
5. **Cadence:** observe first hatch only on the next regular tick, then one full batch per three seconds; simulate server hitch and confirm no catch-up burst.
6. **Concurrency:** spam Start/Stop/tier/purchase from two clients and overlap a manual hatch; confirm one per-player batch, stable pause state and no duplicate loop.
7. **Entitlement loss:** save x10, remove the x10 entitlement in a controlled test profile, rejoin/start and confirm x10 remains selected with `BATCH_NOT_ENTITLED` and no smaller hatch.
8. **Economy/capacity:** test exact Coin totals and free-slot boundaries for x1/x2/x5/x10; failures must produce zero pets and no partial/smaller batch.
9. **Shiny charges:** hold Shiny Potion charges during auto batches and verify charges remain unchanged; manual hatch still consumes them.
10. **Expiry race:** begin a batch just before expiry and confirm that batch can commit, while the exact-expiry tick starts nothing new.
11. **UI generations:** Prompt A→B, PromptHidden, Shop close/reopen, navigation, delayed responses and server state events; only the newest revision/local owner may render.
12. **Rolling deployment:** new client behavior against a server without QOF-18 remotes must disable gracefully; old AutoHatch purchase/batch remotes against QOF-18 must remain mutation-free.
13. **Presentation:** let auto batches outpace rare cinematics and verify the existing FIFO presents each unique `batchId` once without stacked modals.
14. **Live multiplayer/DataStore:** test server transfer, leave during in-flight work, shutdown save, reconnect and simultaneous players under normal latency.
