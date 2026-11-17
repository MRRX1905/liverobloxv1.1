--!strict
local TweenService = game:GetService("TweenService")
local LaneService = {}
local Config: any
local members: {[string]: { model: Model, tier: string, sequence: number }} = {}
local nextSequence = 0

function LaneService.Init(config: any)
	Config = config
end

local function rowFor(tier: string): string
	if tier == "king" then return "king" end
	if tier == "giant" then return "giant" end
	return "normal"
end

local function targetCFrame(row: string, index: number, size: number): CFrame
	local lane = Config.Get("lanes")
	local spacing = lane.spacing * math.clamp(size, 1, 4)
	local slot = math.ceil(index / 2)
	local x = if index == 1 then 0 elseif index % 2 == 0 then -slot * spacing else slot * spacing
	local depth = if row == "king" then lane.kingDepth elseif row == "giant" then lane.giantDepth else lane.normalDepth
	local scale = math.clamp(size, 1, 12)
	return CFrame.new(x, 1 + (lane.verticalOffset - 1) * scale, lane.rowZ - depth) * CFrame.Angles(0, math.pi, 0)
end

function LaneService.Register(key: string, model: Model, tier: string)
	nextSequence += 1
	members[key] = { model = model, tier = rowFor(tier), sequence = nextSequence }
	LaneService.Reflow()
end

function LaneService.CanRegister(tier: string): boolean
	local row = rowFor(tier)
	local caps = Config.Get("spawn.maxPerRow")
	local cap = if row == "king" then caps.king elseif row == "giant" then caps.giant else caps.normal
	return LaneService.Count(row) < cap
end

function LaneService.Oldest(row: string): string?
	local found, sequence = nil, math.huge
	for key, entry in pairs(members) do
		if entry.tier == row and entry.sequence < sequence then found, sequence = key, entry.sequence end
	end
	return found
end

function LaneService.Remove(key: string)
	members[key] = nil
	LaneService.Reflow()
end

function LaneService.SetTier(key: string, tier: string)
	local entry = members[key]
	if entry then entry.tier = rowFor(tier); LaneService.Reflow() end
end

function LaneService.Skip(key: string)
	local entry = members[key]
	if not entry or not entry.model.Parent then return end
	nextSequence += 1
	entry.sequence = -nextSequence
	local root = entry.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local target = targetCFrame(entry.tier, 1, entry.model:GetScale()) + Vector3.new(0, 3, 0)
		root.AssemblyLinearVelocity = Vector3.new(0, 30, 0)
		task.delay(0.25, function() if entry.model.Parent then entry.model:PivotTo(target) end end)
	end
	LaneService.Reflow()
end

function LaneService.Reflow()
	local grouped: {[string]: {{ key: string, entry: any }}} = { normal = {}, giant = {}, king = {} }
	for key, entry in pairs(members) do
		if entry.model.Parent then table.insert(grouped[entry.tier], { key = key, entry = entry }) end
	end
	for row, list in pairs(grouped) do
		table.sort(list, function(a, b) return a.entry.sequence < b.entry.sequence end)
		for index, item in ipairs(list) do
			local model = item.entry.model :: Model
			local cf = targetCFrame(row, index, model:GetScale())
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local tween = TweenService:Create(root, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf })
				tween:Play()
			end
		end
	end
end

function LaneService.Count(row: string?): number
	local total = 0
	for _, entry in pairs(members) do if not row or entry.tier == row then total += 1 end end
	return total
end

function LaneService.Clear()
	table.clear(members)
end

return LaneService
