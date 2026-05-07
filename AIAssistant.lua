-- AIAssistant.lua | Multi-provider AI scripting assistant
-- Supports: Anthropic Claude, OpenAI ChatGPT, Google Gemini
-- Features: session persistence, remote/dex context injection, safe script preview

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
	keys = {
		anthropic = "YOUR_ANTHROPIC_KEY",
		openai    = "YOUR_OPENAI_KEY",
		gemini    = "YOUR_GEMINI_KEY",
	},
	provider = "anthropic", -- default: "anthropic" | "openai" | "gemini"
	models = {
		anthropic = "claude-haiku-4-5-20251001",
		openai    = "gpt-4o-mini",
		gemini    = "gemini-2.0-flash",
	},
	max_tokens  = 1024,
	system      = "You are a Roblox Luau scripting assistant running inside an executor. When given remote or instance data, generate clean executor-compatible scripts. When returning executable code, wrap it in <SCRIPT></SCRIPT> tags. Be concise.",
	session_dir = "ai_sessions/",
}

-- ============================================================
-- SERVICES
-- ============================================================
local Players       = game:GetService("Players")
local HttpService   = game:GetService("HttpService")
local UIS           = game:GetService("UserInputService")
local MPS           = game:GetService("MarketplaceService")
local RunService    = game:GetService("RunService")
local lp            = Players.LocalPlayer
local gui           = lp:WaitForChild("PlayerGui")

-- ============================================================
-- SESSION PERSISTENCE
-- ============================================================
local sessionFile, sessionMeta, history = nil, {}, {}

local function getGameName()
	local ok, info = pcall(function() return MPS:GetProductInfo(game.PlaceId) end)
	return (ok and info and info.Name) or ("Place_" .. game.PlaceId)
end

local function sanitiseFilename(s)
	return s:gsub("[^%w%-_]", "_"):sub(1, 40)
end

local function initSession()
	local gameName = sanitiseFilename(getGameName())
	local date     = os.date("%Y-%m-%d_%H-%M")
	local fname    = CFG.session_dir .. gameName .. "_" .. date .. ".json"
	sessionMeta    = { game = getGameName(), placeId = game.PlaceId, date = os.date("%Y-%m-%d %H:%M:%S"), provider = CFG.provider }
	sessionFile    = fname
	-- ensure dir exists by writing a placeholder if needed
	pcall(function()
		if not isfolder(CFG.session_dir) then makefolder(CFG.session_dir) end
	end)
end

local function saveSession()
	if not sessionFile then return end
	pcall(function()
		writefile(sessionFile, HttpService:JSONEncode({ meta = sessionMeta, history = history }))
	end)
end

local function listSessions()
	local files = {}
	pcall(function()
		if isfolder(CFG.session_dir) then
			for _, f in ipairs(listfiles(CFG.session_dir)) do
				if f:match("%.json$") then table.insert(files, f) end
			end
		end
	end)
	return files
end

local function loadSession(path)
	local ok, raw = pcall(readfile, path)
	if not ok or not raw then return false end
	local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok2 or not data then return false end
	sessionMeta = data.meta or {}
	history     = data.history or {}
	sessionFile = path
	CFG.provider = sessionMeta.provider or CFG.provider
	return true
end

-- ============================================================
-- PROVIDER HTTP
-- ============================================================
local function buildRequest(messages)
	local p = CFG.provider
	if p == "anthropic" then
		return {
			Url    = "https://api.anthropic.com/v1/messages",
			Method = "POST",
			Headers = {
				["x-api-key"]         = CFG.keys.anthropic,
				["anthropic-version"] = "2023-06-01",
				["content-type"]      = "application/json",
			},
			Body = HttpService:JSONEncode({
				model      = CFG.models.anthropic,
				max_tokens = CFG.max_tokens,
				system     = CFG.system,
				messages   = messages,
			}),
		}
	elseif p == "openai" then
		local msgs = {{ role = "system", content = CFG.system }}
		for _, m in ipairs(messages) do table.insert(msgs, m) end
		return {
			Url    = "https://api.openai.com/v1/chat/completions",
			Method = "POST",
			Headers = {
				["Authorization"] = "Bearer " .. CFG.keys.openai,
				["content-type"]  = "application/json",
			},
			Body = HttpService:JSONEncode({
				model      = CFG.models.openai,
				max_tokens = CFG.max_tokens,
				messages   = msgs,
			}),
		}
	elseif p == "gemini" then
		local parts = {{ text = CFG.system .. "\n\n" }}
		for _, m in ipairs(messages) do
			table.insert(parts, { text = ("[" .. m.role .. "]: " .. m.content .. "\n") })
		end
		return {
			Url    = "https://generativelanguage.googleapis.com/v1beta/models/" .. CFG.models.gemini .. ":generateContent?key=" .. CFG.keys.gemini,
			Method = "POST",
			Headers = { ["content-type"] = "application/json" },
			Body   = HttpService:JSONEncode({ contents = {{ parts = parts }} }),
		}
	end
end

local function parseResponse(raw, statusCode)
	if statusCode ~= 200 then return nil, "HTTP " .. tostring(statusCode) end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok then return nil, "JSON parse error" end
	local p = CFG.provider
	if p == "anthropic" then
		return (data.content and data.content[1] and data.content[1].text), nil
	elseif p == "openai" then
		return (data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content), nil
	elseif p == "gemini" then
		return (data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts and data.candidates[1].content.parts[1] and data.candidates[1].content.parts[1].text), nil
	end
	return nil, "unknown provider"
end

local function extractScript(text)
	return text:match("<SCRIPT>(.-)</SCRIPT>")
end

-- ============================================================
-- CONTEXT HELPERS
-- ============================================================
local function getDexContext()
	local lines = {"[Dex Explorer Snapshot]"}
	local function scan(inst, depth)
		if depth > 3 then return end
		local ok, children = pcall(function() return inst:GetChildren() end)
		if not ok or type(children) ~= "table" then return end
		for _, c in ipairs(children) do
			local nameOk, cname = pcall(function() return c.Name end)
			local classOk, cclass = pcall(function() return c.ClassName end)
			if nameOk and classOk then
				table.insert(lines, string.rep("  ", depth) .. cclass .. " \"" .. cname .. "\"")
				scan(c, depth + 1)
			end
		end
	end
	scan(game, 0)
	if #lines > 80 then
		local trimmed = {}
		for i = 1, 80 do trimmed[i] = lines[i] end
		table.insert(trimmed, "... (truncated)")
		return table.concat(trimmed, "\n")
	end
	return table.concat(lines, "\n")
end

local firedRemotes = {}
local function hookRemotes()
	local mt = getrawmetatable(game)
	local oldIndex = mt.__index
	setreadonly(mt, false)
	mt.__namecall = newcclosure(function(self, ...)
		local method = getnamecallmethod()
		if method == "FireServer" or method == "InvokeServer" then
			local args = {...}
			local entry = {
				remote = tostring(self),
				path   = self:GetFullName(),
				method = method,
				args   = #args,
			}
			if #firedRemotes < 50 then table.insert(firedRemotes, entry) end
		end
		return oldIndex(self, ...)
	end)
	setreadonly(mt, true)
end

local hookOk = pcall(hookRemotes)

local function getRemoteContext()
	if not hookOk or #firedRemotes == 0 then return "[No remotes captured yet — interact with the game first]" end
	local lines = {"[RemoteSpy Capture - last " .. math.min(#firedRemotes, 20) .. " calls]"}
	for i = math.max(1, #firedRemotes - 19), #firedRemotes do
		local r = firedRemotes[i]
		table.insert(lines, r.method .. " | " .. r.path .. " | args: " .. r.args)
	end
	return table.concat(lines, "\n")
end

-- ============================================================
-- GUI
-- ============================================================
if gui:FindFirstChild("AIAssistGui") then gui:FindFirstChild("AIAssistGui"):Destroy() end

local sg = Instance.new("ScreenGui"); sg.Name = "AIAssistGui"; sg.ResetOnSpawn = false; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; sg.Parent = gui

local DARK   = Color3.fromRGB(13,13,18)
local PANEL  = Color3.fromRGB(22,22,32)
local BORDER = Color3.fromRGB(55,55,80)
local ACCENT = Color3.fromRGB(90,110,230)
local TEXT   = Color3.fromRGB(210,210,225)
local MUTED  = Color3.fromRGB(90,90,115)
local GREEN  = Color3.fromRGB(60,180,100)
local RED    = Color3.fromRGB(180,60,60)

local function corner(p, r) local c = Instance.new("UICorner", p); c.CornerRadius = UDim.new(0, r or 6); return c end
local function stroke(p, col, t) local s = Instance.new("UIStroke", p); s.Color = col or BORDER; s.Thickness = t or 1; return s end
local function pad(p, a, b, c2, d) local u = Instance.new("UIPadding", p); u.PaddingTop = UDim.new(0,a); u.PaddingBottom = UDim.new(0,b or a); u.PaddingLeft = UDim.new(0,c2 or a); u.PaddingRight = UDim.new(0,d or c2 or a) end

-- main frame
local frame = Instance.new("Frame"); frame.Name = "Main"; frame.Size = UDim2.new(0,360,0,500); frame.Position = UDim2.new(0,40,0,40); frame.BackgroundColor3 = DARK; frame.BorderSizePixel = 0; frame.Active = true; frame.Parent = sg
corner(frame, 10); stroke(frame)

-- titlebar
local tb = Instance.new("Frame"); tb.Size = UDim2.new(1,0,0,34); tb.BackgroundColor3 = PANEL; tb.BorderSizePixel = 0; tb.Parent = frame
corner(tb, 10)
local tbfix = Instance.new("Frame"); tbfix.Size = UDim2.new(1,0,0.5,0); tbfix.Position = UDim2.new(0,0,0.5,0); tbfix.BackgroundColor3 = PANEL; tbfix.BorderSizePixel = 0; tbfix.Parent = tb

local titleLbl = Instance.new("TextLabel"); titleLbl.Size = UDim2.new(1,-100,1,0); titleLbl.Position = UDim2.new(0,10,0,0); titleLbl.BackgroundTransparency = 1; titleLbl.Text = "AI Assistant"; titleLbl.TextColor3 = TEXT; titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 13; titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = tb

-- provider dropdown (simple cycle button)
local providerBtn = Instance.new("TextButton"); providerBtn.Size = UDim2.new(0,80,0,22); providerBtn.Position = UDim2.new(1,-170,0,6); providerBtn.BackgroundColor3 = Color3.fromRGB(40,40,60); providerBtn.Text = CFG.provider; providerBtn.TextColor3 = TEXT; providerBtn.Font = Enum.Font.GothamBold; providerBtn.TextSize = 11; providerBtn.BorderSizePixel = 0; providerBtn.Parent = tb
corner(providerBtn, 4)
local providers = {"anthropic","openai","gemini"}
local providerIdx = 1
providerBtn.MouseButton1Click:Connect(function()
	providerIdx = (providerIdx % #providers) + 1
	CFG.provider = providers[providerIdx]
	providerBtn.Text = CFG.provider
	sessionMeta.provider = CFG.provider
end)

-- sessions button
local sessBtn = Instance.new("TextButton"); sessBtn.Size = UDim2.new(0,54,0,22); sessBtn.Position = UDim2.new(1,-110,0,6); sessBtn.BackgroundColor3 = Color3.fromRGB(40,60,40); sessBtn.Text = "Sessions"; sessBtn.TextColor3 = TEXT; sessBtn.Font = Enum.Font.Gotham; sessBtn.TextSize = 10; sessBtn.BorderSizePixel = 0; sessBtn.Parent = tb
corner(sessBtn, 4)

local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.new(0,28,0,22); closeBtn.Position = UDim2.new(1,-52,0,6); closeBtn.BackgroundColor3 = RED; closeBtn.Text = "×"; closeBtn.TextColor3 = Color3.new(1,1,1); closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16; closeBtn.BorderSizePixel = 0; closeBtn.Parent = tb
corner(closeBtn, 4)
closeBtn.MouseButton1Click:Connect(function() saveSession(); sg:Destroy() end)

-- tab bar
local tabBar = Instance.new("Frame"); tabBar.Size = UDim2.new(1,-16,0,26); tabBar.Position = UDim2.new(0,8,0,38); tabBar.BackgroundColor3 = PANEL; tabBar.BorderSizePixel = 0; tabBar.Parent = frame
corner(tabBar, 5)
local tabLayout = Instance.new("UIListLayout", tabBar); tabLayout.FillDirection = Enum.FillDirection.Horizontal; tabLayout.Padding = UDim.new(0,2)
pad(tabBar, 2, 2, 2, 2)

local function makeTab(name, w)
	local b = Instance.new("TextButton"); b.Size = UDim2.new(0,w,1,0); b.BackgroundColor3 = Color3.fromRGB(35,35,50); b.Text = name; b.TextColor3 = MUTED; b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.BorderSizePixel = 0; b.Parent = tabBar
	corner(b, 4); return b
end

local tabChat   = makeTab("Chat", 70)
local tabRemote = makeTab("RemoteSpy", 90)
local tabDex    = makeTab("Dex", 55)
local tabScript = makeTab("Script", 65)

-- content area
local contentY0 = 70
local contentH  = 500 - contentY0 - 52 -- minus titlebar, tabbar, input area

-- CHAT panel
local chatScroll = Instance.new("ScrollingFrame"); chatScroll.Size = UDim2.new(1,-16,0,contentH); chatScroll.Position = UDim2.new(0,8,0,contentY0); chatScroll.BackgroundTransparency = 1; chatScroll.BorderSizePixel = 0; chatScroll.ScrollBarThickness = 3; chatScroll.ScrollBarImageColor3 = ACCENT; chatScroll.CanvasSize = UDim2.new(0,0,0,0); chatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; chatScroll.Parent = frame
local chatLayout = Instance.new("UIListLayout", chatScroll); chatLayout.Padding = UDim.new(0,5); chatLayout.SortOrder = Enum.SortOrder.LayoutOrder
pad(chatScroll, 4, 4, 4, 4)

-- REMOTE panel
local remotePanel = Instance.new("Frame"); remotePanel.Size = UDim2.new(1,-16,0,contentH); remotePanel.Position = UDim2.new(0,8,0,contentY0); remotePanel.BackgroundTransparency = 1; remotePanel.Visible = false; remotePanel.Parent = frame
local remoteScroll = Instance.new("ScrollingFrame"); remoteScroll.Size = UDim2.new(1,0,1,-30); remoteScroll.BackgroundColor3 = PANEL; remoteScroll.BorderSizePixel = 0; remoteScroll.ScrollBarThickness = 3; remoteScroll.CanvasSize = UDim2.new(0,0,0,0); remoteScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; remoteScroll.Parent = remotePanel
corner(remoteScroll)
local remoteTxt = Instance.new("TextLabel"); remoteTxt.Size = UDim2.new(1,-8,0,0); remoteTxt.Position = UDim2.new(0,4,0,4); remoteTxt.AutomaticSize = Enum.AutomaticSize.Y; remoteTxt.BackgroundTransparency = 1; remoteTxt.Text = "Interact with the game to capture remotes."; remoteTxt.TextColor3 = MUTED; remoteTxt.Font = Enum.Font.Code; remoteTxt.TextSize = 11; remoteTxt.TextWrapped = true; remoteTxt.TextXAlignment = Enum.TextXAlignment.Left; remoteTxt.Parent = remoteScroll
local injectRemoteBtn = Instance.new("TextButton"); injectRemoteBtn.Size = UDim2.new(1,0,0,26); injectRemoteBtn.Position = UDim2.new(0,0,1,-26); injectRemoteBtn.BackgroundColor3 = ACCENT; injectRemoteBtn.Text = "Inject into Chat"; injectRemoteBtn.TextColor3 = Color3.new(1,1,1); injectRemoteBtn.Font = Enum.Font.GothamBold; injectRemoteBtn.TextSize = 12; injectRemoteBtn.BorderSizePixel = 0; injectRemoteBtn.Parent = remotePanel
corner(injectRemoteBtn)

-- DEX panel
local dexPanel = Instance.new("Frame"); dexPanel.Size = UDim2.new(1,-16,0,contentH); dexPanel.Position = UDim2.new(0,8,0,contentY0); dexPanel.BackgroundTransparency = 1; dexPanel.Visible = false; dexPanel.Parent = frame
local dexScroll = Instance.new("ScrollingFrame"); dexScroll.Size = UDim2.new(1,0,1,-30); dexScroll.BackgroundColor3 = PANEL; dexScroll.BorderSizePixel = 0; dexScroll.ScrollBarThickness = 3; dexScroll.CanvasSize = UDim2.new(0,0,0,0); dexScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; dexScroll.Parent = dexPanel
corner(dexScroll)
local dexTxt = Instance.new("TextLabel"); dexTxt.Size = UDim2.new(1,-8,0,0); dexTxt.Position = UDim2.new(0,4,0,4); dexTxt.AutomaticSize = Enum.AutomaticSize.Y; dexTxt.BackgroundTransparency = 1; dexTxt.Text = "Loading..."; dexTxt.TextColor3 = Color3.fromRGB(140,200,140); dexTxt.Font = Enum.Font.Code; dexTxt.TextSize = 10; dexTxt.TextWrapped = true; dexTxt.TextXAlignment = Enum.TextXAlignment.Left; dexTxt.Parent = dexScroll
local injectDexBtn = Instance.new("TextButton"); injectDexBtn.Size = UDim2.new(1,0,0,26); injectDexBtn.Position = UDim2.new(0,0,1,-26); injectDexBtn.BackgroundColor3 = ACCENT; injectDexBtn.Text = "Inject into Chat"; injectDexBtn.TextColor3 = Color3.new(1,1,1); injectDexBtn.Font = Enum.Font.GothamBold; injectDexBtn.TextSize = 12; injectDexBtn.BorderSizePixel = 0; injectDexBtn.Parent = dexPanel
corner(injectDexBtn)

-- SCRIPT panel
local scriptPanel = Instance.new("Frame"); scriptPanel.Size = UDim2.new(1,-16,0,contentH); scriptPanel.Position = UDim2.new(0,8,0,contentY0); scriptPanel.BackgroundTransparency = 1; scriptPanel.Visible = false; scriptPanel.Parent = frame
local scriptScroll = Instance.new("ScrollingFrame"); scriptScroll.Size = UDim2.new(1,0,1,-30); scriptScroll.BackgroundColor3 = PANEL; scriptScroll.BorderSizePixel = 0; scriptScroll.ScrollBarThickness = 3; scriptScroll.CanvasSize = UDim2.new(0,0,0,0); scriptScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; scriptScroll.Parent = scriptPanel
corner(scriptScroll)
local scriptPreview = Instance.new("TextLabel"); scriptPreview.Size = UDim2.new(1,-8,0,0); scriptPreview.Position = UDim2.new(0,4,0,4); scriptPreview.AutomaticSize = Enum.AutomaticSize.Y; scriptPreview.BackgroundTransparency = 1; scriptPreview.Text = "No script generated yet."; scriptPreview.TextColor3 = Color3.fromRGB(150,220,150); scriptPreview.Font = Enum.Font.Code; scriptPreview.TextSize = 11; scriptPreview.TextWrapped = true; scriptPreview.TextXAlignment = Enum.TextXAlignment.Left; scriptPreview.Parent = scriptScroll
local execBtn = Instance.new("TextButton"); execBtn.Size = UDim2.new(1,0,0,26); execBtn.Position = UDim2.new(0,0,1,-26); execBtn.BackgroundColor3 = GREEN; execBtn.Text = "Execute Script"; execBtn.TextColor3 = Color3.new(1,1,1); execBtn.Font = Enum.Font.GothamBold; execBtn.TextSize = 12; execBtn.BorderSizePixel = 0; execBtn.Parent = scriptPanel
corner(execBtn)

local lastScript = nil
execBtn.MouseButton1Click:Connect(function()
	if not lastScript or lastScript == "" then return end
	local ok, err = pcall(loadstring(lastScript))
	if not ok then warn("[AIAssistant] Execute error: " .. tostring(err)) end
end)

-- input bar
local inputBg = Instance.new("Frame"); inputBg.Size = UDim2.new(1,-16,0,44); inputBg.Position = UDim2.new(0,8,1,-50); inputBg.BackgroundColor3 = PANEL; inputBg.BorderSizePixel = 0; inputBg.Parent = frame
corner(inputBg); stroke(inputBg)
local inputBox = Instance.new("TextBox"); inputBox.Size = UDim2.new(1,-50,1,-8); inputBox.Position = UDim2.new(0,8,0,4); inputBox.BackgroundTransparency = 1; inputBox.PlaceholderText = "Ask something..."; inputBox.PlaceholderColor3 = MUTED; inputBox.Text = ""; inputBox.TextColor3 = TEXT; inputBox.Font = Enum.Font.Gotham; inputBox.TextSize = 12; inputBox.ClearTextOnFocus = false; inputBox.MultiLine = false; inputBox.TextXAlignment = Enum.TextXAlignment.Left; inputBox.Parent = inputBg
local sendBtn = Instance.new("TextButton"); sendBtn.Size = UDim2.new(0,36,0,30); sendBtn.Position = UDim2.new(1,-42,0,7); sendBtn.BackgroundColor3 = ACCENT; sendBtn.Text = "▶"; sendBtn.TextColor3 = Color3.new(1,1,1); sendBtn.Font = Enum.Font.GothamBold; sendBtn.TextSize = 14; sendBtn.BorderSizePixel = 0; sendBtn.Parent = inputBg
corner(sendBtn, 5)

-- status
local statusLbl = Instance.new("TextLabel"); statusLbl.Size = UDim2.new(0.6,0,0,12); statusLbl.Position = UDim2.new(0,8,1,-13); statusLbl.BackgroundTransparency = 1; statusLbl.Text = ""; statusLbl.TextColor3 = MUTED; statusLbl.Font = Enum.Font.Gotham; statusLbl.TextSize = 10; statusLbl.TextXAlignment = Enum.TextXAlignment.Left; statusLbl.Parent = frame

-- ============================================================
-- TAB SWITCHING
-- ============================================================
local tabs = {
	{btn=tabChat,   panel=chatScroll},
	{btn=tabRemote, panel=remotePanel},
	{btn=tabDex,    panel=dexPanel},
	{btn=tabScript, panel=scriptPanel},
}
local function switchTab(idx)
	for i, t in ipairs(tabs) do
		t.panel.Visible = (i == idx)
		t.btn.BackgroundColor3 = (i == idx) and ACCENT or Color3.fromRGB(35,35,50)
		t.btn.TextColor3 = (i == idx) and Color3.new(1,1,1) or MUTED
	end
	if idx == 2 then remoteTxt.Text = getRemoteContext() end
	if idx == 3 then task.spawn(function() dexTxt.Text = getDexContext() end) end
end
switchTab(1)
for i, t in ipairs(tabs) do t.btn.MouseButton1Click:Connect(function() switchTab(i) end) end

-- ============================================================
-- CHAT BUBBLES
-- ============================================================
local msgOrder = 0
local function addBubble(text, isUser, isSystem)
	msgOrder = msgOrder + 1
	local bg = isUser and Color3.fromRGB(55,75,190) or (isSystem and Color3.fromRGB(50,40,20) or PANEL)
	local bubble = Instance.new("Frame"); bubble.BackgroundColor3 = bg; bubble.BorderSizePixel = 0; bubble.AutomaticSize = Enum.AutomaticSize.Y; bubble.Size = UDim2.new(1,0,0,0); bubble.LayoutOrder = msgOrder; bubble.Parent = chatScroll
	corner(bubble); pad(bubble, 6, 6, 8, 8)
	local lbl = Instance.new("TextLabel", bubble); lbl.Size = UDim2.new(1,0,0,0); lbl.AutomaticSize = Enum.AutomaticSize.Y; lbl.BackgroundTransparency = 1
	local prefix = isUser and "[You] " or (isSystem and "[System] " or ("[" .. CFG.provider .. "] "))
	lbl.Text = prefix .. text; lbl.TextColor3 = isUser and Color3.fromRGB(230,235,255) or (isSystem and Color3.fromRGB(220,180,100) or TEXT); lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12; lbl.TextWrapped = true; lbl.TextXAlignment = Enum.TextXAlignment.Left
	task.defer(function() chatScroll.CanvasPosition = Vector2.new(0, chatScroll.AbsoluteCanvasSize.Y) end)
end

-- ============================================================
-- SEND
-- ============================================================
local busy = false
local function sendMessage(extraPrefix)
	if busy then return end
	local text = inputBox.Text:match("^%s*(.-)%s*$")
	if text == "" then return end
	inputBox.Text = ""
	local fullText = extraPrefix and (extraPrefix .. "\n\n" .. text) or text
	addBubble(text, true)
	table.insert(history, { role = "user", content = fullText })
	busy = true; statusLbl.Text = "Waiting for " .. CFG.provider .. "..."
	sendBtn.BackgroundColor3 = Color3.fromRGB(50,50,80)

	task.spawn(function()
		local req = buildRequest(history)
		local ok, res = pcall(request, req)
		if ok and res then
			local reply, err = parseResponse(res.Body, res.StatusCode)
			if reply then
				table.insert(history, { role = "assistant", content = reply })
				-- check for script block
				local script = extractScript(reply)
				if script then
					lastScript = script
					local displayText = reply:gsub("<SCRIPT>.-</SCRIPT>", "[Script generated — see Script tab]")
					addBubble(displayText, false)
					addBubble("Script detected. Switch to the Script tab to review and execute.", false, true)
				else
					addBubble(reply, false)
				end
				saveSession()
			else
				addBubble("Error: " .. tostring(err), false, true)
				table.remove(history, #history)
			end
		else
			addBubble("Request failed: " .. tostring(res), false, true)
			table.remove(history, #history)
		end
		busy = false; statusLbl.Text = ""; sendBtn.BackgroundColor3 = ACCENT
	end)
end

sendBtn.MouseButton1Click:Connect(function() sendMessage() end)
inputBox.FocusLost:Connect(function(enter) if enter then sendMessage() end end)

injectRemoteBtn.MouseButton1Click:Connect(function()
	local ctx = getRemoteContext()
	switchTab(1)
	addBubble("[RemoteSpy injected — type your request below]", false, true)
	table.insert(history, { role = "user", content = ctx })
	table.insert(history, { role = "assistant", content = "Remote context received. What would you like me to do with these remotes?" })
	addBubble("Remote context received. What would you like me to do with these remotes?", false)
end)

injectDexBtn.MouseButton1Click:Connect(function()
	local ctx = getDexContext()
	switchTab(1)
	addBubble("[Dex snapshot injected — type your request below]", false, true)
	table.insert(history, { role = "user", content = ctx })
	table.insert(history, { role = "assistant", content = "Dex snapshot received. What would you like me to do with this instance tree?" })
	addBubble("Dex snapshot received. What would you like me to do with this instance tree?", false)
end)

-- ============================================================
-- SESSIONS PANEL (simple overlay)
-- ============================================================
local sessOverlay = Instance.new("Frame"); sessOverlay.Size = UDim2.new(1,0,1,0); sessOverlay.BackgroundColor3 = Color3.fromRGB(10,10,15); sessOverlay.BackgroundTransparency = 0.1; sessOverlay.BorderSizePixel = 0; sessOverlay.Visible = false; sessOverlay.ZIndex = 10; sessOverlay.Parent = frame
corner(sessOverlay)
pad(sessOverlay, 8)
local sessTitle = Instance.new("TextLabel", sessOverlay); sessTitle.Size = UDim2.new(1,0,0,24); sessTitle.BackgroundTransparency = 1; sessTitle.Text = "Saved Sessions"; sessTitle.TextColor3 = TEXT; sessTitle.Font = Enum.Font.GothamBold; sessTitle.TextSize = 13; sessTitle.TextXAlignment = Enum.TextXAlignment.Left
local sessClose = Instance.new("TextButton", sessOverlay); sessClose.Size = UDim2.new(0,60,0,22); sessClose.Position = UDim2.new(1,-60,0,1); sessClose.BackgroundColor3 = RED; sessClose.Text = "Close"; sessClose.TextColor3 = Color3.new(1,1,1); sessClose.Font = Enum.Font.Gotham; sessClose.TextSize = 11; sessClose.BorderSizePixel = 0
corner(sessClose, 4)
sessClose.MouseButton1Click:Connect(function() sessOverlay.Visible = false end)
local sessScroll = Instance.new("ScrollingFrame", sessOverlay); sessScroll.Size = UDim2.new(1,0,1,-32); sessScroll.Position = UDim2.new(0,0,0,32); sessScroll.BackgroundTransparency = 1; sessScroll.BorderSizePixel = 0; sessScroll.ScrollBarThickness = 3; sessScroll.CanvasSize = UDim2.new(0,0,0,0); sessScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
local sessListLayout = Instance.new("UIListLayout", sessScroll); sessListLayout.Padding = UDim.new(0,4)

sessBtn.MouseButton1Click:Connect(function()
	-- clear old list
	for _, c in ipairs(sessScroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	local files = listSessions()
	if #files == 0 then
		local lbl = Instance.new("TextLabel", sessScroll); lbl.Size = UDim2.new(1,0,0,24); lbl.BackgroundTransparency = 1; lbl.Text = "No sessions saved yet."; lbl.TextColor3 = MUTED; lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12
	else
		for _, f in ipairs(files) do
			local btn = Instance.new("TextButton", sessScroll); btn.Size = UDim2.new(1,0,0,28); btn.BackgroundColor3 = PANEL; btn.Text = f:match("([^/\\]+)$") or f; btn.TextColor3 = TEXT; btn.Font = Enum.Font.Gotham; btn.TextSize = 11; btn.BorderSizePixel = 0; btn.TextTruncate = Enum.TextTruncate.AtEnd
			corner(btn, 4)
			btn.MouseButton1Click:Connect(function()
				if loadSession(f) then
					history = history -- already set
					providerBtn.Text = CFG.provider
					-- redraw chat
					for _, c in ipairs(chatScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
					msgOrder = 0
					for _, m in ipairs(history) do addBubble(m.content:sub(1,200), m.role == "user") end
					sessOverlay.Visible = false
					switchTab(1)
					addBubble("Session loaded: " .. (sessionMeta.game or "?") .. " | " .. (sessionMeta.date or "?"), false, true)
				end
			end)
		end
	end
	sessOverlay.Visible = true
end)

-- ============================================================
-- DRAG
-- ============================================================
local dragging, dragStart, startPos
tb.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = i.Position; startPos = frame.Position end end)
tb.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then local d = i.Position - dragStart; frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y) end end)

-- ============================================================
-- INIT
-- ============================================================
initSession()
addBubble("Ready | Game: " .. getGameName() .. " | Provider: " .. CFG.provider, false, true)
addBubble("Use the RemoteSpy and Dex tabs to inject context, then ask me to generate a script.", false, true)
