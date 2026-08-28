## Status

**Code-verifiziert – Roblox-Studio-Test ausstehend.** Source, Pure-Lua regression suite, generated-place parity, binary `BATTLE_PETS_QOF-12_TEST.rbxl`, and browser-friendly `BATTLE_PETS_QOF-12_RBXLX.zip` are complete. QOF-12 activates only the Movement Speed and Magnet branches on top of QOF-11. It centralizes WalkSpeed authority and introduces a real server-owned currency pickup/claim boundary for world breakables. Profile schema remains V7 because the existing `upgradeTreePurchases` Boolean map persists every new entitlement ID.

## Canonical Upgrade Tree contracts

Every new purchase requires `Eggs II` at its branch root and then follows a strict contiguous chain. Legacy IDs are not reinterpreted.

Movement Speed:

| ID | Total tree multiplier | Cost |
|---|---:|---:|
| `coreSpeed1` | x1.05 | 5,000 Coins |
| `coreSpeed2` | x1.10 | 25,000 Coins |
| `coreSpeed3` | x1.15 | 100,000 Coins |
| `coreSpeed4` | x1.20 | 300,000 Coins |

Magnet:

| ID | Total tree multiplier | Cost |
|---|---:|---:|
| `coreMagnet1` | x1.25 | 10,000 Coins |
| `coreMagnet2` | x1.50 | 50,000 Coins |
| `coreMagnet3` | x2.00 | 200,000 Coins |

The old `eggSpeed I-III` branch remains dormant and keeps its historical roll-speed meaning. Sparse, forged, unknown, or prerequisite-incomplete QOF-12 flags grant neutral x1 entitlements. Costs, prerequisites, availability, debit, mutation, rollback, and replicated state remain server-owned by `UpgradeTreeService`.

## Central movement authority

`MovementService` is the only runtime owner of `Humanoid.WalkSpeed`:

```text
WalkSpeed = clamp(16 × Sprinting × FasterRunning × ShopSpeed × TreeSpeed,
                  16,
                  128)
```

Missing, malformed, non-finite, zero, negative, and sub-neutral sources normalize to x1. The service binds an already-present character after profile load, every later respawn, delayed Humanoid creation, and both normal and pre-script player paths. Character generations and listeners are cleaned on removal. Successful Mastery, Shop, and Upgrade Tree purchases refresh immediately; a one-second server reconciliation also catches quest progression, timed Speed Potion expiry, and competing WalkSpeed property writes.

This is entitlement and property authority, not a full movement anti-cheat. QOF-12 does not add displacement policing for client CFrame, velocity, teleport, seat, knockback, or network-ownership anomalies; those require a separate exemption-aware security slice.

## Server-owned Magnet pickups

World destructible Coins and Diamonds no longer mutate balances at destruction. Contribution allocation remains unchanged, including disconnected-contributor reallocation and deterministic remainder conservation. The server then:

1. Resolves each contributor's Shop and quest/mastery reward bonuses exactly once at destruction, including a single DropCloner roll.
2. Stores the resulting integer amount in an owner-bound transient pickup record.
3. Replicates a cosmetic neon pickup Part; attributes are presentation only and never authority.
4. Polls server character position every 0.2 seconds and claims only within the effective radius.
5. Performs one exact bonus-free reward credit, removes registry authority and the visual, advances `earnCoins`, then fires the existing outbound `CollectCurrency` popup event.

```text
PickupRadius = clamp(8 × TreeMagnet × DropMagnetMastery, 8, 32 studs)
```

There is no inbound pickup or currency remote. Clients never supply pickup amount, currency, owner, position, radius, or entitlement. Wrong-owner, unknown, malformed, out-of-range, duplicate, and already-claiming requests fail without mutation. A failed exact credit returns the record to pending.

Pending pickups are capped at 24 per player. They settle after 15 seconds and synchronously on player leave before profile save, preserving the pre-QOF-12 economy guarantee that valid breakable rewards are not lost if a player does not walk over the visual. XP and `destroyDestructibles` progression remain immediate. Campaign rewards, admin grants, refunds, shop purchases, and hatch transactions remain outside the pickup layer.

Both pet-attack and Crit-QTE destruction now use one finalizer for drop resolution, contributor rewards, replication, target cleanup, model destruction, and respawn.

## Client, effects, and lifecycle

The generic Upgrade Tree controller renders the seven new Player-tree nodes and continues to send only a bounded upgrade ID. Existing currency popups and onboarding react to `CollectCurrency` only after an authoritative claim commits. No client claim controller, amount-bearing request, movement setter, or schema field is introduced.

The raw FBX/Blend egg-model experiment remains isolated on `demo/egg-3d-models` and is not included in QOF-12.

## Automated verification

The release verification covers:

- Pure-Lua behavior suite: **150 passed, 0 failed**.
- Exact IDs, chains, costs, multipliers, caps, availability, duplicate prevention, rollback, and legacy isolation.
- Existing-character, delayed-character, respawn, removal, source composition, malformed values, heartbeat reconciliation, and WalkSpeed restoration.
- Owner/range validation, range cap, exact-once credit, failed-credit retry, timeout/leave settlement, malformed pickup rejection, and visual cleanup.
- Earned reward snapshot followed by exact delayed credit without reapplying bonuses.
- Luau compilation, Python syntax, JSON/XML parsing, and `git diff --check`.
- Generator execution and byte-exact generated-place source parity.
- Binary RBXL signature plus binary-to-XML roundtrip source parity.
- Browser ZIP contains exactly the byte-identical `BATTLE_PETS.rbxlx` entry.
- Expected generated script inventory: **64 ModuleScripts, 1 Script, 1 LocalScript**.
- Semantic behavioral review before release publication.

## Roblox Studio validation scenarios

Studio is unavailable in the release sandbox, so these engine checks remain mandatory:

1. Without `Eggs II`, verify all Movement and Magnet roots are locked and no Coins are removed. Buy the full chains and verify each exact cost, strict order, purchased state, and duplicate rejection.
2. Verify neutral WalkSpeed is 16. Test Sprinting, FasterRunning, Speed Potion, and each tree stage independently and together; confirm total WalkSpeed never exceeds 128.
3. Purchase or unlock movement sources while alive, let a Speed Potion expire while idle, respawn repeatedly, reset during load, and test an already-spawned character. Verify authoritative speed updates within one second and survives no stale character listener.
4. Destroy a breakable and verify Coins/Diamonds do not change immediately when outside pickup range. Move inside 8 studs and verify exactly one balance update, one popup, visual removal, and correct `earnCoins` increment.
5. Test Magnet stages at 10, 12, and 16 studs with neutral DropMagnet. Combine Tree x2 and DropMagnet x3; verify the effective radius stops at 32 studs and a pickup just beyond the boundary remains pending.
6. With two players contributing, verify owner-specific pickups cannot be collected by the other player and proportional totals/remainders match the destroyed reward.
7. Trigger simultaneous pet and Crit-QTE destruction attempts, rapid movement across the boundary, death/respawn near a pickup, and duplicate visual contact. Verify each pickup credits exactly once.
8. Leave with pending pickups and allow another pickup to time out. Verify both settle once before save/after 15 seconds and remain correct after rejoin.
9. Verify Coin Potion, LuckyDrops, CoinCollector, DropCloner, Diamonds bonuses, and DropMagnet are applied once at their documented phase; changing a bonus after destruction must not alter a pending amount.
10. Verify campaign victory, admin grants, purchases/refunds, hatch costs, storage/equip capacity, Double Luck, and QOF-09 cinematics remain unchanged.
11. Test desktop, mobile, touch, keyboard, and gamepad tree navigation. Verify the new upper/lower Player-tree branches do not overlap and prices/lock states remain readable.

## Known boundary

Automated verification cannot substitute for Roblox Studio engine execution, live replication, physics/network ownership, DataStore sessions, runtime UI layout/input routing, or multiplayer race observation. Pickup visuals are globally replicated but owner authority is server-only. The 15-second and leave settlements intentionally preserve reward value rather than enforcing permanent loss for missed physical collection. These choices and the scenarios above must be validated before promotion beyond QOF testing.
