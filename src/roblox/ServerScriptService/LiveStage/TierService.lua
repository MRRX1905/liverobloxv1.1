--!strict
local TierService = {}
local Config: any
local Lane: any
local Spawn: any
local Profile = require(script.Parent.ProfileService)
local totals: {[string]: { roseCoins: number, allCoins: number, tier: string, fan: boolean, lastSkip: number }} = {}
local priority = { normal = 0, giant = 1, king = 2 }

function TierService.Init(config: any, lane: any, spawn: any)
	Config, Lane, Spawn = config, lane, spawn
end

local function stateFor(userId: string): any
	if not totals[userId] then totals[userId] = { roseCoins = 0, allCoins = 0, tier = "normal", permanentTier = "normal", expiries = {}, fan = false, lastSkip = 0 } end
	return totals[userId]
end

local function activeTier(state: any): string
	local result = state.permanentTier or "normal"
	for tier, expiresAt in pairs(state.expiries) do
		if expiresAt > os.clock() and (priority[tier] or 0) > (priority[result] or 0) then result = tier end
	end
	return result
end

function TierService.Get(userId: string): any
	return stateFor(userId)
end

function TierService.Handle(event: {[string]: any})
	local userId = tostring(event.tiktokUserId or event.tiktokUsername or "")
	if userId == "" then return end
	local state = stateFor(userId)
	if event.isFan and not state.fan then
		state.fan = true
		local fanModel = Spawn.Get(userId)
		if fanModel then fanModel:SetAttribute("IsFan", true); Profile.Refresh(fanModel) end
	end
	if event.type ~= "gift" then return end
	local rules = Config.Get("tiers")
	local giftId, giftName = tonumber(event.giftId) or 0, string.lower(tostring(event.giftName or ""))
	local isRose = giftId == rules.rose.giftId or giftName == string.lower(rules.rose.giftName)
	local isDonut = giftId == rules.donut.giftId or giftName == string.lower(rules.donut.giftName)
	local count = math.clamp(math.floor(tonumber(event.repeatCount) or 1), 1, 10000)
	local coins = math.max(0, tonumber(event.diamondCount) or 0) * count
	state.allCoins += coins
	if isRose then
		state.roseCoins += (tonumber(rules.rose.coinValue) or 1) * count
		if rules.skip.roseCount > 0 and count >= rules.skip.roseCount and os.clock() - state.lastSkip >= rules.skip.cooldown then
			state.lastSkip = os.clock()
			Lane.Skip(userId)
		end
		if state.roseCoins >= rules.giant.requiredCoins then TierService.SetTier(userId, "giant") end
	end
	if isDonut and math.max(coins, (tonumber(rules.donut.coinValue) or 0) * count) >= rules.king.requiredCoins then TierService.SetTier(userId, "king") end
end

function TierService.SetTier(userId: string, tier: string)
	local state = stateFor(userId)
	if (priority[tier] or 0) <= (priority[state.tier] or 0) then return end
	state.tier = tier
	local duration = if tier == "king" then Config.Get("tiers.king.durationMinutes") else Config.Get("tiers.giant.durationMinutes")
	if duration > 0 then
		local expiresAt = os.clock() + duration * 60
		state.expiries[tier] = expiresAt
		task.delay(duration * 60, function()
			if state.expiries[tier] ~= expiresAt then return end
			state.expiries[tier] = nil
			local restoredTier = activeTier(state)
			if restoredTier == state.tier then return end
			state.tier = restoredTier
			local currentModel = Spawn.Get(userId)
			if currentModel and not Lane.CanRegister(restoredTier) then
				if Config.Get("spawn.resetMode") == "resetAll" then Spawn.ResetAll(); currentModel = nil
				else
					local row = if restoredTier == "king" then "king" elseif restoredTier == "giant" then "giant" else "normal"
					local oldest = Lane.Oldest(row)
					if oldest and oldest ~= userId then Spawn.Remove(oldest) end
				end
			end
			if currentModel then
				currentModel:SetAttribute("Tier", restoredTier)
				Spawn.ApplyTier(currentModel, restoredTier)
				Lane.SetTier(userId, restoredTier)
				Profile.Refresh(currentModel)
				Spawn.Announce("tier", currentModel, restoredTier)
			end
		end)
	else
		state.permanentTier = tier
	end
	local model = Spawn.Get(userId)
	if model and not Lane.CanRegister(tier) then
		if Config.Get("spawn.resetMode") == "resetAll" then
			Spawn.ResetAll()
		else
			local row = if tier == "king" then "king" else "giant"
			local oldest = Lane.Oldest(row)
			if oldest then Spawn.Remove(oldest) end
		end
		model = Spawn.Get(userId)
	end
	if model then
		model:SetAttribute("Tier", tier)
		Spawn.ApplyTier(model, tier)
		Lane.SetTier(userId, tier)
		Profile.Refresh(model)
		Spawn.Announce("tier", model, tier)
	end
end

function TierService.IsFan(userId: string): boolean return stateFor(userId).fan end
function TierService.Tier(userId: string): string return stateFor(userId).tier end
function TierService.Clear(reset: boolean)
	if not reset then return end
	if Config.Get("spawn.persistTiersAfterReset") then return end
	table.clear(totals)
end

return TierService
