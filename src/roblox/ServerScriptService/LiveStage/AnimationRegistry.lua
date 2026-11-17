--!strict
local DataStoreService = game:GetService("DataStoreService")
local Registry = {}
local STORE = DataStoreService:GetDataStore("LiveStageAnimations_v1")
local entries: {any} = {}
local cache: {[string]: Animation} = {}
local priorities = {
	Core = Enum.AnimationPriority.Core,
	Idle = Enum.AnimationPriority.Idle,
	Movement = Enum.AnimationPriority.Movement,
	Action = Enum.AnimationPriority.Action,
	Action2 = Enum.AnimationPriority.Action2,
	Action3 = Enum.AnimationPriority.Action3,
	Action4 = Enum.AnimationPriority.Action4,
}

local DEFAULTS = {
	{ id = "507771019", name = "wave", type = "emote", rig = "R15", looped = false, priority = "Action", speed = 1, weight = 1, enabled = true, tags = { "greet" } },
	{ id = "507777268", name = "dance", type = "dance", rig = "R15", looped = true, priority = "Action", speed = 1, weight = 1, enabled = true, tags = { "dance" } },
}

local function cleanEntry(entry: any): (any?, string?)
	if type(entry) ~= "table" or type(entry.name) ~= "string" or #entry.name < 1 or #entry.name > 40 then return nil, "Name must be 1–40 characters." end
	local id = tostring(entry.id or ""):gsub("rbxassetid://", "")
	if not id:match("^%d+$") then return nil, "Animation ID must be numeric." end
	local tags = {}
	if type(entry.tags) == "table" then
		for _, tag in ipairs(entry.tags) do
			if type(tag) == "string" and #tag > 0 and #tag <= 32 and #tags < 16 then table.insert(tags, tag) end
		end
	end
	local priority = if priorities[tostring(entry.priority)] then tostring(entry.priority) else "Action"
	return {
		id = id,
		name = string.lower(entry.name),
		type = entry.type == "emote" and "emote" or "dance",
		rig = entry.rig == "R6" and "R6" or "R15",
		looped = entry.looped ~= false,
		priority = priority,
		speed = math.clamp(tonumber(entry.speed) or 1, 0.25, 2),
		weight = math.clamp(tonumber(entry.weight) or 1, 0, 100),
		enabled = entry.enabled ~= false,
		tags = tags,
	}, nil
end

function Registry.Load()
	local ok, result = pcall(function() return STORE:GetAsync("registry") end)
	if ok and type(result) == "table" and result.version == 1 and type(result.items) == "table" then
		entries = result.items
	else
		entries = table.clone(DEFAULTS)
		if not ok then warn("[LiveStage] Animation registry unavailable; loaded defaults") end
	end
end

function Registry.List(): {any} return table.clone(entries) end

function Registry.Replace(nextItems: any): (boolean, string?)
	if type(nextItems) ~= "table" or #nextItems > 80 then return false, "Animation list must contain at most 80 entries." end
	local previous, cleaned, names = entries, {}, {}
	for _, entry in ipairs(nextItems) do
		local item, reason = cleanEntry(entry)
		if not item then return false, reason end
		if names[item.name] then return false, "Animation names must be unique." end
		names[item.name] = true
		table.insert(cleaned, item)
	end
	entries = cleaned
	local ok, err = pcall(function() STORE:UpdateAsync("registry", function() return { version = 1, items = entries } end) end)
	if not ok then entries = previous; return false, tostring(err) end
	table.clear(cache)
	return true, nil
end

function Registry.Add(entry: any): (boolean, string?)
	local clean, reason = cleanEntry(entry)
	if not clean then return false, reason end
	for _, existing in ipairs(entries) do if existing.name == clean.name then return false, "That animation name already exists." end end
	table.insert(entries, clean)
	local ok, err = pcall(function() STORE:UpdateAsync("registry", function() return { version = 1, items = entries } end) end)
	if not ok then table.remove(entries); return false, tostring(err) end
	cache[clean.id] = nil
	return true, nil
end

function Registry.Remove(name: string): (boolean, string?)
	for index, entry in ipairs(entries) do
		if string.lower(entry.name) == string.lower(name) then
			table.remove(entries, index)
			local ok, err = pcall(function() STORE:UpdateAsync("registry", function() return { version = 1, items = entries } end) end)
			if not ok then table.insert(entries, index, entry); return false, tostring(err) end
			cache[tostring(entry.id)] = nil
			return true, nil
		end
	end
	return false, "Animation not found."
end

function Registry.Play(model: Model, requested: string?): boolean
	local candidates, totalWeight = {}, 0
	for _, entry in ipairs(entries) do
		local matches = if requested and requested ~= "" then string.lower(entry.name) == string.lower(requested) else entry.type == "dance"
		local weight = math.max(0, tonumber(entry.weight) or 0)
		if entry.enabled ~= false and matches and weight > 0 then totalWeight += weight; table.insert(candidates, entry) end
	end
	if #candidates == 0 or totalWeight <= 0 then return false end
	local roll, selected = math.random() * totalWeight, candidates[#candidates]
	for _, entry in ipairs(candidates) do roll -= entry.weight; if roll <= 0 then selected = entry; break end end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local id = tostring(selected.id)
	local animation = cache[id]
	if not animation then animation = Instance.new("Animation"); animation.AnimationId = "rbxassetid://" .. id; cache[id] = animation end
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok then warn("[LiveStage] Animation failed to load", selected.name, track); return false end
	track.Looped = selected.looped
	track.Priority = priorities[selected.priority] or Enum.AnimationPriority.Action
	track:Play(0.2, 1, selected.speed)
	return true
end

return Registry
