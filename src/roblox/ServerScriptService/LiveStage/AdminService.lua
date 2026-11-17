--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local AdminService = {}
local Config: any
local Spawn: any
local Registry: any
local Camera: any
local Remotes: any
local relayStatus = "starting"
local viewerCount = 0
local recentEvents: {any} = {}

function AdminService.Init(config: any, spawn: any, registry: any, camera: any, remotes: any)
	Config, Spawn, Registry, Camera, Remotes = config, spawn, registry, camera, remotes
	Remotes.AdminRequest.OnServerInvoke = function(player: Player, request: any)
		return AdminService.Handle(player, request)
	end
end

function AdminService.IsAdmin(player: Player): boolean
	local admin = Config.Get("admin")
	if table.find(admin.userIds, player.UserId) then return true end
	if admin.groupId > 0 then
		local ok, rank = pcall(function() return player:GetRankInGroup(admin.groupId) end)
		if ok and rank >= admin.minimumGroupRank then return true end
	end
	return false
end

function AdminService.SetRelayStatus(value: string)
	relayStatus = string.sub(value, 1, 180)
	Remotes.StageUpdate:FireAllClients("status", relayStatus)
end

function AdminService.SetViewerCount(value: number)
	viewerCount = math.clamp(math.floor(value), 0, 1_000_000)
	for _, player in ipairs(Players:GetPlayers()) do if AdminService.IsAdmin(player) then Remotes.StageUpdate:FireClient(player, "audience", viewerCount) end end
end

function AdminService.SetRecentEvents(value: {any}) recentEvents = value end

function AdminService.Handle(player: Player, request: any): {[string]: any}
	if not AdminService.IsAdmin(player) then return { ok = false, error = "not_authorized" } end
	if type(request) ~= "table" or type(request.action) ~= "string" then return { ok = false, error = "invalid_request" } end
	local action = request.action
	if action == "get" then
		return { ok = true, settings = Config.Get(), animations = Registry.List(), summary = Spawn.GetAdminSummary(), relayStatus = relayStatus, cameraMode = Camera.Current(), viewerCount = viewerCount, recentEvents = recentEvents }
	elseif action == "updateSettings" and type(request.json) == "string" then
		local ok, err = Config.UpdateFromJSON(request.json)
		return { ok = ok, error = err }
	elseif action == "resetDefaults" then
		local ok, err = Config.Reset()
		return { ok = ok, error = err }
	elseif action == "testSpawn" then
		Spawn.TestSpawn(); return { ok = true }
	elseif action == "testScenario" then
		return Spawn.TestScenario(tostring(request.scenario or ""), tostring(request.username or "mrafiumri"))
	elseif action == "spawnUser" then
		return Spawn.ManualSpawn(tostring(request.username or ""))
	elseif action == "clearTests" then
		Spawn.ClearTestCharacters(); return { ok = true }
	elseif action == "clearStage" or action == "resetStage" then
		Spawn.ResetAll(); return { ok = true }
	elseif action == "addAnimation" then
		local ok, err = Registry.Add(request.animation)
		return { ok = ok, error = err }
	elseif action == "removeAnimation" then
		local ok, err = Registry.Remove(tostring(request.name or ""))
		return { ok = ok, error = err }
	elseif action == "replaceAnimations" then
		local ok, items = pcall(function() return HttpService:JSONDecode(tostring(request.json or "")) end)
		if not ok then return { ok = false, error = "Invalid animation JSON." } end
		local replaced, err = Registry.Replace(items)
		return { ok = replaced, error = err }
	elseif action == "cameraMode" then
		local target = if typeof(request.target) == "Instance" and request.target:IsA("Model") then request.target else nil
		local ok, err = Camera.SetMode(tostring(request.mode or ""), target)
		return { ok = ok, error = err }
	elseif action == "moderate" then
		local userId = string.sub(tostring(request.userId or ""), 1, 80)
		if userId == "" then return { ok = false, error = "userId_required" } end
		local settings = Config.Get()
		local list = if request.blocked == false then settings.moderation.mutedUsers else settings.moderation.blockedUsers
		if not table.find(list, userId) then table.insert(list, userId) end
		local ok, err = Config.UpdateFromJSON(HttpService:JSONEncode(settings))
		if ok and Spawn.Get(userId) then Spawn.Remove(userId) end
		return { ok = ok, error = err }
	end
	return { ok = false, error = "unknown_action" }
end

return AdminService
