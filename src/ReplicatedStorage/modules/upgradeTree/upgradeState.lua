export type Source<T> = (() -> T) & ((T) -> ())

export type Upgrade = {
	id: string,
	requireId: { string },
	requirements: {
		{
			currency: string,
			amount: number,
		}
	},
}

export type State = {
	currency: Source<{ [string]: number }>,
	purchased: Source<{ [string]: boolean }>,
	setCurrency: (name: string, amount: number) -> (),
	addCurrency: (name: string, amount: number) -> (),
	isPurchased: (id: string) -> boolean,
	isUnlocked: (upgrade: Upgrade) -> boolean,
	canBuy: (upgrade: Upgrade) -> boolean,
	buy: (upgrade: Upgrade) -> boolean,
}

local function copyTable<T>(input: { [string]: T }): { [string]: T }
	local output = {}
	for k, v in input do
		output[k] = v
	end
	return output
end

local function createUpgradeState(
	vide,
	initialCurrency: { [string]: number }?,
	initialPurchased: { [string]: boolean }?
): State
	local currency = vide.source(initialCurrency or {})
	local purchased = vide.source(initialPurchased or {})
	local state = {} :: State

	function state.setCurrency(name: string, amount: number)
		local next = copyTable(currency())
		next[name] = math.max(0, amount)
		currency(next)
	end

	function state.addCurrency(name: string, amount: number)
		local next = copyTable(currency())
		next[name] = math.max(0, (next[name] or 0) + amount)
		currency(next)
	end

	function state.isPurchased(id: string): boolean
		return purchased()[id] == true
	end

	function state.isUnlocked(upgrade: Upgrade): boolean
		for _, requiredId in upgrade.requireId do
			if not state.isPurchased(requiredId) then
				return false
			end
		end
		return true
	end

	function state.canBuy(upgrade: Upgrade): boolean
		if state.isPurchased(upgrade.id) then return false end
		if not state.isUnlocked(upgrade) then return false end
		local bal = currency()
		for _, req in upgrade.requirements do
			if (bal[req.currency] or 0) < req.amount then
				return false
			end
		end
		return true
	end

	function state.buy(upgrade: Upgrade): boolean
		if not state.canBuy(upgrade) then return false end
		local nextCurrency = copyTable(currency())
		for _, req in upgrade.requirements do
			nextCurrency[req.currency] = (nextCurrency[req.currency] or 0) - req.amount
		end
		currency(nextCurrency)
		local nextPurchased = copyTable(purchased())
		nextPurchased[upgrade.id] = true
		purchased(nextPurchased)
		return true
	end

	state.currency = currency
	state.purchased = purchased
	return state
end

return createUpgradeState