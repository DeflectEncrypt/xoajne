-- AIGui.lua
-- Rayfield-inspired AI Script GUI
-- Modules: RemoteSpy, Dex Explorer, ScriptBlox/RScripts, AI Chat

--// Services
local Players     = game:GetService("Players")
local HttpService  = game:GetService("HttpService")
local CoreGui     = game:GetService("CoreGui")
local UIS         = game:GetService("UserInputService")

local LP      = Players.LocalPlayer
local LPName  = LP and LP.Name or "User"

--// UNC Helpers
local function safeRequest(opts)
    local fn = request or (syn and syn.request) or http_request
    if not fn then return nil end
    local ok, res = pcall(fn, opts)
    return ok and res or nil
end
local function readFileSafe(path)  local ok,d=pcall(readfile,path) return ok and d or nil end
local function writeFileSafe(p,d)  pcall(writefile,p,d) end
local function isFileSafe(path)    local ok,r=pcall(isfile,path) return ok and r end
local function mkFolderSafe(path)  pcall(makefolder,path) end

--// Folder structure
mkFolderSafe("zrxc")
mkFolderSafe("zrxc/AI")

local SETTINGS_PATH  = "zrxc/settings.json"
local AGENTS_PATH    = "zrxc/AI/AI.json"
local CONVO_PATH     = "zrxc/AI/conservation.json"
local INSTRUCT_PATH  = "zrxc/AI/instructions.txt"
local INSTRUCT_URL   = "https://raw.githubusercontent.com/DeflectEncrypt/xoajne/refs/heads/main/Instruction.txt"
local FONT_PATH      = "zrxc/font.ttf"

--// JSON helpers
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

--// Settings
local DEFAULT_SETTINGS = {autoExecute=false, autoSwitch=true}
local Settings = loadJSON(SETTINGS_PATH, DEFAULT_SETTINGS)
local function saveSettings() saveJSON(SETTINGS_PATH, Settings) end

--// Agents  {list=[{id,provider,model,apiKey,active}], nextId=N}
local Agents = loadJSON(AGENTS_PATH, nil)
if type(Agents) ~= "table" or not Agents.list then
    Agents = {list={}, nextId=1}
end
Agents.nextId = Agents.nextId or (#Agents.list + 1)

local function writeAgentFile()
    if #Agents.list == 0 then
        writeFileSafe(AGENTS_PATH, '--[[ There is no agents yet, please add a valid AI --]]')
    else
        saveJSON(AGENTS_PATH, Agents)
    end
end

--// Conversation
local ConvoData  = loadJSON(CONVO_PATH, {history={}})
local ChatHistory = ConvoData.history or {}
local function saveConvo() saveJSON(CONVO_PATH, {history=ChatHistory}) end

--// Instructions
local function loadInstructions()
    if isFileSafe(INSTRUCT_PATH) then
        local d = readFileSafe(INSTRUCT_PATH)
        if d and d ~= "" then return d end
    end
    local res = safeRequest({Url=INSTRUCT_URL, Method="GET"})
    if res and res.Body and res.Body ~= "" then
        writeFileSafe(INSTRUCT_PATH, res.Body)
        return res.Body
    end
    return "You are a Roblox Exploit Luau scripter running inside a user executor environment."
end
local SystemPrompt = loadInstructions()

--// Font
local function getCustomFont()
    local ok, asset = pcall(getcustomasset, FONT_PATH)
    if ok and asset and asset ~= "" then return Font.new(asset) end
    return Font.new("rbxasset://fonts/families/RobotoMono.json")
end
local CF = getCustomFont()

local function getIcon(path)
    local ok, asset = pcall(getcustomasset, path)
    return ok and asset or ""
end

--// RemoteSpy
local RemoteLog   = {}
local RemoteHooks = {}
local SpyActive   = false

local function startRemoteSpy()
    if SpyActive then return end
    SpyActive = true
    local function hookRem(rem)
        if RemoteHooks[rem] then return end
        RemoteHooks[rem] = true
        if rem.ClassName == "RemoteEvent" then
            pcall(hookfunction, rem.FireServer, newcclosure(function(...)
                table.insert(RemoteLog, {type="FireServer",    name=rem.Name, path=rem:GetFullName(), t=os.clock()})
            end))
            pcall(function()
                rem.OnClientEvent:Connect(function(...)
                    table.insert(RemoteLog, {type="OnClientEvent", name=rem.Name, path=rem:GetFullName(), t=os.clock()})
                end)
            end)
        elseif rem.ClassName == "RemoteFunction" then
            pcall(hookfunction, rem.InvokeServer, newcclosure(function(...)
                table.insert(RemoteLog, {type="InvokeServer",  name=rem.Name, path=rem:GetFullName(), t=os.clock()})
            end))
            pcall(function()
                rem.OnClientInvoke = function(...)
                    table.insert(RemoteLog, {type="OnClientInvoke", name=rem.Name, path=rem:GetFullName(), t=os.clock()})
                end
            end)
        end
    end
    for _, v in ipairs(game:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then pcall(hookRem, v) end
    end
    game.DescendantAdded:Connect(function(v)
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then pcall(hookRem, v) end
    end)
end

local function stopRemoteSpy() SpyActive=false RemoteHooks={} end

local function remoteLogSummary(n)
    n = n or 20
    local lines = {}
    for i = math.max(1, #RemoteLog-n+1), #RemoteLog do
        local e = RemoteLog[i]
        lines[#lines+1] = ("[%s] %s (%s)"):format(e.type, e.name, e.path)
    end
    return #lines>0 and table.concat(lines,"\n") or "No remotes logged."
end

--// Dex helpers
local function dexChildren(inst)
    local ok,r = pcall(function() return inst:GetChildren() end)
    return ok and r or {}
end
local function dexSummary(inst, depth)
    depth = depth or 0
    if depth > 2 then return "" end
    local lines = {}
    for _, c in ipairs(dexChildren(inst)) do
        lines[#lines+1] = string.rep("  ",depth)..c.ClassName.." ["..c.Name.."]"
        local sub = dexSummary(c, depth+1)
        if sub ~= "" then lines[#lines+1] = sub end
    end
    return table.concat(lines,"\n")
end

local function buildContext()
    local lines = {"=== GAME CONTEXT ===",
        "PlaceId: "..tostring(game.PlaceId),
        "LocalPlayer: "..LPName}
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            lines[#lines+1] = "WalkSpeed: "..tostring(hum.WalkSpeed)
            lines[#lines+1] = "Health: "..tostring(hum.Health)
        end
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            local p = root.Position
            lines[#lines+1] = ("Position: %.1f, %.1f, %.1f"):format(p.X,p.Y,p.Z)
        end
    end
    lines[#lines+1] = "\n=== WORKSPACE (depth 2) ==="
    lines[#lines+1] = dexSummary(workspace)
    lines[#lines+1] = "\n=== REMOTE LOG (last 20) ==="
    lines[#lines+1] = remoteLogSummary()
    return table.concat(lines,"\n")
end

--// ScriptBlox / RScripts
local function fetchScriptBlox(q)
    local res = safeRequest({Url="https://scriptblox.com/api/script/search?q="..HttpService:UrlEncode(q).."&page=1",Method="GET"})
    if res and res.Body then
        local ok,d = pcall(HttpService.JSONDecode,HttpService,res.Body)
        if ok and d and d.result and d.result.scripts then
            local out={}
            for i,s in ipairs(d.result.scripts) do
                if i>5 then break end
                out[#out+1] = ("[%d] %s\n%s"):format(i,s.title or "?",s.script or "")
            end
            return table.concat(out,"\n---\n")
        end
    end
    return "No results from ScriptBlox."
end
local function fetchRScripts(q)
    local res = safeRequest({Url="https://rscripts.net/api/scripts?q="..HttpService:UrlEncode(q).."&page=1",Method="GET"})
    if res and res.Body then
        local ok,d = pcall(HttpService.JSONDecode,HttpService,res.Body)
        if ok and d then
            local list = d.scripts or d.data or d
            if type(list)=="table" then
                local out={}
                for i,s in ipairs(list) do
                    if i>5 then break end
                    out[#out+1] = ("[%d] %s\n%s"):format(i,s.title or s.name or "?",s.script or s.content or "")
                end
                return table.concat(out,"\n---\n")
            end
        end
    end
    return "No results from RScripts."
end

--// AI Providers
local PROVIDERS = {
    HuggingFace = function(ag, msgs)
        local res = safeRequest({Url="https://api-inference.huggingface.co/v1/chat/completions",Method="POST",
            Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode({model=ag.model,messages=msgs,max_tokens=1024})})
        if res and res.Body then local ok,d=pcall(HttpService.JSONDecode,HttpService,res.Body) if ok and d and d.choices then return d.choices[1].message.content,res.StatusCode end end
        return nil, res and res.StatusCode or 0
    end,
    Google = function(ag, msgs)
        local parts={}
        for _,m in ipairs(msgs) do if m.role~="system" then parts[#parts+1]={role=m.role=="assistant" and "model" or "user",parts={{text=m.content}}} end end
        local res = safeRequest({Url="https://generativelanguage.googleapis.com/v1beta/models/"..ag.model..":generateContent?key="..ag.apiKey,
            Method="POST",Headers={["Content-Type"]="application/json"},Body=HttpService:JSONEncode({contents=parts})})
        if res and res.Body then local ok,d=pcall(HttpService.JSONDecode,HttpService,res.Body) if ok and d and d.candidates then return d.candidates[1].content.parts[1].text,res.StatusCode end end
        return nil, res and res.StatusCode or 0
    end,
    Anthropic = function(ag, msgs)
        local sys,fmsgs="",{}
        for _,m in ipairs(msgs) do if m.role=="system" then sys=m.content else fmsgs[#fmsgs+1]=m end end
        local res = safeRequest({Url="https://api.anthropic.com/v1/messages",Method="POST",
            Headers={["x-api-key"]=ag.apiKey,["anthropic-version"]="2023-06-01",["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode({model=ag.model,max_tokens=1024,system=sys,messages=fmsgs})})
        if res and res.Body then local ok,d=pcall(HttpService.JSONDecode,HttpService,res.Body) if ok and d and d.content then return d.content[1].text,res.StatusCode end end
        return nil, res and res.StatusCode or 0
    end,
    OpenAI = function(ag, msgs)
        local res = safeRequest({Url="https://api.openai.com/v1/chat/completions",Method="POST",
            Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode({model=ag.model,messages=msgs,max_tokens=1024})})
        if res and res.Body then local ok,d=pcall(HttpService.JSONDecode,HttpService,res.Body) if ok and d and d.choices then return d.choices[1].message.content,res.StatusCode end end
        return nil, res and res.StatusCode or 0
    end,
    Grok = function(ag, msgs)
        local res = safeRequest({Url="https://api.x.ai/v1/chat/completions",Method="POST",
            Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode({model=ag.model or "grok-3-latest",messages=msgs,max_tokens=1024})})
        if res and res.Body then local ok,d=pcall(HttpService.JSONDecode,HttpService,res.Body) if ok and d and d.choices then return d.choices[1].message.content,res.StatusCode end end
        return nil, res and res.StatusCode or 0
    end,
    DeepSeek = function(ag, msgs)
        local res = safeRequest({Url="https://api.deepseek.com/v1/chat/completions",Method="POST",
            Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},
            Body=HttpService:JSONEncode({model=ag.model or "deepseek-chat",messages=msgs,max_tokens=1024})})
        if res and res.Body then local ok,d=pcall(HttpService.JSONDecode,HttpService,res.Body) if ok and d and d.choices then return d.choices[1].message.content,res.StatusCode end end
        return nil, res and res.StatusCode or 0
    end,
}

local function isRL(code) return code==429 or code==503 end

local function callAI(userMsg)
    if #Agents.list==0 then return nil,"NO_AGENTS" end
    local sys = SystemPrompt.."\n\n"..buildContext()
    local msgs = {{role="system",content=sys}}
    for _,m in ipairs(ChatHistory) do msgs[#msgs+1]=m end
    msgs[#msgs+1] = {role="user",content=userMsg}

    local startIdx=1
    for i,ag in ipairs(Agents.list) do if ag.active then startIdx=i break end end

    for i=startIdx,#Agents.list do
        local ag=Agents.list[i]
        local fn=PROVIDERS[ag.provider]
        if not fn then continue end
        local reply,code=fn(ag,msgs)
        if reply then
            ChatHistory[#ChatHistory+1]={role="user",content=userMsg}
            ChatHistory[#ChatHistory+1]={role="assistant",content=reply}
            if #ChatHistory>40 then table.remove(ChatHistory,1) table.remove(ChatHistory,1) end
            for _,a in ipairs(Agents.list) do a.active=false end
            ag.active=true
            writeAgentFile() saveConvo()
            return reply,nil,i>startIdx and i or nil
        elseif isRL(code) and Settings.autoSwitch then
            ag.active=false
        else
            return nil,"ERROR_"..tostring(code)
        end
    end
    return nil,"ALL_RATELIMITED"
end

--// Auto-execute
if Settings.autoExecute then
    pcall(function() local s=readFileSafe("zrxc/autoexec.lua") if s then queueonteleport(s) end end)
end

--// GUI setup
local ScreenGui=Instance.new("ScreenGui")
ScreenGui.Name="AIGui" ScreenGui.ResetOnSpawn=false ScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
if not pcall(function() ScreenGui.Parent=CoreGui end) then ScreenGui.Parent=LP.PlayerGui end

local T={
    bg=Color3.fromRGB(13,13,18), surface=Color3.fromRGB(20,20,28), surface2=Color3.fromRGB(26,26,36),
    border=Color3.fromRGB(40,40,58), accent=Color3.fromRGB(88,130,255), accentD=Color3.fromRGB(60,90,200),
    text=Color3.fromRGB(230,230,240), textMute=Color3.fromRGB(120,120,150),
    danger=Color3.fromRGB(220,60,60), success=Color3.fromRGB(60,200,100), white=Color3.fromRGB(255,255,255),
}

local function corner(p,r)   local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 8) c.Parent=p return c end
local function stroke(p,t,c) local s=Instance.new("UIStroke") s.Thickness=t or 1 s.Color=c or T.border s.Parent=p return s end
local function pad(p,t,b,l,r)
    local u=Instance.new("UIPadding")
    u.PaddingTop=UDim.new(0,t or 6) u.PaddingBottom=UDim.new(0,b or 6)
    u.PaddingLeft=UDim.new(0,l or 8) u.PaddingRight=UDim.new(0,r or 8)
    u.Parent=p return u
end
local function listLayout(p,dir,halign,valign,padding)
    local l=Instance.new("UIListLayout") l.FillDirection=dir or Enum.FillDirection.Vertical
    l.HorizontalAlignment=halign or Enum.HorizontalAlignment.Left
    l.VerticalAlignment=valign or Enum.VerticalAlignment.Top
    if padding then l.Padding=UDim.new(0,padding) end
    l.Parent=p return l
end

local function mkLabel(parent,text,size,color,xalign)
    local l=Instance.new("TextLabel")
    l.Text=text l.TextSize=size or 14 l.TextColor3=color or T.text
    l.BackgroundTransparency=1 l.FontFace=CF l.TextWrapped=true
    l.TextXAlignment=xalign or Enum.TextXAlignment.Left
    l.Size=UDim2.new(1,0,0,(size or 14)+6) l.Parent=parent return l
end

local function mkBtn(parent,text,bg,tc)
    local b=Instance.new("TextButton")
    b.Text=text b.TextSize=13 b.TextColor3=tc or T.white b.BackgroundColor3=bg or T.accent
    b.FontFace=CF b.AutoButtonColor=false b.Size=UDim2.new(1,0,0,32) corner(b,6)
    local orig=bg or T.accent
    b.MouseEnter:Connect(function() b.BackgroundColor3=Color3.new(orig.R*.82,orig.G*.82,orig.B*.82) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3=orig end)
    b.Parent=parent return b
end

local function mkToggle(parent,label,state,onChange)
    local row=Instance.new("Frame") row.BackgroundTransparency=1 row.Size=UDim2.new(1,0,0,36) row.Parent=parent
    local lbl=mkLabel(row,label,13,T.text) lbl.Size=UDim2.new(1,-54,1,0) lbl.TextYAlignment=Enum.TextYAlignment.Center
    local track=Instance.new("Frame") track.Size=UDim2.new(0,42,0,22) track.Position=UDim2.new(1,-46,0.5,-11)
    track.BackgroundColor3=state and T.accent or T.border corner(track,11) track.Parent=row
    local knob=Instance.new("Frame") knob.Size=UDim2.new(0,18,0,18)
    knob.Position=state and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
    knob.BackgroundColor3=T.white corner(knob,9) knob.Parent=track
    local cur=state
    local btn=Instance.new("TextButton") btn.Size=UDim2.new(1,0,1,0) btn.BackgroundTransparency=1 btn.Text="" btn.Parent=row
    btn.MouseButton1Click:Connect(function()
        cur=not cur track.BackgroundColor3=cur and T.accent or T.border
        knob.Position=cur and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
        onChange(cur)
    end)
    return row
end

local function mkTextBox(parent,placeholder,multiline)
    local b=Instance.new("TextBox")
    b.Size=UDim2.new(1,0,0,multiline and 130 or 30)
    b.BackgroundColor3=T.surface2 b.TextColor3=T.text b.PlaceholderColor3=T.textMute
    b.PlaceholderText=placeholder b.Text="" b.TextSize=12 b.FontFace=CF
    b.TextXAlignment=Enum.TextXAlignment.Left
    b.TextYAlignment=multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
    b.ClearTextOnFocus=false b.MultiLine=multiline or false b.TextWrapped=multiline or false
    corner(b,6) pad(b,5,5,8,8) b.Parent=parent return b
end

local function scrollFrame(parent,size,pos)
    local s=Instance.new("ScrollingFrame")
    s.Size=size s.Position=pos or UDim2.new(0,8,0,8)
    s.BackgroundTransparency=1 s.ScrollBarThickness=3 s.ScrollBarImageColor3=T.border
    s.AutomaticCanvasSize=Enum.AutomaticSize.Y s.CanvasSize=UDim2.new(0,0,0,0)
    s.Parent=parent return s
end

--// Main window
local Main=Instance.new("Frame")
Main.Size=UDim2.new(0,520,0,540) Main.Position=UDim2.new(0.5,-260,0.5,-270)
Main.BackgroundColor3=T.bg Main.BorderSizePixel=0 corner(Main,12) stroke(Main,1,T.border)
Main.Parent=ScreenGui

local dragging,dStart,dPos
Main.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true dStart=i.Position dPos=Main.Position end end)
Main.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-dStart Main.Position=UDim2.new(dPos.X.Scale,dPos.X.Offset+d.X,dPos.Y.Scale,dPos.Y.Offset+d.Y)
    end
end)

--// Title bar
local TBar=Instance.new("Frame") TBar.Size=UDim2.new(1,0,0,44) TBar.BackgroundColor3=T.surface
corner(TBar,12) stroke(TBar,1,T.border) TBar.Parent=Main
local tLbl=mkLabel(TBar,"AI  GUI",15,T.text) tLbl.Position=UDim2.new(0,14,0,0) tLbl.Size=UDim2.new(0.5,0,1,0) tLbl.TextYAlignment=Enum.TextYAlignment.Center
local xBtn=Instance.new("TextButton") xBtn.Size=UDim2.new(0,28,0,28) xBtn.Position=UDim2.new(1,-36,0.5,-14)
xBtn.Text="✕" xBtn.TextSize=13 xBtn.TextColor3=T.textMute xBtn.BackgroundColor3=T.surface2 xBtn.FontFace=CF
corner(xBtn,6) xBtn.Parent=TBar xBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

--// Sidebar
local Sidebar=Instance.new("Frame") Sidebar.Size=UDim2.new(0,52,1,-44) Sidebar.Position=UDim2.new(0,0,0,44)
Sidebar.BackgroundColor3=T.surface Sidebar.BorderSizePixel=0 Sidebar.Parent=Main
listLayout(Sidebar,Enum.FillDirection.Vertical,Enum.HorizontalAlignment.Center,nil,4)
pad(Sidebar,8,0,0,0)

--// Content area
local Content=Instance.new("Frame") Content.Size=UDim2.new(1,-52,1,-44) Content.Position=UDim2.new(0,52,0,44)
Content.BackgroundColor3=T.bg Content.BorderSizePixel=0 Content.Parent=Main

--// Tab system
local Tabs,TabFrames={},{}
local TAB_DEFS={
    {id="agents",     icon="🤖", ipath="zrxc/icons/agents.png"},
    {id="history",    icon="💬", ipath="zrxc/icons/history.png"},
    {id="management", icon="⚙️",  ipath="zrxc/icons/management.png"},
    {id="settings",   icon="🔧", ipath="zrxc/icons/settings.png"},
}

local function showTab(id)
    for tid,f in pairs(TabFrames) do f.Visible=(tid==id) end
    for tid,b in pairs(Tabs) do b.BackgroundColor3=T.accent b.BackgroundTransparency=(tid==id) and 0 or 1 end
end

for _,def in ipairs(TAB_DEFS) do
    local btn=Instance.new("TextButton") btn.Size=UDim2.new(0,40,0,40)
    btn.Text=def.icon btn.TextSize=18 btn.TextColor3=T.text btn.BackgroundColor3=T.accent
    btn.BackgroundTransparency=1 btn.FontFace=CF corner(btn,8)
    local asset=getIcon(def.ipath)
    if asset~="" then
        local img=Instance.new("ImageLabel") img.Size=UDim2.new(0.6,0,0.6,0) img.Position=UDim2.new(0.2,0,0.2,0)
        img.BackgroundTransparency=1 img.ScaleType=Enum.ScaleType.Fit img.Image=asset img.Parent=btn btn.Text=""
    end
    btn.Parent=Sidebar
    local f=Instance.new("Frame") f.Size=UDim2.new(1,0,1,0) f.BackgroundTransparency=1 f.Visible=false f.Parent=Content
    TabFrames[def.id]=f Tabs[def.id]=btn
    btn.MouseButton1Click:Connect(function() showTab(def.id) end)
end

--// ════════════════════════
--// TAB 1 — AGENTS (chat)
--// ════════════════════════
local AgentFrame=TabFrames["agents"]

-- No-agent screen
local NAS=Instance.new("Frame") NAS.Size=UDim2.new(1,0,1,0) NAS.BackgroundTransparency=1 NAS.Parent=AgentFrame
listLayout(NAS,Enum.FillDirection.Vertical,Enum.HorizontalAlignment.Center,Enum.VerticalAlignment.Center,6)

local function nasLbl(txt,sz,col,tr)
    local l=mkLabel(NAS,txt,sz,col,Enum.TextXAlignment.Center)
    l.Size=UDim2.new(1,-20,0,sz+8) if tr then l.TextTransparency=tr end return l
end
nasLbl("Hello",22,T.text)
nasLbl(LPName,14,T.textMute)
nasLbl("You don't have an AI api implemented yet.",12,T.textMute,0.4)

-- Clickable link (underline via child frame, no UITextDecoration)
local naLink=Instance.new("TextButton") naLink.Size=UDim2.new(0,170,0,22) naLink.BackgroundTransparency=1
naLink.Text="Go to AI Management" naLink.TextSize=12 naLink.TextColor3=T.accent naLink.FontFace=CF naLink.Parent=NAS
local ul=Instance.new("Frame") ul.Size=UDim2.new(1,0,0,1) ul.Position=UDim2.new(0,0,1,-1)
ul.BackgroundColor3=T.accent ul.BorderSizePixel=0 ul.Parent=naLink
naLink.MouseButton1Click:Connect(function() showTab("management") end)

-- Chat screen
local CS=Instance.new("Frame") CS.Size=UDim2.new(1,0,1,0) CS.BackgroundTransparency=1 CS.Visible=false CS.Parent=AgentFrame

local hdr=Instance.new("Frame") hdr.Size=UDim2.new(1,0,0,68) hdr.BackgroundTransparency=1 hdr.Parent=CS
local ht=mkLabel(hdr,"Welcome",20,T.text) ht.Position=UDim2.new(0,12,0,6) ht.Size=UDim2.new(1,-12,0,26)
local hs=mkLabel(hdr,LPName,13,T.textMute) hs.Position=UDim2.new(0,12,0,30) hs.Size=UDim2.new(1,-12,0,18)
local hp=mkLabel(hdr,"How can I assist you today?",12,T.textMute) hp.TextTransparency=0.4 hp.Position=UDim2.new(0,12,0,50) hp.Size=UDim2.new(1,-12,0,16)

local MsgScroll=scrollFrame(CS,UDim2.new(1,-16,1,-136),UDim2.new(0,8,0,70))
listLayout(MsgScroll,nil,nil,nil,6) pad(MsgScroll,4,4,0,0)

-- Rate-limit warning bar
local RLW=Instance.new("Frame") RLW.Size=UDim2.new(1,-16,0,38) RLW.Position=UDim2.new(0,8,1,-132)
RLW.BackgroundColor3=T.danger RLW.Visible=false corner(RLW,6) RLW.Parent=CS
local RLText=mkLabel(RLW,"",11,T.white) RLText.Position=UDim2.new(0,8,0,4) RLText.Size=UDim2.new(1,-16,0,26)
local RLRow=Instance.new("Frame") RLRow.Size=UDim2.new(1,0,0,30) RLRow.Position=UDim2.new(0,0,1,-32)
RLRow.BackgroundTransparency=1 RLRow.Visible=false RLRow.Parent=RLW
local RLC=Instance.new("TextButton") RLC.Size=UDim2.new(0.48,0,1,0) RLC.Position=UDim2.new(0.01,0,0,0)
RLC.Text="Continue" RLC.TextSize=11 RLC.TextColor3=T.white RLC.BackgroundColor3=T.accentD RLC.FontFace=CF corner(RLC,4) RLC.Parent=RLRow
local RLN=Instance.new("TextButton") RLN.Size=UDim2.new(0.48,0,1,0) RLN.Position=UDim2.new(0.51,0,0,0)
RLN.Text="New Chat" RLN.TextSize=11 RLN.TextColor3=T.white RLN.BackgroundColor3=Color3.fromRGB(70,70,70) RLN.FontFace=CF corner(RLN,4) RLN.Parent=RLRow
RLC.MouseButton1Click:Connect(function() RLW.Visible=false end)
RLN.MouseButton1Click:Connect(function()
    RLW.Visible=false ChatHistory={}
    for _,c in ipairs(MsgScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    saveConvo()
end)

-- Input row
local IR=Instance.new("Frame") IR.Size=UDim2.new(1,-16,0,40) IR.Position=UDim2.new(0,8,1,-52)
IR.BackgroundColor3=T.surface2 corner(IR,8) stroke(IR,1,T.border) IR.Parent=CS
local CI=Instance.new("TextBox") CI.Size=UDim2.new(1,-48,1,0) CI.Position=UDim2.new(0,8,0,0)
CI.BackgroundTransparency=1 CI.Text="" CI.PlaceholderText="Message..." CI.PlaceholderColor3=T.textMute
CI.TextColor3=T.text CI.TextSize=13 CI.FontFace=CF CI.TextXAlignment=Enum.TextXAlignment.Left
CI.ClearTextOnFocus=false CI.Parent=IR
local SB=Instance.new("TextButton") SB.Size=UDim2.new(0,38,0,32) SB.Position=UDim2.new(1,-42,0.5,-16)
SB.Text="↑" SB.TextSize=16 SB.TextColor3=T.white SB.BackgroundColor3=T.accent SB.FontFace=CF corner(SB,6) SB.Parent=IR

-- Spy toggle button
local SpyBtn=Instance.new("TextButton") SpyBtn.Size=UDim2.new(1,-16,0,22) SpyBtn.Position=UDim2.new(0,8,1,-24)
SpyBtn.Text="[ RemoteSpy: OFF ]" SpyBtn.TextSize=11 SpyBtn.TextColor3=T.textMute SpyBtn.BackgroundTransparency=1
SpyBtn.FontFace=CF SpyBtn.Parent=CS
SpyBtn.MouseButton1Click:Connect(function()
    if SpyActive then stopRemoteSpy() SpyBtn.Text="[ RemoteSpy: OFF ]" SpyBtn.TextColor3=T.textMute
    else startRemoteSpy() SpyBtn.Text="[ RemoteSpy: ON  ]" SpyBtn.TextColor3=T.success end
end)

local Thinking=nil
local function addBubble(text,isUser)
    local bub=Instance.new("Frame") bub.Size=UDim2.new(1,0,0,0) bub.AutomaticSize=Enum.AutomaticSize.Y
    bub.BackgroundColor3=isUser and T.accent or T.surface2 corner(bub,8) pad(bub,6,6,10,10)
    local lbl=Instance.new("TextLabel") lbl.Size=UDim2.new(1,0,0,0) lbl.AutomaticSize=Enum.AutomaticSize.Y
    lbl.BackgroundTransparency=1 lbl.Text=text lbl.TextSize=12 lbl.TextColor3=T.text
    lbl.FontFace=CF lbl.TextXAlignment=Enum.TextXAlignment.Left lbl.TextWrapped=true lbl.Parent=bub
    bub.Parent=MsgScroll
    task.wait() MsgScroll.CanvasPosition=Vector2.new(0,MsgScroll.AbsoluteCanvasSize.Y)
    return bub
end

local function updateAgentUI()
    local has=#Agents.list>0 NAS.Visible=not has CS.Visible=has
end

local function sendMessage()
    local msg=CI.Text if msg=="" then return end CI.Text=""
    addBubble(msg,true)
    Thinking=addBubble("...",false)
    task.spawn(function()
        local reply,err,swIdx=callAI(msg)
        if Thinking then Thinking:Destroy() Thinking=nil end
        if reply then
            if swIdx then
                local ag=Agents.list[swIdx]
                RLText.Text="Rate limited. Switched to Agent"..(ag and ag.id or "?").." ("..( ag and ag.model or "?")..")"
                RLW.Size=UDim2.new(1,-16,0,72) RLRow.Visible=true RLW.Visible=true
            end
            addBubble(reply,false)
        elseif err=="NO_AGENTS" then
            addBubble("No agents configured. Add one in AI Management.",false)
        elseif err=="ALL_RATELIMITED" then
            RLText.Text="All agents rate limited. No backup available."
            RLW.Size=UDim2.new(1,-16,0,38) RLRow.Visible=false RLW.Visible=true
        else
            addBubble("Error: "..tostring(err),false)
        end
    end)
end

SB.MouseButton1Click:Connect(sendMessage)
CI.FocusLost:Connect(function(enter) if enter then sendMessage() end end)

-- Restore saved messages
for _,m in ipairs(ChatHistory) do addBubble(m.content, m.role=="user") end

--// ════════════════════════
--// TAB 2 — HISTORY
--// ════════════════════════
local HistFrame=TabFrames["history"]
local hScroll=scrollFrame(HistFrame,UDim2.new(1,-16,1,-50),UDim2.new(0,8,0,8))
listLayout(hScroll,nil,nil,nil,4)
local hClear=mkBtn(HistFrame,"Clear History",T.danger,T.white)
hClear.Size=UDim2.new(1,-16,0,28) hClear.Position=UDim2.new(0,8,1,-36)
hClear.MouseButton1Click:Connect(function()
    ChatHistory={}
    for _,c in ipairs(hScroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
    saveConvo()
end)

local function refreshHistory()
    for _,c in ipairs(hScroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
    for _,m in ipairs(ChatHistory) do
        local l=mkLabel(hScroll,"["..m.role.."] "..m.content,11,m.role=="user" and T.accent or T.text)
        l.Size=UDim2.new(1,0,0,0) l.AutomaticSize=Enum.AutomaticSize.Y
    end
end
Tabs["history"].MouseButton1Click:Connect(refreshHistory)

--// ════════════════════════
--// TAB 3 — AI MANAGEMENT
--// ════════════════════════
local MgmtFrame=TabFrames["management"]
local agScroll=scrollFrame(MgmtFrame,UDim2.new(1,-16,1,-52),UDim2.new(0,8,0,8))
listLayout(agScroll,nil,nil,nil,6)
local AddBtn=mkBtn(MgmtFrame,"+ Add New AI",T.accent,T.white)
AddBtn.Size=UDim2.new(1,-16,0,32) AddBtn.Position=UDim2.new(0,8,1,-42)

-- Provider picker popup
local PPick=Instance.new("Frame") PPick.Size=UDim2.new(0,300,0,340) PPick.Position=UDim2.new(0.5,-150,0.5,-170)
PPick.BackgroundColor3=T.surface PPick.Visible=false corner(PPick,10) stroke(PPick,1,T.border) PPick.ZIndex=10 PPick.Parent=ScreenGui
mkLabel(PPick,"Select Provider",15,T.text,Enum.TextXAlignment.Center).Position=UDim2.new(0,0,0,10)
local ppX=Instance.new("TextButton") ppX.Size=UDim2.new(0,24,0,24) ppX.Position=UDim2.new(1,-30,0,8)
ppX.Text="✕" ppX.TextSize=12 ppX.TextColor3=T.textMute ppX.BackgroundTransparency=1 ppX.FontFace=CF ppX.Parent=PPick
ppX.MouseButton1Click:Connect(function() PPick.Visible=false end)
listLayout(PPick,Enum.FillDirection.Vertical,Enum.HorizontalAlignment.Center,nil,4)
pad(PPick,40,8,0,0)

-- Confirm delete popup
local ConfPop=Instance.new("Frame") ConfPop.Size=UDim2.new(0,280,0,110) ConfPop.Position=UDim2.new(0.5,-140,0.5,-55)
ConfPop.BackgroundColor3=T.surface ConfPop.Visible=false corner(ConfPop,10) stroke(ConfPop,1,T.danger) ConfPop.ZIndex=12 ConfPop.Parent=ScreenGui
local cLbl=mkLabel(ConfPop,"Are you sure? This cannot be undone.",12,T.text,Enum.TextXAlignment.Center)
cLbl.Position=UDim2.new(0,10,0,14) cLbl.Size=UDim2.new(1,-20,0,20)
local cYes=mkBtn(ConfPop,"Delete",T.danger,T.white) cYes.Size=UDim2.new(0.44,0,0,28) cYes.Position=UDim2.new(0.04,0,0,58)
local cNo=mkBtn(ConfPop,"Cancel",T.surface2,T.text)  cNo.Size=UDim2.new(0.44,0,0,28)  cNo.Position=UDim2.new(0.52,0,0,58)
cNo.MouseButton1Click:Connect(function() ConfPop.Visible=false end)
local pendingDel=nil

-- Agent config popup (file-based)
local CfgPop=Instance.new("Frame") CfgPop.Size=UDim2.new(0,320,0,220) CfgPop.Position=UDim2.new(0.5,-160,0.5,-110)
CfgPop.BackgroundColor3=T.surface CfgPop.Visible=false corner(CfgPop,10) stroke(CfgPop,1,T.border) CfgPop.ZIndex=11 CfgPop.Parent=ScreenGui
pad(CfgPop,40,10,14,14)
local cfgTLbl=mkLabel(CfgPop,"Configure Agent",14,T.text,Enum.TextXAlignment.Center)
cfgTLbl.Position=UDim2.new(0,-14,0,-30) cfgTLbl.Size=UDim2.new(1,28,0,22)
local cfgInfo1=mkLabel(CfgPop,"A file has been created at:",11,T.textMute) cfgInfo1.Size=UDim2.new(1,0,0,18)
local cfgPathLbl=mkLabel(CfgPop,"",11,T.accent) cfgPathLbl.Size=UDim2.new(1,0,0,18)
local cfgInfo2=mkLabel(CfgPop,"Fill in your API Key and Model Name, then click Done.",11,T.textMute)
cfgInfo2.Size=UDim2.new(1,0,0,36) cfgInfo2.TextWrapped=true
local cfgDone=mkBtn(CfgPop,"Done — reload agent from file",T.accent,T.white) cfgDone.Size=UDim2.new(1,0,0,30)
local cfgCancel=mkBtn(CfgPop,"Cancel",T.surface2,T.text) cfgCancel.Size=UDim2.new(1,0,0,28)
cfgCancel.MouseButton1Click:Connect(function() CfgPop.Visible=false end)

local pendingAgPath,pendingAgId,pendingAgProv=nil,nil,nil

local PROV_LIST={"HuggingFace","Google","Anthropic","OpenAI","Grok","DeepSeek"}
for _,pname in ipairs(PROV_LIST) do
    local pb=mkBtn(PPick,pname,T.surface2,T.text) pb.Size=UDim2.new(0.88,0,0,28)
    pb.MouseButton1Click:Connect(function()
        PPick.Visible=false
        local agId=Agents.nextId
        local agFile="zrxc/AI/agent"..agId..".txt"
        pendingAgPath=agFile pendingAgId=agId pendingAgProv=pname
        writeFileSafe(agFile,"Provider: "..pname.."\nAPI Key: \nModel Name: \n")
        cfgTLbl.Text="Configure Agent"..agId.." ("..pname..")"
        cfgPathLbl.Text=agFile
        cfgInfo2.TextColor3=T.textMute
        cfgInfo2.Text="Fill in your API Key and Model Name, then click Done."
        CfgPop.Visible=true
    end)
end

cfgDone.MouseButton1Click:Connect(function()
    if not pendingAgPath then return end
    local raw=readFileSafe(pendingAgPath)
    if not raw then cfgInfo2.Text="Could not read file." cfgInfo2.TextColor3=T.danger return end
    local apiKey,model="",""
    for line in raw:gmatch("[^\n]+") do
        local k,v=line:match("^(.-):%s*(.+)$")
        if k and v then
            local vt=v:match("^%s*(.-)%s*$")
            if k=="API Key"     then apiKey=vt end
            if k=="Model Name"  then model=vt  end
        end
    end
    if apiKey=="" or model=="" then
        cfgInfo2.Text="API Key or Model Name is empty. Edit the file first."
        cfgInfo2.TextColor3=T.danger return
    end
    Agents.list[#Agents.list+1]={id=pendingAgId,provider=pendingAgProv,apiKey=apiKey,model=model,active=false}
    Agents.nextId=pendingAgId+1
    writeAgentFile()
    CfgPop.Visible=false pendingAgPath=nil pendingAgId=nil pendingAgProv=nil
    refreshAgentList()
end)

local function refreshAgentList()
    for _,c in ipairs(agScroll:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    for i,ag in ipairs(Agents.list) do
        local row=Instance.new("Frame") row.Size=UDim2.new(1,0,0,44)
        row.BackgroundColor3=T.surface2 corner(row,8) stroke(row,1,T.border) row.Parent=agScroll
        local nl=mkLabel(row,"Agent"..ag.id.."  |  ["..ag.provider.."]  "..ag.model,12,T.text)
        nl.Position=UDim2.new(0,10,0,0) nl.Size=UDim2.new(1,-50,1,0) nl.TextYAlignment=Enum.TextYAlignment.Center
        local del=Instance.new("TextButton") del.Size=UDim2.new(0,30,0,30) del.Position=UDim2.new(1,-38,0.5,-15)
        del.Text="✕" del.TextSize=13 del.TextColor3=T.danger del.BackgroundTransparency=1 del.FontFace=CF del.Parent=row
        local idx=i
        del.MouseButton1Click:Connect(function() pendingDel=idx ConfPop.Visible=true end)
    end
    updateAgentUI()
end

cYes.MouseButton1Click:Connect(function()
    if not pendingDel then return end
    table.remove(Agents.list,pendingDel) pendingDel=nil ConfPop.Visible=false
    if #Agents.list==0 then Agents.nextId=1 end
    writeAgentFile() refreshAgentList()
end)

AddBtn.MouseButton1Click:Connect(function() PPick.Visible=true end)
refreshAgentList()

--// ════════════════════════
--// TAB 4 — SETTINGS
--// ════════════════════════
local SetFrame=TabFrames["settings"]
local sScroll=scrollFrame(SetFrame,UDim2.new(1,-16,1,-30),UDim2.new(0,8,0,8))
listLayout(sScroll,nil,nil,nil,6) pad(sScroll,6,6,0,0)

mkToggle(sScroll,"Auto-Execute (queueonteleport)",Settings.autoExecute,function(v)
    Settings.autoExecute=v saveSettings()
    if v then pcall(function() local s=readFileSafe("zrxc/autoexec.lua") if s then queueonteleport(s) end end) end
end)
mkToggle(sScroll,"Auto-Switch on Rate Limit",Settings.autoSwitch,function(v)
    Settings.autoSwitch=v saveSettings()
end)

local custBtn=mkBtn(sScroll,"Customise Instructions",T.surface2,T.text)
custBtn.MouseButton1Click:Connect(function()
    local ip=Instance.new("Frame") ip.Size=UDim2.new(0,320,0,270) ip.Position=UDim2.new(0.5,-160,0.5,-135)
    ip.BackgroundColor3=T.surface ip.ZIndex=13 corner(ip,10) stroke(ip,1,T.border) ip.Parent=ScreenGui
    pad(ip,40,10,12,12)
    mkLabel(ip,"Edit Instructions",14,T.text,Enum.TextXAlignment.Center).Position=UDim2.new(0,-12,0,-30)
    local ibox=mkTextBox(ip,"Instructions...",true) ibox.Text=SystemPrompt ibox.Size=UDim2.new(1,0,0,160)
    local sv=mkBtn(ip,"Save",T.accent,T.white) sv.Size=UDim2.new(0.46,0,0,28) sv.Position=UDim2.new(0.02,0,0,172)
    sv.MouseButton1Click:Connect(function()
        SystemPrompt=ibox.Text writeFileSafe(INSTRUCT_PATH,SystemPrompt)
        print("[AIGui] Instructions saved to zrxc/AI/instructions.txt — edit that file to make further changes.")
        ip:Destroy()
    end)
    local cn=mkBtn(ip,"Cancel",T.surface2,T.text) cn.Size=UDim2.new(0.46,0,0,28) cn.Position=UDim2.new(0.52,0,0,172)
    cn.MouseButton1Click:Connect(function() ip:Destroy() end)
end)

local clrBtn=mkBtn(sScroll,"Clear Cache",T.surface2,T.text)
clrBtn.MouseButton1Click:Connect(function()
    RemoteLog={} clrBtn.Text="Cleared!" task.delay(2,function() clrBtn.Text="Clear Cache" end)
end)

local dbgBtn=mkBtn(sScroll,"Fetch Debug (Copy Clipboard)",T.surface2,T.text)
dbgBtn.MouseButton1Click:Connect(function()
    local info={agents=#Agents.list,remotes=#RemoteLog,spyActive=SpyActive,settings=Settings,t=os.clock()}
    local ok,enc=pcall(HttpService.JSONEncode,HttpService,info)
    if ok then pcall(setclipboard,enc) end
    dbgBtn.Text="Copied!" task.delay(2,function() dbgBtn.Text="Fetch Debug (Copy Clipboard)" end)
end)

local helloLbl=mkLabel(SetFrame,"Hello..!",11,T.textMute,Enum.TextXAlignment.Right)
helloLbl.TextTransparency=0.4 helloLbl.Position=UDim2.new(0,0,1,-22) helloLbl.Size=UDim2.new(1,-10,0,18)

--// Init
showTab("agents")
updateAgentUI()
