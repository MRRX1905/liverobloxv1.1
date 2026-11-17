--!strict
local AuraService = {}
local Config: any
local active: {[Model]: {Instance}} = {}
local random = Random.new()

function AuraService.Init(config: any) Config = config end

function AuraService.Apply(model: Model, tier: string)
	AuraService.Remove(model)
	if not Config.Get("vfx.aurasEnabled") then return end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local candidates, weightTotal = {}, 0
	for _, preset in ipairs(Config.Get("vfx.auras")) do
		if preset.tier == tier then weightTotal += math.max(0, tonumber(preset.weight) or 0); table.insert(candidates, preset) end
	end
	local selected = candidates[1]
	if weightTotal > 0 then
		local roll = random:NextNumber(0, weightTotal)
		for _, preset in ipairs(candidates) do roll -= math.max(0, tonumber(preset.weight) or 0); if roll <= 0 then selected = preset; break end end
	end
	local hex = string.gsub(tostring(selected and selected.color or "#B781FF"), "#", "")
	local value = if #hex == 6 then tonumber(hex, 16) else nil
	local color = if value then Color3.fromRGB(bit32.rshift(value, 16), bit32.band(bit32.rshift(value, 8), 255), bit32.band(value, 255)) else Color3.fromRGB(183, 129, 255)
	local list: {Instance} = {}
	local highlight = Instance.new("Highlight")
	highlight.Name = "LiveStageAura"
	highlight.FillColor = color
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = if tier == "king" then 0.7 else 0.86
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	table.insert(list, highlight)
	local light = Instance.new("PointLight")
	light.Name = "LiveStageGlow"
	light.Color = color
	local activeCount = 0
	for _ in pairs(active) do activeCount += 1 end
	local quality = Config.Get("vfx.quality")
	light.Brightness = if activeCount > 18 or quality == "low" then 0.5 elseif tier == "king" then 2.5 else 1
	light.Range = if activeCount > 18 or quality == "low" then 8 elseif tier == "king" then 24 else 12
	light.Parent = root
	table.insert(list, light)
	active[model] = list
end

function AuraService.Burst(model: Model, color: Color3?)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(255, 224, 140))
	emitter.LightEmission = 0.8
	emitter.Lifetime = NumberRange.new(0.4, 0.85)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = attachment
	emitter:Emit(math.clamp(math.floor(Config.Get("vfx.maxParticleRate") * 2), 4, 60))
	task.delay(1.5, function() attachment:Destroy() end)
end

function AuraService.Remove(model: Model)
	for _, instance in ipairs(active[model] or {}) do instance:Destroy() end
	active[model] = nil
end

function AuraService.Clear() for model in pairs(active) do AuraService.Remove(model) end end

return AuraService
