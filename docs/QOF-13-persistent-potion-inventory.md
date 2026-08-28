# QOF-13 – Persistent Potion Inventory

## Status

**Code-verifiziert – Roblox-Studio-Test ausstehend.** Source, 167-test regression suite, generated-place parity, semantic review, binary `BATTLE_PETS_QOF-13_TEST.rbxl`, and browser-friendly `BATTLE_PETS_QOF-13_RBXLX.zip` are complete. QOF-13 replaces immediate potion activation at purchase time with a server-authoritative purchase into the existing persistent V7 `potionInventory`. Drinking, active effects, absolute timers, potion slots, duration upgrades, Shiny charges, and Auto-Drink remain disabled for QOF-14.

## Canonical purchase catalog

| Potion ID | Price | Stored future effect |
|---|---:|---|
| `LuckPotion` | 100 Diamonds | x2 Luck for 600 seconds when consumed |
| `MegaLuckPotion` | 350 Diamonds | x5 Luck for 300 seconds when consumed |
| `SpeedPotion` | 50 Diamonds | x2 Walk Speed for 300 seconds when consumed |
| `CoinPotion` | 125 Diamonds | x2 Coin rewards for 600 seconds when consumed |
| `ShinyPotion` | 1,000 Diamonds | x10 Shiny chance for three hatch charges when consumed |

Each potion count is independently capped at 999. `LuckyPotion` and `PowerPotion` remain legacy compatibility data only and are not valid QOF-13 products. They are not migrated because previous purchases created process-local effects rather than persistent inventory. `ExtraEquipSlot` remains a separate permanent purchase with its existing 1,000-Diamond price and five-purchase maximum. Auto-Hatch remains fail-closed.

## Server-authoritative transaction

Canonical potion purchases use the exact bounded V2 request:

```lua
{
    contractVersion = 2,
    action = "purchasePotion",
    itemId = "LuckPotion", -- canonical whitelist only
    quantity = 1,
}
```

The client never supplies price, currency, effect, duration, resulting count, or activation state. Legacy potion strings—including the overlapping `SpeedPotion` and `CoinPotion` IDs—are rejected without debit. The only retained string purchase is `ExtraEquipSlot`; `AutoHatch` is admitted only to return its explicit dormant message.

`ShopService` serializes purchases per player, validates profile and inventory before debit, resolves price from `BalanceConfig.Potions.Catalog`, and opens an opaque silent debit through `CurrencyService.beginSpendTransaction`. It mutates exactly one inventory count, constructs the authoritative state, and then commits the currency transaction, which emits the first balance event. Injected faults after debit, after mutation, or during state construction restore the exact previous inventory key and roll back against the already captured profile without a second DataService lookup or client event. `ShopBuffsUpdated` is sent only after the currency and inventory state have committed; a failed replication event cannot roll back an already committed purchase.

Buying a potion never writes `activeBuffs`, never writes the legacy in-memory buff map, and never refreshes Movement. Therefore purchase alone cannot change WalkSpeed, hatch luck, Shiny chance, pet damage, Coin rewards, pickup claims, or hatch behavior.

## State and persistence contract

The shop state is a fresh V2 DTO:

```lua
{
    contractVersion = 2,
    purchaseMode = "inventoryOnly",
    potionInventory = { [canonicalPotionId] = count },
    maxPotionInventory = 999,
    purchases = { extraEquipSlots = count },
    maxExtraEquipSlots = 5,
    buffs = {}, -- read-only legacy compatibility projection
}
```

Nested state is copied away from the live profile and from the event payload. `DataService.getClientData` independently deep-copies potion inventory, active buff state, and upgrades. Existing V7 normalization already whitelists canonical IDs, floors counts, rejects non-finite values, caps each count at 999, and includes the inventory in save snapshots. No schema bump is required.

## Client and rolling compatibility

`ShopData` now presents exactly the five canonical potion cards plus `ExtraEquipSlot`. Potion cards display server-confirmed `OWNED n/999 • STORED` state and do not show `ACTIVE` or a countdown. The old 0.25-second shop timer heartbeat is removed. Potion BUY buttons remain disabled until the server advertises `contractVersion = 2` and `purchaseMode = "inventoryOnly"`; an old server therefore cannot accidentally interpret a new purchase as immediate activation. New servers reject old potion-string clients without charging them.

The shop retains its responsive one-/two-column scrolling layout and device-neutral `Activated` controls. The Potion Shop proximity prompt and HUD navigation continue to open the same screen. Runtime focus, narrow-phone layout, and gamepad navigation remain Studio validation items.

## Automated verification

Current source verification covers:

- Pure-Lua behavior suite: **167 passed, 0 failed**.
- All five canonical IDs and server-owned prices.
- Exact V2 request shape, unknown/legacy rejection, insufficient balance, missing profile, and per-player lock.
- Independent 998→999 boundary, full-cap rejection before debit, and per-potion isolation.
- Exact rollback after spend, mutation, and authoritative-state construction faults.
- No event before commit; protected post-commit replication; independent returned/event DTOs.
- No potion activation, timer, charge, Movement refresh, or Gameplay multiplier at purchase.
- `ExtraEquipSlot` and Auto-Hatch regressions.
- V7 inventory normalization, deep-copy projection, persistence cloning, migration roundtrip, and legacy-ID removal.
- Luau compilation and `git diff --check`.
- Generated-place parity for all 66 Runtime-Sources.
- Binary RBXL `<roblox!` signature and binary-to-XML roundtrip parity.
- Browser ZIP with exactly one byte-identical `BATTLE_PETS.rbxlx` entry.
- Semantic behavioral review: **APPROVED**.

## Roblox Studio validation scenarios

Studio is unavailable in the release sandbox. The final test build must be checked as follows:

1. Open the Potion Shop from both the HUD and `PotionShopPrompt`. Confirm exactly five potion cards plus Extra Equip Slot; `LuckyPotion`, `PowerPotion`, and Auto-Hatch must not appear.
2. Verify exact prices: 100, 350, 50, 125, and 1,000 Diamonds. Buy each potion once and confirm exactly one debit and `OWNED 1/999 • STORED`.
3. Buy multiple copies of one potion and verify only that potion count changes. Reopen the shop and confirm the server value is retained.
4. Buy Speed, Luck, Mega Luck, Coin, and Shiny potions while observing WalkSpeed, hatch odds/results, Coin rewards, and Shiny behavior. None may activate from purchase alone.
5. Leave and rejoin after purchases. Confirm Diamond balance and all potion counts persist together.
6. With insufficient Diamonds, attempt every item. Confirm no count or balance changes and a clear error is shown.
7. Test Extra Equip Slot purchase/max behavior and verify equipped-pet capacity still changes exactly as before without touching potion inventory.
8. Rapidly click BUY, reopen the shop during purchase, and test two devices for one account sequentially. Confirm no duplicate debit, skipped count, stale optimistic value, or stuck button.
9. Test PC, phone, tablet, touch, keyboard, and gamepad. Verify one-/two-column layout, scrolling, readable long names, close behavior, focus, and safe-area/header spacing.
10. Regression-test QOF-12 pickups/Movement, QOF-11 Double Luck, hatching, pet equip/storage, campaign rewards, and DataStore rejoin behavior.

## Known boundary

Automated verification cannot execute Roblox engine replication, real DataStore sessions, live UI sizing/input routing, or multiplayer timing. QOF-13 intentionally provides inventory acquisition only: there is no drink button, no activation remote, no active-effect UI, and no gameplay effect. Those behaviors belong to QOF-14 and must not be inferred from the stored catalog metadata.
