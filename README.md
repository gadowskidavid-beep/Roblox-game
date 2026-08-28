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
- Includes a dormant server transaction foundation for future Gold and Rainbow machines (no public machine UI or stations yet)

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

16 pets distributed across 8 zone eggs with progressive rarity. Each pet can appear in Normal, Golden (Shiny), or Rainbow variant forms. Shiny and Rainbow variants have boosted stats and unique visual effects.

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
      DataService.lua             -- Save/load with DataStore + session locking
      DataSchema.lua              -- Versioned player data schema and migrations
      PetService.lua              -- Pet hatching, inventory, canonical conversion mutations
      MachineService.lua          -- Dormant atomic Gold/Rainbow transaction foundation
      EggService.lua              -- Egg station logic and hatching
      ShopService.lua             -- Inventory-only shop purchases
      PotionService.lua           -- Potion consumption, effects, upgrades, Auto-Drink
      CampaignService.lua         -- Campaign level logic
      CurrencyService.lua         -- Coins and diamonds management
      ZoneService.lua             -- Zone unlocking and destructibles
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

tests/
  run_tests.lua                   -- Minimal test runner (describe/it/expect)
  DataSchema.spec.lua             -- Unit tests for schema and migrations
  PotionService.spec.lua          -- Potion consumption/effect transaction tests

tools/
  generate_rbxlx.py               -- Generates BATTLE_PETS.rbxlx from src/ tree
  fix_hierarchy.py                -- Hierarchy repair utility
```

## Architecture

The game uses a server-authoritative architecture where all state mutations happen server-side to prevent exploits.

### Server Services

| Service | Responsibility |
|---------|---------------|
| **DataService** | Loads/saves player data via DataStore with session locking and auto-save |
| **DataSchema** | Defines the canonical player data shape, handles migrations and normalization |
| **PetService** | Manages pet inventory and canonical mutation-free conversion preparation/rollback |
| **MachineService** | Owns the dormant atomic Gold/Rainbow payment, consumption, roll, and quest foundation |
| **EggService** | Handles egg hatching with rarity rolls and variant chances |
| **ShopService** | Retains purchase ownership; potion purchases only add inventory |
| **PotionService** | Owns timed potion sources, Shiny charges, upgrades, Auto-Drink, and effect state |
| **ZoneService** | Spawns all 8 zones, gates, egg stations, and destructibles |
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

This reads the entire `src/` tree and produces `BATTLE_PETS.rbxlx` with procedurally generated geometry for all 8 zones.

## Testing & CI

### Local Testing

The `tests/` directory contains a minimal Luau test runner and spec files:

```bash
luau tests/run_tests.lua
```

The runner provides `describe`, `it`, and `expect` helpers and prints results to stdout. It exits with code 1 on any failure.

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
