--!strict
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local ConfigService = {}
local STORE = DataStoreService:GetDataStore("LiveStageConfig_v1")

local DEFAULTS: {[string]: any} = {
	version = 1,
	relay = { baseUrl = "https://replace-with-your-public-relay.example", transport = "polling", pollSeconds = 1, batchSize = 100, maxRetries = 5 },
	spawn = { maxTotal = 30, maxPerRow = { normal = 15, giant = 8, king = 4 }, resetMode = "resetAll", userCooldown = 5, globalCooldown = 0.15, persistTiersAfterReset = true, maxCommentLength = 180 },
	lanes = { normalDepth = 0, giantDepth = 28, kingDepth = 58, rowZ = 0, spacing = 12, rowGap = 18, verticalOffset = 4 },
	tiers = {
		rose = { giftName = "Rose", giftId = 5655, coinValue = 1 },
		donut = { giftName = "Donut", giftId = 5879, coinValue = 30 },
		giant = { requiredCoins = 10, scale = 2.0, durationMinutes = 0 },
		king = { requiredCoins = 30, scale = 3.5, durationMinutes = 0 },
		skip = { roseCount = 1, cooldown = 15 },
		fans = { title = "FANS", color = "#FF2D55" },
	},
	profile = { enabled = true, priceCacheHours = 24, maxAssetsPerPass = 100, maxDistance = 120 },
	camera = { mode = "autoDirector", focusSeconds = 4, fov = 60, offset = { x = 0, y = 7, z = 18 }, transitionSeconds = 1.2 },
	vfx = { quality = "high", maxParticleRate = 16, aurasEnabled = true, auras = {
		{ name = "Violet", tier = "normal", color = "#B781FF", weight = 5 },
		{ name = "Ice", tier = "normal", color = "#72D3FF", weight = 4 },
		{ name = "Rose", tier = "normal", color = "#FF6D9A", weight = 2 },
		{ name = "Nova", tier = "giant", color = "#5CCEFF", weight = 5 },
		{ name = "Solar", tier = "giant", color = "#FFD16E", weight = 2 },
		{ name = "Crown", tier = "king", color = "#FFC24E", weight = 1 },
	} },
	admin = { userIds = { 567888546 }, groupId = 0, minimumGroupRank = 255 },
	moderation = { blockedUsers = {}, mutedUsers = {} },
	animations = {},
}

local current = table.clone(DEFAULTS)
local ready = false
local arrayKeys = { userIds = true, blockedUsers = true, mutedUsers = true, auras = true, animations = true }

local function deepClone(value: any): any
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = deepClone(item) end
	return copy
end

local function merge(target: {[any]: any}, source: any)
	if type(source) ~= "table" then return end
	for key, value in pairs(source) do
		if arrayKeys[key] and type(value) == "table" then
			target[key] = deepClone(value)
		elseif target[key] ~= nil and type(target[key]) == "table" and type(value) == "table" then
			merge(target[key], value)
		elseif target[key] ~= nil and type(target[key]) == type(value) then
			target[key] = value
		end
	end
end

local function applyPublishedConfig()
	local okService, robloxConfig = pcall(function() return game:GetService("ConfigService") end)
	if not okService then return end
	local okSnapshot, snapshot = pcall(function() return (robloxConfig :: any):GetConfigAsync() end)
	if not okSnapshot or not snapshot then return end
	local mapped = {
		StageMaxCharacters = { "spawn", "maxTotal" },
		StageSpawnCooldown = { "spawn", "userCooldown" },
		StageGiantCoins = { "tiers", "giant", "requiredCoins" },
		StageKingCoins = { "tiers", "king", "requiredCoins" },
	}
	for configKey, path in pairs(mapped) do
		local okValue, value = pcall(function() return (snapshot :: any):GetValue(configKey) end)
		if okValue and type(value) == "number" then
			local target = current
			for index = 1, #path - 1 do target = target[path[index]] end
			target[path[#path]] = value
		end
	end
end

function ConfigService.Load()
	current = deepClone(DEFAULTS)
	applyPublishedConfig()
	local ok, stored = pcall(function() return STORE:GetAsync("config") end)
	if ok then merge(current, stored) else warn("[LiveStage] Settings store unavailable; using defaults") end
	ready = true
end

function ConfigService.Get(path: string?): any
	if not ready then ConfigService.Load() end
	if not path or path == "" then return deepClone(current) end
	local value: any = current
	for piece in string.gmatch(path, "[^.]+") do
		if type(value) ~= "table" then return nil end
		value = value[piece]
	end
	return value
end

function ConfigService.UpdateFromJSON(json: string): (boolean, string?)
	if #json > 80_000 then return false, "Settings payload is too large." end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok or type(decoded) ~= "table" then return false, "Settings must be a JSON object." end
	local nextConfig = deepClone(current)
	merge(nextConfig, decoded)
	local spawn = nextConfig.spawn
	local tiers = nextConfig.tiers
	if spawn.maxTotal < 1 or spawn.maxTotal > 100 then return false, "maxTotal must be between 1 and 100." end
	if spawn.userCooldown < 0 or spawn.userCooldown > 120 then return false, "userCooldown must be between 0 and 120 seconds." end
	if spawn.resetMode ~= "resetAll" and spawn.resetMode ~= "removeOldest" then return false, "resetMode must be resetAll or removeOldest." end
	if tiers.giant.scale < 1 or tiers.giant.scale > 8 or tiers.king.scale < tiers.giant.scale or tiers.king.scale > 12 then return false, "Tier scales are outside supported limits." end
	if tiers.giant.requiredCoins < 1 or tiers.giant.requiredCoins > 1_000_000 or tiers.king.requiredCoins < 1 or tiers.king.requiredCoins > 1_000_000 then return false, "Gift thresholds must be between 1 and 1,000,000 coins." end
	if tiers.giant.durationMinutes < 0 or tiers.giant.durationMinutes > 10_080 or tiers.king.durationMinutes < 0 or tiers.king.durationMinutes > 10_080 then return false, "Tier duration must be between 0 and 10,080 minutes." end
	if tiers.skip.roseCount < 1 or tiers.skip.roseCount > 10_000 or tiers.skip.cooldown < 0 or tiers.skip.cooldown > 3600 then return false, "Skip count or cooldown is outside supported limits." end
	for _, row in ipairs({ "normal", "giant", "king" }) do
		if spawn.maxPerRow[row] < 1 or spawn.maxPerRow[row] > 100 then return false, row .. " row capacity must be between 1 and 100." end
	end
	if nextConfig.relay.transport ~= "polling" and nextConfig.relay.transport ~= "webstream" then return false, "Relay transport must be polling or webstream." end
	if not string.match(nextConfig.relay.baseUrl, "^https://") then return false, "Relay URL must use HTTPS." end
	if nextConfig.camera.mode ~= "autoDirector" and nextConfig.camera.mode ~= "followLatest" and nextConfig.camera.mode ~= "followTierUp" and nextConfig.camera.mode ~= "wideStage" and nextConfig.camera.mode ~= "manual" then return false, "Unknown camera mode." end
	if nextConfig.camera.fov < 35 or nextConfig.camera.fov > 100 or nextConfig.camera.focusSeconds < 1 or nextConfig.camera.focusSeconds > 60 or nextConfig.camera.transitionSeconds < 0.05 or nextConfig.camera.transitionSeconds > 10 then return false, "Camera settings are outside supported limits." end
	if nextConfig.profile.priceCacheHours < 1 or nextConfig.profile.priceCacheHours > 720 or nextConfig.profile.maxAssetsPerPass < 1 or nextConfig.profile.maxAssetsPerPass > 250 then return false, "Profile cache or asset limit is outside supported limits." end
	if nextConfig.vfx.quality ~= "low" and nextConfig.vfx.quality ~= "medium" and nextConfig.vfx.quality ~= "high" then return false, "VFX quality must be low, medium, or high." end
	if type(nextConfig.vfx.auras) ~= "table" or #nextConfig.vfx.auras > 30 then return false, "Aura pool must contain at most 30 entries." end
	if type(nextConfig.moderation.blockedUsers) ~= "table" or #nextConfig.moderation.blockedUsers > 1000 or type(nextConfig.moderation.mutedUsers) ~= "table" or #nextConfig.moderation.mutedUsers > 1000 then return false, "Moderation lists are too large." end
	local saved, errorMessage = pcall(function() STORE:UpdateAsync("config", function() return nextConfig end) end)
	if not saved then return false, tostring(errorMessage) end
	current = nextConfig
	return true, nil
end

function ConfigService.Reset()
	local defaults = deepClone(DEFAULTS)
	local previousAdmins = current.admin
	defaults.admin = deepClone(previousAdmins)
	local ok, err = pcall(function() STORE:UpdateAsync("config", function() return defaults end) end)
	if not ok then return false, tostring(err) end
	current = defaults
	return true, nil
end

function ConfigService.Defaults(): {[string]: any}
	return deepClone(DEFAULTS)
end

return ConfigService
