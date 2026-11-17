--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local function ensure(className: string, name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then return existing end
	if existing then existing:Destroy() end
	local object = Instance.new(className); object.Name = name; object.Parent = parent
	return object
end

local remotesFolder = ensure("Folder", "LiveStageRemotes", ReplicatedStorage) :: Folder
local remotes = {
	AdminRequest = ensure("RemoteFunction", "AdminRequest", remotesFolder) :: RemoteFunction,
	StageUpdate = ensure("RemoteEvent", "StageUpdate", remotesFolder) :: RemoteEvent,
	Camera = ensure("RemoteEvent", "Camera", remotesFolder) :: RemoteEvent,
	StageNotice = ensure("RemoteEvent", "StageNotice", remotesFolder) :: RemoteEvent,
}

local Config = require(script.Parent.ConfigService)
local Profile = require(script.Parent.ProfileService)
local EventBridge = require(script.Parent.EventBridge)
local Lane = require(script.Parent.LaneService)
local Tier = require(script.Parent.TierService)
local Registry = require(script.Parent.AnimationRegistry)
local Dance = require(script.Parent.DanceService)
local Aura = require(script.Parent.AuraService)
local Spawn = require(script.Parent.SpawnService)
local Camera = require(script.Parent.CameraService)
local Admin = require(script.Parent.AdminService)

Config.Load()
Profile.Init(Config)
Registry.Load()
Lane.Init(Config)
Aura.Init(Config)
Dance.Init(Registry)
Spawn.Init(Config, Lane, Aura, Dance, remotes, Tier)
Tier.Init(Config, Lane, Spawn)
Camera.Init(Config, remotes.Camera)
Camera.SetTargetProvider(Spawn.GetActiveModels)
Spawn.SetCamera(Camera)
Admin.Init(Config, Spawn, Registry, Camera, remotes)

local function createStage()
	local stage = workspace:FindFirstChild("LiveStageSet")
	if stage then
		local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
		if spawn then spawn.Position = Vector3.new(0, 2, 50); spawn.Anchored = true end
		workspace:SetAttribute("LiveStageCameraTarget", Vector3.new(0, 14, -60))
		return
	end
	local model = Instance.new("Model"); model.Name = "LiveStageSet"; model.Parent = workspace
	local function part(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material)
		local p = Instance.new("Part"); p.Name = name; p.Size = size; p.Position = position; p.Color = color; p.Material = material; p.Anchored = true; p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth; p.Parent = model; return p
	end
	part("PerformanceDeck", Vector3.new(180, 2, 82), Vector3.new(0, 0, -28), Color3.fromRGB(30, 36, 55), Enum.Material.Slate)
	part("AudienceLip", Vector3.new(180, 1, 3), Vector3.new(0, 1.5, -4), Color3.fromRGB(90, 204, 255), Enum.Material.Neon)
	part("Backdrop", Vector3.new(180, 70, 2), Vector3.new(0, 34, -68), Color3.fromRGB(20, 25, 41), Enum.Material.SmoothPlastic)
	part("TopTrim", Vector3.new(180, 1, 2), Vector3.new(0, 66, -67), Color3.fromRGB(177, 111, 255), Enum.Material.Neon)
	for _, x in ipairs({ -84, 84 }) do
		part("LightTower", Vector3.new(3, 42, 3), Vector3.new(x, 22, -28), Color3.fromRGB(53, 62, 88), Enum.Material.Metal)
		local lamp = part("StageLamp", Vector3.new(9, 2, 2), Vector3.new(x, 45, -28), Color3.fromRGB(255, 196, 92), Enum.Material.Neon)
		local light = Instance.new("PointLight"); light.Range = 42; light.Brightness = 2; light.Color = lamp.Color; light.Parent = lamp
	end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then spawn.Position = Vector3.new(0, 2, 18); spawn.Anchored = true end
	workspace:SetAttribute("LiveStageCameraTarget", Vector3.new(0, 14, -60))
end

createStage()

local recentEvents: {any} = {}
local viewerCount = 0
local function filterRelayText(text: string): string
	local sourceId = if game.CreatorType == Enum.CreatorType.User then game.CreatorId else 1
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(string.sub(text, 1, 180), sourceId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return if ok and type(result) == "string" then result else "[text hidden]"
end
local function pushLog(event: any)
	local entry = { type = event.type, user = filterRelayText(tostring(event.tiktokUsername or "viewer")), comment = filterRelayText(tostring(event.comment or event.giftName or "")), timestamp = event.timestamp }
	table.insert(recentEvents, 1, entry)
	while #recentEvents > 20 do table.remove(recentEvents) end
	Admin.SetRecentEvents(recentEvents)
	for _, player in ipairs(Players:GetPlayers()) do if Admin.IsAdmin(player) then remotes.StageUpdate:FireClient(player, "event", entry) end end
end

EventBridge.Start(Config, function(event: any)
	Tier.Handle(event)
	if event.type == "roomUser" then
		viewerCount = tonumber(event.viewerCount) or 0
		Admin.SetViewerCount(viewerCount)
	elseif event.type == "gift" then
		task.spawn(function() Spawn.Ensure(event) end)
	elseif event.type == "chat" then
		task.spawn(function() Spawn.Handle(event) end)
	end
	if event.type ~= "status" and event.type ~= "roomUser" then task.spawn(function() pushLog(event) end) end
end, function(status: string)
	Admin.SetRelayStatus(status)
end)

remotes.AdminRequest.OnServerInvoke = function(player: Player, request: any)
	local response = Admin.Handle(player, request)
	if response.ok and request.action == "updateSettings" then Spawn.RefreshConfig(); Camera.Refresh(); remotes.StageUpdate:FireAllClients("settingsChanged") end
	return response
end

Players.PlayerAdded:Connect(function(player)
	if Admin.IsAdmin(player) then
		remotes.StageUpdate:FireClient(player, "admin", true)
	else
		remotes.StageUpdate:FireClient(player, "admin", false)
	end
end)

game:BindToClose(function()
	Spawn.ResetAll()
end)

print("[LiveStage] Core services started. Relay polling is non-blocking; offline relay does not stop the stage.")
