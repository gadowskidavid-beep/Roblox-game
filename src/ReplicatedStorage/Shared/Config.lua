local Config = {
	GameName = "SHIFT//BREAK",
	DataStoreName = "ShiftBreakProfiles_v1",
	MinimumPlayers = 1,

	Round = {
		IntermissionDuration = 15,
		WaveDuration = 70,
		WaveClearDuration = 6,
		ResultDuration = 8,
		Waves = 3,
		ShiftInterval = 22,
		BaseQuota = 12,
		QuotaPerPlayer = 7,
		QuotaGrowthPerWave = 8,
	},

	Player = {
		StartingCapacity = 5,
		BaseWalkSpeed = 16,
		SprintWalkSpeed = 25,
		MaxStamina = 100,
		StaminaDrainPerSecond = 30,
		StaminaRegenPerSecond = 22,
		PulseRadius = 24,
		PulseCooldown = 9,
		PulseStunDuration = 4,
	},

	Echo = {
		MaximumBase = 24,
		MaximumPerPlayer = 4,
		SpawnInterval = 1.2,
		Lifetime = 40,
	},

	Enemy = {
		BaseMaximum = 4,
		MaximumPerWave = 3,
		SpawnInterval = 3.5,
		BaseSpeed = 8,
		SpeedPerWave = 1.4,
		Damage = 16,
		DamageRadius = 4.5,
		DamageCooldown = 1.25,
	},

	Rewards = {
		EchoFlux = 1,
		WaveFlux = 8,
		VictoryFlux = 45,
		ParticipationFlux = 6,
	},

	Upgrades = {
		Order = { "Capacity", "Speed", "Pulse" },
		Definitions = {
			Capacity = {
				DisplayName = "ECHO-TASCHE",
				Description = "+2 Tragfähigkeit pro Stufe",
				Costs = { 35, 80, 150 },
				Bonuses = { 2, 4, 6 },
			},
			Speed = {
				DisplayName = "PHASEN-SCHUHE",
				Description = "+1.5 Lauftempo pro Stufe",
				Costs = { 40, 90, 165 },
				Bonuses = { 1.5, 3, 4.5 },
			},
			Pulse = {
				DisplayName = "PULS-KERN",
				Description = "−1 Sekunde Puls-Cooldown pro Stufe",
				Costs = { 45, 100, 180 },
				Bonuses = { 1, 2, 3 },
			},
		},
	},

	Tags = {
		LobbySpawn = "SB_LobbySpawn",
		PlayerSpawn = "SB_PlayerSpawn",
		EchoSpawn = "SB_EchoSpawn",
		EnemySpawn = "SB_EnemySpawn",
		DepositAnchor = "SB_DepositAnchor",
		StableOnly = "SB_StableOnly",
		FracturedOnly = "SB_FracturedOnly",
	},

	Colors = {
		Background = Color3.fromRGB(7, 9, 18),
		Panel = Color3.fromRGB(16, 20, 38),
		Stable = Color3.fromRGB(67, 231, 255),
		Fractured = Color3.fromRGB(255, 55, 183),
		Echo = Color3.fromRGB(255, 232, 102),
		Danger = Color3.fromRGB(255, 73, 91),
		Success = Color3.fromRGB(101, 255, 157),
		Text = Color3.fromRGB(240, 245, 255),
		MutedText = Color3.fromRGB(151, 162, 196),
	},
}

return Config
