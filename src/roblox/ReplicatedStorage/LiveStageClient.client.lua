--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("LiveStageRemotes")
local adminRequest = remotes:WaitForChild("AdminRequest") :: RemoteFunction
local stageUpdate = remotes:WaitForChild("StageUpdate") :: RemoteEvent
local cameraRemote = remotes:WaitForChild("Camera") :: RemoteEvent
local noticeRemote = remotes:WaitForChild("StageNotice") :: RemoteEvent
local settings: {[string]: any} = {}
local page = "Dashboard"
local admin, open = false, false
local relayStatus, cameraMode = "Connecting...", "autoDirector"
local count = 0
local viewerCount = 0
local recentEvents: {any} = {}
local cameraConfig: any = { fov = 60, offset = { x = 0, y = 7, z = 18 } }
local target: Model?
local smoothed: CFrame?
local noticeId = 0

local gui = Instance.new("ScreenGui"); gui.Name = "LiveStageUI"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Parent = player:WaitForChild("PlayerGui")
local openButton = Instance.new("TextButton"); openButton.Name = "LiveStageAdmin"; openButton.AnchorPoint = Vector2.new(1, 0); openButton.Position = UDim2.new(1, -18, 0, 16); openButton.Size = UDim2.fromOffset(116, 38); openButton.Text = "LIVE STAGE"; openButton.Visible = false; openButton.Font = Enum.Font.GothamBold; openButton.TextSize = 12; openButton.TextColor3 = Color3.new(1, 1, 1); openButton.BackgroundColor3 = Color3.fromRGB(36, 43, 63); openButton.Parent = gui
local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 10); oc.Parent = openButton
local panel = Instance.new("Frame"); panel.Name = "AdminConsole"; panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.fromScale(0.5, 0.5); panel.Size = UDim2.new(0.86, 0, 0.82, 0); panel.BackgroundColor3 = Color3.fromRGB(17, 20, 31); panel.Visible = false; panel.Parent = gui
local sizeConstraint = Instance.new("UISizeConstraint"); sizeConstraint.MinSize = Vector2.new(350, 320); sizeConstraint.MaxSize = Vector2.new(980, 720); sizeConstraint.Parent = panel
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 16); pc.Parent = panel
local border = Instance.new("UIStroke"); border.Color = Color3.fromRGB(69, 83, 121); border.Parent = panel
local heading = Instance.new("TextLabel"); heading.BackgroundTransparency = 1; heading.Position = UDim2.fromOffset(18, 10); heading.Size = UDim2.new(1, -80, 0, 30); heading.Text = "LIVE STAGE CONTROL"; heading.TextColor3 = Color3.new(1, 1, 1); heading.TextXAlignment = Enum.TextXAlignment.Left; heading.Font = Enum.Font.GothamBold; heading.TextSize = 20; heading.Parent = panel
local close = Instance.new("TextButton"); close.Position = UDim2.new(1, -48, 0, 10); close.Size = UDim2.fromOffset(34, 32); close.Text = "×"; close.TextSize = 22; close.TextColor3 = Color3.new(1, 1, 1); close.BackgroundColor3 = Color3.fromRGB(47, 53, 72); close.Parent = panel
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 8); cc.Parent = close
local status = Instance.new("TextLabel"); status.BackgroundColor3 = Color3.fromRGB(27, 33, 49); status.BackgroundTransparency = 0; status.Position = UDim2.fromOffset(16, 44); status.Size = UDim2.new(1, -32, 0, 26); status.TextXAlignment = Enum.TextXAlignment.Left; status.TextColor3 = Color3.fromRGB(158, 218, 196); status.Font = Enum.Font.GothamMedium; status.TextSize = 12; status.Parent = panel
local statusCorner = Instance.new("UICorner"); statusCorner.CornerRadius = UDim.new(0, 8); statusCorner.Parent = status
local statusPadding = Instance.new("UIPadding"); statusPadding.PaddingLeft = UDim.new(0, 10); statusPadding.Parent = status
local tabs = Instance.new("ScrollingFrame"); tabs.BackgroundTransparency = 1; tabs.Position = UDim2.fromOffset(16, 76); tabs.Size = UDim2.new(1, -32, 0, 38); tabs.ScrollBarThickness = 2; tabs.ScrollingDirection = Enum.ScrollingDirection.X; tabs.AutomaticCanvasSize = Enum.AutomaticSize.X; tabs.Parent = panel
local tabLayout = Instance.new("UIListLayout"); tabLayout.FillDirection = Enum.FillDirection.Horizontal; tabLayout.Padding = UDim.new(0, 6); tabLayout.Parent = tabs
local testBar = Instance.new("ScrollingFrame"); testBar.Name = "QuickTests"; testBar.BackgroundTransparency = 1; testBar.Position = UDim2.fromOffset(20, 119); testBar.Size = UDim2.new(1, -40, 0, 42); testBar.ScrollBarThickness = 2; testBar.ScrollingDirection = Enum.ScrollingDirection.X; testBar.AutomaticCanvasSize = Enum.AutomaticSize.X; testBar.CanvasSize = UDim2.new(0, 0, 0, 0); testBar.Parent = panel
local testTitle = Instance.new("TextLabel"); testTitle.BackgroundTransparency = 1; testTitle.Position = UDim2.fromOffset(0, 0); testTitle.Size = UDim2.fromOffset(86, 38); testTitle.Text = "QUICK TESTS"; testTitle.TextColor3 = Color3.fromRGB(151, 167, 197); testTitle.Font = Enum.Font.GothamBold; testTitle.TextSize = 10; testTitle.Parent = testBar
local editor = Instance.new("TextBox"); editor.Name = "SettingsJSON"; editor.ClearTextOnFocus = false; editor.MultiLine = true; editor.TextXAlignment = Enum.TextXAlignment.Left; editor.TextYAlignment = Enum.TextYAlignment.Top; editor.TextWrapped = false; editor.Font = Enum.Font.Code; editor.TextSize = 14; editor.TextColor3 = Color3.fromRGB(228, 233, 245); editor.BackgroundColor3 = Color3.fromRGB(25, 29, 43); editor.Position = UDim2.fromOffset(20, 168); editor.Size = UDim2.new(1, -40, 1, -242); editor.Parent = panel
local ec = Instance.new("UICorner"); ec.CornerRadius = UDim.new(0, 10); ec.Parent = editor
local ep = Instance.new("UIPadding"); ep.PaddingTop = UDim.new(0, 10); ep.PaddingLeft = UDim.new(0, 10); ep.PaddingRight = UDim.new(0, 10); ep.Parent = editor
local footer = Instance.new("ScrollingFrame"); footer.BackgroundTransparency = 1; footer.Position = UDim2.new(0, 16, 1, -60); footer.Size = UDim2.new(1, -32, 0, 42); footer.ScrollBarThickness = 3; footer.ScrollingDirection = Enum.ScrollingDirection.X; footer.AutomaticCanvasSize = Enum.AutomaticSize.X; footer.CanvasSize = UDim2.new(0, 0, 0, 0); footer.Parent = panel
local footerLayout = Instance.new("UIListLayout"); footerLayout.FillDirection = Enum.FillDirection.Horizontal; footerLayout.Padding = UDim.new(0, 7); footerLayout.Parent = footer
local feedback = Instance.new("TextLabel"); feedback.BackgroundTransparency = 1; feedback.Size = UDim2.fromOffset(140, 38); feedback.Text = ""; feedback.TextXAlignment = Enum.TextXAlignment.Left; feedback.TextColor3 = Color3.fromRGB(161, 221, 185); feedback.Font = Enum.Font.Gotham; feedback.TextSize = 12; feedback.Parent = footer

local function makeButton(parent: Instance, text: string, width: number, color: Color3): TextButton
	local button = Instance.new("TextButton"); button.Size = UDim2.fromOffset(width, 38); button.Text = text; button.TextColor3 = Color3.new(1, 1, 1); button.Font = Enum.Font.GothamBold; button.TextSize = 11; button.BackgroundColor3 = color; button.Parent = parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = button
	return button
end
local function invoke(request: {[string]: any}): any
	local ok, result = pcall(function() return adminRequest:InvokeServer(request) end)
	return if ok then result else { ok = false, error = tostring(result) }
end
local function pageSettings(name: string): any
	if name == "Spawn" then return { spawn = settings.spawn, lanes = settings.lanes, profile = settings.profile } end
	if name == "Tiers" then return { tiers = settings.tiers } end
	if name == "Camera" then return { camera = settings.camera } end
	if name == "VFX" then return { vfx = settings.vfx } end
	if name == "Moderation" then return { moderation = settings.moderation } end
	return settings
end
local function renderDashboard()
	local feed = {}
	for index = 1, math.min(10, #recentEvents) do
		local entry = recentEvents[index]
		table.insert(feed, tostring(entry.type) .. "  " .. tostring(entry.user) .. "  " .. tostring(entry.comment))
	end
	status.Text = "  RELAY  " .. relayStatus .. "     •     LIVE VIEWERS  " .. tostring(viewerCount) .. "     •     STAGE CHARACTERS  " .. tostring(count) .. "     •     CAMERA  " .. cameraMode
	editor.Text = "WELCOME TO THE LIVE STAGE\n\nComment once to bring a viewer onto the stage. To use a Roblox avatar, comment only the Roblox username, for example: mrafiumri, zlib, or kenami. No !join command is needed.\n\nGIFTS\nConfigured Roses move a viewer to the front of their lane. Cumulative Roses upgrade them to Giant. The configured King gift upgrades them to King Giant.\n\nDANCE\n!dance [name] plays a dance. !emote [name] plays an emote.\n\nRECENT LIVE ACTIVITY\n" .. (#feed > 0 and table.concat(feed, "\n") or "Waiting for live events…") .. "\n\nUse the buttons above to run the comment, Giant, King Giant, and lane-skip checks. Edit settings from the tabs. The relay secret is never shown here."
end
local function refresh()
	local result = invoke({ action = "get" })
	if not result.ok then feedback.Text = tostring(result.error); return end
	settings = result.settings; relayStatus = result.relayStatus or relayStatus; count = result.summary and result.summary.active or 0; cameraMode = result.cameraMode or cameraMode; viewerCount = result.viewerCount or 0; recentEvents = result.recentEvents or {}
	if page == "Dashboard" then renderDashboard()
	elseif page == "Animations" then editor.Text = HttpService:JSONEncode(result.animations)
	else editor.Text = HttpService:JSONEncode(pageSettings(page)) end
end
local pages = { "Dashboard", "Spawn", "Tiers", "Animations", "Camera", "VFX", "Moderation" }
local save = makeButton(footer, "SAVE SETTINGS", 118, Color3.fromRGB(61, 94, 164))
local testSpawn = makeButton(footer, "TEST SPAWN", 96, Color3.fromRGB(54, 128, 105))
local resetDefaults = makeButton(footer, "RESET DEFAULTS", 108, Color3.fromRGB(102, 82, 147))
local clearStage = makeButton(footer, "CLEAR STAGE", 92, Color3.fromRGB(152, 78, 82))
local plainNameTest = makeButton(testBar, "USERNAME COMMENT", 130, Color3.fromRGB(47, 112, 118)); plainNameTest.Name = "UsernameCommentTest"; plainNameTest.Position = UDim2.fromOffset(88, 0)
local giantTest = makeButton(testBar, "ROSE → GIANT", 120, Color3.fromRGB(48, 104, 147)); giantTest.Name = "RoseToGiantTest"; giantTest.Position = UDim2.fromOffset(224, 0)
local kingTest = makeButton(testBar, "DONUT → KING", 120, Color3.fromRGB(136, 99, 42)); kingTest.Name = "DonutToKingTest"; kingTest.Position = UDim2.fromOffset(350, 0)
local skipTest = makeButton(testBar, "ROSE LANE SKIP", 124, Color3.fromRGB(106, 77, 148)); skipTest.Name = "RoseLaneSkipTest"; skipTest.Position = UDim2.fromOffset(476, 0)
local manualUsername = Instance.new("TextBox"); manualUsername.Name = "ManualRobloxUsername"; manualUsername.ClearTextOnFocus = false; manualUsername.PlaceholderText = "Roblox username (e.g. mrafiumri)"; manualUsername.Text = ""; manualUsername.Font = Enum.Font.Gotham; manualUsername.TextSize = 13; manualUsername.TextColor3 = Color3.fromRGB(235, 239, 250); manualUsername.PlaceholderColor3 = Color3.fromRGB(142, 151, 175); manualUsername.BackgroundColor3 = Color3.fromRGB(30, 36, 53); manualUsername.Position = UDim2.fromOffset(20, 164); manualUsername.Size = UDim2.fromOffset(260, 38); manualUsername.Parent = panel
local manualCorner = Instance.new("UICorner"); manualCorner.CornerRadius = UDim.new(0, 8); manualCorner.Parent = manualUsername
local manualPadding = Instance.new("UIPadding"); manualPadding.PaddingLeft = UDim.new(0, 10); manualPadding.Parent = manualUsername
local manualSpawn = makeButton(panel, "SPAWN AVATAR", 150, Color3.fromRGB(47, 112, 118)); manualSpawn.Name = "ManualSpawnAvatar"; manualSpawn.Position = UDim2.fromOffset(290, 164)
local tabButtons: {[string]: TextButton} = {}
local function selectPage(name: string)
	page = name; refresh()
	testBar.Visible = name == "Dashboard"
	editor.TextEditable = name ~= "Dashboard"
	manualUsername.Visible = name == "Dashboard"
	manualSpawn.Visible = name == "Dashboard"
	editor.Position = if testBar.Visible then UDim2.fromOffset(20, 210) else UDim2.fromOffset(20, 124)
	editor.Size = if testBar.Visible then UDim2.new(1, -40, 1, -284) else UDim2.new(1, -40, 1, -198)
	save.Visible = name ~= "Dashboard"
	testSpawn.Visible = name == "Dashboard" or name == "Spawn"
	resetDefaults.Visible = name == "Dashboard"
	clearStage.Visible = name == "Dashboard" or name == "Moderation"
	for tabName, tab in pairs(tabButtons) do tab.BackgroundColor3 = if tabName == name then Color3.fromRGB(65, 90, 135) else Color3.fromRGB(42, 49, 70) end
end
for _, name in ipairs(pages) do
	local tab = makeButton(tabs, name, 96, Color3.fromRGB(42, 49, 70)); tab.Size = UDim2.fromOffset(96, 32)
	tabButtons[name] = tab
	tab.Activated:Connect(function() selectPage(name) end)
end
save.Activated:Connect(function()
	local request = if page == "Animations" then { action = "replaceAnimations", json = editor.Text } else { action = "updateSettings", json = editor.Text }
	local result = invoke(request)
	feedback.Text = if result.ok then "Saved and live." else tostring(result.error)
	if result.ok then refresh() end
end)
testSpawn.Activated:Connect(function() local result = invoke({ action = "testSpawn" }); feedback.Text = if result.ok then "Test character sent to stage." else tostring(result.error) end)
resetDefaults.Activated:Connect(function() local result = invoke({ action = "resetDefaults" }); feedback.Text = if result.ok then "Defaults restored." else tostring(result.error); if result.ok then refresh() end end)
clearStage.Activated:Connect(function() local result = invoke({ action = "clearStage" }); feedback.Text = if result.ok then "Stage cleared." else tostring(result.error) end)
local function runScenario(scenario: string)
	feedback.Text = "Running " .. scenario .. " check…"
	local result = invoke({ action = "testScenario", scenario = scenario, username = "mrafiumri" })
	if not result.ok then feedback.Text = "Check failed: " .. tostring(result.error or result.tier or "unknown error"); return end
	if scenario == "comment" then feedback.Text = if result.avatarLinked then "Username comment linked · Roblox user " .. tostring(result.robloxUserId) else "Comment spawned a viewer; Roblox name lookup did not match"
	elseif scenario == "giant" then feedback.Text = "Giant passed · scale " .. tostring(result.scale)
	elseif scenario == "king" then feedback.Text = "King Giant passed · scale " .. tostring(result.scale)
	else feedback.Text = "Lane skip passed · viewer moved to front" end
	refresh()
end
plainNameTest.Activated:Connect(function() runScenario("comment") end)
giantTest.Activated:Connect(function() runScenario("giant") end)
kingTest.Activated:Connect(function() runScenario("king") end)
skipTest.Activated:Connect(function() runScenario("skip") end)
manualSpawn.Activated:Connect(function()
	local username = string.gsub(manualUsername.Text, "^%s*(.-)%s*$", "%1")
	if username == "" then feedback.Text = "Enter a Roblox username first."; return end
	feedback.Text = "Loading @" .. username .. "…"
	local result = invoke({ action = "spawnUser", username = username })
	if not result.ok then feedback.Text = tostring(result.error or "Avatar could not load."); return end
	feedback.Text = if result.alreadyOnStage then "@" .. result.username .. " is already on stage." else "Loaded @" .. result.username .. " · " .. tostring(result.tier) .. " · " .. tostring(result.scale) .. "×"
	refresh()
end)
local function toggle()
	if not admin then return end
	open = not open; panel.Visible = open
	if open then selectPage("Dashboard") end
end
openButton.Activated:Connect(toggle)
close.Activated:Connect(function() open = false; panel.Visible = false end)
local toggleAction = ReplicatedStorage:WaitForChild("Inputs"):WaitForChild("AdminConsoleContext"):WaitForChild("ToggleConsole") :: InputAction
toggleAction.Pressed:Connect(toggle)

stageUpdate.OnClientEvent:Connect(function(kind: string, a: any)
	if kind == "admin" then admin = a == true; openButton.Visible = admin
	elseif kind == "status" then relayStatus = tostring(a); if panel.Visible then refresh() end
	elseif kind == "audience" then viewerCount = tonumber(a) or viewerCount; if panel.Visible and page == "Dashboard" then renderDashboard() end
	elseif kind == "event" and type(a) == "table" and panel.Visible and page == "Dashboard" then table.insert(recentEvents, 1, a); while #recentEvents > 20 do table.remove(recentEvents) end; renderDashboard()
	elseif kind == "settingsChanged" and panel.Visible then refresh()
	elseif kind == "action" and typeof(a) == "Instance" and a:IsA("Model") then target = a end
end)
local banner = Instance.new("TextLabel"); banner.AnchorPoint = Vector2.new(0.5, 0); banner.Position = UDim2.new(0.5, 0, 0, 24); banner.Size = UDim2.fromOffset(400, 50); banner.BackgroundColor3 = Color3.fromRGB(20, 23, 36); banner.TextColor3 = Color3.new(1, 1, 1); banner.Text = ""; banner.Font = Enum.Font.GothamBold; banner.TextSize = 20; banner.Visible = false; banner.Parent = gui
local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 12); bc.Parent = banner
noticeRemote.OnClientEvent:Connect(function(text: string)
	noticeId += 1; local id = noticeId; banner.Text = text; banner.Visible = true
	task.delay(2.5, function() if id == noticeId then banner.Visible = false end end)
end)
cameraRemote.OnClientEvent:Connect(function(kind: string, model: any, config: any)
	if kind == "wide" then target = nil; cameraMode = "wideStage"
	elseif kind == "focus" and typeof(model) == "Instance" and model:IsA("Model") then target = model; cameraConfig = config or cameraConfig; cameraMode = cameraConfig.mode or cameraMode end
end)

local camera = workspace.CurrentCamera
RunService:BindToRenderStep("LiveStageCamera", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
	if not camera then camera = workspace.CurrentCamera end
	if not camera then return end
	if cameraMode == "wideStage" then
		local point = workspace:GetAttribute("LiveStageCameraTarget")
		if typeof(point) == "Vector3" then
			local cf = CFrame.lookAt(point + Vector3.new(0, 8, 115), point)
			local duration = math.max(tonumber(cameraConfig.transitionSeconds) or 1, 0.05)
			camera.CameraType = Enum.CameraType.Scriptable; camera.FieldOfView = cameraConfig.fov or 60; camera.CFrame = camera.CFrame:Lerp(cf, math.clamp(dt / duration, 0, 1))
		end
		return
	end
	if not target or not target.Parent or cameraMode == "manual" then return end
	local torso = target:FindFirstChild("UpperTorso") or target:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") then return end
	local offset = cameraConfig.offset or { x = 0, y = 7, z = 18 }
	local focus = torso.Position + Vector3.new(0, 2.5 * target:GetScale(), 0)
	local position = focus + Vector3.new(offset.x or 0, offset.y or 7, offset.z or 18) * math.clamp(target:GetScale(), 1, 4)
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances = { target, player.Character }
	local hit = workspace:Raycast(focus, position - focus, params); if hit then position = hit.Position + hit.Normal * 1.5 end
	local desired = CFrame.lookAt(position, focus); local duration = math.max(tonumber(cameraConfig.transitionSeconds) or 1, 0.05); smoothed = if smoothed then smoothed:Lerp(desired, math.clamp(dt / duration, 0, 1)) else desired
	camera.CameraType = Enum.CameraType.Scriptable; camera.FieldOfView = cameraConfig.fov or 60; camera.CFrame = smoothed
end)

local initial = invoke({ action = "get" })
if initial.ok then admin = true; openButton.Visible = true; settings = initial.settings; relayStatus = initial.relayStatus or relayStatus end
