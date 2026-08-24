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

## MVP Features

- 2 fully playable collecting zones (Gruene Wiesen + Stadt)
- 4 pets with different rarities (Dog, Cat, Dragon, Phoenix)
- Campaign portal with level selection
- 3 enemy types + 1 boss for campaign battles
- Energy and deployment system for campaign
- Automatic pet movement and combat
- Base HP and win/lose conditions
- Pet inventory with equip, delete, and multi-select
- DataStore save/load system
- Full UI in the Pet Simulator 1 style
- Egg hatching with animations
- Coins, diamonds, and crate destruction system

## Source Tree Structure

```
default.project.json          -- Rojo project file
BATTLE_PETS.rbxlx             -- Directly openable place file
README.md                     -- This file

src/
  ServerScriptService/
    Server/
      Main.server.lua         -- Server entry point
      Services/
        DataService.lua       -- Save/load with DataStore
        PetService.lua        -- Pet hatching, equipping, inventory
        CampaignService.lua   -- Campaign level logic
        CurrencyService.lua   -- Coins and diamonds management
        ZoneService.lua       -- Zone unlocking and destructibles

  StarterPlayer/
    StarterPlayerScripts/
      Client/
        Main.client.lua       -- Client entry point
        UIController.lua      -- All UI management
        PetController.lua     -- Client-side pet visuals
        CampaignController.lua -- Campaign UI and visuals

  ReplicatedStorage/
    Shared/
      Config.lua              -- Game constants and configuration
      PetData.lua             -- Pet and egg definitions
      ZoneData.lua            -- Zone properties and destructibles
      CampaignData.lua        -- Campaign levels and enemies
```

## Using with Rojo (Optional)

If you have [Rojo](https://rojo.space/) installed, you can sync the source tree into Roblox Studio for a live development workflow:

1. Install Rojo (VS Code extension + Roblox Studio plugin)
2. Run `rojo serve` in the project root
3. Connect from Roblox Studio using the Rojo plugin
4. Edits to `.lua` files will sync automatically

Without Rojo, you can directly edit the `BATTLE_PETS.rbxlx` file in Roblox Studio.

## Technical Notes

- Server-authoritative architecture (no client-side exploits possible)
- All geometry is procedurally generated via code (no external assets)
- No external packages, plugins, images, sounds, or paid assets required
- Pure Luau codebase
