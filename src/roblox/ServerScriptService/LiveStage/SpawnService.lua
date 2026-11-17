--!strict
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local UserService = game:GetService("UserService")
local SpawnService = {}
local Config: any
local Lane: any
local Aura: any
local Animations: any
local Remotes: any
local Tier: any
local Camera: any
local Profile = require(script.Parent.ProfileService)
local folder: Folder
local characters: {[string]: Model} = {}
local linkedRobloxIds: {[string]: number} = {}
local nameCache: {[string]: number} = {}
local nameFailureCache: {[string]: number} = {}
local lastUsernameLookup = 0
local spawnTimes: {[string]: number} = {}
local priceCache: {[number]: number} = {}
local priceExpiry: {[number]: number} = {}
local appearanceCache: {[number]: { total: number, expires: number }} = {}
local thumbnailCache: {[number]: string} = {}
local robloxInfoCache: {[number]: { displayName: string, username: string }} = {}
local busy: {[string]: boolean} = {}
local pendingSpawns = 0
local resetGeneration = 0
local lastGlobalSpawn = 0
local enqueueProfile: (Model, number) -> () = function() end

local function filtered(text: string, linkedUserId: number?): string?
	local clean = string.sub(text, 1, Config.Get("spawn.maxCommentLength"))
	if clean == "" then return nil end
	local sourceUserId = linkedUserId or if game.CreatorType == Enum.CreatorType.User then game.CreatorId else 1
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(clean, sourceUserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then return result end
	return nil
end

local function resolveUsername(username: string, maxAttempts: number?): number?
	local normalized = string.gsub(username, "^@", "")
	if #normalized < 3 or #normalized > 20 or not string.match(normalized, "^[%w_]+$") then return nil end
	local cacheKey = string.lower(normalized)
	if nameCache[cacheKey] then return nameCache[cacheKey] end
	if (nameFailureCache[cacheKey] or 0) > os.clock() then return nil end
	for attempt = 1, math.clamp(maxAttempts or 3, 1, 3) do
		local ok, value = pcall(function() return Players:GetUserIdFromNameAsync(normalized) end)
		if ok and type(value) == "number" then nameCache[cacheKey] = value; return value end
		if attempt < (maxAttempts or 3) then task.wait(attempt) end
	end
	nameFailureCache[cacheKey] = os.clock() + 60
	return nil
end

local function makeProfile(model: Model, tiktokName: string, linkedId: number?, state: any)
	if not Config.Get("profile.enabled") then return end
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LiveStageProfile"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(250 * model:GetScale(), 86 * model:GetScale())
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.5 * model:GetScale(), 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = Config.Get("profile.maxDistance")
	billboard.Parent = model
	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(18, 21, 33)
	card.BackgroundTransparency = 0.1
	card.Parent = billboard
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = card
	local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(93, 107, 145); stroke.Transparency = 0.25; stroke.Parent = card
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"; portrait.BackgroundTransparency = 1; portrait.Position = UDim2.fromOffset(8, 8); portrait.Size = UDim2.fromOffset(54, 54); portrait.Parent = card
	local portraitCorner = Instance.new("UICorner"); portraitCorner.CornerRadius = UDim.new(1, 0); portraitCorner.Parent = portrait
	local name = Instance.new("TextLabel")
	name.Name = "ViewerName"; name.BackgroundTransparency = 1; name.Position = UDim2.fromOffset(70, 7); name.Size = UDim2.new(1, -78, 0, 23); name.Font = Enum.Font.GothamBold; name.TextColor3 = Color3.new(1, 1, 1); name.TextSize = 15; name.TextXAlignment = Enum.TextXAlignment.Left; name.TextTruncate = Enum.TextTruncate.AtEnd; name.Parent = card
	local handle = Instance.new("TextLabel")
	handle.Name = "TikTokHandle"; handle.BackgroundTransparency = 1; handle.Position = UDim2.fromOffset(70, 29); handle.Size = UDim2.new(1, -78, 0, 19); handle.Font = Enum.Font.Gotham; handle.TextColor3 = Color3.fromRGB(177, 187, 208); handle.TextSize = 12; handle.TextXAlignment = Enum.TextXAlignment.Left; handle.TextTruncate = Enum.TextTruncate.AtEnd; handle.Parent = card
	local badge = Instance.new("TextLabel")
	badge.Name = "TierBadge"; badge.BackgroundTransparency = 1; badge.Position = UDim2.fromOffset(70, 51); badge.Size = UDim2.new(1, -78, 0, 20); badge.Font = Enum.Font.GothamBold; badge.TextSize = 12; badge.TextXAlignment = Enum.TextXAlignment.Left; badge.Parent = card
	name.Text = if linkedId then "Roblox player" else (filtered(tostring(model:GetAttribute("TikTokNickname") or tiktokName), linkedId) or "Viewer")
	handle.Text = "@" .. (filtered(tiktokName, linkedId) or "viewer")
	local title = if state.fan then Config.Get("tiers.fans.title") .. "  •  " else ""
	badge.Text = title .. string.upper(state.tier) .. "  •  calculating..."
	badge.TextColor3 = if state.tier == "king" then Color3.fromRGB(255, 200, 90) elseif state.tier == "giant" then Color3.fromRGB(113, 211, 255) else Color3.fromRGB(198, 177, 255)
	if linkedId then
		enqueueProfile(model, linkedId)
	end
end

function SpawnService.GetAppearanceCost(userId: number): number
	local cached = appearanceCache[userId]
	if cached and cached.expires > os.time() then return cached.total end
	local appearanceOk: boolean = false
	local appearance: any = nil
	for attempt = 1, 3 do
		appearanceOk, appearance = pcall(function() return Players:GetCharacterAppearanceInfoAsync(userId) end)
		if appearanceOk then break end
		task.wait(attempt)
	end
	if not appearanceOk or type(appearance) ~= "table" then return 0 end
	local assetIds: {number} = {}
	for _, asset in ipairs(appearance.assets or {}) do
		local id = tonumber(asset.id)
		if id and id > 0 then table.insert(assetIds, id) end
	end
	local total = 0
	for index, assetId in ipairs(assetIds) do
		if index > Config.Get("profile.maxAssetsPerPass") then break end
		if priceCache[assetId] == nil or (priceExpiry[assetId] or 0) < os.time() then
			local ok: boolean = false
			local product: any = nil
			for attempt = 1, 3 do
				ok, product = pcall(function() return MarketplaceService:GetProductInfoAsync(assetId, Enum.InfoType.Asset) end)
				if ok then break end
				task.wait(attempt)
			end
			if ok and type(product) == "table" and product.IsForSale and tonumber(product.PriceInRobux) then priceCache[assetId] = product.PriceInRobux :: number else priceCache[assetId] = 0 end
			priceExpiry[assetId] = os.time() + Config.Get("profile.priceCacheHours") * 3600
			task.wait(0.1)
		end
		total += priceCache[assetId] or 0
	end
	appearanceCache[userId] = { total = total, expires = os.time() + Config.Get("profile.priceCacheHours") * 3600 }
	return total
end

local profileQueue: {{ model: Model, userId: number }} = {}
local profileWorker = false
enqueueProfile = function(model: Model, userId: number)
	table.insert(profileQueue, { model = model, userId = userId })
	if profileWorker then return end
	profileWorker = true
	task.spawn(function()
		while #profileQueue > 0 do
			local request = table.remove(profileQueue, 1)
			if request.model.Parent then
				if not thumbnailCache[request.userId] then
					local ok, image = pcall(function() return Players:GetUserThumbnailAsync(request.userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150) end)
					if ok then thumbnailCache[request.userId] = image end
				end
				local portrait = request.model:FindFirstChild("Portrait", true)
				if portrait and portrait:IsA("ImageLabel") then portrait.Image = thumbnailCache[request.userId] or "" end
				local identity = robloxInfoCache[request.userId]
				if not identity then
					local okInfo, info = pcall(function() return UserService:GetUserInfosByUserIdsAsync({ request.userId }) end)
					if okInfo and type(info) == "table" and info[1] then identity = { displayName = tostring(info[1].DisplayName), username = tostring(info[1].Username) } end
					if not identity then
						local okName, accountName = pcall(function() return Players:GetNameFromUserIdAsync(request.userId) end)
						if okName then identity = { displayName = accountName, username = accountName } end
					end
					if identity then robloxInfoCache[request.userId] = identity end
				end
				local name = request.model:FindFirstChild("ViewerName", true)
				if identity and name and name:IsA("TextLabel") then name.Text = identity.displayName .. "  @" .. identity.username end
				local total = SpawnService.GetAppearanceCost(request.userId)
				if request.model.Parent then Profile.SetWornCost(request.model, total) end
			end
			task.wait(0.15)
		end
		profileWorker = false
	end)
end

function SpawnService.Init(config: any, lane: any, aura: any, animations: any, remotes: any, tier: any)
	Config, Lane, Aura, Animations, Remotes, Tier = config, lane, aura, animations, remotes, tier
	folder = workspace:FindFirstChild("LiveStageCharacters") :: Folder?
	if not folder then folder = Instance.new("Folder"); folder.Name = "LiveStageCharacters"; folder.Parent = workspace end
end

function SpawnService.Get(key: string): Model? return characters[key] end
function SpawnService.Count(): number local n = 0; for _ in pairs(characters) do n += 1 end; return n end

function SpawnService.Announce(kind: string, model: Model?, detail: string?)
	if Camera and model then Camera.Focus(kind, model) end
	if Remotes then Remotes.StageUpdate:FireAllClients("action", kind, model, detail or "") end
end
function SpawnService.SetCamera(camera: any) Camera = camera end

function SpawnService.ApplyTier(model: Model, tier: string)
	local scale = if tier == "king" then Config.Get("tiers.king.scale") elseif tier == "giant" then Config.Get("tiers.giant.scale") else 1
	local target = math.clamp(scale, 1, 12)
	local ok, err = pcall(function() model:ScaleTo(target) end)
	if not ok then warn("[LiveStage] Could not scale character", model.Name, tier, err) end
	Aura.Apply(model, tier)
	if tier ~= "normal" then Aura.Burst(model, if tier == "king" then Color3.fromRGB(255, 188, 68) else Color3.fromRGB(86, 206, 255)) end
end

local function createModel(key: string, tiktokUsername: string, nickname: string, robloxId: number?, state: any): Model?
	local description: HumanoidDescription
	local avatarLoaded = false
	if robloxId then
		local ok, result = pcall(function() return Players:GetHumanoidDescriptionFromUserIdAsync(robloxId) end)
		if ok and typeof(result) == "Instance" and result:IsA("HumanoidDescription") then
			description = result
			avatarLoaded = true
		else
			description = Instance.new("HumanoidDescription")
			warn("[LiveStage] Roblox avatar description failed; using a default avatar", robloxId, result)
		end
	else
		description = Instance.new("HumanoidDescription")
	end
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15) end)
	if not ok or not model then
		warn("[LiveStage] Avatar rig creation failed; retrying with a default rig", robloxId or 0, model)
		local fallback = Instance.new("HumanoidDescription")
		ok, model = pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(fallback, Enum.HumanoidRigType.R15) end)
	end
	if not ok or not model then warn("[LiveStage] Could not create fallback R15 rig", model); return nil end
	model.Name = "Viewer_" .. key:gsub("[^%w]", ""):sub(1, 14)
	model:SetAttribute("TikTokUserId", key)
	model:SetAttribute("TikTokUsername", tiktokUsername)
	model:SetAttribute("TikTokNickname", nickname)
	model:SetAttribute("RobloxUserId", robloxId or 0)
	model:SetAttribute("AvatarLoaded", avatarLoaded)
	model:SetAttribute("Tier", state.tier)
	model:SetAttribute("CreatedAt", os.time())
	model:SetAttribute("IsFan", state.fan)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = filtered(nickname, robloxId) or filtered(tiktokUsername, robloxId) or "Viewer"
		humanoid.BreakJointsOnDeath = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	model.Parent = folder
	local initialScale = if state.tier == "king" then Config.Get("tiers.king.scale") elseif state.tier == "giant" then Config.Get("tiers.giant.scale") else 1
	local scaleOk, scaleError = pcall(function() model:ScaleTo(math.clamp(initialScale, 1, 12)) end)
	if not scaleOk then warn("[LiveStage] Initial avatar scale failed; keeping character spawned", key, state.tier, scaleError) end
	model:PivotTo(CFrame.new(0, 1 + 3 * initialScale, - (if state.tier == "king" then Config.Get("lanes.kingDepth") elseif state.tier == "giant" then Config.Get("lanes.giantDepth") else Config.Get("lanes.normalDepth"))) * CFrame.Angles(0, math.pi, 0))
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then root:SetNetworkOwner(nil) end
	makeProfile(model, tiktokUsername, robloxId, state)
	Profile.Refresh(model)
	Aura.Apply(model, state.tier)
	Aura.Burst(model)
	return model
end

function SpawnService.Ensure(event: {[string]: any}, forceSpawn: boolean?): Model?
	local key = tostring(event.tiktokUserId or event.tiktokUsername or "")
	if key == "" or busy[key] then return characters[key] end
	if table.find(Config.Get("moderation.blockedUsers"), key) then return nil end
	if characters[key] and characters[key].Parent then return characters[key] end
	if not forceSpawn and (os.clock() - (spawnTimes[key] or 0) < Config.Get("spawn.userCooldown") or os.clock() - lastGlobalSpawn < Config.Get("spawn.globalCooldown")) then return nil end
	local requestedTier = Tier.Tier(key)
	if not Lane.CanRegister(requestedTier) then
		if Config.Get("spawn.resetMode") == "resetAll" then SpawnService.ResetAll()
		else
			local row = if requestedTier == "king" then "king" elseif requestedTier == "giant" then "giant" else "normal"
			local oldest = Lane.Oldest(row)
			if oldest then SpawnService.Remove(oldest) end
		end
	end
	if SpawnService.Count() + pendingSpawns >= Config.Get("spawn.maxTotal") then
		if Config.Get("spawn.resetMode") == "resetAll" then SpawnService.ResetAll() else SpawnService.RemoveOldest() end
	end
	busy[key] = true
	spawnTimes[key] = os.clock(); lastGlobalSpawn = os.clock()
	pendingSpawns += 1
	local generation = resetGeneration
	local robloxId = linkedRobloxIds[key]
	local state = Tier.Get(key)
	local tiktokUsername = tostring(event.tiktokUsername or "")
	local nickname = tostring(event.nickname or tiktokUsername)
	if tiktokUsername == "" then tiktokUsername = tostring(event.tiktokUserId or "Viewer") end
	if nickname == "" then nickname = tiktokUsername end
	local createOk, model = pcall(createModel, key, tiktokUsername, nickname, robloxId, state)
	pendingSpawns = math.max(0, pendingSpawns - 1)
	if not createOk then warn("[LiveStage] Character creation failed", model); model = nil end
	if generation ~= resetGeneration then if model then model:Destroy() end; busy[key] = nil; return nil end
	if model then characters[key] = model; Lane.Register(key, model, state.tier); SpawnService.Announce("spawn", model, state.tier) end
	busy[key] = nil
	return model
end

function SpawnService.ManualSpawn(username: string): {[string]: any}
	local normalized = string.gsub(string.sub(username, 1, 20), "^@", "")
	if #normalized < 3 or not string.match(normalized, "^[%w_]+$") then return { ok = false, error = "Enter a Roblox username (3–20 letters, numbers, or underscores)." } end
	local robloxId = resolveUsername(normalized)
	if not robloxId then return { ok = false, error = "Roblox username was not found. Check the spelling and try again." } end
	local key = "admin-roblox-" .. tostring(robloxId)
	linkedRobloxIds[key] = robloxId
	nameCache[string.lower(normalized)] = robloxId
	local alreadyOnStage = characters[key] ~= nil and characters[key].Parent ~= nil
	local model = SpawnService.Ensure({ tiktokUserId = key, tiktokUsername = normalized, nickname = normalized }, true)
	if not model then return { ok = false, error = "Roblox found the user, but the avatar could not load. Try again in a moment." } end
	return { ok = true, username = normalized, robloxUserId = robloxId, tier = Tier.Tier(key), scale = model:GetScale(), alreadyOnStage = alreadyOnStage }
end

function SpawnService.React(model: Model, comment: string, key: string)
	local safe = filtered(comment, linkedRobloxIds[key])
	if safe and #safe > 0 then
		local head = model:FindFirstChild("Head") :: BasePart?
		if head then
			local gui = Instance.new("BillboardGui"); gui.Name = "CommentBubble"; gui.Adornee = head; gui.Size = UDim2.fromOffset(220, 52); gui.StudsOffset = Vector3.new(0, 3.8 * model:GetScale(), 0); gui.AlwaysOnTop = true; gui.Parent = model
			local label = Instance.new("TextLabel"); label.Size = UDim2.fromScale(1, 1); label.BackgroundColor3 = Color3.fromRGB(28, 32, 45); label.BackgroundTransparency = 0.08; label.TextColor3 = Color3.new(1, 1, 1); label.TextWrapped = true; label.TextScaled = true; label.Font = Enum.Font.GothamMedium; label.Text = safe; label.Parent = gui
			local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = label
			task.delay(4, function() if gui.Parent then gui:Destroy() end end)
		end
	end
	Animations.Play(model, nil)
	SpawnService.Announce("comment", model, "")
end

function SpawnService.Handle(event: {[string]: any})
	if event.type ~= "chat" then return end
	local key = tostring(event.tiktokUserId or event.tiktokUsername or "")
	if table.find(Config.Get("moderation.mutedUsers"), key) then return end
	local comment = tostring(event.comment or "")
	local existingModel = characters[key]
	if existingModel and existingModel.Parent then
		local tiktokUsername = tostring(event.tiktokUsername or "")
		local nickname = tostring(event.nickname or "")
		if tiktokUsername ~= "" and tiktokUsername ~= tostring(existingModel:GetAttribute("TikTokUsername") or "") then
			existingModel:SetAttribute("TikTokUsername", tiktokUsername)
			local handle = existingModel:FindFirstChild("TikTokHandle", true)
			if handle and handle:IsA("TextLabel") then handle.Text = "@" .. (filtered(tiktokUsername, linkedRobloxIds[key]) or "viewer") end
		end
		if nickname ~= "" and nickname ~= tostring(existingModel:GetAttribute("TikTokNickname") or "") then
			existingModel:SetAttribute("TikTokNickname", nickname)
			local humanoid = existingModel:FindFirstChildOfClass("Humanoid")
			if humanoid then humanoid.DisplayName = filtered(nickname, linkedRobloxIds[key]) or filtered(tostring(existingModel:GetAttribute("TikTokUsername") or "Viewer"), linkedRobloxIds[key]) or "Viewer" end
			local name = existingModel:FindFirstChild("ViewerName", true)
			if name and name:IsA("TextLabel") and not linkedRobloxIds[key] then name.Text = filtered(nickname, nil) or "Viewer" end
		end
	end
	local command, argument = string.match(comment, "^%s*!([%w]+)%s*(.-)%s*$")
	local forceLinkedSpawn = false
	if not command then
		local plainUsername = string.match(comment, "^%s*@?([%w_]+)%s*$")
		if plainUsername and os.clock() - lastUsernameLookup >= 0.5 then
			lastUsernameLookup = os.clock()
			local robloxId = resolveUsername(plainUsername, 1)
			if robloxId then
				local previousId = linkedRobloxIds[key]
				linkedRobloxIds[key] = robloxId
				if existingModel and previousId ~= robloxId then
					Lane.Remove(key); Aura.Remove(existingModel); existingModel:Destroy(); characters[key] = nil
					existingModel = nil; forceLinkedSpawn = true
				end
			end
		end
	end
	if command == "join" or command == "avatar" then
		local id = resolveUsername(argument)
		if id then linkedRobloxIds[key] = id; nameCache[string.lower(argument)] = id end
		local existing = characters[key]
		if existing then Lane.Remove(key); Aura.Remove(existing); existing:Destroy(); characters[key] = nil end
		SpawnService.Ensure(event, true)
		return
	end
	local model = characters[key] or SpawnService.Ensure(event, forceLinkedSpawn)
	if not model then return end
	if command == "dance" or command == "emote" then Animations.Play(model, argument ~= "" and argument or nil); SpawnService.Announce("dance", model, ""); return end
	SpawnService.React(model, comment, key)
end

function SpawnService.RemoveOldest()
	local chosenKey, oldest = nil, math.huge
	for key, model in pairs(characters) do
		local created = model:GetAttribute("CreatedAt") or 0
		if created < oldest then oldest = created; chosenKey = key end
	end
	if chosenKey then SpawnService.Remove(chosenKey) end
end

function SpawnService.Remove(key: string)
	local model = characters[key]
	if not model then return end
	Lane.Remove(key); Aura.Remove(model); characters[key] = nil; model:Destroy()
end

function SpawnService.ResetAll()
	resetGeneration += 1
	if Remotes then Remotes.StageNotice:FireAllClients("STAGE RESET") end
	for key, model in pairs(characters) do
		local highlight = Instance.new("Highlight"); highlight.FillColor = Color3.new(1, 1, 1); highlight.OutlineTransparency = 1; highlight.Parent = model
		for _, descendant in ipairs(model:GetDescendants()) do if descendant:IsA("BasePart") then descendant.CanCollide = false end end
		task.delay(0.35, function() if model.Parent then model:Destroy() end end)
		characters[key] = nil
	end
	Lane.Clear(); Aura.Clear(); Tier.Clear(true)
end

function SpawnService.GetAdminSummary(): {[string]: any}
	local list = {}
	for key, model in pairs(characters) do table.insert(list, { id = key, name = model.Name, tier = Tier.Tier(key) }) end
	return { active = #list, characters = list }
end

function SpawnService.GetActiveModels(): {Model}
	local result = {}
	for _, model in pairs(characters) do if model.Parent then table.insert(result, model) end end
	return result
end

function SpawnService.RefreshConfig()
	for key, model in pairs(characters) do
		if model.Parent then
			local tier = Tier.Tier(key)
			SpawnService.ApplyTier(model, tier)
			local billboard = model:FindFirstChild("LiveStageProfile", true)
			if Config.Get("profile.enabled") then
				if not billboard then makeProfile(model, tostring(model:GetAttribute("TikTokUsername") or "Viewer"), linkedRobloxIds[key], Tier.Get(key)) end
				billboard = model:FindFirstChild("LiveStageProfile", true)
				if billboard and billboard:IsA("BillboardGui") then
					billboard.MaxDistance = Config.Get("profile.maxDistance")
					billboard.Size = UDim2.fromOffset(250 * model:GetScale(), 86 * model:GetScale())
				end
				Profile.Refresh(model)
			elseif billboard then
				billboard:Destroy()
			end
		end
	end
	Lane.Reflow()
end

function SpawnService.TestSpawn()
	SpawnService.Ensure({ tiktokUserId = "admin-test-" .. HttpService:GenerateGUID(false), tiktokUsername = "test_viewer", nickname = "Stage Test" })
end

function SpawnService.TestScenario(scenario: string, username: string?): {[string]: any}
	local suffix = string.sub(HttpService:GenerateGUID(false), 1, 8)
	local key = "admin-test-" .. scenario .. "-" .. suffix
	local label = username or ("stage_" .. suffix)
	local chatEvent = { type = "chat", tiktokUserId = key, tiktokUsername = "stage_test_" .. suffix, nickname = label, comment = label }
	local linkedTestId = resolveUsername(label, 3)
	if linkedTestId then linkedRobloxIds[key] = linkedTestId end
	if scenario == "comment" then
		SpawnService.Handle(chatEvent)
		local model = characters[key]
		local robloxUserId = model and model:GetAttribute("RobloxUserId") or 0
		return { ok = model ~= nil, avatarLinked = robloxUserId > 0, tier = model and model:GetAttribute("Tier") or "missing", robloxUserId = robloxUserId, viewerName = label }
	end
	if scenario == "fan" then
		local model = SpawnService.Ensure(chatEvent, true)
		if not model then return { ok = false, error = "test_spawn_failed" } end
		Tier.Handle({ type = "chat", tiktokUserId = key, tiktokUsername = chatEvent.tiktokUsername, nickname = label, isFan = true })
		local badge = model:FindFirstChild("TierBadge", true) :: TextLabel?
		local title = if badge then badge.Text else ""
		return { ok = model:GetAttribute("IsFan") == true and string.find(title, tostring(Config.Get("tiers.fans.title")), 1, true) ~= nil, title = title, avatarLinked = (model:GetAttribute("RobloxUserId") or 0) > 0 }
	end
	if scenario == "giant" or scenario == "king" then
		local model = SpawnService.Ensure(chatEvent, true)
		if not model then return { ok = false, error = "test_spawn_failed" } end
		local rules = Config.Get("tiers")
		local gift
		if scenario == "giant" then
			local roseCount = math.ceil(rules.giant.requiredCoins / math.max(tonumber(rules.rose.coinValue) or 1, 1))
			gift = { type = "gift", tiktokUserId = key, tiktokUsername = chatEvent.tiktokUsername, nickname = label, giftName = rules.rose.giftName, giftId = rules.rose.giftId, diamondCount = 1, repeatCount = roseCount, repeatEnd = true }
		else
			local cost = math.max(tonumber(rules.donut.coinValue) or 0, tonumber(rules.king.requiredCoins) or 1)
			gift = { type = "gift", tiktokUserId = key, tiktokUsername = chatEvent.tiktokUsername, nickname = label, giftName = rules.donut.giftName, giftId = rules.donut.giftId, diamondCount = cost, repeatCount = 1, repeatEnd = true }
		end
		Tier.Handle(gift)
		return { ok = Tier.Tier(key) == scenario, avatarLinked = (model:GetAttribute("RobloxUserId") or 0) > 0, avatarLoaded = model:GetAttribute("AvatarLoaded") == true, tier = Tier.Tier(key), scale = model:GetScale(), viewerName = label }
	end
	if scenario == "skip" then
		local first = SpawnService.Ensure({ type = "chat", tiktokUserId = key .. "-a", tiktokUsername = "stage_a", nickname = "Lane A", comment = "Lane A" }, true)
		task.wait(0.2)
		local target = SpawnService.Ensure({ type = "chat", tiktokUserId = key .. "-b", tiktokUsername = "stage_b", nickname = "Lane B", comment = "Lane B" }, true)
		if not first or not target then return { ok = false, error = "test_spawn_failed" } end
		task.wait(0.6)
		local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		local firstRoot = first:FindFirstChild("HumanoidRootPart") :: BasePart?
		local beforeX = if targetRoot then targetRoot.Position.X else 999
		local rules = Config.Get("tiers")
		Tier.Handle({ type = "gift", tiktokUserId = key .. "-b", tiktokUsername = "stage_b", nickname = "Lane B", giftName = rules.rose.giftName, giftId = rules.rose.giftId, diamondCount = 1, repeatCount = rules.skip.roseCount, repeatEnd = true })
		task.wait(0.7)
		local afterX = if targetRoot and targetRoot.Parent then targetRoot.Position.X else 999
		local firstAfterX = if firstRoot and firstRoot.Parent then firstRoot.Position.X else 999
		return { ok = math.abs(beforeX) > 1 and math.abs(afterX) < 1 and math.abs(firstAfterX) > 1, tier = Tier.Tier(key .. "-b"), beforeX = beforeX, afterX = afterX, firstAfterX = firstAfterX }
	end
	return { ok = false, error = "unknown_test_scenario" }
end

function SpawnService.ClearTestCharacters()
	for key in pairs(characters) do if string.sub(key, 1, 11) == "admin-test-" then SpawnService.Remove(key) end end
end

return SpawnService
