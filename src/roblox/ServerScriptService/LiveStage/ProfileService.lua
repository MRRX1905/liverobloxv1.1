--!strict
local ProfileService = {}
local Config: any

function ProfileService.Init(config: any) Config = config end

function ProfileService.SetWornCost(model: Model, total: number)
	model:SetAttribute("WornCost", math.max(0, math.floor(total)))
	ProfileService.Refresh(model)
end

function ProfileService.Refresh(model: Model)
	local card = model:FindFirstChild("LiveStageProfile", true)
	if not card then return end
	local badge = card:FindFirstChild("TierBadge", true)
	if not badge or not badge:IsA("TextLabel") then return end
	local tier = tostring(model:GetAttribute("Tier") or "normal")
	local fan = model:GetAttribute("IsFan") == true
	local cost = model:GetAttribute("WornCost")
	local amount = if type(cost) == "number" then tostring(math.floor(cost)) else nil
	if amount then
		while true do
			local changed
			amount, changed = string.gsub(amount, "^(%d+)(%d%d%d)", "%1,%2")
			if changed == 0 then break end
		end
	end
	local suffix = if amount then "  •  Est. R$ " .. amount else "  •  estimating..."
	local fanText = if fan then tostring(Config.Get("tiers.fans.title")) .. "  •  " else ""
	badge.Text = fanText .. string.upper(tier) .. suffix
	if fan then
		local hex = string.gsub(tostring(Config.Get("tiers.fans.color")), "#", "")
		local value = if #hex == 6 then tonumber(hex, 16) else nil
		badge.TextColor3 = if value then Color3.fromRGB(bit32.rshift(value, 16), bit32.band(bit32.rshift(value, 8), 255), bit32.band(value, 255)) else Color3.fromRGB(255, 45, 85)
	else
		badge.TextColor3 = if tier == "king" then Color3.fromRGB(255, 200, 90) elseif tier == "giant" then Color3.fromRGB(113, 211, 255) else Color3.fromRGB(198, 177, 255)
	end
end

return ProfileService
