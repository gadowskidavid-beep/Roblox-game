local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIController = {}
UIController.__index = UIController

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in properties do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function addCorner(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function addStroke(parent, color, transparency, thickness)
	return create("UIStroke", {
		Color = color,
		Transparency = transparency or 0.65,
		Thickness = thickness or 1,
	}, parent)
end

local function formatTime(seconds)
	seconds = math.max(0, math.ceil(seconds or 0))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function UIController.new(config)
	local self = setmetatable({}, UIController)
	self._config = config
	self._player = Players.LocalPlayer
	self._purchaseCallback = nil
	self._toastToken = 0
	self._state = {}
	self._upgradeButtons = {}
	if UserInputService.TouchEnabled then
		self._controls = {
			Sprint = "SPRINT",
			Pulse = "RISS-PULS",
			Deposit = "Am Anker die Interaktion antippen",
			Intro = "Touch: SPRINT · PULS · Anker-Interaktion",
		}
	elseif UserInputService.GamepadEnabled then
		self._controls = {
			Sprint = "[L3]  SPRINT",
			Pulse = "[R2]  RISS-PULS",
			Deposit = "Am Anker [X] übertragen",
			Intro = "[L3] Sprint     [R2] Riss-Puls     [X] Übertragen",
		}
	else
		self._controls = {
			Sprint = "[SHIFT]  SPRINT",
			Pulse = "[Q]  RISS-PULS",
			Deposit = "Sammeln → am Kern [E] übertragen",
			Intro = "[SHIFT] Sprint     [Q] Riss-Puls     [E] Übertragen",
		}
	end
	self:_build()
	self:UpdatePlayer()
	return self
end

function UIController:_label(parent, properties)
	properties.BackgroundTransparency = properties.BackgroundTransparency == nil and 1 or properties.BackgroundTransparency
	properties.TextColor3 = properties.TextColor3 or self._config.Colors.Text
	properties.Font = properties.Font or Enum.Font.Gotham
	properties.TextSize = properties.TextSize or 16
	return create("TextLabel", properties, parent)
end

function UIController:_panel(parent, name, position, size)
	local panel = create("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = self._config.Colors.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, parent)
	addCorner(panel, 12)
	addStroke(panel, self._config.Colors.Stable, 0.72, 1)
	return panel
end

function UIController:_build()
	local gui = create("ScreenGui", {
		Name = "ShiftBreakHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}, self._player:WaitForChild("PlayerGui"))
	self.Gui = gui

	local root = create("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, gui)
	self.Root = root

	self:_label(root, {
		Name = "Brand",
		Position = UDim2.fromOffset(24, 16),
		Size = UDim2.fromOffset(260, 44),
		Text = "SHIFT//BREAK",
		TextColor3 = self._config.Colors.Stable,
		Font = Enum.Font.GothamBlack,
		TextSize = 25,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self:_label(root, {
		Position = UDim2.fromOffset(25, 48),
		Size = UDim2.fromOffset(250, 20),
		Text = "RISSBERGUNGSPROTOKOLL",
		TextColor3 = self._config.Colors.MutedText,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local statusPanel = self:_panel(root, "StatusPanel", UDim2.new(0.5, 0, 0, 62), UDim2.new(0.9, 0, 0, 88))
	statusPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	create("UISizeConstraint", {
		MinSize = Vector2.new(300, 88),
		MaxSize = Vector2.new(410, 88),
	}, statusPanel)
	self.PhaseStrip = create("Frame", {
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = self._config.Colors.Stable,
		BorderSizePixel = 0,
	}, statusPanel)
	addCorner(self.PhaseStrip, 12)
	self.StatusLabel = self:_label(statusPanel, {
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -130, 0, 32),
		Text = "SYSTEMSTART",
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self.TimerLabel = self:_label(statusPanel, {
		Position = UDim2.new(1, -120, 0, 13),
		Size = UDim2.fromOffset(102, 34),
		Text = "00:00",
		TextColor3 = self._config.Colors.Echo,
		Font = Enum.Font.RobotoMono,
		TextSize = 25,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	self.DetailLabel = self:_label(statusPanel, {
		Position = UDim2.fromOffset(18, 50),
		Size = UDim2.new(1, -36, 0, 24),
		Text = "Verbindung wird hergestellt …",
		TextColor3 = self._config.Colors.MutedText,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local objectivePanel = self:_panel(root, "ObjectivePanel", UDim2.fromOffset(24, 88), UDim2.fromOffset(305, 110))
	self:_label(objectivePanel, {
		Position = UDim2.fromOffset(15, 11),
		Size = UDim2.new(1, -30, 0, 20),
		Text = "RISS-ANKER",
		TextColor3 = self._config.Colors.MutedText,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self.ObjectiveLabel = self:_label(objectivePanel, {
		Position = UDim2.fromOffset(15, 34),
		Size = UDim2.new(1, -30, 0, 28),
		Text = "0 / 0 ECHOS",
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local progressBack = create("Frame", {
		Position = UDim2.fromOffset(15, 76),
		Size = UDim2.new(1, -30, 0, 12),
		BackgroundColor3 = self._config.Colors.Background,
		BorderSizePixel = 0,
	}, objectivePanel)
	addCorner(progressBack, 6)
	self.ProgressFill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = self._config.Colors.Stable,
		BorderSizePixel = 0,
	}, progressBack)
	addCorner(self.ProgressFill, 6)
	self.ObjectiveHint = self:_label(objectivePanel, {
		Position = UDim2.fromOffset(15, 91),
		Size = UDim2.new(1, -30, 0, 15),
		Text = self._controls.Deposit,
		TextColor3 = self._config.Colors.MutedText,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local playerPanel = self:_panel(root, "PlayerPanel", UDim2.new(0, 24, 1, -164), UDim2.fromOffset(305, 136))
	self.HeldLabel = self:_label(playerPanel, {
		Position = UDim2.fromOffset(15, 12),
		Size = UDim2.new(0.64, 0, 0, 29),
		Text = "ECHOS  0 / 5",
		Font = Enum.Font.GothamBlack,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self.FluxLabel = self:_label(playerPanel, {
		Position = UDim2.new(0.62, 0, 0, 12),
		Size = UDim2.new(0.32, 0, 0, 29),
		Text = "◇ 0",
		TextColor3 = self._config.Colors.Echo,
		Font = Enum.Font.RobotoMono,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	self:_label(playerPanel, {
		Position = UDim2.fromOffset(15, 54),
		Size = UDim2.new(1, -30, 0, 17),
		Text = "AUSDAUER",
		TextColor3 = self._config.Colors.MutedText,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local staminaBack = create("Frame", {
		Position = UDim2.fromOffset(15, 76),
		Size = UDim2.new(1, -30, 0, 12),
		BackgroundColor3 = self._config.Colors.Background,
		BorderSizePixel = 0,
	}, playerPanel)
	addCorner(staminaBack, 6)
	self.StaminaFill = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self._config.Colors.Success,
		BorderSizePixel = 0,
	}, staminaBack)
	addCorner(self.StaminaFill, 6)
	self.UpgradeSummary = self:_label(playerPanel, {
		Position = UDim2.fromOffset(15, 100),
		Size = UDim2.new(1, -30, 0, 20),
		Text = "TASCHE 0  ·  TEMPO 0  ·  PULS 0",
		TextColor3 = self._config.Colors.MutedText,
		Font = Enum.Font.RobotoMono,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local abilities = self:_panel(root, "Abilities", UDim2.new(0.5, 0, 1, -60), UDim2.new(0.9, 0, 0, 64))
	abilities.AnchorPoint = Vector2.new(0.5, 0.5)
	create("UISizeConstraint", {
		MinSize = Vector2.new(310, 64),
		MaxSize = Vector2.new(360, 64),
	}, abilities)
	self.SprintLabel = self:_label(abilities, {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.new(0.5, -18, 0, 45),
		BackgroundColor3 = self._config.Colors.Background,
		BackgroundTransparency = 0.15,
		Text = self._controls.Sprint,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
	})
	addCorner(self.SprintLabel, 8)
	self.PulseLabel = self:_label(abilities, {
		Position = UDim2.new(0.5, 10, 0, 9),
		Size = UDim2.new(0.5, -18, 0, 45),
		BackgroundColor3 = self._config.Colors.Background,
		BackgroundTransparency = 0.15,
		Text = self._controls.Pulse,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
	})
	addCorner(self.PulseLabel, 8)

	self.ShopPanel = self:_panel(root, "ShopPanel", UDim2.new(1, -18, 0, 128), UDim2.new(0.9, 0, 0, 354))
	self.ShopPanel.AnchorPoint = Vector2.new(1, 0)
	create("UISizeConstraint", {
		MinSize = Vector2.new(300, 354),
		MaxSize = Vector2.new(330, 354),
	}, self.ShopPanel)
	self:_label(self.ShopPanel, {
		Position = UDim2.fromOffset(17, 14),
		Size = UDim2.new(1, -34, 0, 26),
		Text = "RISS-WERKSTATT",
		TextColor3 = self._config.Colors.Echo,
		Font = Enum.Font.GothamBlack,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self:_label(self.ShopPanel, {
		Position = UDim2.fromOffset(17, 41),
		Size = UDim2.new(1, -34, 0, 34),
		Text = "Permanente Upgrades · nur zwischen Runden",
		TextColor3 = self._config.Colors.MutedText,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	for index, upgradeName in self._config.Upgrades.Order do
		local button = create("TextButton", {
			Name = upgradeName,
			Position = UDim2.fromOffset(17, 80 + (index - 1) * 82),
			Size = UDim2.new(1, -34, 0, 70),
			BackgroundColor3 = self._config.Colors.Background,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
		}, self.ShopPanel)
		addCorner(button, 9)
		addStroke(button, self._config.Colors.Echo, 0.74, 1)

		local title = self:_label(button, {
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -110, 0, 24),
			Text = upgradeName,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local description = self:_label(button, {
			Position = UDim2.fromOffset(12, 33),
			Size = UDim2.new(1, -24, 0, 25),
			Text = "",
			TextColor3 = self._config.Colors.MutedText,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local price = self:_label(button, {
			Position = UDim2.new(1, -102, 0, 8),
			Size = UDim2.fromOffset(90, 25),
			Text = "◇ 0",
			TextColor3 = self._config.Colors.Echo,
			Font = Enum.Font.RobotoMono,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
		})

		self._upgradeButtons[upgradeName] = {
			button = button,
			title = title,
			description = description,
			price = price,
		}
		button.MouseButton1Click:Connect(function()
			if self._purchaseCallback then
				self._purchaseCallback(upgradeName)
			end
		end)
	end

	self.Toast = self:_label(root, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.new(0.8, 0, 0, 54),
		BackgroundColor3 = self._config.Colors.Panel,
		BackgroundTransparency = 1,
		Text = "",
		TextTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextWrapped = true,
		ZIndex = 30,
	})
	addCorner(self.Toast, 10)
	create("UISizeConstraint", {
		MinSize = Vector2.new(280, 54),
		MaxSize = Vector2.new(540, 54),
	}, self.Toast)
	addStroke(self.Toast, self._config.Colors.Stable, 0.5, 1)

	self.PhaseFlash = create("Frame", {
		Name = "PhaseFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self._config.Colors.Stable,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 40,
	}, root)

	self.Intro = create("Frame", {
		Name = "Intro",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = self._config.Colors.Background,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, root)
	local introCard = self:_panel(self.Intro, "IntroCard", UDim2.fromScale(0.5, 0.5), UDim2.new(0.9, 0, 0, 340))
	introCard.AnchorPoint = Vector2.new(0.5, 0.5)
	create("UISizeConstraint", {
		MinSize = Vector2.new(310, 340),
		MaxSize = Vector2.new(580, 340),
	}, introCard)
	introCard.ZIndex = 51
	self:_label(introCard, {
		Position = UDim2.fromOffset(30, 30),
		Size = UDim2.new(1, -60, 0, 55),
		Text = "SHIFT//BREAK",
		TextColor3 = self._config.Colors.Stable,
		Font = Enum.Font.GothamBlack,
		TextSize = 37,
		ZIndex = 52,
	})
	self:_label(introCard, {
		Position = UDim2.fromOffset(35, 94),
		Size = UDim2.new(1, -70, 0, 150),
		Text = string.format("Die Realität kippt alle %d Sekunden.\n\nSammle Echos · bringe sie in der STABILEN Phase zum Anker · überlebe Schatten in der GEBROCHENEN Phase.\n\n%s", self._config.Round.ShiftInterval, self._controls.Intro),
		TextColor3 = self._config.Colors.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 52,
	})
	local enterButton = create("TextButton", {
		Position = UDim2.new(0.5, -125, 1, -74),
		Size = UDim2.fromOffset(250, 46),
		BackgroundColor3 = self._config.Colors.Stable,
		BorderSizePixel = 0,
		Text = "PROTOKOLL STARTEN",
		TextColor3 = self._config.Colors.Background,
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		ZIndex = 52,
	}, introCard)
	addCorner(enterButton, 8)
	enterButton.MouseButton1Click:Connect(function()
		self:DismissIntro()
	end)

	if UserInputService.TouchEnabled then
		abilities.Position = UDim2.new(0.5, 0, 1, -138)
		playerPanel.Position = UDim2.new(0, 8, 1, -240)
		objectivePanel.Position = UDim2.fromOffset(8, 88)
	end
end

function UIController:SetPurchaseCallback(callback)
	self._purchaseCallback = callback
end

function UIController:DismissIntro()
	if not self.Intro.Visible then
		return
	end
	local tween = TweenService:Create(self.Intro, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		self.Intro.Visible = false
	end)
end

function UIController:UpdatePlayer()
	local held = self._player:GetAttribute("HeldEchoes") or 0
	local capacity = self._player:GetAttribute("MaxCapacity") or self._config.Player.StartingCapacity
	local flux = self._player:GetAttribute("Flux") or 0
	local stamina = self._player:GetAttribute("Stamina") or self._config.Player.MaxStamina
	local capacityLevel = self._player:GetAttribute("UpgradeCapacity") or 0
	local speedLevel = self._player:GetAttribute("UpgradeSpeed") or 0
	local pulseLevel = self._player:GetAttribute("UpgradePulse") or 0

	self.HeldLabel.Text = string.format("ECHOS  %d / %d", held, capacity)
	self.HeldLabel.TextColor3 = held >= capacity and self._config.Colors.Echo or self._config.Colors.Text
	self.FluxLabel.Text = string.format("◇ %d", flux)
	self.UpgradeSummary.Text = string.format("TASCHE %d  ·  TEMPO %d  ·  PULS %d", capacityLevel, speedLevel, pulseLevel)

	local staminaRatio = math.clamp(stamina / self._config.Player.MaxStamina, 0, 1)
	self.StaminaFill.Size = UDim2.fromScale(staminaRatio, 1)
	self.StaminaFill.BackgroundColor3 = staminaRatio < 0.25 and self._config.Colors.Danger or self._config.Colors.Success

	local levels = {
		Capacity = capacityLevel,
		Speed = speedLevel,
		Pulse = pulseLevel,
	}
	for upgradeName, widgets in self._upgradeButtons do
		local definition = self._config.Upgrades.Definitions[upgradeName]
		local level = levels[upgradeName]
		local isMax = level >= #definition.Costs
		widgets.title.Text = string.format("%s  ·  STUFE %d/%d", definition.DisplayName, level, #definition.Costs)
		widgets.description.Text = definition.Description
		widgets.price.Text = isMax and "MAX" or string.format("◇ %d", definition.Costs[level + 1])
		widgets.price.TextColor3 = isMax and self._config.Colors.Success or self._config.Colors.Echo
		widgets.button.BackgroundTransparency = isMax and 0.35 or 0.08
	end
end

function UIController:SetState(state)
	self._state = state
	local statusText = {
		Waiting = "WARTE AUF SPIELER",
		Intermission = "NÄCHSTER RISS ÖFFNET",
		Running = state.phase == "FRACTURED" and "DIMENSIONSBRUCH" or "STABILE BERGUNG",
		WaveClear = "WELLE STABILISIERT",
		Victory = "RISS VERSIEGELT",
		Defeat = "SYNCHRONISIERUNG GESCHEITERT",
	}
	self.StatusLabel.Text = statusText[state.status] or "SYSTEM BEREIT"
	self.TimerLabel.Text = formatTime(state.timeRemaining)

	local phaseColor = state.phase == "FRACTURED" and self._config.Colors.Fractured or self._config.Colors.Stable
	self.PhaseStrip.BackgroundColor3 = phaseColor
	self.ProgressFill.BackgroundColor3 = phaseColor
	if state.status == "Running" then
		self.DetailLabel.Text = string.format("WELLE %d/%d  ·  PHASENWECHSEL IN %s", state.wave or 0, state.maxWaves or 0, formatTime(state.shiftRemaining))
	else
		self.DetailLabel.Text = string.format("SPIELER %d/%d  ·  WELLE %d/%d", state.playerCount or 0, state.minimumPlayers or 1, state.wave or 0, state.maxWaves or 0)
	end

	local target = state.target or 0
	local banked = state.banked or 0
	self.ObjectiveLabel.Text = string.format("%d / %d ECHOS", banked, target)
	local ratio = target > 0 and math.clamp(banked / target, 0, 1) or 0
	TweenService:Create(self.ProgressFill, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(ratio, 1) }):Play()
	self.ObjectiveHint.Text = state.phase == "FRACTURED" and ("ANKER OFFLINE · " .. self._controls.Pulse .. " einsetzen") or self._controls.Deposit
	self.ShopPanel.Visible = state.status ~= "Running" and state.status ~= "WaveClear"
end

function UIController:SetPulseCooldown(seconds)
	seconds = math.max(0, seconds or 0)
	if seconds > 0.05 then
		self.PulseLabel.Text = string.format("%s  %.1fs", self._controls.Pulse, seconds)
		self.PulseLabel.TextColor3 = self._config.Colors.MutedText
	else
		self.PulseLabel.Text = self._controls.Pulse
		self.PulseLabel.TextColor3 = self._config.Colors.Stable
	end
end

function UIController:SetSprinting(active)
	self.SprintLabel.TextColor3 = active and self._config.Colors.Success or self._config.Colors.Text
end

function UIController:ShowMessage(text, tone)
	self._toastToken += 1
	local token = self._toastToken
	local colors = {
		Info = self._config.Colors.Text,
		Success = self._config.Colors.Success,
		Danger = self._config.Colors.Danger,
		Stable = self._config.Colors.Stable,
		Fractured = self._config.Colors.Fractured,
	}
	self.Toast.Text = text
	self.Toast.TextColor3 = colors[tone] or self._config.Colors.Text
	self.Toast.Visible = true
	TweenService:Create(self.Toast, TweenInfo.new(0.18), { TextTransparency = 0, BackgroundTransparency = 0.08 }):Play()

	task.delay(3.2, function()
		if token ~= self._toastToken then
			return
		end
		local tween = TweenService:Create(self.Toast, TweenInfo.new(0.35), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			if token == self._toastToken then
				self.Toast.Visible = false
			end
		end)
	end)
end

function UIController:FlashPhase(phase)
	local color = phase == "FRACTURED" and self._config.Colors.Fractured or self._config.Colors.Stable
	self.PhaseFlash.BackgroundColor3 = color
	self.PhaseFlash.BackgroundTransparency = 0.72
	local tween = TweenService:Create(self.PhaseFlash, TweenInfo.new(0.65, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
	tween:Play()
end

return UIController
