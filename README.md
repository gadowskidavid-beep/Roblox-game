# Battle Pets

A Roblox Pet Simulator game with a campaign side-mode, inspired by Pet Simulator 1 and Battle Cats.

## How to Open

Open `BATTLE_PETS.rbxlx` in Roblox Studio to play or edit the game directly.

## Game Overview

### Main Mode: Collecting (Pet Simulator)
- Explore a free 3D world across 8 themed zones
- Pets automatically destroy coin piles, diamond piles, and crates
- Collect coins and diamonds to buy eggs and hatch new pets
- Each pet has a rarity: Common, Uncommon, Rare, Epic, or Legendary
- Unlock new zones by spending coins at zone gates
- Upgrade your pets, speed, luck, and more through the upgrade system
- Buy and drink persistent potions with timed Luck, Speed, Coin, and Shiny-charge effects
- Use the live Gold Machine in Zone 3 (Normal → Golden, 750 Diamonds) and Rainbow Machine in Zone 6 (Golden → Rainbow, 2,500 Diamonds)
- Buy QOF-18 Auto-Hatch Access for exactly 500 Diamonds: 10 minutes of station-bound x1/x2/x5/x10 paid egg batches every 3 seconds
- Enchant any inventory pet through its Details panel for exactly 500 Diamonds per roll/reroll: one slot with Strong I-III damage or Agile I-III campaign-speed outcomes
- Complete a 96-card Pet Dex covering Normal/Gold/Rainbow × standard/Shiny for all 16 species

### Side Mode: Campaign (Battle Cats-style)
- Accessible through a portal in the main world
- 48 levels across 8 regions (6 levels per region, every 6th is a boss)
- Deploy pets using energy that regenerates automatically
- Pets fight autonomously in a left-to-right lane
- Destroy the enemy base to win each level
- Earn special rewards: unique pets, eggs, diamonds, and permanent bonuses

## Zones

1. **Gruene Wiesen** - Free starter zone (green meadows)
2. **Stadt** - City (500 coins)
3. **Strand** - Beach (2,000 coins)
4. **Wueste** - Desert (5,000 coins)
5. **Eiswelt** - Ice World (15,000 coins)
6. **Vulkan** - Volcano (40,000 coins)
7. **Himmel** - Sky (100,000 coins)
8. **Weltraum** - Space (300,000 coins)

## Pets

16 pets distributed across 8 zone eggs with progressive rarity. Every species has six independent Dex states: Normal, Normal Shiny, Gold, Gold Shiny, Rainbow, and Rainbow Shiny. DataSchema V11 persists these canonical discoveries plus rolling compatibility mirrors and at most one canonical, whitelist-only `enchantId`: Strong multiplies canonical damage, while Agile snapshots canonical campaign lane speed at deployment.

## Source Tree Structure

```
default.project.json              -- Rojo project file
BATTLE_PETS.rbxlx                 -- Directly openable place file
selene.toml                       -- Selene linter configuration
README.md                         -- This file

src/
  ServerScriptService/
    Main.server.lua               -- Server entry point (boots all services)
    Services/
      DataService.lua             -- Session locking plus per-profile leave/shutdown settlement retries and isolated release
      DataSchema.lua              -- Versioned player data schema and migrations
      PetService.lua              -- All pet mutations behind the shared lease; Strong/Agile stats and canonical conversions
      MachineService.lua          -- Atomic shared-lease Gold/Rainbow payment, consumption, roll, rollback, settlement
      EnchantingService.lua       -- Strict V1 pet-enchant state, roll/reroll, revision, transaction, rollback authority
      EggService.lua              -- Lease-held paid/free batch transactions with retained rollback lifecycle
      AutoHatchService.lua        -- Paid expiry, station sessions, scheduler, DTO/revision authority
      ShopService.lua             -- Inventory-only shop purchases; legacy Auto-Hatch loop hard-disabled
      PotionService.lua           -- Potion consumption, effects, upgrades, Auto-Drink
      CampaignService.lua         -- Campaign level logic
      CurrencyService.lua         -- Coins and diamonds management
      ZoneService.lua             -- Zone/destructible spawning plus private machine and egg-station registries
      QuestService.lua            -- Quest tracking and rewards
      MasteryService.lua          -- Mastery point buffs
      UpgradeService.lua          -- Player upgrades (delegates to QuestService)

  StarterPlayer/
    StarterPlayerScripts/
      Main.client.lua             -- Client entry point
      UIController.lua            -- All UI management
      PetController.lua           -- Client-side pet visuals and effects
      CampaignController.lua      -- Campaign UI and visuals
      EffectsController.lua       -- Visual effects (shiny, rainbow, particles)
      MusicController.lua         -- Zone-based music and SFX

  ReplicatedStorage/
    Shared/
      Config.lua                  -- Game constants and configuration
      PetData.lua                 -- Pet and egg definitions (16 pets, 8 eggs)
      ZoneData.lua                -- Zone properties and destructibles
      CampaignData.lua            -- Campaign levels and enemies
      QuestData.lua               -- Quest definitions and rewards
      MasteryData.lua             -- Mastery tree definitions
      AutoHatchClientSession.lua  -- Pure prompt generation and state-revision ownership
      PetEnchantMath.lua          -- Canonical six-ID enchant whitelist and Strong/Agile math
      PetDex.lua                  -- Pure six-state keys, migration, validation, and client projection
      EnchantingClientSession.lua -- Pet/generation/revision-bound request ownership
      EnchantingClientContract.lua -- Pure exact canonical V1 response validation

tests/
  run_tests.lua                   -- Minimal test runner (describe/it/expect)
  DataSchema.spec.lua             -- Schema V11, Pet Dex migration, and whitelist-only enchant persistence
  PetDex.spec.lua                -- Six-state keys, conservative migration, backfill, and hostile boundaries
  PetDexClient.spec.lua          -- Combined UI, live update, stale refresh, and defensive remote contracts
  PotionService.spec.lua          -- Potion consumption/effect transaction tests
  AutoHatchService.spec.lua       -- Paid purchase/session/scheduler/expiry tests
  AutoHatchClient.spec.lua        -- Rolling discovery and stale-response tests
  PetEnchantMath.spec.lua         -- Canonical pool, defensive copy, Strong/Agile semantics
  EnchantingService.spec.lua      -- Contract, transaction, rollback, settlement and shared-lease tests
  EnchantingClient.spec.lua       -- Optional discovery, exact requests, revisions and inventory UX
  CampaignService.spec.lua        -- Agile deploy snapshot and fallible stat-provider boundaries

tools/
  generate_rbxlx.py               -- Deterministically generates BATTLE_PETS.rbxlx from automatic runtime inventory
  runtime_inventory.py            -- Fail-closed complete src/ runtime discovery
  build_release.py                -- Reproducible RBXL/RBXLX/ZIP/SHA256 release orchestrator
  convert_place.rbxmk.lua         -- Pinned bidirectional rbxmk place conversion
  rbxmk.lock.json                 -- Canonical rbxmk version/platform/executable hash
  fix_hierarchy.py                -- Hierarchy repair utility
```

## Architecture

The game uses a server-authoritative architecture where all state mutations happen server-side to prevent exploits.

### Server Services

| Service | Responsibility |
|---------|---------------|
| **DataService** | Loads/saves player data via DataStore with session locking and auto-save |
| **DataSchema** | Defines Schema V11; migrates the six-state Pet Dex and persists only a canonical whitelisted `enchantId` |
| **PetService** | Owns pet inventory, opaque per-player mutation leases/incarnations, canonical Strong/Agile stats, and conversion preparation/rollback |
| **MachineService** | Owns active Gold/Rainbow admission, shared-lease payment/consumption/roll/rollback/settlement; successful outputs start unenchanted |
| **EnchantingService** | Owns strict Contract V1 GET/ROLL DTOs, exact 500-Diamond transactions, optimistic revisions, rollback, retryable settlement, and shutdown gating |
| **EggService** | Owns atomic paid manual and automatic egg-batch economy, capacity, rollback, events, and quests |
| **AutoHatchService** | Owns QOF-18 paid absolute expiry, strict Contract V1 DTOs, station sessions, revisions, cancellation, and the non-overlapping 3-second scheduler |
| **ShopService** | Retains purchase ownership; potion purchases only add inventory |
| **PotionService** | Owns timed potion sources, Shiny charges, upgrades, Auto-Drink, and effect state |
| **ZoneService** | Spawns all zones plus private-authority machine and concrete Egg-station registries, gates, and destructibles |
| **CampaignService** | Runs campaign battles, energy system, and boss encounters |
| **CurrencyService** | Awards and deducts coins/diamonds with validation |
| **QuestService** | Tracks quest progress and distributes rewards |
| **MasteryService** | Applies mastery point buffs to pet stats |
| **UpgradeService** | Legacy upgrade handler, now delegates to QuestService |

### Client Controllers

| Controller | Responsibility |
|------------|---------------|
| **UIController** | Manages all screen UI (inventory, shop, quests, hatch popups) |
| **PetController** | Renders pet models following the player, handles animations |
| **CampaignController** | Campaign level select and battle visualization |
| **EffectsController** | Particle effects for shiny/rainbow variants and hatching |
| **MusicController** | Zone-based background music and sound effects |

## Using with Rojo

If you have [Rojo](https://rojo.space/) installed, you can sync the source tree into Roblox Studio for a live development workflow:

1. Install Rojo (VS Code extension + Roblox Studio plugin)
2. Run `rojo serve default.project.json` in the project root
3. Connect from Roblox Studio using the Rojo plugin
4. Edits to `.lua` files will sync automatically

Without Rojo, you can directly edit the `BATTLE_PETS.rbxlx` file in Roblox Studio.

## Regenerating the Place File

```bash
python3 tools/generate_rbxlx.py
```

The generator performs a deterministic, fail-closed inventory of every supported runtime surface under `src/`, embeds each source exactly once, and produces `BATTLE_PETS.rbxlx` with procedurally generated geometry for all 8 zones. Unknown runtime layouts, symlinks, invalid UTF-8, CRLF, or unsafe CDATA terminate the build instead of silently omitting code.

Create and verify the complete reproducible QOF-21 release with the pinned rbxmk 0.9.1 binary:

```bash
python3 tools/build_release.py --qof 21 --rbxmk /path/to/rbxmk
python3 tests/verify_release_artifacts.py --qof 21 --fresh-build --rbxmk /path/to/rbxmk
```

Use `python3 tools/build_release.py --qof 21 --rbxmk /path/to/rbxmk --check` for a non-mutating drift check. See [`docs/QOF-21-reproducible-release.md`](docs/QOF-21-reproducible-release.md) for the lock, deterministic ZIP, provenance, and roundtrip contracts.

## Testing & CI

### Local Testing

The `tests/` directory contains a minimal Luau test runner and spec files:

```bash
luau tests/run_tests.lua
```

The runner provides `describe`, `it`, and `expect` helpers and prints results to stdout. It exits with code 1 on any failure.

Verify a freshly generated place against every runtime source with:

```bash
python3 tests/verify_generated_place.py
```

QOF-20 coverage adds the six canonical Pet Dex states for all 16 species, Schema V11 conservative Legacy migration and exact inventory backfill, canonical-plus-Legacy transactional writes, canonical-only new-discovery semantics, separate Gold-Shiny/Rainbow-Shiny handling, defensive remote copies, 96-card client rendering, confirmed Hatch/Machine live updates that invalidate older snapshots, and stale/failed refresh protection. QOF-21 independently inventories every runtime source, verifies byte-exact Place parity and the complete roundtrip semantic tree, requires a byte-stable binary reserialization, pins rbxmk, reproduces XML/RBXL/ZIP twice, transactionally publishes with rollback, and independently validates exact SHA-256 provenance. The generated place must contain exactly **75 ModuleScripts + 1 Script + 1 LocalScript = 77 runtime sources**, each byte-identical and present exactly once. See [`docs/QOF-20-six-state-pet-dex.md`](docs/QOF-20-six-state-pet-dex.md) and [`docs/QOF-21-reproducible-release.md`](docs/QOF-21-reproducible-release.md).

QOF-19 regression coverage remains in place for the active six-result Enchanting balance, whitelist-only canonical `enchantId`, strict V1 GET/ROLL DTOs, exact `false` no-enchant sentinel, paid same-result rerolls, revision advancement, shared Machine/Enchant inventory leases, rollback and settlement boundaries, inventory-detail failure handling, Strong/Agile semantics, and Machine enchant-consumption warnings. See [`docs/QOF-19-pet-enchanting.md`](docs/QOF-19-pet-enchanting.md).

QOF-18 coverage remains in place for Schema V9 absolute-expiry/offline boundaries, exact 500-Diamond atomic access purchases, strict V1 DTO/revision/deep-copy contracts, private Egg-station clone/token/property authority, x1/x2/x5/x10 no-fallback entitlements, first-tick/no-overlap/no-backlog scheduling, stop/leave/expiry generations, stable pause/resume reasons, rolling optional remote discovery, station UI generations, and no Shiny-charge consumption. See [`docs/QOF-18-paid-auto-hatch.md`](docs/QOF-18-paid-auto-hatch.md).

QOF-17's machine coverage remains in place for both station registries, exact machine economics and chances, business-failure consumption, technical rollback, Shiny propagation, Gold-only quest progress, client generations, and generic prompt routing.

### Linting

The project uses [selene](https://kampfkarren.github.io/selene/) for static analysis:

```bash
selene src/
```

Configuration lives in `selene.toml` (uses the `roblox` standard library).

### CI (GitHub Actions)

The `.github/workflows/luau-check.yml` workflow runs on every push and PR to `main`:

1. **Selene Lint** - Installs selene via `cargo install selene` and lints all files under `src/`
2. **Luau Tests** (allow-failure) - Runs `luau tests/run_tests.lua` if the Luau CLI is available

## Technical Notes

- Server-authoritative architecture (no client-side exploits possible)
- All geometry is procedurally generated via code (no external assets)
- No external packages, plugins, images, sounds, or paid assets required
- Pure Luau codebase
- 8 themed zones with progressive difficulty
- 16 unique pets across all rarity tiers
- Shiny and Rainbow variant system with configurable drop rates
- QOF-19 inventory-native enchanting needs no world station and adds no second Machine remote; `UseMachine` remains the sole Machine mutation endpoint
