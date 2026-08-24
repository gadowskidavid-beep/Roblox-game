--[[
	CampaignData.lua - Campaign level and enemy definitions for Battle Pets
	Defines 48 levels across 8 regions, enemy types, wave compositions, and rewards.
]]

local CampaignData = {}

-- Enemy type definitions
CampaignData.Enemies = {
	Slime = {
		name = "Slime",
		hp = 20,
		damage = 3,
		speed = 4,
		modelDescription = "A bouncy green blob with googly eyes",
	},
	Goblin = {
		name = "Goblin",
		hp = 35,
		damage = 5,
		speed = 6,
		modelDescription = "A small purple goblin with pointy ears and a wooden club",
	},
	Golem = {
		name = "Golem",
		hp = 60,
		damage = 8,
		speed = 3,
		modelDescription = "A large stone creature with glowing blue runes",
	},
	DragonKing = {
		name = "Dragon King",
		isBoss = true,
		hp = 200,
		damage = 15,
		speed = 5,
		modelDescription = "A massive dark dragon with golden horns and fiery breath",
	},
}

-- Energy costs to deploy pets (based on rarity)
CampaignData.DeployCosts = {
	Common = 10,
	Uncommon = 20,
	Rare = 35,
	Epic = 45,
	Legendary = 50,
}

-- Region names (one per 6 levels)
CampaignData.Regions = {
	[1] = "Verdant Fields",
	[2] = "Urban Ruins",
	[3] = "Coastal Shore",
	[4] = "Desert Sands",
	[5] = "Frozen Tundra",
	[6] = "Volcanic Depths",
	[7] = "Sky Citadel",
	[8] = "Cosmic Void",
}

-- Helper to compute the scale factor for a given level
local function getScaleFactor(level)
	return 1 + (level - 1) * 0.15
end

-- Generate all 48 levels
CampaignData.Levels = {}

for region = 1, 8 do
	for stage = 1, 6 do
		local levelNum = (region - 1) * 6 + stage
		local isBoss = (stage == 6)
		local scale = getScaleFactor(levelNum)

		-- Determine wave composition
		local waves = {}
		if isBoss then
			-- Boss levels: 3 waves of regular enemies + boss wave
			waves[1] = {
				{ enemy = "Slime", count = math.ceil(3 * scale) },
				{ enemy = "Goblin", count = math.ceil(2 * scale) },
			}
			waves[2] = {
				{ enemy = "Goblin", count = math.ceil(3 * scale) },
				{ enemy = "Golem", count = math.ceil(1 * scale) },
			}
			waves[3] = {
				{ enemy = "Golem", count = math.ceil(2 * scale) },
				{ enemy = "Goblin", count = math.ceil(2 * scale) },
			}
			waves[4] = {
				{ enemy = "DragonKing", count = 1 },
			}
		elseif stage <= 2 then
			-- Early levels: mostly slimes
			waves[1] = {
				{ enemy = "Slime", count = math.ceil(3 * scale) },
			}
			waves[2] = {
				{ enemy = "Slime", count = math.ceil(4 * scale) },
			}
		elseif stage <= 4 then
			-- Mid levels: mixed enemies
			waves[1] = {
				{ enemy = "Slime", count = math.ceil(3 * scale) },
				{ enemy = "Goblin", count = math.ceil(1 * scale) },
			}
			waves[2] = {
				{ enemy = "Goblin", count = math.ceil(2 * scale) },
				{ enemy = "Slime", count = math.ceil(2 * scale) },
			}
			waves[3] = {
				{ enemy = "Golem", count = math.ceil(1 * scale) },
				{ enemy = "Goblin", count = math.ceil(2 * scale) },
			}
		else
			-- Stage 5: harder mix before boss
			waves[1] = {
				{ enemy = "Goblin", count = math.ceil(3 * scale) },
				{ enemy = "Golem", count = math.ceil(1 * scale) },
			}
			waves[2] = {
				{ enemy = "Golem", count = math.ceil(2 * scale) },
				{ enemy = "Goblin", count = math.ceil(3 * scale) },
			}
			waves[3] = {
				{ enemy = "Golem", count = math.ceil(2 * scale) },
				{ enemy = "Slime", count = math.ceil(4 * scale) },
			}
		end

		-- Determine rewards
		local rewards = {
			Coins = math.floor(50 * scale * region),
			Diamonds = math.floor(5 * scale * region),
		}

		-- Boss levels give special egg rewards
		if isBoss then
			rewards.SpecialEgg = true
			rewards.Coins = rewards.Coins * 3
			rewards.Diamonds = rewards.Diamonds * 3
		end

		-- Enemy base health scales with level
		local enemyBaseHP = math.floor(500 * scale)

		CampaignData.Levels[levelNum] = {
			levelNum = levelNum,
			region = region,
			regionName = CampaignData.Regions[region],
			stage = stage,
			isBoss = isBoss,
			waves = waves,
			rewards = rewards,
			enemyBaseHP = enemyBaseHP,
			energyCost = 5 + math.floor(levelNum / 6),
		}
	end
end

return CampaignData
