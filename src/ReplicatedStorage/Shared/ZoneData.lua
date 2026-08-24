--[[
	ZoneData.lua - Zone definitions for Battle Pets
	Defines all 8 zones with their properties, colors, and destructible types.
	Only zones 1-2 are fully playable in the MVP, but all 8 are defined for progression.
]]

local ZoneData = {}

-- Background music asset IDs per zone (Roblox built-in/public sounds)
ZoneData.ZoneMusic = {
	[1] = { assetId = "rbxassetid://1837849285", volume = 0.4 }, -- calm meadow
	[2] = { assetId = "rbxassetid://1845756489", volume = 0.35 }, -- urban/city vibe
	[3] = { assetId = "rbxassetid://1839345857", volume = 0.4 }, -- beach waves
	[4] = { assetId = "rbxassetid://1836677287", volume = 0.35 }, -- desert wind
	[5] = { assetId = "rbxassetid://1838857745", volume = 0.3 }, -- icy ambiance
	[6] = { assetId = "rbxassetid://1838497253", volume = 0.4 }, -- volcanic rumble
	[7] = { assetId = "rbxassetid://1837017665", volume = 0.35 }, -- heavenly chime
	[8] = { assetId = "rbxassetid://1836150807", volume = 0.3 }, -- space ambient
}

ZoneData.Zones = {
	[1] = {
		name = "Gruene Wiesen",
		unlockCost = 0,
		groundColor = Color3.fromRGB(76, 153, 0),
		skyColor = Color3.fromRGB(135, 206, 235),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 15,
				drops = { Coins = { min = 5, max = 15 } },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 25,
				drops = { Diamonds = { min = 1, max = 3 } },
			},
			Crate = {
				displayName = "Crate",
				hp = 40,
				drops = { Coins = { min = 10, max = 30 }, Diamonds = { min = 1, max = 2 } },
			},
		},
	},
	[2] = {
		name = "Stadt",
		unlockCost = 500,
		groundColor = Color3.fromRGB(128, 128, 128),
		skyColor = Color3.fromRGB(170, 200, 220),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 25,
				drops = { Coins = { min = 10, max = 25 } },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 50,
				drops = { Diamonds = { min = 3, max = 8 } },
			},
			Crate = {
				displayName = "Crate",
				hp = 35,
				drops = { Coins = { min = 20, max = 50 }, Diamonds = { min = 2, max = 5 } },
			},
		},
	},
	[3] = {
		name = "Strand",
		unlockCost = 2000,
		groundColor = Color3.fromRGB(237, 201, 136),
		skyColor = Color3.fromRGB(100, 180, 255),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 50,
				drops = { Coins = 25 },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 100,
				drops = { Diamonds = 10 },
			},
			Crate = {
				displayName = "Crate",
				hp = 70,
				drops = { Coins = 50, Diamonds = 5 },
			},
		},
	},
	[4] = {
		name = "Wueste",
		unlockCost = 5000,
		groundColor = Color3.fromRGB(210, 180, 100),
		skyColor = Color3.fromRGB(255, 200, 100),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 100,
				drops = { Coins = 50 },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 200,
				drops = { Diamonds = 20 },
			},
			Crate = {
				displayName = "Crate",
				hp = 150,
				drops = { Coins = 100, Diamonds = 10 },
			},
		},
	},
	[5] = {
		name = "Eiswelt",
		unlockCost = 15000,
		groundColor = Color3.fromRGB(200, 230, 255),
		skyColor = Color3.fromRGB(180, 210, 240),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 200,
				drops = { Coins = 100 },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 400,
				drops = { Diamonds = 40 },
			},
			Crate = {
				displayName = "Crate",
				hp = 300,
				drops = { Coins = 200, Diamonds = 20 },
			},
		},
	},
	[6] = {
		name = "Vulkan",
		unlockCost = 40000,
		groundColor = Color3.fromRGB(80, 30, 10),
		skyColor = Color3.fromRGB(200, 80, 30),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 400,
				drops = { Coins = 200 },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 800,
				drops = { Diamonds = 80 },
			},
			Crate = {
				displayName = "Crate",
				hp = 600,
				drops = { Coins = 400, Diamonds = 40 },
			},
		},
	},
	[7] = {
		name = "Himmel",
		unlockCost = 100000,
		groundColor = Color3.fromRGB(255, 255, 220),
		skyColor = Color3.fromRGB(200, 220, 255),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 800,
				drops = { Coins = 400 },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 1600,
				drops = { Diamonds = 160 },
			},
			Crate = {
				displayName = "Crate",
				hp = 1200,
				drops = { Coins = 800, Diamonds = 80 },
			},
		},
	},
	[8] = {
		name = "Weltraum",
		unlockCost = 300000,
		groundColor = Color3.fromRGB(20, 10, 40),
		skyColor = Color3.fromRGB(10, 5, 30),
		destructibles = {
			CoinPile = {
				displayName = "Coin Pile",
				hp = 1600,
				drops = { Coins = 800 },
			},
			DiamondPile = {
				displayName = "Diamond Pile",
				hp = 3200,
				drops = { Diamonds = 320 },
			},
			Crate = {
				displayName = "Crate",
				hp = 2400,
				drops = { Coins = 1600, Diamonds = 160 },
			},
		},
	},
}

return ZoneData
