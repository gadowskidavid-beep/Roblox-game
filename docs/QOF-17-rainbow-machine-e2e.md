# QOF-17 Rainbow Machine End-to-End

## Runtime scope

QOF-17 keeps the QOF-16 Gold Machine active and activates `RainbowMachine` through the same machine runtime. The canonical contracts are:

| Machine | Zone | Input | Output | Cost | Inputs / chance |
|---|---:|---|---|---:|---|
| `GoldMachine` | 3 | Normal | Golden | 750 Diamonds | 1–7 / 13%, 26%, 39%, 50%, 63%, 88%, 100% |
| `RainbowMachine` | 6 | Golden | Rainbow | 2,500 Diamonds | 1–7 / 13%, 26%, 39%, 50%, 63%, 88%, 100% |

The global machine gate remains an emergency kill switch and both definitions retain independent runtime gates. QOF-17 adds no runtime module and no remote. `UseMachine` remains the sole public mutation route. The historical `ConvertToGoldenPet` RemoteFunction remains discoverable for rolling clients but always returns the existing mutation-free compatibility rejection.

## Shared transaction authority

`MachineService.attemptConversion` resolves either active definition into a private scalar snapshot and executes the same locked transaction path. The client supplies only the machine ID, station-session token, and a plain dense list of one to seven unique pet instance IDs. Zone, source/target variant, cost, chance, and output are server-owned.

The transaction revalidates profile zone unlock and the private world validator before preparing pets. `PetService.prepareVariantConversion` enforces ownership, one species, the exact source variant, Favorite and Equipped protection, and projected inventory capacity. Shiny is an OR across all consumed inputs: one or more Shiny Golden inputs produce one Shiny Rainbow output on success; multiple Shiny inputs do not stack.

After a silent exact Diamond debit, the server rolls once against the canonical input-count curve and commits the pet mutation. An ordinary unsuccessful roll is a committed business result: the full price and all selected inputs are consumed with no output. A successful roll consumes the same resources and creates one canonical target-variant pet. Technical errors before final currency commit roll back both pet and currency state, including exact inventory identity/order and transaction-owned discovery state.

Inventory replication and quest notifications remain protected post-commit boundaries. `goldenPetsConverted` advances only for a successful `machineType == "Gold"` result after currency commit. Rainbow success, Rainbow business failure, admission rejection, and technical rollback never advance it.

## Private world authority

`ZoneService` uses one internal station builder and one module-private registry to create exactly:

- one `GoldMachine` Model under the generated `Zone_3` folder;
- one `RainbowMachine` Model under the generated `Zone_6` folder.

Each station receives its own server-generated GUID and retains exact server references to its Zones folder, zone folder, Model, Anchor, and ProximityPrompt. The record also owns the expected machine/zone attributes, Anchor shape, anchored/collision state, size, spawn CFrame, color and material, plus Prompt name, parent, enabled state, hold duration, line-of-sight setting, activation distance, action text, and machine-specific object text.

Every use fails closed unless those exact references, ancestry, attributes, and properties are still intact; the request ID and token match the same registry record; the player is a real Player with the required zone unlocked; a real descendant HumanoidRootPart exists; and it is within 12 studs of the registered Anchor. Copied names/attributes, cloned stations, token swaps between Gold and Rainbow, replacement ancestry, or property tampering do not establish authority. The validator is published only after both station builds and all world initialization complete.

## Generic station-bound client flow

`MachineClientSession` accepts exactly `GoldMachine` and `RainbowMachine`. Invalid starts clear prior authority. Start, request, close, station replacement, and cross-machine replacement use generation ownership so stale responses cannot mutate the current presentation.

The central `ProximityPromptService` router recognizes the existing `UseMachinePrompt` shape and only the two accepted machine IDs. It opens one generic Machine UI capability and invokes the existing `UseMachine` RemoteFunction. Retriggering even the same station first revokes the previous UI/session generation, preventing an old confirmation closure from becoming current again.

There is one station-bound `UseMachineBtn` and no global Rainbow action:

- Gold sessions show only Normal-base pets and render Golden / 750 Diamonds.
- Rainbow sessions show only Golden-base pets and render Rainbow / 2,500 Diamonds.
- Both require one to seven current pets of the same species.
- Favorite and Equipped pets cannot be selected; Shiny inputs remain eligible.
- Confirmation renders the exact chance and explicitly states that pets and the full Diamond price are consumed on failure.

The existing lifecycle protections remain: PromptHidden, inventory close, navigation, and overlay cancel revoke the session and selection; one request may be in flight; a pre-transaction request error keeps retry controls available; terminal business results clear selection; and delayed cleanup may destroy only the exact overlay generation that scheduled it. Currency and inventory remain server-replicated rather than optimistically mutated.

## Verification contract

The QOF-17 regression suite retains QOF-16 Gold and rolling-client assertions while adding both active definitions, Rainbow success/failure/rollback, Shiny propagation, Gold-counter isolation, seven-input guarantee, two-station exact integrity, clone/token-swap tampering, Zone 6 unlock/distance, cross-machine client generations, dynamic UI source/target/price contracts, and generated-place source parity.

Required checks:

```bash
luau tests/run_tests.lua
luau-compile <every .lua/.luau source>
python3 tools/generate_rbxlx.py
python3 tests/verify_generated_place.py
python3 -m py_compile tools/generate_rbxlx.py tests/verify_generated_place.py
git diff --check
```

The generator requires no source change because QOF-17 adds no runtime file or static place geometry; both station Models are created by `ZoneService` at runtime.
