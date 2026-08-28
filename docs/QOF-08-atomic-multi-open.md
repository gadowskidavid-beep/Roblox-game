# QOF-08 – Atomic Multi-Open

## Status

Implemented in source; Roblox Studio runtime validation remains required.

## Product contract

QOF-08 activates the stable save IDs deferred by QOF-07:

| Tree node | Effect | Cost | Prerequisite |
| --- | ---: | ---: | --- |
| `Eggs III` | x2 eggs | 500 Diamonds | `Eggs II` |
| `Eggs IV` | x5 eggs | 2,500 Diamonds | `Eggs III` |
| `Eggs V` | x10 eggs | 10,000 Diamonds | `Eggs IV` |

The complete effective chain is `Eggs I → Eggs II → Eggs III → Eggs IV → Eggs V`.
Unknown IDs and sparse or forged chains are inert. Existing complete legacy chains are
activated without a schema migration. The V6 boolean purchase map remains the source
of persistence truth.

Players may select x1, x2, x5, or x10 up to their highest effective entitlement. The
server validates the selected tier for every request; the client selection is never
authoritative. The selected tier is a session preference used by paid Auto-Hatch and
defaults to x1 after joining.

## Atomic server transaction

For every batch the server validates, in order:

1. Player, egg ID, allowed count, and effective entitlement.
2. Manual proximity to the matching server-created egg station. Server-driven
   Auto-Hatch is the only proximity bypass.
3. Egg zone ownership.
4. Capacity for every result in the selected batch.
5. The full Coin price (`unit price × count`).
6. Every canonical random pet outcome without mutating persistent state.

Only after all preflight checks succeed does the service spend the total price and
commit all pets and discovery keys. A failure after debit or inventory mutation restores
both currency and the complete inventory/discovery snapshot. There are no partial pets,
partial charges, bonus refunds, or smaller silent fallback batches.

The transaction reuses the canonical QOF-06/QOF-07 outcome path for every roll. Multi-Open
does not alter species, Gold, Rainbow, Shiny, Egg Quality, general Luck, or chance caps.
Quest hatch progress advances by the committed batch size. Inventory replicates once per
batch.

## Network and client contract

`HatchEgg` accepts `(eggType, selectedCount)`. The server returns and emits one batch DTO:

```lua
{
    batchId = "<server correlation id>",
    eggType = "BasicEgg",
    count = 5,
    totalCost = 500,
    pets = { -- exactly count canonical V6 pet result tables
        -- ...
    },
}
```

`SetHatchBatchSize` stores only a server-validated session preference for Auto-Hatch.
Every actual hatch validates the entitlement again.

The client mounts one contextual x1/x2/x5/x10 selector while an egg prompt is visible.
The highlighted Auto-Hatch preference is applied only from the latest server response, so
rapid throttled taps cannot diverge from the server session value. Committed batches enter
a serialized, failure-safe presentation queue. Each shared reveal completes below the
three-second Auto-Hatch cadence, then replaces the single owned result surface for both
x1 and xN with one live-reflowing, safe-inset-aware grid (five columns on wide layouts,
two on narrow/mobile layouts). Animation or grid errors always finalize controller state
and advance the queue. It never opens stacked single-pet modals. Prompt routing is centralized through `ProximityPromptService`, so
respawns do not duplicate hatch connections.

## Deliberately deferred to QOF-09

- Dedicated rare-result cinematics and rare-result timing rules.
- Additional sound, particle, and camera choreography.
- Persistent preferred batch size across joins.
- Changes to the existing Auto-Hatch item duration or cadence.

## Compatibility and safety

- No DataSchema version bump is required.
- QOF-07 single hatch remains x1 and uses the same atomic path.
- Campaign reward hatches retain the compatible single-roll PetService API.
- Auto-Hatch remains paid and uses the selected batch with no resource fallback.
- `upgradeTree.lua` and the vendored Vide package remain unchanged.
