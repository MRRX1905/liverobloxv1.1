--!strict
local HttpService = game:GetService("HttpService")
local EventBridge = {}
local Config: any
local cursor = 0
local seen: {[string]: boolean} = {}
local seenCount = 0
local status = "starting"

local function safeSecret(): any
	local ok, secret = pcall(function() return HttpService:GetSecret("TIKTOK_RELAY_SECRET") end)
	if not ok then return nil end
	return secret
end

local function validEvent(event: any): boolean
	if type(event) ~= "table" or type(event.id) ~= "string" or #event.id > 100 then return false end
	local validTypes = { chat = true, gift = true, member = true, follow = true, subscribe = true, roomUser = true, streamEnd = true, status = true }
	if not validTypes[event.type] then return false end
	if event.type ~= "roomUser" and event.type ~= "status" and (type(event.tiktokUserId) ~= "string" or event.tiktokUserId == "") and (type(event.tiktokUsername) ~= "string" or event.tiktokUsername == "") then return false end
	return true
end

local function dispatchBody(body: string, onEvent: (any) -> (), onStatus: (string) -> ())
	local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
	if not ok or type(decoded) ~= "table" then return end
	if decoded.droppedBeforeCursor == true then onStatus("Relay queue overran; continuing from latest retained events") end
	local batch = decoded.events
	if type(batch) ~= "table" then return end
	for _, event in ipairs(batch) do
		if validEvent(event) and not seen[event.id] then
			seen[event.id] = true
			seenCount += 1
			onEvent(event)
		end
	end
	if tonumber(decoded.cursor) then
		if decoded.droppedBeforeCursor == true then cursor = tonumber(decoded.cursor) :: number
		else cursor = math.max(cursor, tonumber(decoded.cursor) :: number) end
	end
	if seenCount > 5000 then table.clear(seen); seenCount = 0 end
end

function EventBridge.Start(config: any, onEvent: (any) -> (), onStatus: (string) -> ())
	Config = config
	task.spawn(function()
		local failures = 0
		while true do
			local relay = Config.Get("relay")
			local baseUrl = string.gsub(tostring(relay.baseUrl), "/+$", "")
			if not string.match(baseUrl, "^https://") or string.find(baseUrl, "replace%-with%-your%-public%-relay") then
				status = "relay URL not configured"; onStatus(status); task.wait(5); continue
			end
			local secret = safeSecret()
			if not secret then status = "TIKTOK_RELAY_SECRET missing"; onStatus(status); task.wait(5); continue end
			if relay.transport == "webstream" then
				local streamUrl = baseUrl .. "/stream?since=" .. tostring(cursor)
				local okStream, stream = pcall(function()
					return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.RawStream, { Url = streamUrl, Method = "GET", Headers = { ["x-stage-secret"] = secret } })
				end)
				if okStream and stream then
					status = "connected (webstream)"; onStatus(status)
					local buffer = ""
					local messageConnection = stream.MessageReceived:Connect(function(chunk: string)
						buffer ..= chunk
						while true do
							local newline = string.find(buffer, "\n", 1, true)
							if not newline then break end
							local line = string.sub(buffer, 1, newline - 1)
							buffer = string.sub(buffer, newline + 1)
							if #line > 0 then dispatchBody(line, onEvent, onStatus) end
						end
					end)
					stream.Error:Connect(function(code: number, message: string) onStatus("webstream error " .. tostring(code) .. ": " .. tostring(message)) end)
					stream.Closed:Wait()
					messageConnection:Disconnect()
					task.wait(1)
				else
					status = "webstream unavailable; falling back to polling"; onStatus(status)
					task.wait(2)
				end
			else
				local url = baseUrl .. "/events?since=" .. tostring(cursor) .. "&limit=" .. tostring(relay.batchSize)
				local okRequest, response = pcall(function()
					return HttpService:RequestAsync({ Url = url, Method = "GET", Headers = { ["x-stage-secret"] = secret } })
				end)
				if okRequest and response.Success then
					failures = 0
					if status ~= "connected (polling)" then status = "connected (polling)"; onStatus(status) end
					dispatchBody(response.Body, onEvent, onStatus)
					task.wait(math.clamp(relay.pollSeconds, 0.25, 10))
				else
					failures += 1
					status = "relay offline"; onStatus(status)
					local retry = math.min(30, 2 ^ math.min(failures, 5))
					task.wait(retry)
				end
			end
		end
	end)
end

function EventBridge.Status(): string return status end
function EventBridge.Cursor(): number return cursor end

return EventBridge
