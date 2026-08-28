# QOF-15 Machine Transaction Foundation

## Status

QOF-15 adds a production transaction foundation for Gold and Rainbow machines without making machines publicly usable. `BalanceConfig.Machines.RuntimeEnabled` remains `false`. `Main.server.lua` initializes `MachineService`, injects `QuestService`, and clears per-player locks on removal, but deliberately does **not** add a remote, event, station, prompt, client UI, or activation validator. Consequently, every public attempt fails closed. Runtime world authority and activation belong to a later QOF.

The retained `ConvertToGoldenPet` remote continues to call `PetService.convertToGoldenPet` with its existing no-price legacy behavior. It is intentionally not delegated to `MachineService` until QOF-16.

## Canonical definitions

| Machine | Zone | Conversion | Price |
|---|---:|---|---:|
| `GoldMachine` | 3 | Normal → Golden | 750 Diamonds |
| `RainbowMachine` | 6 | Golden → Rainbow | 2,500 Diamonds |

Both machines accept a dense list of 1–7 unique owned pet instance IDs. Their exact success chances are 13%, 26%, 39%, 50%, 63%, 88%, and 100%. Inputs must share one species and the configured source variant. Favorite pets and pets equipped through either `pet.equipped` or `equippedPets` are rejected. If any input is Shiny, a successful output is Shiny; Shiny remains an independent modifier.

## Transaction boundary

`MachineService.attemptConversion` applies this order under a per-player lock:

1. Check the dormant runtime gate, player, machine ID, strict ID-list shape, dependencies, and presence of an injected activation validator.
2. Check loaded profile, unlocked machine zone, and the injected authoritative activation result.
3. Ask `PetService.prepareVariantConversion` to validate every pet and build a canonical output without mutation.
4. Begin one silent exact debit with `CurrencyService.beginSpendTransaction`.
5. Roll once through the injectable random source and commit the pet mutation through `PetService.commitVariantConversion`.
6. Commit currency once, then replicate inventory once.
7. After a committed successful Gold conversion only, increment `goldenPetsConverted` once. Rainbow and failed rolls never increment it.

A normal failed roll is a committed business outcome: it consumes the exact configured price and all inputs but creates no output. A success consumes the same price and inputs and creates exactly one output.

Unexpected errors before the final currency commit call `PetService.rollbackVariantConversion` and `CurrencyService.rollbackSpendTransaction`. Pet rollback restores the original inventory table object and original pet references in their original order. Discovery rollback is ownership-scoped: it reverses only the key/value written by this transaction while the same table and written value remain current, removes a transaction-created table only if it is still empty, and preserves unrelated keys or replacement tables produced by concurrent work. Silent currency rollback emits no misleading client balance event. Post-commit inventory and quest notifications are protected so transport failures cannot make a completed transaction retryable.

## Pet authority

The mutation-free PetService prepare API derives output fields from the existing canonical helpers:

- `PetVariantPresentation.resolve` for names (`Gold`, `Rainbow`, and composed Shiny labels)
- `PetVariantMath.getBaseDamage` for the compatibility damage mirror
- `getLegacyDiscoveryKey` for the current four-category discovery contract
- `golden = outputVariant == "Golden"` as a compatibility mirror only

Projected inventory size is checked after accounting for consumed inputs, so a full inventory may validly replace one consumed pet with one result.

## Test and artifact coverage

`tests/MachineService.spec.lua` is registered in the pure-Lua runner and covers exact definitions and chance boundaries, strict malformed input rejection, ownership/species/variant/protection checks, both business outcomes, Shiny composition, Gold-only quest semantics, projected capacity, insufficient funds, reentrant locking, cleanup, technical fault rollback, dormancy, missing activation authority, and the unchanged legacy route. The generated-place verifier requires `MachineService`, QOF-15 lifecycle wiring, 66 ModuleScripts, one Script, one LocalScript, and 68 byte-exact runtime sources.

## Deferred limitations

QOF-15 does not provide physical machine models, proximity prompts, an activation validator, a request remote, a result event, rate-limit wiring, or machine UI. Rainbow is transaction-capable internally but publicly dormant. The combined six-state Pet Dex migration remains deferred; machine discovery uses the existing compatibility keys. The legacy Golden conversion remains a separate behavior until QOF-16.
