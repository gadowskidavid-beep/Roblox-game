local upgradeTreeSettings = {
	
	
	
	currentTree = "mainTree", --Tree the player starts in
	contentSize = Vector2.new(2000,2000), --size of the upgradeTree
	panLimit = Vector2.new(1000,1000), -- how far the player can pan
	hexStagger = 0.1, --time of staggering animation of hexagons opening
	hexStaggerClose = 0.08, --time of staggering animation of hexagons closing
	hexClosedScale = .0001, -- size of hex when closed (keep low)
	dim = .2, --background transparency of menu
	fovMenu = 55,--field of view in tree
	hoverScale = 1.1, --scale of hex when hovered
	clickScale = 0.5, --scale of hex when clicked
	desc = false, --show descriptions
	newTagChance = 100, -- % chance of newTag appearing
	maxZoomIn = 0.5, --max zoom in
	maxZoomOut = 2, --max zoom out
	strokeSize = 4, --stroke thickness of the Texts#
	hexRadius = 125, -- how big the hexes are
	
	hexImg = {
		blue   = "rbxassetid://93624040434245",
		grey = "rbxassetid://116333682711721",
		red = "rbxassetid://88737779884826",
		gold = "rbxassetid://106651893002083",
	}, --images of the hexagons
	
	upgradeIcon = {
		redBook = "rbxassetid://74926877279424",
		oneEgg = "rbxassetid://115133441053724",
		twoEggs = "rbxassetid://123167849994463",
		threeEggs = "rbxassetid://132503986973330",
		fourEggs = "rbxassetid://108560446021709",
		fiveEggs = "rbxassetid://103968395124569",
		player = "rbxassetid://132473480715661",
		house = "rbxassetid://135608169397339",
		friends = "rbxassetid://88824686925184",
		lightning = "rbxassetid://93720048292311",
		clover = "rbxassetid://77723077485482",
		purpleClover = "rbxassetid://83151654742132",
		coin = "rbxassetid://111031759264614",
		clock = "rbxassetid://71087124456943",
		star = "rbxassetid://125659070991331",
		crown = "rbxassetid://107405159333282",
		dice = "rbxassetid://84038429632404",
		goldDice = "rbxassetid://93878325078402",
		x = "rbxassetid://83653552618422",
	},-- icons of the upgrades in the hexagon
	
	currencyIcon = {
		coins = "rbxassetid://111031759264614",
	},-- icons of the currency in the requirements
	
	
	--images
	
	dropShadowImage = "rbxassetid://136954378081653", -- dropshadow of the hex, image of the hex with only the shadow
	newTagImage = "rbxassetid://133285745758804", --Image of the new Tag
	notificationImage = "rbxassetid://139522588014781", --image of the notification background
	
	--colors
	textColor = Color3.fromRGB(242, 245, 250), --normal text
	mutedTextColor = Color3.fromRGB(172, 181, 196), --muted text
	
	--font
	font = "rbxasset://fonts/families/Montserrat.json", --font
}

return upgradeTreeSettings
