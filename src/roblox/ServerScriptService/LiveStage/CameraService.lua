--!strict
local CameraService = {}
local Config: any
local Remote: RemoteEvent?
local currentTarget: Model?
local lastFocus = 0
local modelProvider: (() -> {Model})?
local directorIndex = 0

local modes = { autoDirector = true, followLatest = true, followTierUp = true, wideStage = true, manual = true }

function CameraService.Init(config: any, remote: RemoteEvent)
	Config, Remote = config, remote
	task.spawn(function()
		while true do
			task.wait(math.clamp(Config.Get("camera.focusSeconds"), 1, 30))
			if Config.Get("camera.mode") == "autoDirector" and modelProvider then
				local models = modelProvider()
				if #models > 0 then
					directorIndex = directorIndex % #models + 1
					currentTarget = models[directorIndex]
					lastFocus = os.clock()
					Remote:FireAllClients("focus", currentTarget, Config.Get("camera"))
				end
			end
		end
	end)
end

function CameraService.SetTargetProvider(provider: () -> {Model}) modelProvider = provider end

function CameraService.Focus(kind: string, target: Model?)
	if not Remote or not target or not target.Parent then return end
	currentTarget, lastFocus = target, os.clock()
	local mode = Config.Get("camera.mode")
	if mode == "followTierUp" and kind ~= "tier" then return end
	if mode == "wideStage" then Remote:FireAllClients("wide", nil, Config.Get("camera")); return end
	if mode == "manual" then return end
	local cameraConfig = Config.Get("camera")
	if kind == "tier" and target:GetAttribute("Tier") == "king" then cameraConfig.fov = math.max(35, cameraConfig.fov - 15) end
	Remote:FireAllClients("focus", target, cameraConfig)
end

function CameraService.SetMode(mode: string, target: Model?): (boolean, string?)
	if not modes[mode] then return false, "Unknown camera mode." end
	local config = Config.Get()
	config.camera.mode = mode
	local ok, err = Config.UpdateFromJSON(game:GetService("HttpService"):JSONEncode(config))
	if not ok then return false, err end
	if mode == "wideStage" then Remote:FireAllClients("wide", nil, Config.Get("camera"))
	elseif mode == "manual" and target then Remote:FireAllClients("focus", target, Config.Get("camera"))
	elseif currentTarget then Remote:FireAllClients("focus", currentTarget, Config.Get("camera")) end
	return true, nil
end

function CameraService.Current(): string return Config.Get("camera.mode") end
function CameraService.Refresh()
	local mode = Config.Get("camera.mode")
	if mode == "wideStage" then Remote:FireAllClients("wide", nil, Config.Get("camera"))
	elseif currentTarget and mode ~= "manual" then Remote:FireAllClients("focus", currentTarget, Config.Get("camera")) end
end
function CameraService.IsStale(): boolean return os.clock() - lastFocus > Config.Get("camera.focusSeconds") end

return CameraService
