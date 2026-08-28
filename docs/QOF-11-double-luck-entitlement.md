## Status

## Status

**Source implementation, automated verification, generated-place parity, and binary artifacts complete; Roblox Studio validation pending.** QOF-11 is a deliberately narrow, server-authoritative release that activates only Double Luck on top of QOF-10. Speed and Magnet remain unavailable. The profile schema remains V7 because the existing `upgradeTreePurchases` Boolean map can persist the new ID without a migration.

## Canonical entitlement

Double Luck is defined once in `BalanceConfig.CoreUpgrades.DoubleLuck`:

- ID: `doubleLuck`.
- Requirement: `Eggs II`.
- Price: 5,000 Diamonds.
- Effect: x2 general hatch luck.
- UI location: the existing Variant Chances tree, connected to `luckBack`.

The new save-safe ID is intentional. Legacy `luck I` through `luck IV` flags retain their old meaning and remain dormant; they are never reinterpreted as Double Luck. A forged or incomplete save containing `doubleLuck = true` without `Eggs II = true` receives no effect. New purchases are validated and charged by `UpgradeTreeService`, which owns the ID, prerequisites, currency, and amount. Duplicate, unavailable, concurrent, and insufficient-balance requests fail before a second debit.

## Server-authoritative luck composition

`UpgradeTreeService.resolveEntitlements` returns a neutral `generalLuckMultiplier = 1` unless the complete active Double Luck requirement is present. `PetService` then composes one server-owned entitlement snapshot with the existing Quest, Mastery, and Shop sources:

```text
GeneralLuck = min(maximum useful existing cap,
                  LuckyEggs × BetterLuck × ShopLuck × TreeDoubleLuck)
```

`PetHatchMath` normalizes missing, malformed, non-finite, zero, negative, and sub-neutral values to x1. The aggregate remains capped at x10 because no currently approved species, Golden, Rainbow, or Shiny probability can benefit beyond that value. Existing final caps remain unchanged:

- Species multiplier: x10.
- Golden chance: 5%.
- Rainbow chance: 0.5%.
- Shiny chance: 0.1%.

Egg Quality remains species-only, while direct Golden/Rainbow/Shiny entitlements remain variant-specific. QOF-11 does not increase any cap or change base probabilities.

## Client and lifecycle boundary

The existing generic Upgrade Tree client renders the new `doubleLuck` data node, its Diamond price, requirement state, and authoritative purchase result. No client-supplied multiplier, cost, prerequisite, or entitlement is trusted. Hatch preparation resolves the complete tree entitlement table once and uses that same snapshot for both general Luck and direct hatch modifiers throughout the atomic batch.

No new visual effect, movement listener, collection loop, DataStore field, remote, or character lifecycle hook is introduced. This keeps the slice isolated from QOF-12.

## Deferred to QOF-12

- **Speed:** requires a centralized movement service, explicit total cap, character respawn reapplication, and hardened composition with existing speed sources.
- **Magnet:** requires a server-owned pickup/claim layer; the current currency flow credits rewards immediately and its collection remote is visual-only.

The raw FBX/Blend egg-model experiment remains isolated on `demo/egg-3d-models` and is not included in QOF-11.

## Automated verification

The release verification covers:

- Pure-Lua behavior suite: **132 passed, 0 failed**.
- Canonical ID, requirement, price, multiplier, availability, duplicate debit, legacy no-op, malformed input, and existing cap behavior.
- Luau compilation of runtime and test sources.
- Python syntax, JSON parsing, XML parsing, and `git diff --check`.
- Generator execution and byte-exact generated-place source parity.
- Expected generated script inventory: **62 ModuleScripts, 1 Script, 1 LocalScript**.
- Semantic behavioral review before release publication.

## Roblox Studio validation scenarios

Studio is not available in the release sandbox, so the following runtime checks remain mandatory:

1. Open Variant Chances without `Eggs II`; verify Double Luck is visible but locked, shows 5,000 Diamonds, and cannot debit.
2. Buy `Eggs I`, then `Eggs II`, then Double Luck. Verify exactly 5,000 Diamonds are removed once, the node becomes purchased, and a duplicate click does not debit.
3. Rejoin after purchase. Verify `doubleLuck` remains purchased and the effect still resolves from the server-owned V7 profile.
4. Compare a controlled hatch sample before and after purchase while all other Luck sources are neutral. Verify effective general Luck changes from x1 to x2 without changing the displayed or enforced chance caps.
5. Combine Lucky Eggs x2 with Double Luck x2 and neutral Mastery/Shop values; verify the effective multiplier is x4. Combine sources above x10 and verify x10 remains the useful aggregate cap.
6. Load a diagnostic profile with legacy `luck I-IV` only; verify it receives no Double Luck effect. Load `doubleLuck = true` without `Eggs II`; verify the effect remains x1.
7. Hatch x1 and Multi-Open batches after purchase; verify every pet in one atomic batch uses the same entitlement snapshot and existing QOF-09 cinematics still run exactly once.
8. Verify Speed and Magnet remain unavailable and that normal movement, respawn, reward collection, storage, equip capacity, and hatch confirmation behavior are unchanged.

## Known boundary

Automated verification cannot substitute for Roblox Studio engine execution, DataStore session behavior, live replication, UI layout/input routing, or statistical runtime sampling. Those checks remain pending and must be recorded against the scenarios above before promoting the build beyond QOF validation.
