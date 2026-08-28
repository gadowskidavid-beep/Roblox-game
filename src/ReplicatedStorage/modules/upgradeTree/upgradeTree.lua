local replicatedStorage = game:GetService("ReplicatedStorage")
local modules = replicatedStorage:WaitForChild("modules")
local formatNumberModule = require(modules:WaitForChild("formatNumber"))
local contentProvider = game:GetService("ContentProvider")

local settings = require(script.Parent:WaitForChild("upgradeTreeSettings"))

local userInputService = game:GetService("UserInputService")

type side = "top" | "top-right" | "bottom-right" | "bottom" | "bottom-left" | "top-left"

type upgradeRequirement = {
	currency:string,
	amount:number,
}

type upgrades = {
	id:string,
	name:string,
	description:string,
	side:side,
	parentId:string,
	requireId:{string},
	visibleWhen: {string}?,
	requirements:{upgradeRequirement},
	upgradeIcon :string?,
	hexColor:string,
	isPortal:boolean?,
	portalTo:string?,
	toggleButton:boolean?,
}

type upgradeTreeData = {
	hexRadius:number,
	panLimit:Vector2,
	hexImg:{string},
	upgradeIcon:{string},
	currencyIcon:{string},
	upgrades:{upgrades},
}

type upgradeState = {
	currency: () -> number,
	addCurrency: (amount: number) -> (),
	isPurchased: (id: string) -> boolean,
	isUnlocked: (upgrade: upgrades) -> boolean,
	canBuy: (upgrade: upgrades) -> boolean,
	buy: (upgrade: upgrades) -> boolean,
}

type props = {
	data: upgradeTreeData,
	state: upgradeState,
	title: string?,
	toggleKey: Enum.KeyCode?,
	startOpen: boolean?,
	enableKeybind: boolean?,
	enableFovZoom: boolean?,
	renderAsFrame: boolean?,
	viewportTarget: GuiObject?,
	currentTree: string?,
}

local contentSize = settings.contentSize
local hexStagger = settings.hexStagger 
local hexStaggerClose = settings.hexStaggerClose 
local hexClosedScale = settings.hexClosedScale
local dim = settings.dim
local fovMenu = settings.fovMenu
local hoverScale = settings.hoverScale
local clickScale = settings.clickScale
local desc = settings.desc
local center = contentSize / 2
local lastBoughtUnit = Vector2.zero
local notificationColor = settings.notificationColor
local newTagChance = settings.newTagChance
local strokeSize = settings.strokeSize
local notificationImage = settings.notificationImage

local dropShadow = settings.dropShadowImage
local newTag = settings.newTagImage

local maxZoomIn = settings.maxZoomIn
local maxZoomOut = settings.maxZoomOut

local soundsFolder = script.Parent.sounds
local sounds = {
	hover = soundsFolder:FindFirstChild("hover"),
	open = soundsFolder:FindFirstChild("open"),
	close = soundsFolder:FindFirstChild("close"),
	upgrade = soundsFolder:FindFirstChild("upgrade"),
}

task.spawn(function()
	local soundList = {}
	for _, sound in sounds do
		if sound then
			table.insert(soundList, sound)
		end
	end
	contentProvider:PreloadAsync(soundList)
end)

local function playSound(sound)
	if not sound then return end
	local clone = sound:Clone()
	clone.Parent = sound.Parent
	clone:Play()
	game:GetService("Debris"):AddItem(clone, math.max(sound.TimeLength, 1) + 0.1)
end



local text = settings.textColor
local mutedText = settings.mutedTextColor

local font = settings.font

local sideUnits: { [string]: Vector2 } = {
	["top"]          = Vector2.new( 0,      1.7321),
	["top-right"]    = Vector2.new( 1.5,    0.8660),
	["bottom-right"] = Vector2.new( 1.5,   -0.8660),
	["bottom"]       = Vector2.new( 0,     -1.7321),
	["bottom-left"]  = Vector2.new(-1.5,   -0.8660),
	["top-left"]     = Vector2.new(-1.5,    0.8660),
}

local function clampVector2(value: Vector2, limit: Vector2): Vector2
	return Vector2.new(
		math.clamp(value.X, -limit.X, limit.X),
		math.clamp(value.Y, -limit.Y, limit.Y)
	)
end

local function getCameraViewportSize(): Vector2
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function makeUpgradeLookup(upgrades: { upgrades }): { [string]: upgrades }
	local lookup = {}
	for _, upgrade in upgrades do
		lookup[upgrade.id] = upgrade
	end
	return lookup
end

local function formatNumber(upgrades: upgrades): string
	return formatNumberModule.format(upgrades)
end

local function buildUnitPositions(upgrades: { upgrades }, lookup: { [string]: upgrades }): { [string]: Vector2 }
	local cache: { [string]: Vector2 } = {}

	local function getPos(upgrade: upgrades): Vector2
		if cache[upgrade.id] then
			return cache[upgrade.id]
		end

		if not upgrade.parentId or not upgrade.side then
			cache[upgrade.id] = Vector2.zero
			return Vector2.zero
		end

		local parentId = upgrade.parentId
		local parentUpgrade = lookup[parentId]

		if not parentUpgrade then
			cache[upgrade.id] = Vector2.zero
			return Vector2.zero
		end

		local parentPos = getPos(parentUpgrade)
		local sideKey = upgrade.side or ""
		local offset = sideUnits[sideKey] or Vector2.zero
		local pos = parentPos + Vector2.new(offset.X, -offset.Y)

		cache[upgrade.id] = pos
		return pos
	end

	for _, upgrade in upgrades do
		getPos(upgrade)
	end

	return cache
end

local function createUpgradeTree(vide,props:props)
	local create = vide.create
	local source = vide.source
	local effect = vide.effect
	local spring = vide.spring
	local cleanup = vide.cleanup
	local action = vide.action
	
	local data = props.data
	local state = props.state
	local currentTree = source(settings.currentTree or "mainTree")
	local radius = data.hexRadius
	local allLookups = {}
	local allUnitPositions = {}
	for treeName, treeUpgrades in data.upgrades do
		local lookup = makeUpgradeLookup(treeUpgrades)
		allLookups[treeName] = lookup
		allUnitPositions[treeName] = buildUnitPositions(treeUpgrades, lookup)
	end
	
	local viewportSize = source(getCameraViewportSize())
	local zoom = source(1)
	local pan = source(Vector2.zero)
	local menuOpen = source(props.startOpen == true)
	local buttonsVisible = source(true)
	local overlayVisible = source(props.startOpen == true)
	local toggleKey = props.toggleKey or Enum.KeyCode.Q
	local enableKeybind = props.enableKeybind ~= false
	local enableFovZoom = props.enableFovZoom ~= false
	
	local hoveredId = source(nil)
	
	
	local dimTransparency = spring(function()
		return if menuOpen() then dim else 1
	end, 0.5,.9)
	
	
	local camera = workspace.CurrentCamera
	local ogFov = if camera then camera.FieldOfView else 70
	local cameraFov = spring(function()
		return if menuOpen() then fovMenu else ogFov
	end, 0.5,.9)
	
	effect(function()
		if not enableFovZoom then return end
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = cameraFov()
		end
	end)

	cleanup(function()
		if not enableFovZoom then return end
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = ogFov
		end
	end)
	
	local dragging = false
	local dragMoved = false
	local dragStart = Vector2.zero
	local panStart = Vector2.zero
	local pinchStartZoom = 1
	
	local function viewportScale(): number
		local size = viewportSize()
		local fitScale = math.min(size.X / 1920, size.Y / 1080)
		return math.clamp(fitScale, 0.5, 1.5)
	end
	
	local function treeScale(): number
		return viewportScale() * zoom()
	end
	
	local function scaledRadius(): number
		return radius * treeScale()
	end
	
	local function scaledPanLimit(): Vector2
		return data.panLimit * treeScale()
	end
	
	local function scaledHexSize(): Vector2
		local nextRadius = scaledRadius()
		return Vector2.new(nextRadius * 2, nextRadius * 2)
	end
	
	local function setZoom(nextZoom: number)
		zoom(math.clamp(nextZoom, maxZoomIn, maxZoomOut))
		pan(clampVector2(pan(), scaledPanLimit()))
	end
	
	local function setMenuOpen(nextOpen: boolean)
		if nextOpen then
			overlayVisible(true)
			menuOpen(true)
			return
		end

		menuOpen(false)
		dragging = false

		local normalDelay = 0.24 + math.max(0, #data.upgrades[currentTree()] - 1) * hexStaggerClose
		local maxDelay = 1 

		task.delay(math.min(normalDelay, maxDelay), function()
			if not menuOpen() then
				overlayVisible(false)
			end
		end)
	end
	
	local function nodePosition(upgrade: upgrades, treeName: string): Vector2
		local positions = allUnitPositions[treeName] or {}
		local unit = positions[upgrade.id] or Vector2.zero
		local r = scaledRadius()
		return center + unit * r
	end
	
	local function isVisible(upgrades:upgrades):boolean
		if state.isPurchased(upgrades.id) then
			return true
		end
		
		local conditions = upgrades.visibleWhen or upgrades.requireId
		
		if #conditions == 0 then
			return true
		end
		
		for _,id in conditions do
			if not state.isPurchased(id) then
				return false
			end
		end
		return true
	end
	
	local function countBuyableInTree(treeName: string): number
		local treeUpgrades = data.upgrades[treeName]
		if not treeUpgrades then return 0 end
		local count = 0
		for _, upgrade in treeUpgrades do
			if state.canBuy(upgrade) and not state.isPurchased(upgrade.id) and not upgrade.isPortal and not upgrade.toggleButton then
				count += 1
			end
		end
		return count
	end
	
	local function statusText(upgrades:upgrades):string
		if state.isUnlocked(upgrades) and not state.isPurchased(upgrades.id) then
			local amount = upgrades.requirements[1].amount
			if amount == 0 then return "FREE!" end
			return formatNumber(amount)
		elseif state.isPurchased(upgrades.id) then
			return "Bought!"
		end
		return "Locked"
	end
	
	local function updateWheelZoom(input)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		
		local wheel = input.Position.Z
		if wheel == 0 then return end
		
		local size = viewportSize()
		local viewportCenter = size / 2
		local mousePos = Vector2.new(input.Position.X, input.Position.Y)
		local mouseOffset = mousePos - viewportCenter

		local oldZoom = zoom()
		local newZoom = math.clamp(oldZoom * (1 + wheel * 0.08), maxZoomIn, maxZoomOut)
		local zoomRatio = newZoom / oldZoom

		local currentPan = pan()
		local newPan = mouseOffset - (mouseOffset - currentPan) * zoomRatio

		zoom(newZoom)
		pan(clampVector2(newPan, data.panLimit * viewportScale() * newZoom))
	end
	
	local function beginDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragMoved = false
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			panStart = pan()
		end
	end
	local function updateDrag(input)
		
		updateWheelZoom(input)

		if not dragging then return end
		
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		
		local current = Vector2.new(input.Position.X, input.Position.Y)
		local delta = current - dragStart

		if delta.Magnitude > 6 then
			dragMoved = true
		end

		pan(clampVector2(panStart + delta, scaledPanLimit()))
	end
	
	
	local function createButton(upgrades: upgrades, index: number, treeName: string)
		local appeared = source(false)
		local justBought = source(false)
		local visible = source(false)
		local seen = source(false)
		local alive = true
		local appearToken = 0
		local prevMenuOpen = false
		local prevShouldBeVisible = false
		
		local positions = allUnitPositions[treeName] or {}
		local unit = positions[upgrades.id] or Vector2.zero
		local distance = unit.Magnitude
		
		local function getZIndex(upgrade: upgrades): number
			local positions = allUnitPositions[treeName] or {}
			local unit = positions[upgrade.id] or Vector2.zero
			local base = 100
			return base + math.round(-unit.Y * 10)
		end
		
		local isHovered = function()
			return hoveredId() == upgrades.id
		end
		
		cleanup(function()
			alive = false
		end)

		effect(function()
			appearToken += 1
			local currentToken = appearToken

			local isOpen = menuOpen()
			local isActiveTree = currentTree() == treeName
			local isButtonsVisible = buttonsVisible()
			local shouldBeVisible = isVisible(upgrades) and isActiveTree and isButtonsVisible
			local justOpened = isOpen and isActiveTree and isButtonsVisible and not prevMenuOpen
			local justUnlocked = shouldBeVisible and not prevShouldBeVisible and not justOpened

			prevMenuOpen = isOpen and isActiveTree and isButtonsVisible
			prevShouldBeVisible = shouldBeVisible

			if not isOpen or not isActiveTree or not isButtonsVisible then
				local closeDelay
				if not isActiveTree or not isButtonsVisible then
					closeDelay = hexStaggerClose * 2
				else
					closeDelay = distance * hexStaggerClose / 2
				end
				task.delay(closeDelay, function()
					if alive and currentToken == appearToken then
						appeared(false)
					end
				end)
				return
			end

			if not shouldBeVisible then
				appeared(false)
				visible(false)
				return
			end

			visible(true)

			local relativeDistance = (unit - lastBoughtUnit).Magnitude

			local delay = if justOpened then
				distance * hexStagger
				elseif justUnlocked then
				relativeDistance * hexStagger
				else
				0

			appeared(false)

			task.delay(delay, function()
				if alive and currentToken == appearToken and menuOpen() then
					appeared(true)
				end
			end)
		end)
		
		cleanup(function()
			appearToken += 1
		end)
	
		
		local function isHovered(): boolean
			return hoveredId() == upgrades.id
		end
		
		
		local scale = spring(function()
			if not appeared() then
				return hexClosedScale
			end
			if justBought() then
				return clickScale
			end

			if isHovered() then 
				return hoverScale
			end
			return 1
		end, .2,1)
		
		local tagScale = spring(function()
			if isHovered() or seen() then
				return 1.3
			end
			return 1
		end, .6, 1)
		
		local tagTransparency = spring(function()
			if isHovered() or seen() then
				return 1
			end
			return 0
		end, .6, 1)
		
		local nameTextNewPos = spring(function()
			if state.isUnlocked(upgrades) and state.isPurchased(upgrades.id) then
				return UDim2.fromScale(0.5, 0.75)
			end
			return UDim2.fromScale(0.5, 0.65)
		end, 1, 1)
		
		local costTransparency = spring(function()
			if state.isUnlocked(upgrades) and state.isPurchased(upgrades.id) then
				return 1
			end
			return 0
		end, 1, 1)
		
		local function strokeThickness(thickness:number)
			return (thickness * treeScale()) / scale()
		end

		
		local propsTable = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				local position = nodePosition(upgrades, treeName)
				return UDim2.fromOffset(position.X, position.Y)
			end,
			Size = function()
				local nextSize = scaledHexSize()
				return UDim2.fromOffset(nextSize.X, nextSize.Y)
			end,
			BackgroundTransparency = 1,
			Visible = visible,

			ZIndex = function()
				local base = getZIndex(upgrades)

				if isHovered() then
					return 10000 + base
				end

				return base
			end,

			create "UIScale" {
				Scale = scale,
			},
			
			--drop shadow
			create "ImageLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.6),
				Size = UDim2.fromScale(1.2, 1),
				BackgroundTransparency = 1,
				Image = dropShadow,
				ZIndex = 0,

			},
			
			create "ImageButton" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(.95, .95),
				BackgroundTransparency = 1,
				Image = function()
					if not state.isUnlocked(upgrades) then
						return data.hexImg["grey"] or ""
					end
					return data.hexImg[upgrades.hexImg]
				end,
				ZIndex = 1,
				AutoButtonColor = false,
				Active = function()
					return appeared()
				end,

				create "UIAspectRatioConstraint" {
					AspectRatio = 1,
				},

				InputBegan = beginDrag,
				InputChanged = updateDrag,

				MouseEnter = function()
					playSound(sounds.hover)
					hoveredId(upgrades.id)
					seen(true)
				end,

				MouseLeave = function()
					if hoveredId() == upgrades.id then
						hoveredId(nil)
					end
				end,

				Activated = function()
					if not dragMoved then
						--if upgrade is a portal
						if upgrades.isPortal and upgrades.portalTo then
							justBought(true)
							task.delay(0.08, function()
								if alive then justBought(false) end
							end)
							buttonsVisible(false)
							task.delay(0.3, function()
								currentTree(upgrades.portalTo)
								buttonsVisible(true)
							end)
							
							if upgrades.portalTo == "mainTree" then
								playSound(sounds.close)
								return
							end
							playSound(sounds.open)
							return
						end	
						
						if upgrades.toggleButton == true  then
							setMenuOpen(false)
							playSound(sounds.close)
							return
						end
						
						if not state.isUnlocked(upgrades) or upgrades.isPortal or upgrades.toggleButton then return end
						lastBoughtUnit = unit
						local success = state.buy(upgrades)
						if success then
							playSound(sounds.upgrade)
							justBought(true)
							task.delay(0.08, function()
								if alive then
									justBought(false)
								end
							end)
						end
					end
				end,
			},
			
			-- new tag
			create "ImageLabel"{
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.3, 0.32),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ImageTransparency = tagTransparency,
				Image = newTag,
				ZIndex = 12,
				Visible = function()
					if upgrades.toggleButton or (upgrades.isPortal and upgrades.portalTo == "mainTree") then return end
					local n = math.random(1,100)
					if n <= newTagChance then
						return true
					end
				end,
				create "UIScale"{
					Scale = tagScale
				},
				create "UIAspectRatioConstraint" {
					AspectRatio = 1,
				},
			},
			
			
			--notification shadow
			create "ImageLabel"{
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.8, 0.25),
				Size = UDim2.fromScale(0.45, 0.4),
				BackgroundTransparency = 1,
				Image = dropShadow,
				ZIndex = 4,
				Visible = function()
					if not upgrades.isPortal or not upgrades.portalTo then return false end
					local count = countBuyableInTree(upgrades.portalTo)
					if count > 0 then
						return true
					end
				end,
			},
			-- notification badge
			create "ImageLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.8, 0.2),
				Size = UDim2.fromScale(0.35, 0.35),
				BackgroundTransparency = 1,
				Image = notificationImage,
				ZIndex = 10,
				
				Visible = function()
					if not upgrades.isPortal or not upgrades.portalTo then return false end
					local count = countBuyableInTree(upgrades.portalTo)
					if count > 0 then
						return true
					end
				end,

				
				create "UIAspectRatioConstraint" {
					AspectRatio = 1,
				},
				
				
				
				
				create "TextLabel" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(.8, .8),
					BackgroundTransparency = 1,
					FontFace = Font.new(
						font,
						Enum.FontWeight.Bold,
						Enum.FontStyle.Normal
					),
					Text = function()
						if not upgrades.isPortal or not upgrades.portalTo then return "" end
						local count = countBuyableInTree(upgrades.portalTo)
						return if count > 0 then tostring(count) else ""
					end,
					TextColor3 = text,
					TextScaled = true,
					ZIndex = 20,

					create "UIStroke" {
						Thickness = function()
							return strokeThickness(strokeSize)
						end,
					}
				},
			},
			
			-- currency Icon
			create "ImageLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.33, 0.8),
				Size = UDim2.fromScale(.2, .2),
				BackgroundTransparency = 1,
				Image = function()
					if upgrades.requirements[1].amount == 0 then
						return ""
					else		
					return	data.currencyIcon[upgrades.requirements[1].currency] or ""
					end
				end,
				ImageTransparency = costTransparency,
				ZIndex = 12,
				Visible = true,

				create "UIAspectRatioConstraint" {
					AspectRatio = 1,
				},
			},

			-- Upgrade Icon
			create "ImageLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(.7, .7),
				BackgroundTransparency = 1,
				Image = data.upgradeIcon[upgrades.upgradeIcon] or "",
				ZIndex = 1,
				Visible = function()
					return state.isUnlocked(upgrades)
				end,

				create "UIAspectRatioConstraint" {
					AspectRatio = 1,
				},
			},
			-- Upgrade Price
			create "TextLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					if upgrades.requirements[1].amount == 0 then
					return UDim2.fromScale(0.50, 0.8)
					else
					return UDim2.fromScale(0.6, 0.8)
					end
				end,
				Size =  function()
					if upgrades.requirements[1].amount == 0 then
					return	UDim2.fromScale(0.4, 0.5)
					else
					return	UDim2.fromScale(0.25, 0.15)
					end
				end,
					
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				FontFace = Font.new(
					font,
					Enum.FontWeight.Bold,
					Enum.FontStyle.Normal
				),
				TextTransparency = costTransparency,
				Text = function()
					if upgrades.isPortal and upgrades.portalTo ~= "mainTree" then
						return "Open"
					elseif upgrades.isPortal and upgrades.portalTo == "mainTree" then
						return "Back"
					elseif upgrades.toggleButton then
						return "Exit"
					end
					return statusText(upgrades)
				end,
				TextColor3 = function()
					if upgrades.toggleButton == true then
						return text
					end
					if state.canBuy(upgrades) and not upgrades.isPortal  then
						return Color3.fromRGB(105, 244, 158)
					end
					return text
				end,
				TextScaled = true,
				Visible = true,
				ZIndex = 12,

				create "UIStroke" {
					Thickness = function()
						return strokeThickness(strokeSize)
					end,
					Transparency = costTransparency,
				}
			},
			-- Upgrade Name
			create "TextLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = nameTextNewPos,
				Size = UDim2.fromScale(1, 0.15),
				BackgroundTransparency = 1,
				FontFace = Font.new(
					font,
					Enum.FontWeight.Bold,
					Enum.FontStyle.Normal
				),
				Text = upgrades.name,
				TextColor3 = text,
				TextScaled = true,
				TextWrapped = true,
				Visible = function()
					return state.isUnlocked(upgrades)
				end,
				ZIndex = 35,

				create "UIStroke" {
					Thickness = function()
						return strokeThickness(strokeSize)
					end,
				}
			},
						-- description Frame
			create "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1.5, 0.4),
			Size = UDim2.fromScale(1.2, 1),
			Transparency = .7,
			ZIndex = 9999,
			
			Visible = function()
				return isHovered() and upgrades.description and desc
			end,

			-- description Text
			create "TextLabel" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.65),
					Size = UDim2.fromScale(.95, .8),
					BackgroundTransparency = 1,
					ZIndex = 9999,
					FontFace = Font.new(
						font,
						Enum.FontWeight.Bold,
						Enum.FontStyle.Normal
					),
					Text = upgrades.description,
					TextColor3 = text,
					TextScaled = true,
					TextWrapped = true,
					create "UIStroke" {
						Thickness = function()
							return strokeThickness(strokeSize)
						end,
					}
			},
				-- cost
				create "TextLabel" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(1,1),
					Size =  UDim2.fromScale(0.5,0.5),
					ZIndex = 9999,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					FontFace = Font.new(
						font,
						Enum.FontWeight.Bold,
						Enum.FontStyle.Normal
					),
					TextTransparency = 0,
					Text = function()
						return statusText(upgrades)
					end,
					TextColor3 = function()
						if state.canBuy(upgrades) then
							return Color3.fromRGB(105, 244, 158)
						end
						return text
					end,
					TextScaled = true,
					Visible = true,

					create "UIStroke" {
						Thickness = function()
							return strokeThickness(strokeSize)
						end,
						Transparency = 0,
					}
				},
				create "TextLabel" {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = nameTextNewPos,
					Size = UDim2.fromScale(1, 0.15),
					BackgroundTransparency = 1,
					FontFace = Font.new(
						font,
						Enum.FontWeight.Bold,
						Enum.FontStyle.Normal
					),
					Text = upgrades.name,
					TextColor3 = text,
					TextScaled = true,
					TextWrapped = true,
					ZIndex = 9999,

					create "UIStroke" {
						Thickness = function()
							return strokeThickness(strokeSize)
						end,
					}
				},
			},
		}
		
		return create("Frame")(propsTable)
	end
	
local function treeContent()
    local content = {}
    
    for treeName, treeUpgrades in data.upgrades do
        for i, upgrade in treeUpgrades do
            table.insert(content, createButton(upgrade, i, treeName))
        end
    end
    
    local propsTable = {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = function()
            local nextPan = pan()
            return UDim2.new(0.5, nextPan.X, 0.5, nextPan.Y)
        end,
        Size = UDim2.fromOffset(contentSize.X, contentSize.Y),
        BackgroundTransparency = 1,
    }
    
    for _, child in content do
        table.insert(propsTable, child)
    end
    
    return create("Frame")(propsTable)
end
	
	local function TreeViewport()
		return create "Frame" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Active = true,
			ZIndex = 1,

			InputBegan = beginDrag,
			InputChanged = updateDrag,
			InputEnded = updateWheelZoom,

			action(function()
				local connection = userInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = false
					end
				end)

				local pinchConnection = userInputService.TouchPinch:Connect(function(touchPositions, scale, _, pinchState)
					if not menuOpen() then return end

					if pinchState == Enum.UserInputState.Begin then
						pinchStartZoom = zoom()
						dragging = false

					elseif pinchState == Enum.UserInputState.Change then
						local sum = Vector2.zero
						for _, pos in touchPositions do
							sum += Vector2.new(pos.X, pos.Y)
						end
						local pinchCenter = sum / #touchPositions

						local size = viewportSize()
						local viewportCenter = size / 2
						local mouseOffset = pinchCenter - viewportCenter

						local oldZoom = zoom()
						local newZoom = math.clamp(pinchStartZoom * scale, maxZoomIn, maxZoomOut)
						local zoomRatio = newZoom / oldZoom

						local currentPan = pan()
						local newPan = mouseOffset - (mouseOffset - currentPan) * zoomRatio

						zoom(newZoom)
						pan(clampVector2(newPan, data.panLimit * viewportScale() * newZoom))
					end
				end)

				cleanup(function()
					connection:Disconnect()
					pinchConnection:Disconnect()
				end)
			end),

			treeContent(),
		}
	end
	
	local viewportAction = action(function()
		if props.viewportTarget then
			viewportSize(props.viewportTarget.AbsoluteSize)

			local targetConnection = props.viewportTarget:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				viewportSize(props.viewportTarget.AbsoluteSize)
				pan(clampVector2(pan(), scaledPanLimit()))
			end)

			cleanup(function()
				targetConnection:Disconnect()
			end)

			return
		end
		
		local viewportConnection: RBXScriptConnection? = nil
		

		local function bindCamera(camera: Camera?)
			if viewportConnection then
				viewportConnection:Disconnect()
				viewportConnection = nil
			end

			if not camera then return end

			viewportSize(camera.ViewportSize)
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				viewportSize(camera.ViewportSize)
				pan(clampVector2(pan(), scaledPanLimit()))
			end)
		end

		bindCamera(workspace.CurrentCamera)

		local cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindCamera(workspace.CurrentCamera)
		end)

		cleanup(function()
			cameraConnection:Disconnect()
			if viewportConnection then
				viewportConnection:Disconnect()
			end
		end)
	end)
	
	local keybindAction = if enableKeybind
		then action(function()
			local connection = userInputService.InputBegan:Connect(function(input)
				if userInputService:GetFocusedTextBox() then return end
				if input.KeyCode == toggleKey then
					setMenuOpen(not menuOpen())
				end
			end)

			cleanup(function()
				connection:Disconnect()
			end)
		end)
		else action(function() end)

	local overlay = create "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = dimTransparency,
		BorderSizePixel = 0,
		Visible = overlayVisible,

		create "CanvasGroup" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			TreeViewport(),
		},
	}
	
	if props.renderAsFrame then
		return create "Frame" {
			Name = "UpgradeTreePreview",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			viewportAction,
			keybindAction,
			overlay,
		}
	end

	return create "ScreenGui" {
		Name = "UpgradeTreeGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,

		viewportAction,
		keybindAction,
		overlay,
	}
end

return createUpgradeTree

