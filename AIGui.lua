-- AIGui.lua
-- Rayfield-inspired AI Script GUI
-- Modules: RemoteSpy, Dex Explorer, ScriptBlox/RScripts, AI Chat

--// Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer
local LPName = LP and LP.Name or "User"

--// UNC Helpers
local function safeRequest(opts)
    local ok, res = pcall(request or (syn and syn.request) or http_request or error, opts)
    if ok and res then return res end
    return nil
end

local function readFileSafe(path)
    local ok, data = pcall(readfile, path)
    return ok and data or nil
end

local function writeFileSafe(path, data)
    pcall(writefile, path, data)
end

local function appendFileSafe(path, data)
    pcall(appendfile, path, data)
end

local function isFileSafe(path)
    local ok, res = pcall(isfile, path)
    return ok and res
end

local function makeFolderSafe(path)
    pcall(makefolder, path)
end

--// Folders & Paths
makeFolderSafe("AIGui")
local SETTINGS_PATH   = "AIGui/settings.json"
local AGENTS_PATH     = "AIGui/agents.json"
local CACHE_PATH      = "AIGui/cache.json"
local INSTRUCT_PATH   = "AIGui/instructions.txt"
local INSTRUCT_URL    = "https://raw.githubusercontent.com/DeflectEncrypt/xoajne/refs/heads/main/Instruction.txt"
local FONT_PATH       = "AIGui/font.ttf"
local FONT_URL        = "" -- placeholder, user fills

--// Default Settings
local DEFAULT_SETTINGS = {
    autoExecute  = false,
    autoSwitch   = true,
    theme        = "dark",
    fontPath     = FONT_PATH,
}

--// Load / Save Helpers
local function loadJSON(path, default)
    local raw = readFileSafe(path)
    if raw and raw ~= "" then
        local ok, t = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok then return t end
    end
    return default
end

local function saveJSON(path, t)
    local ok, enc = pcall(HttpService.JSONEncode, HttpService, t)
    if ok then writeFileSafe(path, enc) end
end

--// State
local Settings = loadJSON(SETTINGS_PATH, DEFAULT_SETTINGS)
local Agents   = loadJSON(AGENTS_PATH,   {list = {}})
local Cache    = loadJSON(CACHE_PATH,    {remotes = {}, dex = {}, fetched = {}})

local function saveSettings() saveJSON(SETTINGS_PATH, Settings) end
local function saveAgents()   saveJSON(AGENTS_PATH,   Agents)   end
local function saveCache()    saveJSON(CACHE_PATH,    Cache)    end

--// Instructions
local function loadInstructions()
    if isFileSafe(INSTRUCT_PATH) then
        local d = readFileSafe(INSTRUCT_PATH)
        if d and d ~= "" then return d end
    end
    local res = safeRequest({Url = INSTRUCT_URL, Method = "GET"})
    if res and res.Body and res.Body ~= "" then
        writeFileSafe(INSTRUCT_PATH, res.Body)
        return res.Body
    end
    return "You are an Roblox Exploit Luau scripter running inside a user executor environment."
end

local SystemPrompt = loadInstructions()

--// Custom Font
local function getCustomFont()
    local ok, asset = pcall(getcustomasset, FONT_PATH)
    if ok and asset then return Font.new(asset) end
    return Font.new("rbxasset://fonts/families/RobotoMono.json")
end

local CustomFont = getCustomFont()

--// Icon Helper (pcall getcustomasset)
local function getIcon(path)
    local ok, asset = pcall(getcustomasset, path)
    if ok and asset then return asset end
    return ""
end

--// RemoteSpy State
local RemoteLog = {}
local RemoteHooks = {}
local SpyActive = false

local function startRemoteSpy()
    if SpyActive then return end
    SpyActive = true
    local function hookRemote(rem)
        if RemoteHooks[rem] then return end
        local t = rem.ClassName
        if t == "RemoteEvent" then
            local ok1, orig1 = pcall(hookfunction, rem.FireServer, function(...)
                table.insert(RemoteLog, {type="FireServer", name=rem.Name, path=rem:GetFullName(), args={...}, time=os.clock()})
                saveCache()
                return orig1(...)
            end)
            local ok2, orig2 = pcall(hookfunction, rem.OnClientEvent, function(...)
                table.insert(RemoteLog, {type="OnClientEvent", name=rem.Name, path=rem:GetFullName(), args={...}, time=os.clock()})
                saveCache()
            end)
            RemoteHooks[rem] = true
        elseif t == "RemoteFunction" then
            local ok3, orig3 = pcall(hookfunction, rem.InvokeServer, function(...)
                table.insert(RemoteLog, {type="InvokeServer", name=rem.Name, path=rem:GetFullName(), args={...}, time=os.clock()})
                saveCache()
                return orig3(...)
            end)
            local ok4 = pcall(function()
                rem.OnClientInvoke = function(...)
                    table.insert(RemoteLog, {type="OnClientInvoke", name=rem.Name, path=rem:GetFullName(), args={...}, time=os.clock()})
                    saveCache()
                end
            end)
            RemoteHooks[rem] = true
        end
    end
    for _, v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            pcall(hookRemote, v)
        end
    end
    game.DescendantAdded:Connect(function(v)
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            pcall(hookRemote, v)
        end
    end)
end

local function stopRemoteSpy()
    SpyActive = false
    RemoteHooks = {}
end

local function getRemoteLogSummary(limit)
    limit = limit or 20
    local lines = {}
    local start = math.max(1, #RemoteLog - limit + 1)
    for i = start, #RemoteLog do
        local e = RemoteLog[i]
        table.insert(lines, string.format("[%s] %s (%s)", e.type, e.name, e.path))
    end
    return table.concat(lines, "\n")
end

--// Dex Explorer Helpers
local function dexGetChildren(inst)
    if not inst then return {} end
    local ok, ch = pcall(function() return inst:GetChildren() end)
    return ok and ch or {}
end

local function dexGetDescendants(inst)
    if not inst then return {} end
    local ok, d = pcall(function() return inst:GetDescendants() end)
    return ok and d or {}
end

local function dexFind(inst, name)
    if not inst then return nil end
    local ok, res = pcall(function() return inst:FindFirstChild(name, true) end)
    return ok and res or nil
end

local function dexGetProperty(inst, prop)
    local ok, val = pcall(function() return inst[prop] end)
    return ok and tostring(val) or "N/A"
end

local function dexSummary(inst, depth)
    depth = depth or 0
    if depth > 3 then return "" end
    local lines = {}
    local ch = dexGetChildren(inst)
    for _, c in ipairs(ch) do
        table.insert(lines, string.rep("  ", depth) .. c.ClassName .. " [" .. c.Name .. "]")
        if depth < 2 then
            local sub = dexSummary(c, depth + 1)
            if sub ~= "" then table.insert(lines, sub) end
        end
    end
    return table.concat(lines, "\n")
end

local function buildGameContext()
    local lines = {"=== GAME CONTEXT ==="}
    table.insert(lines, "PlaceId: " .. tostring(game.PlaceId))
    table.insert(lines, "GameId: " .. tostring(game.GameId))
    table.insert(lines, "LocalPlayer: " .. LPName)
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            table.insert(lines, "WalkSpeed: " .. tostring(hum.WalkSpeed))
            table.insert(lines, "Health: " .. tostring(hum.Health))
        end
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            local p = root.Position
            table.insert(lines, string.format("Position: %.1f, %.1f, %.1f", p.X, p.Y, p.Z))
        end
    end
    table.insert(lines, "\n=== WORKSPACE TREE (depth 2) ===")
    table.insert(lines, dexSummary(workspace, 0))
    table.insert(lines, "\n=== RECENT REMOTES (last 20) ===")
    table.insert(lines, getRemoteLogSummary(20))
    return table.concat(lines, "\n")
end

--// ScriptBlox / RScripts API
local function fetchScriptBlox(query, page)
    page = page or 1
    local url = "https://scriptblox.com/api/script/search?q=" .. HttpService:UrlEncode(query) .. "&page=" .. page
    local res = safeRequest({Url = url, Method = "GET"})
    if res and res.Body then
        local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if ok and data and data.result and data.result.scripts then
            local out = {}
            for i, s in ipairs(data.result.scripts) do
                if i > 5 then break end
                table.insert(out, string.format("[%d] %s | Game: %s\n%s", i, s.title or "?", tostring(s.game and s.game.name or "?"), s.script or ""))
            end
            return table.concat(out, "\n---\n")
        end
    end
    return "No results from ScriptBlox."
end

local function fetchRScripts(query, page)
    page = page or 1
    local url = "https://rscripts.net/api/scripts?q=" .. HttpService:UrlEncode(query) .. "&page=" .. page
    local res = safeRequest({Url = url, Method = "GET"})
    if res and res.Body then
        local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
        if ok and data then
            local list = data.scripts or data.data or data
            if type(list) == "table" then
                local out = {}
                for i, s in ipairs(list) do
                    if i > 5 then break end
                    table.insert(out, string.format("[%d] %s\n%s", i, s.title or s.name or "?", s.script or s.content or ""))
                end
                return table.concat(out, "\n---\n")
            end
        end
    end
    return "No results from RScripts."
end

--// AI Providers
local PROVIDERS = {
    HuggingFace = {
        name = "HuggingFace",
        call = function(agent, messages)
            local body = HttpService:JSONEncode({
                model   = agent.model,
                messages = messages,
                max_tokens = 1024,
            })
            local res = safeRequest({
                Url     = "https://api-inference.huggingface.co/v1/chat/completions",
                Method  = "POST",
                Headers = {["Authorization"] = "Bearer " .. agent.apiKey, ["Content-Type"] = "application/json"},
                Body    = body,
            })
            if res and res.Body then
                local ok, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and d and d.choices then return d.choices[1].message.content, res.StatusCode end
            end
            return nil, res and res.StatusCode or 0
        end,
    },
    Google = {
        name = "Google",
        call = function(agent, messages)
            local parts = {}
            for _, m in ipairs(messages) do
                if m.role ~= "system" then
                    table.insert(parts, {role = m.role == "assistant" and "model" or "user", parts = {{text = m.content}}})
                end
            end
            local body = HttpService:JSONEncode({contents = parts})
            local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. agent.model .. ":generateContent?key=" .. agent.apiKey
            local res = safeRequest({Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = body})
            if res and res.Body then
                local ok, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and d and d.candidates then return d.candidates[1].content.parts[1].text, res.StatusCode end
            end
            return nil, res and res.StatusCode or 0
        end,
    },
    Anthropic = {
        name = "Anthropic",
        call = function(agent, messages)
            local sys = ""
            local msgs = {}
            for _, m in ipairs(messages) do
                if m.role == "system" then sys = m.content
                else table.insert(msgs, {role = m.role, content = m.content}) end
            end
            local body = HttpService:JSONEncode({model = agent.model, max_tokens = 1024, system = sys, messages = msgs})
            local res = safeRequest({
                Url     = "https://api.anthropic.com/v1/messages",
                Method  = "POST",
                Headers = {["x-api-key"] = agent.apiKey, ["anthropic-version"] = "2023-06-01", ["Content-Type"] = "application/json"},
                Body    = body,
            })
            if res and res.Body then
                local ok, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and d and d.content then return d.content[1].text, res.StatusCode end
            end
            return nil, res and res.StatusCode or 0
        end,
    },
    OpenAI = {
        name = "OpenAI",
        call = function(agent, messages)
            local body = HttpService:JSONEncode({model = agent.model, messages = messages, max_tokens = 1024})
            local res = safeRequest({
                Url     = "https://api.openai.com/v1/chat/completions",
                Method  = "POST",
                Headers = {["Authorization"] = "Bearer " .. agent.apiKey, ["Content-Type"] = "application/json"},
                Body    = body,
            })
            if res and res.Body then
                local ok, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and d and d.choices then return d.choices[1].message.content, res.StatusCode end
            end
            return nil, res and res.StatusCode or 0
        end,
    },
    Grok = {
        name = "Grok",
        call = function(agent, messages)
            local body = HttpService:JSONEncode({model = agent.model or "grok-3-latest", messages = messages, max_tokens = 1024})
            local res = safeRequest({
                Url     = "https://api.x.ai/v1/chat/completions",
                Method  = "POST",
                Headers = {["Authorization"] = "Bearer " .. agent.apiKey, ["Content-Type"] = "application/json"},
                Body    = body,
            })
            if res and res.Body then
                local ok, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and d and d.choices then return d.choices[1].message.content, res.StatusCode end
            end
            return nil, res and res.StatusCode or 0
        end,
    },
    DeepSeek = {
        name = "DeepSeek",
        call = function(agent, messages)
            local body = HttpService:JSONEncode({model = agent.model or "deepseek-chat", messages = messages, max_tokens = 1024})
            local res = safeRequest({
                Url     = "https://api.deepseek.com/v1/chat/completions",
                Method  = "POST",
                Headers = {["Authorization"] = "Bearer " .. agent.apiKey, ["Content-Type"] = "application/json"},
                Body    = body,
            })
            if res and res.Body then
                local ok, d = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and d and d.choices then return d.choices[1].message.content, res.StatusCode end
            end
            return nil, res and res.StatusCode or 0
        end,
    },
}

--// Chat History
local ChatHistory = {}

local function isRateLimited(statusCode)
    return statusCode == 429 or statusCode == 503
end

local function callAI(userMessage)
    if #Agents.list == 0 then return nil, "NO_AGENTS" end

    local gameCtx = buildGameContext()
    local fullSystem = SystemPrompt .. "\n\n" .. gameCtx

    local messages = {{role = "system", content = fullSystem}}
    for _, m in ipairs(ChatHistory) do table.insert(messages, m) end
    table.insert(messages, {role = "user", content = userMessage})

    local startIdx = 1
    -- find current active agent index
    for i, ag in ipairs(Agents.list) do
        if ag.active then startIdx = i break end
    end

    for i = startIdx, #Agents.list do
        local agent = Agents.list[i]
        local provider = PROVIDERS[agent.provider]
        if not provider then continue end
        local reply, code = provider.call(agent, messages)
        if reply then
            table.insert(ChatHistory, {role = "user",      content = userMessage})
            table.insert(ChatHistory, {role = "assistant", content = reply})
            if #ChatHistory > 40 then table.remove(ChatHistory, 1) table.remove(ChatHistory, 1) end
            agent.active = true
            saveAgents()
            return reply, nil, i > startIdx and i or nil -- nil switch idx if same agent
        elseif isRateLimited(code) and Settings.autoSwitch then
            agent.active = false
            -- switched, continue loop
        else
            return nil, "ERROR_" .. tostring(code)
        end
    end
    return nil, "ALL_RATELIMITED"
end

--// Auto-execute
if Settings.autoExecute then
    pcall(function()
        local script_content = readFileSafe("AIGui/autoexec.lua")
        if script_content then
            queueonteleport(script_content)
        end
    end)
end

--// GUI Construction
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name         = "AIGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = CoreGui end)
if not ScreenGui.Parent then ScreenGui.Parent = LP.PlayerGui end

--// Theme
local T = {
    bg       = Color3.fromRGB(13,  13,  18),
    surface  = Color3.fromRGB(20,  20,  28),
    surface2 = Color3.fromRGB(26,  26,  36),
    border   = Color3.fromRGB(40,  40,  58),
    accent   = Color3.fromRGB(88,  130, 255),
    accentD  = Color3.fromRGB(60,  90,  200),
    text     = Color3.fromRGB(230, 230, 240),
    textMute = Color3.fromRGB(120, 120, 150),
    danger   = Color3.fromRGB(220, 60,  60),
    success  = Color3.fromRGB(60,  200, 100),
    white    = Color3.fromRGB(255, 255, 255),
}

local function mkStroke(parent, thickness, color, transparency)
    local s = Instance.new("UIStroke")
    s.Thickness    = thickness or 1
    s.Color        = color or T.border
    s.Transparency = transparency or 0
    s.Parent       = parent
    return s
end

local function mkCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent       = parent
    return c
end

local function mkPad(parent, t, b, l, r)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, t or 6)
    p.PaddingBottom = UDim.new(0, b or 6)
    p.PaddingLeft   = UDim.new(0, l or 8)
    p.PaddingRight  = UDim.new(0, r or 8)
    p.Parent        = parent
    return p
end

local function mkLabel(parent, text, size, color, xalign)
    local l = Instance.new("TextLabel")
    l.Text              = text
    l.TextSize          = size or 14
    l.TextColor3        = color or T.text
    l.BackgroundTransparency = 1
    l.FontFace          = CustomFont
    l.TextXAlignment    = xalign or Enum.TextXAlignment.Left
    l.TextWrapped       = true
    l.Size              = UDim2.new(1, 0, 0, size and size + 6 or 20)
    l.Parent            = parent
    return l
end

local function mkButton(parent, text, bgColor, textColor)
    local b = Instance.new("TextButton")
    b.Text           = text
    b.TextSize       = 13
    b.TextColor3     = textColor or T.white
    b.BackgroundColor3 = bgColor or T.accent
    b.FontFace       = CustomFont
    b.AutoButtonColor = false
    b.Size           = UDim2.new(1, 0, 0, 32)
    mkCorner(b, 6)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = T.accentD end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = bgColor or T.accent end)
    b.Parent         = parent
    return b
end

local function mkToggle(parent, label, state, onChange)
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 36)
    row.Parent = parent

    local lbl = mkLabel(row, label, 13, T.text)
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.TextYAlignment = Enum.TextYAlignment.Center

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 42, 0, 22)
    track.Position = UDim2.new(1, -46, 0.5, -11)
    track.BackgroundColor3 = state and T.accent or T.border
    mkCorner(track, 11)
    track.Parent = row

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = T.white
    mkCorner(knob, 9)
    knob.Parent = track

    local current = state
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = row
    btn.MouseButton1Click:Connect(function()
        current = not current
        track.BackgroundColor3 = current and T.accent or T.border
        knob.Position = current and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
        onChange(current)
    end)
    return row
end

--// Main Window
local Main = Instance.new("Frame")
Main.Size              = UDim2.new(0, 520, 0, 540)
Main.Position          = UDim2.new(0.5, -260, 0.5, -270)
Main.BackgroundColor3  = T.bg
Main.BorderSizePixel   = 0
mkCorner(Main, 12)
mkStroke(Main, 1, T.border)
Main.Parent            = ScreenGui

--// Drag
local dragging, dragStart, startPos
Main.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = i.Position
        startPos  = Main.Position
    end
end)
Main.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
game:GetService("UserInputService").InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = i.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

--// Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1, 0, 0, 44)
TitleBar.BackgroundColor3 = T.surface
mkCorner(TitleBar, 12)
TitleBar.Parent           = Main
mkStroke(TitleBar, 1, T.border)

local TitleLabel = mkLabel(TitleBar, "AI  GUI", 15, T.text, Enum.TextXAlignment.Left)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.Size     = UDim2.new(0.5, 0, 1, 0)
TitleLabel.TextYAlignment = Enum.TextYAlignment.Center

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size              = UDim2.new(0, 28, 0, 28)
CloseBtn.Position          = UDim2.new(1, -36, 0.5, -14)
CloseBtn.Text              = "✕"
CloseBtn.TextSize          = 13
CloseBtn.TextColor3        = T.textMute
CloseBtn.BackgroundColor3  = T.surface2
CloseBtn.FontFace          = CustomFont
mkCorner(CloseBtn, 6)
CloseBtn.Parent            = TitleBar
CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

--// Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Size             = UDim2.new(0, 52, 1, -44)
Sidebar.Position         = UDim2.new(0, 0, 0, 44)
Sidebar.BackgroundColor3 = T.surface
Sidebar.BorderSizePixel  = 0
Sidebar.Parent           = Main

local SideList = Instance.new("UIListLayout")
SideList.FillDirection   = Enum.FillDirection.Vertical
SideList.HorizontalAlignment = Enum.HorizontalAlignment.Center
SideList.Padding         = UDim.new(0, 4)
SideList.Parent          = Sidebar
Instance.new("UIPadding", Sidebar).PaddingTop = UDim.new(0, 8)

--// Content Area
local Content = Instance.new("Frame")
Content.Size             = UDim2.new(1, -52, 1, -44)
Content.Position         = UDim2.new(0, 52, 0, 44)
Content.BackgroundColor3 = T.bg
Content.BorderSizePixel  = 0
Content.Parent           = Main

--// Tab System
local Tabs = {}
local TabFrames = {}
local ActiveTab = nil

local TAB_DEFS = {
    {id = "agents",     icon = "🤖", iconPath = "AIGui/icons/agents.png"},
    {id = "history",    icon = "💬", iconPath = "AIGui/icons/history.png"},
    {id = "management", icon = "⚙️",  iconPath = "AIGui/icons/management.png"},
    {id = "settings",   icon = "🔧", iconPath = "AIGui/icons/settings.png"},
}

local function showTab(id)
    for tid, frame in pairs(TabFrames) do
        frame.Visible = (tid == id)
    end
    for tid, btn in pairs(Tabs) do
        btn.BackgroundColor3 = (tid == id) and T.accent or Color3.fromRGB(0,0,0)
        btn.BackgroundTransparency = (tid == id) and 0 or 1
    end
    ActiveTab = id
end

for _, def in ipairs(TAB_DEFS) do
    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(0, 40, 0, 40)
    btn.Text               = def.icon
    btn.TextSize           = 18
    btn.TextColor3         = T.text
    btn.BackgroundColor3   = T.accent
    btn.BackgroundTransparency = 1
    btn.FontFace           = CustomFont
    mkCorner(btn, 8)

    -- try icon image
    local img = Instance.new("ImageLabel")
    img.Size               = UDim2.new(0.6, 0, 0.6, 0)
    img.Position           = UDim2.new(0.2, 0, 0.2, 0)
    img.BackgroundTransparency = 1
    img.ScaleType          = Enum.ScaleType.Fit
    local ok, asset = pcall(getcustomasset, def.iconPath)
    if ok and asset and asset ~= "" then
        img.Image  = asset
        btn.Text   = ""
    end
    img.Parent = btn
    btn.Parent = Sidebar

    local frame = Instance.new("Frame")
    frame.Size             = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Visible          = false
    frame.Parent           = Content
    TabFrames[def.id] = frame

    Tabs[def.id] = btn
    btn.MouseButton1Click:Connect(function() showTab(def.id) end)
end

--// ════════════════════════════════
--// TAB 1 — AGENTS (Chat)
--// ════════════════════════════════
local AgentFrame = TabFrames["agents"]

-- No-agent screen
local NoAgentScreen = Instance.new("Frame")
NoAgentScreen.Size             = UDim2.new(1, 0, 1, 0)
NoAgentScreen.BackgroundTransparency = 1
NoAgentScreen.Visible          = true
NoAgentScreen.Parent           = AgentFrame

local naList = Instance.new("UIListLayout", NoAgentScreen)
naList.FillDirection = Enum.FillDirection.Vertical
naList.HorizontalAlignment = Enum.HorizontalAlignment.Center
naList.VerticalAlignment   = Enum.VerticalAlignment.Center
naList.Padding             = UDim.new(0, 6)

local naTitle = mkLabel(NoAgentScreen, "Hello", 22, T.text, Enum.TextXAlignment.Center)
naTitle.Size = UDim2.new(1, 0, 0, 30)

local naSub = mkLabel(NoAgentScreen, LPName, 14, T.textMute, Enum.TextXAlignment.Center)
naSub.Size = UDim2.new(1, 0, 0, 20)

local naMsg = mkLabel(NoAgentScreen, "You don't have an AI api implemented yet.\nPlease consider going to ", 12, T.textMute, Enum.TextXAlignment.Center)
naMsg.TextTransparency = 0.4
naMsg.Size = UDim2.new(1, -20, 0, 40)

local naLink = Instance.new("TextButton")
naLink.Size = UDim2.new(0, 130, 0, 20)
naLink.BackgroundTransparency = 1
naLink.Text = "AI Management"
naLink.TextSize = 12
naLink.TextColor3 = T.accent
naLink.FontFace = CustomFont
naLink.Parent = NoAgentScreen
local naUD = Instance.new("UITextDecoration") -- underline via stroke hack
-- simple underline with stroke
naLink.MouseButton1Click:Connect(function() showTab("management") end)

-- Chat screen
local ChatScreen = Instance.new("Frame")
ChatScreen.Size             = UDim2.new(1, 0, 1, 0)
ChatScreen.BackgroundTransparency = 1
ChatScreen.Visible          = false
ChatScreen.Parent           = AgentFrame

-- Header
local chatHeader = Instance.new("Frame")
chatHeader.Size             = UDim2.new(1, 0, 0, 64)
chatHeader.BackgroundTransparency = 1
chatHeader.Parent           = ChatScreen

local chatTitle = mkLabel(chatHeader, "Welcome", 20, T.text)
chatTitle.Position = UDim2.new(0, 12, 0, 6)
chatTitle.Size     = UDim2.new(1, -12, 0, 26)

local chatSub = mkLabel(chatHeader, LPName, 13, T.textMute)
chatSub.Position = UDim2.new(0, 12, 0, 30)
chatSub.Size     = UDim2.new(1, -12, 0, 18)

local chatPrompt = mkLabel(chatHeader, "How can I assist you today?", 12, T.textMute)
chatPrompt.TextTransparency = 0.4
chatPrompt.Position         = UDim2.new(0, 12, 0, 46)
chatPrompt.Size             = UDim2.new(1, -12, 0, 16)

-- Message scroll
local MsgScroll = Instance.new("ScrollingFrame")
MsgScroll.Size              = UDim2.new(1, -16, 1, -130)
MsgScroll.Position          = UDim2.new(0, 8, 0, 66)
MsgScroll.BackgroundTransparency = 1
MsgScroll.ScrollBarThickness = 3
MsgScroll.ScrollBarImageColor3 = T.border
MsgScroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
MsgScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
MsgScroll.Parent            = ChatScreen

local MsgList = Instance.new("UIListLayout", MsgScroll)
MsgList.FillDirection = Enum.FillDirection.Vertical
MsgList.Padding       = UDim.new(0, 6)
Instance.new("UIPadding", MsgScroll).PaddingTop = UDim.new(0, 4)

-- Rate-limit warning bar
local RLWarn = Instance.new("Frame")
RLWarn.Size             = UDim2.new(1, -16, 0, 0)
RLWarn.Position         = UDim2.new(0, 8, 1, -125)
RLWarn.BackgroundColor3 = T.danger
RLWarn.Visible          = false
mkCorner(RLWarn, 6)
RLWarn.Parent           = ChatScreen

local RLText = mkLabel(RLWarn, "", 11, T.white)
RLText.Position = UDim2.new(0, 8, 0, 4)
RLText.Size     = UDim2.new(1, -16, 1, -8)

local RLBtnRow = Instance.new("Frame")
RLBtnRow.Size             = UDim2.new(1, 0, 0, 30)
RLBtnRow.Position         = UDim2.new(0, 0, 1, -32)
RLBtnRow.BackgroundTransparency = 1
RLBtnRow.Parent           = RLWarn

local RLContinue = Instance.new("TextButton")
RLContinue.Size = UDim2.new(0.48, 0, 1, 0)
RLContinue.Position = UDim2.new(0.01, 0, 0, 0)
RLContinue.Text = "Continue"
RLContinue.TextSize = 11
RLContinue.TextColor3 = T.white
RLContinue.BackgroundColor3 = T.accentD
RLContinue.FontFace = CustomFont
mkCorner(RLContinue, 4)
RLContinue.Parent = RLBtnRow

local RLNew = Instance.new("TextButton")
RLNew.Size = UDim2.new(0.48, 0, 1, 0)
RLNew.Position = UDim2.new(0.51, 0, 0, 0)
RLNew.Text = "New Chat"
RLNew.TextSize = 11
RLNew.TextColor3 = T.white
RLNew.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
RLNew.FontFace = CustomFont
mkCorner(RLNew, 4)
RLNew.Parent = RLBtnRow

RLContinue.MouseButton1Click:Connect(function() RLWarn.Visible = false end)
RLNew.MouseButton1Click:Connect(function()
    RLWarn.Visible = false
    ChatHistory = {}
    for _, c in ipairs(MsgScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
end)

-- Input row
local InputRow = Instance.new("Frame")
InputRow.Size             = UDim2.new(1, -16, 0, 40)
InputRow.Position         = UDim2.new(0, 8, 1, -50)
InputRow.BackgroundColor3 = T.surface2
InputRow.Parent           = ChatScreen
mkCorner(InputRow, 8)
mkStroke(InputRow, 1, T.border)

local ChatInput = Instance.new("TextBox")
ChatInput.Size              = UDim2.new(1, -48, 1, 0)
ChatInput.Position          = UDim2.new(0, 8, 0, 0)
ChatInput.BackgroundTransparency = 1
ChatInput.Text              = ""
ChatInput.PlaceholderText   = "Message..."
ChatInput.PlaceholderColor3 = T.textMute
ChatInput.TextColor3        = T.text
ChatInput.TextSize          = 13
ChatInput.FontFace          = CustomFont
ChatInput.TextXAlignment    = Enum.TextXAlignment.Left
ChatInput.ClearTextOnFocus  = false
ChatInput.Parent            = InputRow

local SendBtn = Instance.new("TextButton")
SendBtn.Size              = UDim2.new(0, 38, 0, 32)
SendBtn.Position          = UDim2.new(1, -42, 0.5, -16)
SendBtn.Text              = "↑"
SendBtn.TextSize          = 16
SendBtn.TextColor3        = T.white
SendBtn.BackgroundColor3  = T.accent
SendBtn.FontFace          = CustomFont
mkCorner(SendBtn, 6)
SendBtn.Parent            = InputRow

-- Spy toggle
local SpyToggleBtn = Instance.new("TextButton")
SpyToggleBtn.Size             = UDim2.new(1, -16, 0, 24)
SpyToggleBtn.Position         = UDim2.new(0, 8, 1, -22)
SpyToggleBtn.Text             = "[ RemoteSpy: OFF ]"
SpyToggleBtn.TextSize         = 11
SpyToggleBtn.TextColor3       = T.textMute
SpyToggleBtn.BackgroundTransparency = 1
SpyToggleBtn.FontFace         = CustomFont
SpyToggleBtn.Parent           = ChatScreen
SpyToggleBtn.MouseButton1Click:Connect(function()
    if SpyActive then
        stopRemoteSpy()
        SpyToggleBtn.Text = "[ RemoteSpy: OFF ]"
        SpyToggleBtn.TextColor3 = T.textMute
    else
        startRemoteSpy()
        SpyToggleBtn.Text = "[ RemoteSpy: ON ]"
        SpyToggleBtn.TextColor3 = T.success
    end
end)

-- Add message bubble
local function addBubble(text, isUser)
    local bubble = Instance.new("Frame")
    bubble.Size             = UDim2.new(1, 0, 0, 0)
    bubble.AutomaticSize    = Enum.AutomaticSize.Y
    bubble.BackgroundColor3 = isUser and T.accent or T.surface2
    bubble.BackgroundTransparency = isUser and 0 or 0
    mkCorner(bubble, 8)
    mkPad(bubble, 6, 6, 10, 10)

    local lbl = Instance.new("TextLabel")
    lbl.Size              = UDim2.new(1, 0, 0, 0)
    lbl.AutomaticSize     = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.Text              = text
    lbl.TextSize          = 12
    lbl.TextColor3        = T.text
    lbl.FontFace          = CustomFont
    lbl.TextXAlignment    = Enum.TextXAlignment.Left
    lbl.TextWrapped       = true
    lbl.RichText          = false
    lbl.Parent            = bubble

    bubble.Parent = MsgScroll
    task.wait()
    MsgScroll.CanvasPosition = Vector2.new(0, MsgScroll.AbsoluteCanvasSize.Y)
    return bubble
end

local Thinking = nil
local function setThinking(on)
    if on then
        Thinking = addBubble("...", false)
    else
        if Thinking then Thinking:Destroy() Thinking = nil end
    end
end

local function updateAgentUI()
    local hasAgents = #Agents.list > 0
    NoAgentScreen.Visible = not hasAgents
    ChatScreen.Visible    = hasAgents
end

local function sendMessage()
    local msg = ChatInput.Text
    if msg == "" or msg == nil then return end
    ChatInput.Text = ""
    addBubble(msg, true)
    setThinking(true)
    task.spawn(function()
        local reply, err, switchedIdx = callAI(msg)
        setThinking(false)
        if reply then
            if switchedIdx then
                local newAgent = Agents.list[switchedIdx]
                RLText.Text = "Rate limited. Switched to agent: " .. (newAgent and newAgent.model or "?") .. ". Would you like to continue or start a new chat?"
                RLWarn.Size = UDim2.new(1, -16, 0, 70)
                RLWarn.Visible = true
            end
            addBubble(reply, false)
        elseif err == "NO_AGENTS" then
            addBubble("No agents configured. Go to AI Management.", false)
        elseif err == "ALL_RATELIMITED" then
            RLText.Text = "All agents are rate limited. No backup available."
            RLWarn.Size = UDim2.new(1, -16, 0, 36)
            RLBtnRow.Visible = false
            RLWarn.Visible = true
        else
            addBubble("Error: " .. tostring(err), false)
        end
    end)
end

SendBtn.MouseButton1Click:Connect(sendMessage)
ChatInput.FocusLost:Connect(function(enter) if enter then sendMessage() end end)

--// ════════════════════════════════
--// TAB 2 — HISTORY
--// ════════════════════════════════
local HistFrame = TabFrames["history"]

local histScroll = Instance.new("ScrollingFrame")
histScroll.Size              = UDim2.new(1, -16, 1, -50)
histScroll.Position          = UDim2.new(0, 8, 0, 8)
histScroll.BackgroundTransparency = 1
histScroll.ScrollBarThickness = 3
histScroll.ScrollBarImageColor3 = T.border
histScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
histScroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
histScroll.Parent            = HistFrame

local histList = Instance.new("UIListLayout", histScroll)
histList.FillDirection = Enum.FillDirection.Vertical
histList.Padding       = UDim.new(0, 4)

local histClear = mkButton(HistFrame, "Clear History", T.danger, T.white)
histClear.Size     = UDim2.new(1, -16, 0, 28)
histClear.Position = UDim2.new(0, 8, 1, -36)
histClear.MouseButton1Click:Connect(function()
    ChatHistory = {}
    for _, c in ipairs(histScroll:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
    end
end)

local function refreshHistory()
    for _, c in ipairs(histScroll:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
    end
    for _, m in ipairs(ChatHistory) do
        local lbl = mkLabel(histScroll, "[" .. m.role .. "] " .. m.content, 11, m.role == "user" and T.accent or T.text)
        lbl.Size = UDim2.new(1, 0, 0, 0)
        lbl.AutomaticSize = Enum.AutomaticSize.Y
    end
end

Tabs["history"].MouseButton1Click:Connect(refreshHistory)

--// ════════════════════════════════
--// TAB 3 — AI MANAGEMENT
--// ════════════════════════════════
local MgmtFrame = TabFrames["management"]

local agentScroll = Instance.new("ScrollingFrame")
agentScroll.Size              = UDim2.new(1, -16, 1, -60)
agentScroll.Position          = UDim2.new(0, 8, 0, 8)
agentScroll.BackgroundTransparency = 1
agentScroll.ScrollBarThickness = 3
agentScroll.ScrollBarImageColor3 = T.border
agentScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
agentScroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
agentScroll.Parent            = MgmtFrame

local agentList = Instance.new("UIListLayout", agentScroll)
agentList.FillDirection = Enum.FillDirection.Vertical
agentList.Padding       = UDim.new(0, 6)

local AddNewBtn = mkButton(MgmtFrame, "+ Add New AI", T.accent, T.white)
AddNewBtn.Size     = UDim2.new(1, -16, 0, 32)
AddNewBtn.Position = UDim2.new(0, 8, 1, -42)

-- Provider picker popup
local ProviderPicker = Instance.new("Frame")
ProviderPicker.Size             = UDim2.new(0, 300, 0, 320)
ProviderPicker.Position         = UDim2.new(0.5, -150, 0.5, -160)
ProviderPicker.BackgroundColor3 = T.surface
ProviderPicker.Visible          = false
mkCorner(ProviderPicker, 10)
mkStroke(ProviderPicker, 1, T.border)
ProviderPicker.ZIndex           = 10
ProviderPicker.Parent           = ScreenGui

local ppTitle = mkLabel(ProviderPicker, "Select Provider", 15, T.text, Enum.TextXAlignment.Center)
ppTitle.Position = UDim2.new(0, 0, 0, 10)
ppTitle.Size     = UDim2.new(1, 0, 0, 24)

local ppClose = Instance.new("TextButton")
ppClose.Size = UDim2.new(0, 24, 0, 24)
ppClose.Position = UDim2.new(1, -30, 0, 8)
ppClose.Text = "✕"
ppClose.TextSize = 12
ppClose.TextColor3 = T.textMute
ppClose.BackgroundTransparency = 1
ppClose.FontFace = CustomFont
ppClose.Parent = ProviderPicker
ppClose.MouseButton1Click:Connect(function() ProviderPicker.Visible = false end)

local ppList = Instance.new("UIListLayout")
ppList.FillDirection = Enum.FillDirection.Vertical
ppList.HorizontalAlignment = Enum.HorizontalAlignment.Center
ppList.Padding = UDim.new(0, 4)
ppList.Parent = ProviderPicker
Instance.new("UIPadding", ProviderPicker).PaddingTop = UDim.new(0, 40)

-- Config popup
local ConfigPopup = Instance.new("Frame")
ConfigPopup.Size             = UDim2.new(0, 300, 0, 200)
ConfigPopup.Position         = UDim2.new(0.5, -150, 0.5, -100)
ConfigPopup.BackgroundColor3 = T.surface
ConfigPopup.Visible          = false
mkCorner(ConfigPopup, 10)
mkStroke(ConfigPopup, 1, T.border)
ConfigPopup.ZIndex           = 11
ConfigPopup.Parent           = ScreenGui

local cfgTitle = mkLabel(ConfigPopup, "Configure Agent", 14, T.text, Enum.TextXAlignment.Center)
cfgTitle.Position = UDim2.new(0, 0, 0, 10)
cfgTitle.Size     = UDim2.new(1, 0, 0, 22)

local cfgPad = Instance.new("UIPadding", ConfigPopup)
cfgPad.PaddingLeft = UDim.new(0, 12)
cfgPad.PaddingRight = UDim.new(0, 12)
cfgPad.PaddingTop = UDim.new(0, 40)

local function mkInputBox(parent, placeholder, yOff)
    local box = Instance.new("TextBox")
    box.Size              = UDim2.new(1, 0, 0, 30)
    box.Position          = UDim2.new(0, 0, 0, yOff)
    box.BackgroundColor3  = T.surface2
    box.TextColor3        = T.text
    box.PlaceholderColor3 = T.textMute
    box.PlaceholderText   = placeholder
    box.Text              = ""
    box.TextSize          = 12
    box.FontFace          = CustomFont
    box.TextXAlignment    = Enum.TextXAlignment.Left
    box.ClearTextOnFocus  = false
    mkCorner(box, 6)
    mkPad(box, 4, 4, 8, 8)
    box.Parent = parent
    return box
end

local cfgApiKey  = mkInputBox(ConfigPopup, "API Key", 0)
local cfgModel   = mkInputBox(ConfigPopup, "Model (e.g. gpt-4o)", 36)

local cfgSave = mkButton(ConfigPopup, "Add Agent", T.accent, T.white)
cfgSave.Position = UDim2.new(0, 0, 0, 78)
cfgSave.Size     = UDim2.new(1, 0, 0, 30)

local cfgCancel = mkButton(ConfigPopup, "Cancel", T.surface2, T.textMute)
cfgCancel.Position = UDim2.new(0, 0, 0, 114)
cfgCancel.Size     = UDim2.new(1, 0, 0, 30)
cfgCancel.MouseButton1Click:Connect(function() ConfigPopup.Visible = false end)

local selectedProvider = nil

-- Confirm delete popup
local ConfirmPopup = Instance.new("Frame")
ConfirmPopup.Size             = UDim2.new(0, 280, 0, 120)
ConfirmPopup.Position         = UDim2.new(0.5, -140, 0.5, -60)
ConfirmPopup.BackgroundColor3 = T.surface
ConfirmPopup.Visible          = false
mkCorner(ConfirmPopup, 10)
mkStroke(ConfirmPopup, 1, T.danger)
ConfirmPopup.ZIndex           = 12
ConfirmPopup.Parent           = ScreenGui

mkLabel(ConfirmPopup, "Are you sure? This cannot be undone.", 12, T.text, Enum.TextXAlignment.Center).Position = UDim2.new(0, 10, 0, 16)
local confirmYes = mkButton(ConfirmPopup, "Delete", T.danger, T.white)
confirmYes.Size     = UDim2.new(0.45, 0, 0, 30)
confirmYes.Position = UDim2.new(0.05, 0, 0, 60)
local confirmNo  = mkButton(ConfirmPopup, "Cancel", T.surface2, T.text)
confirmNo.Size     = UDim2.new(0.45, 0, 0, 30)
confirmNo.Position = UDim2.new(0.51, 0, 0, 60)
confirmNo.MouseButton1Click:Connect(function() ConfirmPopup.Visible = false end)

local pendingDeleteIdx = nil

local function refreshAgentList()
    for _, c in ipairs(agentScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i, agent in ipairs(Agents.list) do
        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, 0, 0, 40)
        row.BackgroundColor3 = T.surface2
        mkCorner(row, 8)
        mkStroke(row, 1, T.border)
        row.Parent           = agentScroll

        local nameLbl = mkLabel(row, "[" .. agent.provider .. "] " .. agent.model, 12, T.text)
        nameLbl.Position = UDim2.new(0, 10, 0, 0)
        nameLbl.Size     = UDim2.new(1, -50, 1, 0)
        nameLbl.TextYAlignment = Enum.TextYAlignment.Center

        local delBtn = Instance.new("TextButton")
        delBtn.Size             = UDim2.new(0, 30, 0, 30)
        delBtn.Position         = UDim2.new(1, -38, 0.5, -15)
        delBtn.Text             = "✕"
        delBtn.TextSize         = 13
        delBtn.TextColor3       = T.danger
        delBtn.BackgroundTransparency = 1
        delBtn.FontFace         = CustomFont
        delBtn.Parent           = row

        local idx = i
        delBtn.MouseButton1Click:Connect(function()
            pendingDeleteIdx = idx
            ConfirmPopup.Visible = true
        end)
    end
    updateAgentUI()
end

confirmYes.MouseButton1Click:Connect(function()
    if pendingDeleteIdx then
        table.remove(Agents.list, pendingDeleteIdx)
        saveAgents()
        pendingDeleteIdx = nil
        ConfirmPopup.Visible = false
        refreshAgentList()
    end
end)

local PROVIDER_NAMES = {"HuggingFace", "Google", "Anthropic", "OpenAI", "Grok", "DeepSeek"}
for _, pname in ipairs(PROVIDER_NAMES) do
    local pb = mkButton(ProviderPicker, pname, T.surface2, T.text)
    pb.Size     = UDim2.new(0.85, 0, 0, 28)
    pb.MouseButton1Click:Connect(function()
        selectedProvider = pname
        cfgTitle.Text   = "Configure: " .. pname
        cfgApiKey.Text  = ""
        cfgModel.Text   = ""
        ProviderPicker.Visible = false
        ConfigPopup.Visible    = true
    end)
end

cfgSave.MouseButton1Click:Connect(function()
    local key   = cfgApiKey.Text
    local model = cfgModel.Text
    if key == "" or model == "" or not selectedProvider then return end
    table.insert(Agents.list, {provider = selectedProvider, apiKey = key, model = model, active = false})
    saveAgents()
    ConfigPopup.Visible = false
    refreshAgentList()
end)

AddNewBtn.MouseButton1Click:Connect(function()
    ProviderPicker.Visible = true
end)

refreshAgentList()

--// ════════════════════════════════
--// TAB 4 — SETTINGS
--// ════════════════════════════════
local SetFrame = TabFrames["settings"]

local setScroll = Instance.new("ScrollingFrame")
setScroll.Size              = UDim2.new(1, -16, 1, -50)
setScroll.Position          = UDim2.new(0, 8, 0, 8)
setScroll.BackgroundTransparency = 1
setScroll.ScrollBarThickness = 3
setScroll.ScrollBarImageColor3 = T.border
setScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
setScroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
setScroll.Parent            = SetFrame

local setList = Instance.new("UIListLayout", setScroll)
setList.FillDirection = Enum.FillDirection.Vertical
setList.Padding       = UDim.new(0, 6)
Instance.new("UIPadding", setScroll).PaddingTop = UDim.new(0, 6)

mkToggle(setScroll, "Auto-Execute (queueonteleport)", Settings.autoExecute, function(v)
    Settings.autoExecute = v
    saveSettings()
    if v then
        local s = readFileSafe("AIGui/autoexec.lua")
        if s then pcall(queueonteleport, s) end
    end
end)

mkToggle(setScroll, "Auto-Switch on Rate Limit", Settings.autoSwitch, function(v)
    Settings.autoSwitch = v
    saveSettings()
end)

-- Customise Instructions
local custBtn = mkButton(setScroll, "Customise Instructions", T.surface2, T.text)
custBtn.MouseButton1Click:Connect(function()
    -- Instruction popup
    local ipop = Instance.new("Frame")
    ipop.Size             = UDim2.new(0, 320, 0, 260)
    ipop.Position         = UDim2.new(0.5, -160, 0.5, -130)
    ipop.BackgroundColor3 = T.surface
    ipop.ZIndex           = 13
    mkCorner(ipop, 10)
    mkStroke(ipop, 1, T.border)
    ipop.Parent           = ScreenGui

    mkLabel(ipop, "Edit Instructions", 14, T.text, Enum.TextXAlignment.Center).Position = UDim2.new(0, 0, 0, 10)

    local ibox = Instance.new("TextBox")
    ibox.Size              = UDim2.new(1, -20, 0, 160)
    ibox.Position          = UDim2.new(0, 10, 0, 40)
    ibox.BackgroundColor3  = T.surface2
    ibox.TextColor3        = T.text
    ibox.PlaceholderText   = "Instructions..."
    ibox.Text              = SystemPrompt
    ibox.TextSize          = 11
    ibox.FontFace          = CustomFont
    ibox.TextXAlignment    = Enum.TextXAlignment.Left
    ibox.TextYAlignment    = Enum.TextYAlignment.Top
    ibox.ClearTextOnFocus  = false
    ibox.MultiLine         = true
    ibox.TextWrapped       = true
    mkCorner(ibox, 6)
    mkPad(ibox, 6, 6, 8, 8)
    ibox.Parent            = ipop

    local isave = mkButton(ipop, "Save", T.accent, T.white)
    isave.Size     = UDim2.new(0.45, 0, 0, 28)
    isave.Position = UDim2.new(0.05, 0, 0, 212)
    isave.MouseButton1Click:Connect(function()
        SystemPrompt = ibox.Text
        writeFileSafe(INSTRUCT_PATH, SystemPrompt)
        print("[AIGui] Instructions saved to AIGui/instructions.txt — edit that file directly to make further changes.")
        ipop:Destroy()
    end)

    local icancel = mkButton(ipop, "Cancel", T.surface2, T.text)
    icancel.Size     = UDim2.new(0.45, 0, 0, 28)
    icancel.Position = UDim2.new(0.52, 0, 0, 212)
    icancel.MouseButton1Click:Connect(function() ipop:Destroy() end)
end)

-- Clear Cache
local clearBtn = mkButton(setScroll, "Clear Cache", T.surface2, T.text)
clearBtn.MouseButton1Click:Connect(function()
    Cache = {remotes = {}, dex = {}, fetched = {}}
    RemoteLog = {}
    saveCache()
    clearBtn.Text = "Cleared!"
    task.delay(2, function() clearBtn.Text = "Clear Cache" end)
end)

-- Fetch Debug
local debugBtn = mkButton(setScroll, "Fetch Debug (Copy to Clipboard)", T.surface2, T.text)
debugBtn.MouseButton1Click:Connect(function()
    local info = {
        agents    = #Agents.list,
        remotes   = #RemoteLog,
        spyActive = SpyActive,
        settings  = Settings,
        timestamp = os.clock(),
    }
    local ok, enc = pcall(HttpService.JSONEncode, HttpService, info)
    if ok then pcall(setclipboard, enc) end
    debugBtn.Text = "Copied!"
    task.delay(2, function() debugBtn.Text = "Fetch Debug (Copy to Clipboard)" end)
end)

-- Hello label
local helloLbl = mkLabel(SetFrame, "Hello..!", 11, T.textMute, Enum.TextXAlignment.Right)
helloLbl.TextTransparency = 0.4
helloLbl.Position         = UDim2.new(0, 0, 1, -24)
helloLbl.Size             = UDim2.new(1, -10, 0, 20)

--// Init
showTab("agents")
updateAgentUI()
