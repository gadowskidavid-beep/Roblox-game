# QOF-14 — Potion Consumption and Buffs

**Status:** Code-verifiziert; Studio-Test ausstehend.

## Authority and contracts

Potion purchases remain QOF-13 inventory-only transactions owned by `ShopService`. `PotionService` independently owns consumption, effects, potion upgrades, Auto-Drink selection, reconciliation, and its V1 state DTO/event. The three mutation remotes accept only exact versioned request tables:

- `ConsumePotion`: `{ contractVersion = 1, action = "consumePotion", potionId }`
- `PurchasePotionUpgrade`: `{ contractVersion = 1, action = "purchasePotionUpgrade", upgradeId }`
- `SetAutoDrinkSelection`: `{ contractVersion = 1, action = "setAutoDrinkSelection", potionId, selected }`

Clients render only returned or pushed authoritative state. Every potion snapshot carries a per-session monotonic `stateRevision`, and the client ignores older snapshots so concurrent fetches cannot regress a newer consume/expiry/Auto-Drink result. Purchase prices and upgrade prices are resolved from `BalanceConfig` on the server.

## Persistence and migration

Schema V8 stores each timed potion independently under its shared buff type, for example:

```lua
activeBuffs = {
    luck = {
        sources = {
            LuckPotion = { expiresAt = 1700000000 },
            MegaLuckPotion = { expiresAt = 1700000300 },
        },
    },
    shinyChance = { charges = 3 },
}
```

Each source extends only itself. The highest active source multiplier applies, while the containing buff type consumes one slot. Legacy V7 numeric timers migrate conservatively to canonical x2 Luck, Speed, or Coin sources. Expiry uses `os.time`, is bounded by the existing persistence cap, and therefore advances while offline. `autoDrinkSelection` is a separate catalog-whitelisted persistent map that defaults empty; Shiny is not selected implicitly.

V8 also dual-writes timed source identity and expiry to the server-private top-level `potionBuffSources` mirror. A rolling QOF-13 server preserves that unknown field even though its V7 normalizer drops structured `activeBuffs` and stamps `schemaVersion = 7`. On the next V8 load, migration validates the mirror against the authoritative catalog, removes expired/malformed/unknown entries, clamps the 30-day horizon, restores each source to its catalog-owned buff type, and synchronizes the mirror from canonical `activeBuffs` at every persistence boundary. When both copies are valid, the later expiry wins so a rolling save cannot shorten an effect. The mirror is never projected to clients and never participates in runtime effects or slot counting; Luck and Mega Luck remain two source identities inside one `luck` slot.

## Runtime behavior

- Luck composes through the existing hatch-luck multiplier seam.
- Speed composes through `MovementService`; activation and expiry request an authoritative refresh.
- Coin Potion is sampled only at the existing breakable-destruction reward snapshot before delayed pickup credit.
- Shiny Potion grants three x10 direct-Shiny rolls, capped at 30 charges. Paid manual hatch intent reserves one charge per boosted egg and applies it to the first N batch rolls. Any hatch rollback restores the exact charge state. Free, campaign compatibility, and station-bypass hatches do not consume charges by default.
- Active slots count distinct active buff types, including nonzero Shiny charge state.
- Duration upgrades are sampled only when drinking a timed potion and never alter existing timers or Shiny charges.
- Manual timed consumption is rejected before inventory mutation when that source is exactly at the moving 30-day expiry cap. Near-cap consumption is intentionally allowed as a partial extension and clamps exactly to the cap.
- Auto-Drink runs only for online players, in canonical catalog order, through the same locked consume transaction. It drinks selected timed sources only when that exact source is missing/expired, and Shiny only at zero charges.
- Upgrade debit uses the silent currency transaction boundary; any pre-commit fault restores profile and currency state without publishing an intermediate balance.

## UI

The procedural Potion Shop now includes Buy and Drink controls, per-potion active timers/charge counts, distinct-slot and Duration status, server-priced slot/Duration/Auto-Drink upgrade controls, and a per-potion Auto-Drink toggle. The authoritative potion DTO includes per-potion consume availability from the same server preflight used under the mutation lock; the UI disables Drink and shows `30D CAP` at the exact timed cap, but the server remains the authority for every request. The shop fetches both purchase and potion state on initialization and whenever opened, and listens for independent potion-state pushes.

## Automated verification

The pure-Lua suite currently passes **192 tests** covering V8 migration, the V8 → simulated QOF-13 structured-source wipe/schema downgrade → V8 recovery path, mirror filtering/synchronization and expiry caps, independent Luck sources, exact-cap rejection and near-cap partial extension, selection whitelisting, consume rollback, slot rules, source extension and precedence, duration-at-consume, Shiny caps/reservations, hatch commit/rollback policy, Auto-Drink ordering/thresholds, strict DTOs, Shop delegation, and expiry refresh. The place generator/verifier expects 65 ModuleScripts plus one server Script and one LocalScript (67 runtime sources).

## Roblox Studio checks

1. Buy each potion and confirm no effect starts until **Drink** is pressed.
2. Drink Luck and Mega Luck, verify one active slot, independent timers, x5 precedence, and same-source extension.
3. Fill distinct slots and verify a new buff type is rejected until a slot expires or is upgraded.
4. Verify Speed applies immediately and clears after expiry/respawn reconciliation.
5. Destroy a breakable before/after Coin Potion expiry and confirm the pickup retains the destruction-time snapshot.
6. Drink Shiny, manually buy x1/x3/Max eggs, and verify only the first charged rolls are boosted and charges decrement by committed egg count.
7. Force/observe failed hatch transactions and confirm pets, currency, and Shiny charges all restore exactly.
8. Verify campaign reward, free, and bypass hatches do not consume Shiny charges.
9. Purchase Duration and confirm only newly consumed timed potions use the new duration.
10. Purchase Auto-Drink, select individual potions, rejoin, and verify no offline consumption plus online refill only at the documented thresholds.
11. Seed a timed source at the exact 30-day cap and confirm Drink is disabled and a direct request is rejected without inventory/revision changes; seed it just below the cap and confirm the partial top-off reaches the cap.
12. During a staged rolling deployment, verify a QOF-13 load/save preserves `potionBuffSources` and a later V8 load restores independent Luck/Mega Luck, Speed, and Coin expiries.

## Known limitation

Roblox Studio multiplayer/DataStore/UI interaction validation remains pending. Pure-Lua and generated-place verification cannot visually validate layout at every device aspect ratio or exercise live DataStore/network scheduling. The rolling QOF-13 compatibility mirror protects timed source data without relying on a complete server drain; operational rollout monitoring is still required to confirm live DataStore behavior and eventual retirement of the compatibility field.
