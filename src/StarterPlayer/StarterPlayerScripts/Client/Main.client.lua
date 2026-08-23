local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UIController = require(script.Parent:WaitForChild("UIController"))
local EffectsController = require(script.Parent:WaitForChild("EffectsController"))

local remotes = ReplicatedStorage:WaitForChild("ShiftBreakRemotes")
local stateRemote = remotes:WaitForChild("GameState")
local messageRemote = remotes:WaitForChild("PlayerMessage")
local actionRemote = remotes:WaitForChild("Action")
local purchaseRemote = remotes:WaitForChild("PurchaseUpgrade")

local ui = UIController.new(Config)
local effects = EffectsController.new(Config)
local currentState = nil
local sprintHeld = false
local purchasePending = false

local function refreshPlayerUI()
	ui:UpdatePlayer()
end

for _, attributeName in {
	"HeldEchoes",
	"MaxCapacity",
	"Flux",
	"Stamina",
	"UpgradeCapacity",
	"UpgradeSpeed",
	"UpgradePulse",
} do
	player:GetAttributeChangedSignal(attributeName):Connect(refreshPlayerUI)
end

ui:SetPurchaseCallback(function(upgradeName)
	if purchasePending then
		return
	end
	purchasePending = true
	task.spawn(function()
		local callSucceeded, success, message = pcall(function()
			return purchaseRemote:InvokeServer(upgradeName)
		end)
		purchasePending = false
		if not callSucceeded then
			ui:ShowMessage("Werkstatt nicht erreichbar. Versuch es erneut.", "Danger")
			return
		end
		ui:ShowMessage(message or "Werkstattantwort erhalten.", success and "Success" or "Danger")
		refreshPlayerUI()
	end)
end)

local function sprintAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		sprintHeld = true
		actionRemote:FireServer("Sprint", true)
		ui:SetSprinting(true)
		effects:SetSprinting(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		sprintHeld = false
		actionRemote:FireServer("Sprint", false)
		ui:SetSprinting(false)
		effects:SetSprinting(false)
	end
	return Enum.ContextActionResult.Sink
end

local function pulseAction(_, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not currentState or currentState.status ~= "Running" then
		return Enum.ContextActionResult.Sink
	end

	local now = Workspace:GetServerTimeNow()
	local cooldownEnd = player:GetAttribute("PulseCooldownEnd") or 0
	if now >= cooldownEnd then
		actionRemote:FireServer("Pulse")
		effects:Pulse(player.Character)
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("ShiftBreakSprint", sprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("ShiftBreakSprint", "SPRINT")
ContextActionService:SetPosition("ShiftBreakSprint", UDim2.new(1, -190, 1, -170))

ContextActionService:BindAction("ShiftBreakPulse", pulseAction, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonR2)
ContextActionService:SetTitle("ShiftBreakPulse", "PULS")
ContextActionService:SetPosition("ShiftBreakPulse", UDim2.new(1, -90, 1, -235))

stateRemote.OnClientEvent:Connect(function(state)
	local previousPhase = currentState and currentState.phase
	currentState = state
	ui:SetState(state)
	local changed = effects:SetPhase(state.phase, previousPhase == nil)
	if changed and previousPhase ~= nil then
		ui:FlashPhase(state.phase)
	end
end)

messageRemote.OnClientEvent:Connect(function(text, tone)
	if typeof(text) == "string" then
		ui:ShowMessage(text, tone)
	end
end)

player.CharacterAdded:Connect(function()
	sprintHeld = false
	ui:SetSprinting(false)
	effects:SetSprinting(false)
end)

RunService.RenderStepped:Connect(function()
	local now = Workspace:GetServerTimeNow()
	local cooldownEnd = player:GetAttribute("PulseCooldownEnd") or 0
	ui:SetPulseCooldown(cooldownEnd - now)

	local stamina = player:GetAttribute("Stamina") or Config.Player.MaxStamina
	if sprintHeld and stamina <= 0.1 then
		sprintHeld = false
		actionRemote:FireServer("Sprint", false)
		ui:SetSprinting(false)
		effects:SetSprinting(false)
	end
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera.FieldOfView = sprintHeld and 78 or 70
	end
end)

print(string.format("[%s] Client bereit.", Config.GameName))
