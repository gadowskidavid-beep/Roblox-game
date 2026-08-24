local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Services = script.Parent:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService"))
local ArenaService = require(Services:WaitForChild("ArenaService"))
local EnemyService = require(Services:WaitForChild("EnemyService"))
local GameService = require(Services:WaitForChild("GameService"))

local dataService = DataService.new()
local arenaService = ArenaService.new()
local enemyService = EnemyService.new(arenaService)
local gameService = GameService.new(dataService, arenaService, enemyService)

dataService:Start()
arenaService:Start()
enemyService:Start()
gameService:Start()

print(string.format("[%s] Server bereit.", Config.GameName))
