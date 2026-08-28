# QOF-10 — Storage and Pet Equip Entitlements

## Status

**Source implementation complete; automated verification and generated-place parity complete; Roblox Studio validation pending.** QOF-10 activates only the Storage and Pet Equip capacity branches, adds a server-authoritative hatch purchase confirmation dialog, and keeps the future Auto-Hatch feature unavailable on both catalog and runtime surfaces. Profile schema remains V7 because no new persisted field is introduced.

## Capacity entitlements

QOF-10 reuses the existing `upgradeTreePurchases` flags so existing saves remain valid:

- Storage I–VI: `playtime1`, `playtime2`, `playtime3`, `streak1`, `streak2`, `streak3`.
- Pet Equip I–III: `friends1`, `friends2`, `friends3`.
- Both branch roots require `Eggs II` for new purchases.
- Speed, Magnet, Double Luck, Potions, Machines, Enchanting, and Pet Dex remain dormant.

Legacy effects and new purchases are intentionally separate. The entitlement resolver grants the value of the highest contiguous capacity prefix, even when an old save predates the external `Eggs II` gate. It stops at the first missing branch ID, so sparse or forged later flags grant no skipped value. Every new capacity purchase still checks `Eggs II` in addition to its direct branch prerequisite. Grandfathering therefore preserves earned effects without creating a purchase bypass.

The server-authoritative limits are:

```text
Inventory = clamp(100 + ExtraSlots quest + Tree Storage, 100, 250)
Equip     = clamp(3 + Friendship + MorePetSlots mastery
                    + legacy shop slots + Tree Pet Equip, 3, 12)
```

`PetService` owns enforcement. The inventory UI uses the same shared `BalanceConfig.Limits` values and observes the same initial and subsequent Upgrade Tree state handled by `UpgradeTreeController`.

## Manual hatch purchase confirmation

Pressing `E` at an egg station no longer debits immediately. It opens one reusable, safe-inset-aware dialog and requests a fresh read-only server quote. The dialog offers:

- **x1** — one egg when one purchase is feasible.
- **x3** — shown only when the player's Multi-Open entitlement cap is at least three; enabled only when coins and inventory also permit three.
- **MAX xN** — the greatest currently feasible amount, bounded by entitlement, free inventory slots, Coins, and the hard transaction maximum of ten.
- **Refresh Quote** and **Cancel**.

Buttons retain a minimum 132×52 touch target. The panel reflows its footer vertically on narrow or short safe-area viewports, while egg options remain scrollable.

The client sends only one of three strict intents:

```lua
{ mode = "Fixed", count = 1 }
{ mode = "Fixed", count = 3 }
{ mode = "Max" }
```

Raw numeric counts, unknown modes, additional keys, malformed values, and unavailable options are rejected. `MAX` is never trusted from a previous quote or client-supplied number. Confirmation acquires the per-player hatch lock first, then resolves fresh entitlement, proximity, zone access, Coins, and free slots inside the same hatch critical section. The transaction revalidates capacity and entitlement, charges the complete total once, commits the complete prepared pet batch, and compensates both inventory and currency if commit fails. Manual purchases never read or mutate `hatchPreferences`.

Prompt replacement, `PromptHidden`, navigation, character removal, cancel, and controller cleanup invalidate pending client request tokens and close the dialog. Late quote or purchase responses cannot reopen or update a stale dialog. QOF-09 `EffectsController` remains the sole Hatch Cinematic owner after an authoritative purchase succeeds.

## Auto-Hatch boundary

`BalanceConfig.Shop.AutoHatchRuntimeEnabled` is `false` for QOF-10. Consequently:

- Auto-Hatch is absent from `ShopData.Items` and `ShopData.Order`.
- Direct server purchase attempts fail before debit.
- No Auto-Hatch loop starts, and stale in-memory buffs are ignored.
- The rolling `SetHatchBatchSize` remote remains present for compatibility but fails closed before mutating the persisted preference.

The V7 preference is preserved for a later owning QOF, but QOF-10 exposes no active way to buy, configure, or run Auto-Hatch.

## Automated verification

The release verification covers:

- Pure-Lua behavior suite: **127 passed, 0 failed**.
- Luau 0.735 compilation of every tracked and newly added `.lua` file.
- Python syntax compilation, JSON parsing, XML parsing, and `git diff --check`.
- Generator execution and exact generated-place source parity.
- Expected generated script inventory: **62 ModuleScripts, 1 Script, 1 LocalScript**.
- Semantic behavioral review: **APPROVED** with no merge-blocking issue.

## Roblox Studio validation scenarios

Studio is not available in the release sandbox, so these runtime/device checks remain mandatory:

1. At a Basic Egg, press `E`; confirm no Coins are removed until x1, x3, or MAX is explicitly confirmed. Cancel and verify no mutation.
2. With Multi-Open caps 1, 2, 5, and 10, verify x3 is hidden for caps 1/2 and shown for caps 5/10. Verify unavailable coin/slot states disable the appropriate visible choices.
3. Change Coins or inventory while the dialog is open, then confirm MAX. Verify the server uses the new feasible count rather than the displayed stale count; use Refresh to display the new quote.
4. Test 320×480 portrait, narrow landscape, tablet, desktop, touch safe insets, keyboard Escape, and gamepad B. Verify no overlap and touch targets remain usable.
5. Walk away, hide/replace the prompt, teleport via navigation, respawn, and cancel while a quote is pending. Verify late responses do not reopen or alter the dialog.
6. Hatch x1, x3, and MAX batches and verify QOF-09 cinematics/result grids run exactly once, Coins equal `unit price × count`, and inventory receives the complete batch.
7. Load legacy saves with full and sparse capacity flags but no `Eggs II`. Verify only the contiguous prefix grants capacity, then verify every new capacity purchase remains blocked until `Eggs II` is owned.
8. Verify the shop has no Auto-Hatch card and that no background hatch or preference change occurs during normal play.

## Known boundary

Automated verification cannot substitute for Roblox Studio's engine UI layout, input routing, camera, DataStore session behavior, or live replication. Those checks remain pending and must be recorded against the scenarios above before promoting the test build beyond QOF validation.
