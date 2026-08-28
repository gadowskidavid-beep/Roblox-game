# QOF-16 Gold Machine End-to-End

## Runtime scope

QOF-16 activates only `GoldMachine`: Zone 3, Normal → Golden, 750 Diamonds, with exact 1–7-input chances of 13%, 26%, 39%, 50%, 63%, 88%, and 100%. `RainbowMachine` remains explicitly disabled at its per-definition gate and has no station or client route. The global machine gate remains an emergency kill switch.

The historical `ConvertToGoldenPet` RemoteFunction remains temporarily discoverable so rolling QOF-15 clients do not block during startup, but its QOF-16 handler is permanently fail-closed and performs no mutation. The legacy PetService implementation remains private compatibility code and no runtime route calls it. `UseMachine` is the sole public machine mutation entry point.

## World authority

`ZoneService` creates exactly one runtime Gold Machine Model in `Workspace/Zones/Zone_3`. It owns an anchored `Anchor` BasePart and `UseMachinePrompt`. A module-private registry retains the exact Model, Anchor, Prompt, zone-folder references, spawn CFrame, dimensions, and a server-generated identity token.

The activation validator fails closed unless all of these are current at request time:

- the machine is the registered Gold definition and its token matches;
- the exact registered Model remains under the exact generated Zone 3 folder;
- Model identity attributes, PrimaryPart, Anchor shape/CFrame, and Prompt properties remain unchanged;
- the player's loaded profile has Zone 3 unlocked;
- the player's Character has a real descendant HumanoidRootPart;
- the HumanoidRootPart is within the server-owned 12-stud radius.

Names, copied attributes, a cloned station, a replacement Prompt, or the replicated token alone never establish authority. `Main.server.lua` injects this validator only when all ZoneService initialization completed; any world-generation failure leaves MachineService without activation authority.

## Remote and transaction contract

The client sends only `machineId`, the prompt-session token, and a dense list of pet instance IDs. `Main.server.lua` applies cooldown and burst accounting, validates bounded primitive/list shape without invoking caller metamethods, and delegates to `MachineService`. It accepts no client price, chance, zone, station instance, source/target variant, or output.

MachineService revalidates the global and per-machine gates before profile, world, pet, RNG, or currency work. PetService validates ownership, one species, Normal source variant, 1–7 unique IDs, Favorite/Equipped protection, and projected capacity. Any Shiny input makes the one successful Gold output Shiny.

A normal RNG failure is a committed business result: all selected pets and 750 Diamonds are consumed, with no output. A success consumes the same resources and creates exactly one canonical Golden pet. Technical errors before final currency commit restore the pending debit and pet mutation. Discovery rollback reverses only the transaction-owned key and preserves unrelated concurrent progress.

`goldenPetsConverted` advances exactly once only after a successful Gold result and final currency commit. Admission errors, Rainbow requests, normal RNG failures, and technical rollbacks never advance it.

## Client flow

The existing central `ProximityPromptService` router recognizes only the exact Gold prompt UX shape. Triggering it opens Pet Inventory in a station-bound multi-select session. The Gold action is absent outside that session. The previous global `Make Golden` action and direct legacy remote call are removed.

The client filters the confirmation UX to 1–7 currently present, non-Favorite, unequipped Normal pets of one species. Normal Shiny pets are valid and a multi-Shiny warning explains that Shiny does not stack. Confirmation shows the canonical 750-Diamond price, selected input count/species, exact chance, and that both pets and Diamonds are consumed on failure.

Remote responses never mutate local economy state optimistically. Existing `CurrencyUpdated` and `PetInventoryUpdated` events remain authoritative. Executable generation state invalidates stale async responses after PromptHidden, inventory close, overlay cancel, navigation, or prompt replacement. Delayed result cleanup captures and identity-checks its own overlay so an older timer cannot destroy a newer confirmation. A business success or failure clears consumed selection; a pre-transaction server error remains visible and retryable while the prompt session is valid.

## Verification and deferred work

Pure-Lua tests cover transaction boundaries, Gold-only gating, Rainbow no-side-effects, hostile request lists, private station integrity, copied/tampered station rejection, unlock/Character/HRP/distance checks, client source contracts, and legacy-route removal. The generated-place verifier requires the server, world, prompt router, and station-bound UI contracts plus byte-exact parity for every runtime source.

Rainbow activation, its Zone 6 station/UI, live DataStore validation, live multiplayer races, and Roblox Studio visual/interaction checks are intentionally outside automated sandbox verification. Rainbow belongs to QOF-17 and is not started here.
