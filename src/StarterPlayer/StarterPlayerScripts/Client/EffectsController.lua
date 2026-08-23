local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EffectsController = {}
EffectsController.__index = EffectsController

function EffectsController.new(config)
	local self = setmetatable({}, EffectsController)
	self._config = config
	self._phase = nil
	self._sprinting = false
	self:_createLighting()
	return self
end

function EffectsController:_createLighting()
	for _, effectName in { "ShiftBreakPhaseColor", "ShiftBreakPhaseBloom", "ShiftBreakRiftAtmosphere" } do
		local previous = Lighting:FindFirstChild(effectName)
		if previous then
			previous:Destroy()
		end
	end

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "ShiftBreakPhaseColor"
	color.Brightness = -0.02
	color.Contrast = 0.08
	color.Saturation = -0.08
	color.TintColor = Color3.fromRGB(218, 247, 255)
	color.Parent = Lighting
	self._color = color

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "ShiftBreakPhaseBloom"
	bloom.Intensity = 0.55
	bloom.Size = 30
	bloom.Threshold = 1.1
	bloom.Parent = Lighting
	self._bloom = bloom

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "ShiftBreakRiftAtmosphere"
	atmosphere.Density = 0.24
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(177, 226, 255)
	atmosphere.Decay = Color3.fromRGB(45, 69, 112)
	atmosphere.Glare = 0.12
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	self._atmosphere = atmosphere

	Lighting.ClockTime = 1.4
	Lighting.Brightness = 1.8
	Lighting.Ambient = Color3.fromRGB(34, 40, 67)
	Lighting.OutdoorAmbient = Color3.fromRGB(18, 23, 42)
end

function EffectsController:SetPhase(phase, instant)
	if self._phase == phase then
		return false
	end
	self._phase = phase

	local fractured = phase == "FRACTURED"
	local duration = instant and 0 or 0.65
	TweenService:Create(self._color, TweenInfo.new(duration), {
		TintColor = fractured and Color3.fromRGB(255, 177, 229) or Color3.fromRGB(218, 247, 255),
		Contrast = fractured and 0.24 or 0.08,
		Saturation = fractured and -0.18 or -0.08,
		Brightness = fractured and -0.09 or -0.02,
	}):Play()
	TweenService:Create(self._bloom, TweenInfo.new(duration), {
		Intensity = fractured and 1.25 or 0.55,
		Size = fractured and 46 or 30,
	}):Play()
	TweenService:Create(self._atmosphere, TweenInfo.new(duration), {
		Color = fractured and Color3.fromRGB(215, 91, 180) or Color3.fromRGB(177, 226, 255),
		Decay = fractured and Color3.fromRGB(61, 12, 77) or Color3.fromRGB(45, 69, 112),
		Density = fractured and 0.34 or 0.24,
		Haze = fractured and 2.4 or 1.4,
	}):Play()
	return true
end

function EffectsController:SetSprinting(active)
	if self._sprinting == active then
		return
	end
	self._sprinting = active
	local camera = Workspace.CurrentCamera
	if camera then
		TweenService:Create(camera, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			FieldOfView = active and 78 or 70,
		}):Play()
	end
end

function EffectsController:Pulse(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local sphere = Instance.new("Part")
	sphere.Name = "LocalRiftPulse"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(2, 2, 2)
	sphere.CFrame = root.CFrame
	sphere.Color = self._config.Colors.Stable
	sphere.Material = Enum.Material.ForceField
	sphere.Transparency = 0.18
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanTouch = false
	sphere.CanQuery = false
	sphere.Parent = Workspace

	local tween = TweenService:Create(sphere, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(self._config.Player.PulseRadius * 2, self._config.Player.PulseRadius * 2, self._config.Player.PulseRadius * 2),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		sphere:Destroy()
	end)
end

return EffectsController
