--// AIGui v2 — Rayfield-inspired AI Script GUI
--// Services
local Players    = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui    = game:GetService("CoreGui")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer
local LPName     = LP and LP.Name or "Player"

--// UNC helpers
local function req(opts) local fn=request or (syn and syn.request) or http_request if not fn then return nil end local ok,r=pcall(fn,opts) return ok and r or nil end
local function rfs(p)    local ok,d=pcall(readfile,p)  return ok and d or nil end
local function wfs(p,d)  pcall(writefile,p,d) end
local function ifs(p)    local ok,r=pcall(isfile,p)    return ok and r end
local function mkf(p)    pcall(makefolder,p) end
local function rfold(p)  local ok,r=pcall(listfiles,p) return ok and r or {} end

--// Folders
mkf("zrxc") mkf("zrxc/ai") mkf("zrxc/module")

--// Paths
local P_SETTING  = "zrxc/setting.json"
local P_AI       = "zrxc/ai/ai.json"
local P_CONVO    = "zrxc/ai/conservation.json"
local P_INSTRUCT = "zrxc/ai/instructions.txt"
local INSTRUCT_URL = "https://raw.githubusercontent.com/DeflectEncrypt/xoajne/refs/heads/main/Instruction.txt"
local CHANGELOG_URL = "https://raw.githubusercontent.com/DeflectEncrypt/xoajne/refs/heads/main/idk"
local CREDITS_URL   = "https://raw.githubusercontent.com/DeflectEncrypt/xoajne/refs/heads/main/sigma"

--// Module asset paths (user drops files into zrxc/module/)
local MOD = {
    font        = "zrxc/module/font.ttf",
    ico_agent   = "zrxc/module/ico_agent.png",
    ico_aimgmt  = "zrxc/module/ico_aimgmt.png",
    ico_changelog="zrxc/module/ico_changelog.png",
    ico_credits = "zrxc/module/ico_credits.png",
    ico_settings= "zrxc/module/ico_settings.png",
    ico_convo   = "zrxc/module/ico_convo.png",
    ico_attach  = "zrxc/module/ico_attach.png",
    ico_send    = "zrxc/module/ico_send.png",
    ico_add     = "zrxc/module/ico_add.png",
    ico_confirm = "zrxc/module/ico_confirm.png",
    ico_search  = "zrxc/module/ico_search.png",
    ico_host    = "zrxc/module/ico_host.png",
    ico_apikey  = "zrxc/module/ico_apikey.png",
    ico_model   = "zrxc/module/ico_model.png",
    ico_hf      = "zrxc/module/ico_hf.png",
    ico_google  = "zrxc/module/ico_google.png",
    ico_anthropic="zrxc/module/ico_anthropic.png",
    ico_openai  = "zrxc/module/ico_openai.png",
    ico_grok    = "zrxc/module/ico_grok.png",
    ico_deepseek= "zrxc/module/ico_deepseek.png",
}
local function asset(key)
    local ok,a=pcall(getcustomasset,MOD[key] or key)
    return ok and a or ""
end
local function font()
    local ok,a=pcall(getcustomasset,MOD.font)
    if ok and a and a~="" then return Font.new(a) end
    return Font.new("rbxasset://fonts/families/RobotoMono.json")
end
local CF=font()

--// JSON
local function jdec(s) local ok,t=pcall(HttpService.JSONDecode,HttpService,s) return ok and t or nil end
local function jenc(t) local ok,s=pcall(HttpService.JSONEncode,HttpService,t) return ok and s or nil end
local function loadJ(p,def) local r=rfs(p) if r and r~="" then local t=jdec(r) if t then return t end end return def end
local function saveJ(p,t)   local s=jenc(t) if s then wfs(p,s) end end

--// State
local Settings   = loadJ(P_SETTING,{autoExecute=false,autoSwitch=true})
local AgentData  = loadJ(P_AI,{list={},nextId=1})
if type(AgentData)~="table" or not AgentData.list then AgentData={list={},nextId=1} end
local ConvoData  = loadJ(P_CONVO,{sessions={},nextId=1})
local ChatHistory= {}
local ActiveSessionId = nil

local function saveSetting() saveJ(P_SETTING,Settings) end
local function saveAgents()
    if #AgentData.list==0 then wfs(P_AI,'--[[ No agents yet, please add a valid AI ]]')
    else saveJ(P_AI,AgentData) end
end
local function saveConvo() saveJ(P_CONVO,ConvoData) end

--// Instructions
local function loadInstructions()
    if ifs(P_INSTRUCT) then local d=rfs(P_INSTRUCT) if d and d~="" then return d end end
    local r=req({Url=INSTRUCT_URL,Method="GET"})
    if r and r.Body and r.Body~="" then wfs(P_INSTRUCT,r.Body) return r.Body end
    return "You are a Roblox Exploit Luau scripter running inside a user executor environment."
end
local SystemPrompt=loadInstructions()

--// Auto-execute
if Settings.autoExecute then
    pcall(function() local s=rfs("zrxc/autoexec.lua") if s then queueonteleport(s) end end)
end

--// Roblox pfp fetch
local function fetchPfp(userId)
    local url="https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds="..tostring(userId).."&size=48x48&format=Png&isCircular=true"
    local r=req({Url=url,Method="GET"})
    if r and r.Body then
        local d=jdec(r.Body)
        if d and d.data and d.data[1] then return d.data[1].imageUrl end
    end
    return ""
end
local function fetchDisplayName(userId)
    local r=req({Url="https://users.roblox.com/v1/users/"..tostring(userId),Method="GET"})
    if r and r.Body then local d=jdec(r.Body) if d then return d.displayName or LPName,d.name or LPName end end
    return LPName,LPName
end

--// RemoteSpy
local RemoteLog={} local RemoteHooks={} local SpyActive=false
local function startSpy()
    if SpyActive then return end SpyActive=true
    local function hook(rem)
        if RemoteHooks[rem] then return end RemoteHooks[rem]=true
        if rem.ClassName=="RemoteEvent" then
            pcall(hookfunction,rem.FireServer,newcclosure(function(...) table.insert(RemoteLog,{type="FireServer",name=rem.Name,path=rem:GetFullName(),t=os.clock()}) end))
            pcall(function() rem.OnClientEvent:Connect(function(...) table.insert(RemoteLog,{type="OnClientEvent",name=rem.Name,path=rem:GetFullName(),t=os.clock()}) end) end)
        elseif rem.ClassName=="RemoteFunction" then
            pcall(hookfunction,rem.InvokeServer,newcclosure(function(...) table.insert(RemoteLog,{type="InvokeServer",name=rem.Name,path=rem:GetFullName(),t=os.clock()}) end))
        end
    end
    for _,v in ipairs(game:GetDescendants()) do if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then pcall(hook,v) end end
    game.DescendantAdded:Connect(function(v) if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then pcall(hook,v) end end)
end
local function stopSpy() SpyActive=false RemoteHooks={} end
local function remoteSum(n) n=n or 20 local l={} for i=math.max(1,#RemoteLog-n+1),#RemoteLog do local e=RemoteLog[i] l[#l+1]=("[%s] %s (%s)"):format(e.type,e.name,e.path) end return #l>0 and table.concat(l,"\n") or "No remotes logged." end

--// Dex
local function dexTree(inst,depth)
    depth=depth or 0 if depth>2 then return "" end
    local lines={}
    local ok,ch=pcall(function() return inst:GetChildren() end)
    if not ok then return "" end
    for _,c in ipairs(ch) do
        lines[#lines+1]=string.rep("  ",depth)..c.ClassName.." ["..c.Name.."]"
        local sub=dexTree(c,depth+1) if sub~="" then lines[#lines+1]=sub end
    end
    return table.concat(lines,"\n")
end
local function buildCtx()
    local l={"=== GAME ===","PlaceId:"..game.PlaceId,"Player:"..LPName}
    local char=LP.Character
    if char then
        local h=char:FindFirstChildOfClass("Humanoid")
        if h then l[#l+1]="WS:"..h.WalkSpeed.." HP:"..h.Health end
        local r=char:FindFirstChild("HumanoidRootPart")
        if r then local p=r.Position l[#l+1]=("XYZ:%.1f,%.1f,%.1f"):format(p.X,p.Y,p.Z) end
    end
    l[#l+1]="\n=== WORKSPACE ===" l[#l+1]=dexTree(workspace)
    l[#l+1]="\n=== REMOTES ===" l[#l+1]=remoteSum()
    return table.concat(l,"\n")
end

--// ScriptBlox / RScripts
local function fetchSB(q) local r=req({Url="https://scriptblox.com/api/script/search?q="..HttpService:UrlEncode(q).."&page=1",Method="GET"}) if r and r.Body then local d=jdec(r.Body) if d and d.result and d.result.scripts then local o={} for i,s in ipairs(d.result.scripts) do if i>5 then break end o[#o+1]=("[%d] %s\n%s"):format(i,s.title or "?",s.script or "") end return table.concat(o,"\n---\n") end end return "No results." end
local function fetchRS(q) local r=req({Url="https://rscripts.net/api/scripts?q="..HttpService:UrlEncode(q).."&page=1",Method="GET"}) if r and r.Body then local d=jdec(r.Body) if d then local list=d.scripts or d.data or d if type(list)=="table" then local o={} for i,s in ipairs(list) do if i>5 then break end o[#o+1]=("[%d] %s\n%s"):format(i,s.title or s.name or "?",s.script or s.content or "") end return table.concat(o,"\n---\n") end end end return "No results." end

--// AI Providers
local PROV={
    HuggingFace=function(ag,msgs) local r=req({Url="https://api-inference.huggingface.co/v1/chat/completions",Method="POST",Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},Body=jenc({model=ag.model,messages=msgs,max_tokens=1024})}) if r and r.Body then local d=jdec(r.Body) if d and d.choices then return d.choices[1].message.content,r.StatusCode end end return nil,r and r.StatusCode or 0 end,
    Google=function(ag,msgs) local pts={} for _,m in ipairs(msgs) do if m.role~="system" then pts[#pts+1]={role=m.role=="assistant" and "model" or "user",parts={{text=m.content}}} end end local r=req({Url="https://generativelanguage.googleapis.com/v1beta/models/"..ag.model..":generateContent?key="..ag.apiKey,Method="POST",Headers={["Content-Type"]="application/json"},Body=jenc({contents=pts})}) if r and r.Body then local d=jdec(r.Body) if d and d.candidates then return d.candidates[1].content.parts[1].text,r.StatusCode end end return nil,r and r.StatusCode or 0 end,
    Anthropic=function(ag,msgs) local sys,fm="",{} for _,m in ipairs(msgs) do if m.role=="system" then sys=m.content else fm[#fm+1]=m end end local r=req({Url="https://api.anthropic.com/v1/messages",Method="POST",Headers={["x-api-key"]=ag.apiKey,["anthropic-version"]="2023-06-01",["Content-Type"]="application/json"},Body=jenc({model=ag.model,max_tokens=1024,system=sys,messages=fm})}) if r and r.Body then local d=jdec(r.Body) if d and d.content then return d.content[1].text,r.StatusCode end end return nil,r and r.StatusCode or 0 end,
    OpenAI=function(ag,msgs) local r=req({Url="https://api.openai.com/v1/chat/completions",Method="POST",Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},Body=jenc({model=ag.model,messages=msgs,max_tokens=1024})}) if r and r.Body then local d=jdec(r.Body) if d and d.choices then return d.choices[1].message.content,r.StatusCode end end return nil,r and r.StatusCode or 0 end,
    Grok=function(ag,msgs) local r=req({Url="https://api.x.ai/v1/chat/completions",Method="POST",Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},Body=jenc({model=ag.model or "grok-3-latest",messages=msgs,max_tokens=1024})}) if r and r.Body then local d=jdec(r.Body) if d and d.choices then return d.choices[1].message.content,r.StatusCode end end return nil,r and r.StatusCode or 0 end,
    DeepSeek=function(ag,msgs) local r=req({Url="https://api.deepseek.com/v1/chat/completions",Method="POST",Headers={["Authorization"]="Bearer "..ag.apiKey,["Content-Type"]="application/json"},Body=jenc({model=ag.model or "deepseek-chat",messages=msgs,max_tokens=1024})}) if r and r.Body then local d=jdec(r.Body) if d and d.choices then return d.choices[1].message.content,r.StatusCode end end return nil,r and r.StatusCode or 0 end,
}
local function isRL(c) return c==429 or c==503 end
local function callAI(userMsg)
    if #AgentData.list==0 then return nil,"NO_AGENTS" end
    local sys=SystemPrompt.."\n\n"..buildCtx()
    local msgs={{role="system",content=sys}}
    for _,m in ipairs(ChatHistory) do msgs[#msgs+1]=m end
    msgs[#msgs+1]={role="user",content=userMsg}
    local si=1 for i,a in ipairs(AgentData.list) do if a.active then si=i break end end
    for i=si,#AgentData.list do
        local ag=AgentData.list[i] local fn=PROV[ag.host]
        if not fn then continue end
        local rep,code=fn(ag,msgs)
        if rep then
            ChatHistory[#ChatHistory+1]={role="user",content=userMsg}
            ChatHistory[#ChatHistory+1]={role="assistant",content=rep}
            if #ChatHistory>40 then table.remove(ChatHistory,1) table.remove(ChatHistory,1) end
            for _,a in ipairs(AgentData.list) do a.active=false end ag.active=true
            saveAgents() return rep,nil,i>si and i or nil
        elseif isRL(code) and Settings.autoSwitch then ag.active=false
        else return nil,"ERR_"..tostring(code) end
    end
    return nil,"ALL_RL"
end

--// ══════════════════════════════════════════
--// GUI
--// ══════════════════════════════════════════
local SG=Instance.new("ScreenGui") SG.Name="AIGuiV2" SG.ResetOnSpawn=false SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
if not pcall(function() SG.Parent=CoreGui end) then SG.Parent=LP.PlayerGui end

local T={
    bg      =Color3.fromRGB(15,15,20),
    panel   =Color3.fromRGB(22,22,30),
    panel2  =Color3.fromRGB(28,28,38),
    sidebar =Color3.fromRGB(18,18,25),
    border  =Color3.fromRGB(45,45,65),
    accent  =Color3.fromRGB(100,140,255),
    accentD =Color3.fromRGB(70,100,210),
    text    =Color3.fromRGB(225,225,240),
    mute    =Color3.fromRGB(110,110,140),
    danger  =Color3.fromRGB(210,60,60),
    success =Color3.fromRGB(60,200,110),
    white   =Color3.fromRGB(255,255,255),
    overlay =Color3.fromRGB(10,10,15),
}

-- Builder helpers
local function c(p,r)     local x=Instance.new("UICorner") x.CornerRadius=UDim.new(0,r or 8) x.Parent=p return x end
local function s(p,t,col) local x=Instance.new("UIStroke") x.Thickness=t or 1 x.Color=col or T.border x.Parent=p return x end
local function pad(p,t,b,l,r) local x=Instance.new("UIPadding") x.PaddingTop=UDim.new(0,t or 6) x.PaddingBottom=UDim.new(0,b or 6) x.PaddingLeft=UDim.new(0,l or 8) x.PaddingRight=UDim.new(0,r or 8) x.Parent=p return x end
local function ll(p,fd,ha,va,gap) local x=Instance.new("UIListLayout") x.FillDirection=fd or Enum.FillDirection.Vertical x.HorizontalAlignment=ha or Enum.HorizontalAlignment.Left x.VerticalAlignment=va or Enum.VerticalAlignment.Top if gap then x.Padding=UDim.new(0,gap) end x.Parent=p return x end
local function gl(p,cols,cpad,rpad) local x=Instance.new("UIGridLayout") x.CellSize=UDim2.new(1/cols,-cpad or 4,0,28) x.CellPadding=UDim2.new(0,cpad or 4,0,rpad or 4) x.Parent=p return x end

local function lbl(p,txt,sz,col,xa)
    local l=Instance.new("TextLabel") l.Text=txt l.TextSize=sz or 13 l.TextColor3=col or T.text
    l.BackgroundTransparency=1 l.FontFace=CF l.TextWrapped=true l.TextXAlignment=xa or Enum.TextXAlignment.Left
    l.Size=UDim2.new(1,0,0,(sz or 13)+6) l.Parent=p return l
end
local function btn(p,txt,bg,tc,sz)
    local b=Instance.new("TextButton") b.Text=txt b.TextSize=sz or 13 b.TextColor3=tc or T.white
    b.BackgroundColor3=bg or T.accent b.FontFace=CF b.AutoButtonColor=false b.Size=UDim2.new(1,0,0,32)
    c(b,6) local orig=bg or T.accent
    b.MouseEnter:Connect(function() b.BackgroundColor3=Color3.new(orig.R*.78,orig.G*.78,orig.B*.78) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3=orig end)
    b.Parent=p return b
end
local function imgBtn(p,iconKey,size)
    local b=Instance.new("ImageButton") b.Size=size or UDim2.new(0,28,0,28)
    b.BackgroundTransparency=1 b.ScaleType=Enum.ScaleType.Fit
    local a=asset(iconKey) b.Image=a b.Parent=p return b
end
local function scroll(p,sz,pos)
    local f=Instance.new("ScrollingFrame") f.Size=sz f.Position=pos or UDim2.new(0,0,0,0)
    f.BackgroundTransparency=1 f.ScrollBarThickness=3 f.ScrollBarImageColor3=T.border
    f.AutomaticCanvasSize=Enum.AutomaticSize.Y f.CanvasSize=UDim2.new(0,0,0,0) f.Parent=p return f
end
local function tbox(p,ph,multi)
    local b=Instance.new("TextBox") b.Size=UDim2.new(1,0,0,multi and 80 or 30)
    b.BackgroundColor3=T.panel2 b.TextColor3=T.text b.PlaceholderColor3=T.mute b.PlaceholderText=ph b.Text=""
    b.TextSize=12 b.FontFace=CF b.TextXAlignment=Enum.TextXAlignment.Left
    b.TextYAlignment=multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
    b.ClearTextOnFocus=false b.MultiLine=multi or false b.TextWrapped=multi or false
    c(b,6) pad(b,5,5,8,8) b.Parent=p return b
end
local function toggle(p,ltext,state,cb)
    local row=Instance.new("Frame") row.BackgroundTransparency=1 row.Size=UDim2.new(1,0,0,36) row.Parent=p
    local l=lbl(row,ltext,13,T.text) l.Size=UDim2.new(1,-54,1,0) l.TextYAlignment=Enum.TextYAlignment.Center
    local track=Instance.new("Frame") track.Size=UDim2.new(0,42,0,22) track.Position=UDim2.new(1,-46,0.5,-11) track.BackgroundColor3=state and T.accent or T.border c(track,11) track.Parent=row
    local knob=Instance.new("Frame") knob.Size=UDim2.new(0,18,0,18) knob.Position=state and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9) knob.BackgroundColor3=T.white c(knob,9) knob.Parent=track
    local cur=state
    local ob=Instance.new("TextButton") ob.Size=UDim2.new(1,0,1,0) ob.BackgroundTransparency=1 ob.Text="" ob.Parent=row
    ob.MouseButton1Click:Connect(function()
        cur=not cur track.BackgroundColor3=cur and T.accent or T.border
        knob.Position=cur and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9) cb(cur)
    end)
    return row,function(v) cur=v track.BackgroundColor3=v and T.accent or T.border knob.Position=v and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9) end
end

-- Popup builder
local function popup(w,h,zi)
    local f=Instance.new("Frame") f.Size=UDim2.new(0,w,0,h) f.Position=UDim2.new(0.5,-w/2,0.5,-h/2)
    f.BackgroundColor3=T.panel f.Visible=false f.ZIndex=zi or 20 c(f,10) s(f,1,T.border) f.Parent=SG return f
end
local function popupClose(pop,xoff,yoff)
    local xb=Instance.new("TextButton") xb.Size=UDim2.new(0,22,0,22) xb.Position=UDim2.new(1,xoff or -28,0,yoff or 8)
    xb.Text="✕" xb.TextSize=12 xb.TextColor3=T.mute xb.BackgroundTransparency=1 xb.FontFace=CF xb.Parent=pop
    xb.MouseButton1Click:Connect(function() pop.Visible=false end) return xb
end

-- Formatted text parser (<head>, <sub>, etc.)
local function parseFormatted(container,raw)
    for _,c2 in ipairs(container:GetChildren()) do if not c2:IsA("UIListLayout") and not c2:IsA("UIPadding") then c2:Destroy() end end
    for line in (raw.."\n"):gmatch("([^\n]*)\n") do
        local tag,content=line:match("^<(%w+)>(.*)$")
        if tag=="head" then
            local l=lbl(container,content,15,T.text) l.Size=UDim2.new(1,0,0,22) l.FontFace=Font.new(CF.Family,Enum.FontWeight.Bold)
        elseif tag=="sub" then
            local l=lbl(container,content,11,T.mute) l.Size=UDim2.new(1,0,0,18)
        elseif tag=="sep" then
            local f=Instance.new("Frame") f.Size=UDim2.new(1,0,0,1) f.BackgroundColor3=T.border f.BorderSizePixel=0 f.Parent=container
        else
            local l=lbl(container,line~="" and line or " ",12,T.text) l.Size=UDim2.new(1,0,0,0) l.AutomaticSize=Enum.AutomaticSize.Y
        end
    end
end

--// ══════════════════════════════════════════
--// MAIN WINDOW
--// ══════════════════════════════════════════
local Win=Instance.new("Frame") Win.Size=UDim2.new(0,580,0,500) Win.Position=UDim2.new(0.5,-290,0.5,-250)
Win.BackgroundColor3=T.bg Win.BorderSizePixel=0 c(Win,12) s(Win,1,T.border) Win.Parent=SG

-- Drag
do local drag,ds,sp=false
    Win.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true ds=i.Position sp=Win.Position end end)
    Win.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)
    UIS.InputChanged:Connect(function(i) if drag and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-ds Win.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y) end end)
end

--// HEADER BAR
local HBar=Instance.new("Frame") HBar.Size=UDim2.new(1,0,0,72) HBar.BackgroundColor3=T.panel HBar.BorderSizePixel=0 c(HBar,12) HBar.Parent=Win
-- round only top corners hack
local HBarCover=Instance.new("Frame") HBarCover.Size=UDim2.new(1,0,0,12) HBarCover.Position=UDim2.new(0,0,1,-12) HBarCover.BackgroundColor3=T.panel HBarCover.BorderSizePixel=0 HBarCover.Parent=HBar
s(HBar,1,T.border)

-- Greeting a() 
local GREETS={"Hello","Welcome","Hey","Wassup","Yoo"}
local BSUBS={"How can I assist you today?","What could I do for you?","Is there anything else I can help with?","I can code for you"}
local greetLbl=lbl(HBar,GREETS[math.random(#GREETS)].." a()",18,T.text)
greetLbl.Position=UDim2.new(0,90,0,10) greetLbl.Size=UDim2.new(1,-100,0,24) greetLbl.FontFace=Font.new(CF.Family,Enum.FontWeight.Bold)

local dispLbl=lbl(HBar,"",14,T.text) dispLbl.Position=UDim2.new(0,90,0,32) dispLbl.Size=UDim2.new(1,-100,0,18)
local userLbl=lbl(HBar,"",12,T.mute) userLbl.Position=UDim2.new(0,90,0,50) userLbl.Size=UDim2.new(1,-100,0,16)

-- PFP circle
local PfpFrame=Instance.new("Frame") PfpFrame.Size=UDim2.new(0,52,0,52) PfpFrame.Position=UDim2.new(0,12,0,10)
PfpFrame.BackgroundColor3=T.panel2 c(PfpFrame,26) PfpFrame.Parent=HBar
local PfpImg=Instance.new("ImageLabel") PfpImg.Size=UDim2.new(1,0,1,0) PfpImg.BackgroundTransparency=1 PfpImg.ScaleType=Enum.ScaleType.Fit c(PfpImg,26) PfpImg.Parent=PfpFrame

-- Close button
local CloseBtn=Instance.new("TextButton") CloseBtn.Size=UDim2.new(0,26,0,26) CloseBtn.Position=UDim2.new(1,-34,0,8)
CloseBtn.Text="✕" CloseBtn.TextSize=13 CloseBtn.TextColor3=T.mute CloseBtn.BackgroundColor3=T.panel2
CloseBtn.FontFace=CF c(CloseBtn,6) CloseBtn.AutoButtonColor=false CloseBtn.Parent=HBar
CloseBtn.MouseButton1Click:Connect(function() SG:Destroy() end)

-- Fetch pfp async
task.spawn(function()
    local userId=LP.UserId
    local dn,un=fetchDisplayName(userId)
    dispLbl.Text=dn userLbl.Text="@"..un
    greetLbl.Text=GREETS[math.random(#GREETS)].." a()"
    local pfpUrl=fetchPfp(userId)
    if pfpUrl~="" then PfpImg.Image=pfpUrl end
end)

--// BODY (below header)
local Body=Instance.new("Frame") Body.Size=UDim2.new(1,0,1,-72) Body.Position=UDim2.new(0,0,0,72)
Body.BackgroundTransparency=1 Body.Parent=Win

--// LEFT SIDEBAR
local LSide=Instance.new("Frame") LSide.Size=UDim2.new(0,52,1,0) LSide.BackgroundColor3=T.sidebar LSide.BorderSizePixel=0 LSide.Parent=Body
-- border right
local LSBorder=Instance.new("Frame") LSBorder.Size=UDim2.new(0,1,1,0) LSBorder.Position=UDim2.new(1,-1,0,0) LSBorder.BackgroundColor3=T.border LSBorder.BorderSizePixel=0 LSBorder.Parent=LSide
pad(LSide,8,8,6,6) ll(LSide,Enum.FillDirection.Vertical,Enum.HorizontalAlignment.Center,Enum.VerticalAlignment.Top,4)

--// RIGHT SIDEBAR
local RSide=Instance.new("Frame") RSide.Size=UDim2.new(0,52,1,0) RSide.Position=UDim2.new(1,-52,0,0) RSide.BackgroundColor3=T.sidebar RSide.BorderSizePixel=0 RSide.Parent=Body
local RSBorder=Instance.new("Frame") RSBorder.Size=UDim2.new(0,1,1,0) RSBorder.BackgroundColor3=T.border RSBorder.BorderSizePixel=0 RSBorder.Parent=RSide
pad(RSide,8,8,6,6) ll(RSide,Enum.FillDirection.Vertical,Enum.HorizontalAlignment.Center,Enum.VerticalAlignment.Top,4)

--// CONTENT
local Content=Instance.new("Frame") Content.Size=UDim2.new(1,-104,1,0) Content.Position=UDim2.new(0,52,0,0)
Content.BackgroundColor3=T.bg Content.BorderSizePixel=0 Content.Parent=Body

--// Tab system
local TabFrames={} local TabBtns={} local ActiveTab=nil
local function showTab(id)
    for tid,f in pairs(TabFrames) do f.Visible=(tid==id) end
    for tid,b in pairs(TabBtns)   do b.BackgroundTransparency=(tid==id) and 0 or 1 b.BackgroundColor3=(tid==id) and T.accent or T.accent end
    ActiveTab=id
end

local function sideBtn(parent,iconKey,fallback,id)
    local b=Instance.new("TextButton") b.Size=UDim2.new(1,0,0,38) b.BackgroundTransparency=1
    b.BackgroundColor3=T.accent b.Text=fallback b.TextSize=18 b.TextColor3=T.text b.FontFace=CF c(b,8) b.Parent=parent
    local a2=asset(iconKey)
    if a2~="" then
        local img=Instance.new("ImageLabel") img.Size=UDim2.new(0.65,0,0.65,0) img.Position=UDim2.new(0.175,0,0.175,0)
        img.BackgroundTransparency=1 img.ScaleType=Enum.ScaleType.Fit img.Image=a2 img.Parent=b b.Text=""
    end
    local f=Instance.new("Frame") f.Size=UDim2.new(1,0,1,0) f.BackgroundTransparency=1 f.Visible=false f.Parent=Content
    TabFrames[id]=f TabBtns[id]=b
    b.MouseButton1Click:Connect(function() showTab(id) end)
    return b,f
end

-- Left tabs
sideBtn(LSide,"ico_agent","🤖","agent")
sideBtn(LSide,"ico_aimgmt","⚙️","aimgmt")
-- Right tabs
sideBtn(RSide,"ico_changelog","📋","changelog")
sideBtn(RSide,"ico_credits","⭐","credits")
sideBtn(RSide,"ico_settings","🔧","settings")

--// ══════════════════════════════════════════
--// CONSERVATION OVERLAY (overlays entire Win)
--// ══════════════════════════════════════════
local ConvoOverlay=Instance.new("Frame") ConvoOverlay.Size=UDim2.new(1,0,1,0) ConvoOverlay.BackgroundColor3=T.overlay
ConvoOverlay.BackgroundTransparency=0.05 ConvoOverlay.Visible=false ConvoOverlay.ZIndex=15 c(ConvoOverlay,12) ConvoOverlay.Parent=Win

local COHeader=Instance.new("Frame") COHeader.Size=UDim2.new(1,0,0,44) COHeader.BackgroundColor3=T.panel COHeader.BorderSizePixel=0 COHeader.Parent=ConvoOverlay
lbl(COHeader,"Conversations",15,T.text).Position=UDim2.new(0,14,0,0) local coh=COHeader:FindFirstChildOfClass("TextLabel") if coh then coh.Size=UDim2.new(1,-40,1,0) coh.TextYAlignment=Enum.TextYAlignment.Center end

local COScroll=scroll(ConvoOverlay,UDim2.new(1,-16,1,-100),UDim2.new(0,8,44,0)) ll(COScroll,nil,nil,nil,6) pad(COScroll,6,6,0,0)

local CONewBtn=btn(ConvoOverlay,"+ New Conversation",T.accent,T.white,12)
CONewBtn.Size=UDim2.new(1,-16,0,30) CONewBtn.Position=UDim2.new(0,8,1,-40)

local ConvoOpen=false
local function refreshConvoList()
    for _,ch in ipairs(COScroll:GetChildren()) do if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end end
    if #ConvoData.sessions==0 then
        local el=lbl(COScroll,"No saved conversations.",12,T.mute,Enum.TextXAlignment.Center) el.Size=UDim2.new(1,0,0,20) el.TextTransparency=0.4
        return
    end
    for i,sess in ipairs(ConvoData.sessions) do
        local row=Instance.new("Frame") row.Size=UDim2.new(1,0,0,44) row.BackgroundColor3=T.panel2 c(row,8) s(row,1,T.border) row.Parent=COScroll
        local nl=lbl(row,sess.name or ("Session "..sess.id),13,T.text) nl.Position=UDim2.new(0,10,0,6) nl.Size=UDim2.new(1,-80,0,18)
        local dl=lbl(row,tostring(#(sess.messages or {})).." messages",11,T.mute) dl.Position=UDim2.new(0,10,0,24) dl.Size=UDim2.new(1,-80,0,16)
        -- Hold detection for rename/delete
        local holding,hthread=false
        local loadBtn=Instance.new("TextButton") loadBtn.Size=UDim2.new(0,50,0,28) loadBtn.Position=UDim2.new(1,-56,0.5,-14)
        loadBtn.Text="Load" loadBtn.TextSize=11 loadBtn.TextColor3=T.white loadBtn.BackgroundColor3=T.accentD loadBtn.FontFace=CF c(loadBtn,5) loadBtn.Parent=row
        loadBtn.MouseButton1Click:Connect(function()
            ActiveSessionId=sess.id ChatHistory=sess.messages or {}
            ConvoOverlay.Visible=false ConvoOpen=false showTab("agent")
        end)
        -- Long press
        local pressTime=0
        row.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.MouseButton1 then
                pressTime=tick()
                hthread=task.delay(0.6,function()
                    -- context popup
                    local cp=popup(200,100,30) cp.Position=UDim2.new(0,row.AbsolutePosition.X-Win.AbsolutePosition.X,0,row.AbsolutePosition.Y-Win.AbsolutePosition.Y+44)
                    local rn=btn(cp,"Rename",T.panel2,T.text,12) rn.Size=UDim2.new(1,-12,0,28) rn.Position=UDim2.new(0,6,0,8)
                    rn.MouseButton1Click:Connect(function()
                        cp.Visible=false
                        local np=popup(240,90,31) popupClose(np)
                        lbl(np,"New name:",12,T.mute).Position=UDim2.new(0,12,0,10)
                        local ntb=tbox(np,"Session name...") ntb.Position=UDim2.new(0,12,0,28) ntb.Size=UDim2.new(1,-24,0,26)
                        local sb2=btn(np,"Save",T.accent,T.white,12) sb2.Size=UDim2.new(1,-24,0,24) sb2.Position=UDim2.new(0,12,0,58)
                        sb2.MouseButton1Click:Connect(function() sess.name=ntb.Text saveConvo() np:Destroy() refreshConvoList() end)
                        np.Visible=true
                    end)
                    local dl2=btn(cp,"Delete",T.danger,T.white,12) dl2.Size=UDim2.new(1,-12,0,28) dl2.Position=UDim2.new(0,6,0,40)
                    dl2.MouseButton1Click:Connect(function()
                        cp.Visible=false table.remove(ConvoData.sessions,i) saveConvo() refreshConvoList()
                    end)
                    cp.Visible=true
                end)
            end
        end)
        row.InputEnded:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.MouseButton1 then if hthread then task.cancel(hthread) end end
        end)
    end
end
CONewBtn.MouseButton1Click:Connect(function()
    local id=ConvoData.nextId or (#ConvoData.sessions+1)
    ConvoData.nextId=(ConvoData.nextId or 1)+1
    local sess={id=id,name="Session "..id,messages={}}
    table.insert(ConvoData.sessions,sess)
    ActiveSessionId=id ChatHistory={} saveConvo()
    ConvoOverlay.Visible=false ConvoOpen=false showTab("agent")
end)

--// ══════════════════════════════════════════
--// TAB: AGENT
--// ══════════════════════════════════════════
local AgF=TabFrames["agent"]

-- Top row with convo icon
local AgTop=Instance.new("Frame") AgTop.Size=UDim2.new(1,0,0,40) AgTop.BackgroundTransparency=1 AgTop.Parent=AgF
local AgTitle=lbl(AgTop,"Hello",20,T.text) AgTitle.Position=UDim2.new(0,12,0,4) AgTitle.Size=UDim2.new(1,-60,0,26) AgTitle.FontFace=Font.new(CF.Family,Enum.FontWeight.Bold)
local AgSub=lbl(AgTop,LPName,13,T.mute) AgSub.Position=UDim2.new(0,12,0,28) AgSub.Size=UDim2.new(1,-60,0,16)
-- b() subtitle
local BSUB_lbl=lbl(AgTop,BSUBS[math.random(#BSUBS)],11,T.mute) BSUB_lbl.TextTransparency=0.3 BSUB_lbl.Position=UDim2.new(0,12,0,46) BSUB_lbl.Size=UDim2.new(1,-60,0,16)
AgTop.Size=UDim2.new(1,0,0,64)

-- Convo icon button
local ConvoIconBtn=imgBtn(AgTop,"ico_convo",UDim2.new(0,30,0,30))
ConvoIconBtn.Position=UDim2.new(1,-36,0,6)
ConvoIconBtn.MouseButton1Click:Connect(function()
    ConvoOpen=not ConvoOpen
    if ConvoOpen then refreshConvoList() ConvoOverlay.Visible=true
    else ConvoOverlay.Visible=false end
end)
-- fallback text if no icon
if ConvoIconBtn.Image=="" then ConvoIconBtn=nil
    local cb2=Instance.new("TextButton") cb2.Size=UDim2.new(0,30,0,30) cb2.Position=UDim2.new(1,-36,0,6)
    cb2.Text="💬" cb2.TextSize=16 cb2.BackgroundTransparency=1 cb2.FontFace=CF cb2.TextColor3=T.accent cb2.Parent=AgTop
    cb2.MouseButton1Click:Connect(function()
        ConvoOpen=not ConvoOpen
        if ConvoOpen then refreshConvoList() ConvoOverlay.Visible=true else ConvoOverlay.Visible=false end
    end)
end

-- No-agent screen
local NAS=Instance.new("Frame") NAS.Size=UDim2.new(1,0,1,-64) NAS.Position=UDim2.new(0,0,0,64) NAS.BackgroundTransparency=1 NAS.Parent=AgF
ll(NAS,Enum.FillDirection.Vertical,Enum.HorizontalAlignment.Center,Enum.VerticalAlignment.Center,6)
local naL1=lbl(NAS,"No AI agents configured.",13,T.mute,Enum.TextXAlignment.Center) naL1.Size=UDim2.new(1,-20,0,20) naL1.TextTransparency=0.4
local naLink=Instance.new("TextButton") naLink.Size=UDim2.new(0,160,0,20) naLink.BackgroundTransparency=1 naLink.Text="Go to AI Management" naLink.TextSize=12 naLink.TextColor3=T.accent naLink.FontFace=CF naLink.Parent=NAS
local uline=Instance.new("Frame") uline.Size=UDim2.new(1,0,0,1) uline.Position=UDim2.new(0,0,1,-1) uline.BackgroundColor3=T.accent uline.BorderSizePixel=0 uline.Parent=naLink
naLink.MouseButton1Click:Connect(function() showTab("aimgmt") end)

-- Chat screen
local CS=Instance.new("Frame") CS.Size=UDim2.new(1,0,1,-64) CS.Position=UDim2.new(0,0,0,64) CS.BackgroundTransparency=1 CS.Visible=false CS.Parent=AgF

local MsgScroll=scroll(CS,UDim2.new(1,-16,1,-108),UDim2.new(0,8,0,0)) ll(MsgScroll,nil,nil,nil,6) pad(MsgScroll,4,4,0,0)

-- Rate limit warn
local RLW=Instance.new("Frame") RLW.Size=UDim2.new(1,-16,0,36) RLW.Position=UDim2.new(0,8,1,-106) RLW.BackgroundColor3=T.danger RLW.Visible=false c(RLW,6) RLW.Parent=CS
local RLTxt=lbl(RLW,"",11,T.white) RLTxt.Position=UDim2.new(0,8,0,4) RLTxt.Size=UDim2.new(1,-16,0,14)
local RLRow=Instance.new("Frame") RLRow.Size=UDim2.new(1,0,0,18) RLRow.Position=UDim2.new(0,0,1,-20) RLRow.BackgroundTransparency=1 RLRow.Visible=false RLRow.Parent=RLW
local RLCA=btn(RLRow,"Continue",T.accentD,T.white,10) RLCA.Size=UDim2.new(0.48,0,1,0) RLCA.Position=UDim2.new(0.01,0,0,0)
local RLNC=btn(RLRow,"New Chat",T.panel2,T.text,10) RLNC.Size=UDim2.new(0.48,0,1,0) RLNC.Position=UDim2.new(0.51,0,0,0)
RLCA.MouseButton1Click:Connect(function() RLW.Visible=false end)
RLNC.MouseButton1Click:Connect(function() RLW.Visible=false ChatHistory={} for _,ch in ipairs(MsgScroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end end)

-- Input area (squircle shape)
local InputArea=Instance.new("Frame") InputArea.Size=UDim2.new(1,-16,0,60) InputArea.Position=UDim2.new(0,8,1,-68)
InputArea.BackgroundColor3=T.panel2 c(InputArea,14) s(InputArea,1,T.border) InputArea.Parent=CS

local CI=Instance.new("TextBox") CI.Size=UDim2.new(1,-72,1,-12) CI.Position=UDim2.new(0,10,0,6)
CI.BackgroundTransparency=1 CI.Text="" CI.PlaceholderText="Message..." CI.PlaceholderColor3=T.mute
CI.TextColor3=T.text CI.TextSize=13 CI.FontFace=CF CI.TextXAlignment=Enum.TextXAlignment.Left
CI.TextYAlignment=Enum.TextYAlignment.Top CI.ClearTextOnFocus=false CI.MultiLine=true CI.TextWrapped=true CI.Parent=InputArea

-- Attach button
local AttachBtn=imgBtn(InputArea,"ico_attach",UDim2.new(0,26,0,26)) AttachBtn.Position=UDim2.new(1,-60,1,-32)
if AttachBtn.Image=="" then AttachBtn.Image="" local af=Instance.new("TextButton") af.Size=UDim2.new(0,26,0,26) af.Position=UDim2.new(1,-60,1,-32) af.Text="📎" af.TextSize=14 af.BackgroundTransparency=1 af.FontFace=CF af.TextColor3=T.mute af.Parent=InputArea AttachBtn=af end

-- Send button
local SendBtn=imgBtn(InputArea,"ico_send",UDim2.new(0,28,0,28)) SendBtn.Position=UDim2.new(1,-30,1,-34)
if SendBtn.Image=="" then local sf=Instance.new("TextButton") sf.Size=UDim2.new(0,28,0,28) sf.Position=UDim2.new(1,-30,1,-34) sf.Text="↑" sf.TextSize=16 sf.TextColor3=T.white sf.BackgroundColor3=T.accent sf.FontFace=CF c(sf,8) sf.Parent=InputArea SendBtn=sf end

-- Attach popup (workspace file browser)
local AttachPop=popup(280,320,25) popupClose(AttachPop)
lbl(AttachPop,"Attach File",14,T.text,Enum.TextXAlignment.Center).Position=UDim2.new(0,0,0,10)
local APScroll=scroll(AttachPop,UDim2.new(1,-16,1,-50),UDim2.new(0,8,40,0)) ll(APScroll,nil,nil,nil,4) pad(APScroll,4,4,0,0)
local AttachedContent=""
local function buildFileTree(parent,path,depth)
    depth=depth or 0 if depth>3 then return end
    local files=rfold(path)
    for _,fp in ipairs(files) do
        local name=fp:match("[/\\]([^/\\]+)$") or fp
        local isF=ifs(fp)
        local rb=Instance.new("TextButton") rb.Size=UDim2.new(1,0,0,22) rb.BackgroundTransparency=1
        rb.Text=string.rep("  ",depth)..(isF and "📄 " or "📁 ")..name rb.TextSize=11 rb.TextColor3=isF and T.text or T.mute
        rb.FontFace=CF rb.TextXAlignment=Enum.TextXAlignment.Left rb.Parent=parent
        if isF then rb.MouseButton1Click:Connect(function() local d=rfs(fp) if d then AttachedContent="[FILE:"..name.."]\n"..d end AttachPop.Visible=false end)
        else rb.MouseButton1Click:Connect(function() buildFileTree(parent,fp,depth+1) end) end
    end
end
AttachBtn.MouseButton1Click:Connect(function()
    for _,ch in ipairs(APScroll:GetChildren()) do if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end end
    buildFileTree(APScroll,"zrxc") AttachPop.Visible=true
end)

local Thinking=nil
local function addBubble(text,isUser)
    local bub=Instance.new("Frame") bub.Size=UDim2.new(1,0,0,0) bub.AutomaticSize=Enum.AutomaticSize.Y
    bub.BackgroundColor3=isUser and T.accent or T.panel2 c(bub,10) pad(bub,8,8,12,12)
    local tl=Instance.new("TextLabel") tl.Size=UDim2.new(1,0,0,0) tl.AutomaticSize=Enum.AutomaticSize.Y
    tl.BackgroundTransparency=1 tl.Text=text tl.TextSize=12 tl.TextColor3=T.text
    tl.FontFace=CF tl.TextXAlignment=Enum.TextXAlignment.Left tl.TextWrapped=true tl.Parent=bub
    bub.Parent=MsgScroll task.wait() MsgScroll.CanvasPosition=Vector2.new(0,MsgScroll.AbsoluteCanvasSize.Y) return bub
end

local function updateAgentUI()
    local has=#AgentData.list>0 NAS.Visible=not has CS.Visible=has
end

local function doSend()
    local msg=CI.Text if msg=="" and AttachedContent=="" then return end
    local full=msg..(AttachedContent~="" and ("\n"..AttachedContent) or "")
    CI.Text="" AttachedContent=""
    addBubble(full,true) Thinking=addBubble("...",false)
    task.spawn(function()
        local rep,err,swi=callAI(full)
        if Thinking then Thinking:Destroy() Thinking=nil end
        if rep then
            if swi then local ag=AgentData.list[swi] RLTxt.Text="Switched to Agent"..(ag and ag.id or "?") RLRow.Visible=true RLW.Size=UDim2.new(1,-16,0,56) RLW.Visible=true end
            addBubble(rep,false)
            -- Save to session
            for _,sess in ipairs(ConvoData.sessions) do if sess.id==ActiveSessionId then sess.messages=ChatHistory break end end
            saveConvo()
        elseif err=="NO_AGENTS" then addBubble("No agents. Go to AI Management.",false)
        elseif err=="ALL_RL" then RLTxt.Text="All agents rate limited." RLRow.Visible=false RLW.Size=UDim2.new(1,-16,0,36) RLW.Visible=true
        else addBubble("Error: "..tostring(err),false) end
    end)
end
SendBtn.MouseButton1Click:Connect(doSend)
CI.FocusLost:Connect(function(enter) if enter then doSend() end end)
-- Restore history
for _,m in ipairs(ChatHistory) do addBubble(m.content,m.role=="user") end

--// ══════════════════════════════════════════
--// TAB: AI MANAGEMENT
--// ══════════════════════════════════════════
local AIF=TabFrames["aimgmt"]

-- Top credentials section
local CredFrame=Instance.new("Frame") CredFrame.Size=UDim2.new(1,-16,0,138) CredFrame.Position=UDim2.new(0,8,0,8)
CredFrame.BackgroundColor3=T.panel2 c(CredFrame,10) s(CredFrame,1,T.border) CredFrame.Parent=AIF
pad(CredFrame,10,10,12,12) ll(CredFrame,nil,nil,nil,6)

-- API Key row
local AKRow=Instance.new("Frame") AKRow.Size=UDim2.new(1,0,0,28) AKRow.BackgroundTransparency=1 AKRow.Parent=CredFrame
local AKIcon=imgBtn(AKRow,"ico_apikey",UDim2.new(0,20,0,20)) AKIcon.Position=UDim2.new(0,0,0.5,-10) if AKIcon.Image=="" then AKIcon.Image="" end
local AKBox=tbox(AKRow,"API Key...") AKBox.Size=UDim2.new(1,-110,1,0) AKBox.Position=UDim2.new(0,26,0,0) AKBox.BackgroundColor3=T.panel
local AKConfirm=Instance.new("TextButton") AKConfirm.Size=UDim2.new(0,70,1,0) AKConfirm.Position=UDim2.new(1,-70,0,0)
AKConfirm.Text="Confirm" AKConfirm.TextSize=11 AKConfirm.TextColor3=T.white AKConfirm.BackgroundColor3=T.accent AKConfirm.FontFace=CF c(AKConfirm,5) AKConfirm.Parent=AKRow

-- Model Name row
local MRow=Instance.new("Frame") MRow.Size=UDim2.new(1,0,0,28) MRow.BackgroundTransparency=1 MRow.Parent=CredFrame
local MIcon=imgBtn(MRow,"ico_model",UDim2.new(0,20,0,20)) MIcon.Position=UDim2.new(0,0,0.5,-10)
local MBox=tbox(MRow,"Model Name...") MBox.Size=UDim2.new(1,-54,1,0) MBox.Position=UDim2.new(0,26,0,0) MBox.BackgroundColor3=T.panel
local MSearch=imgBtn(MRow,"ico_search",UDim2.new(0,24,0,24)) MSearch.Position=UDim2.new(1,-26,0.5,-12)
if MSearch.Image=="" then MSearch.Image="" local ms2=Instance.new("TextButton") ms2.Size=UDim2.new(0,24,0,24) ms2.Position=UDim2.new(1,-26,0.5,-12) ms2.Text="🔍" ms2.TextSize=14 ms2.BackgroundTransparency=1 ms2.FontFace=CF ms2.TextColor3=T.mute ms2.Parent=MRow MSearch=ms2 end

-- Host dropdown row
local HRow=Instance.new("Frame") HRow.Size=UDim2.new(1,0,0,28) HRow.BackgroundTransparency=1 HRow.Parent=CredFrame
local HIcon=imgBtn(HRow,"ico_host",UDim2.new(0,20,0,20)) HIcon.Position=UDim2.new(0,0,0.5,-10)
local HBtn=Instance.new("TextButton") HBtn.Size=UDim2.new(1,-26,1,0) HBtn.Position=UDim2.new(0,26,0,0)
HBtn.Text="Host: (select)" HBtn.TextSize=12 HBtn.TextColor3=T.text HBtn.BackgroundColor3=T.panel HBtn.FontFace=CF HBtn.TextXAlignment=Enum.TextXAlignment.Left
c(HBtn,6) pad(HBtn,0,0,8,8) HBtn.Parent=HRow
local SelectedHost=""

-- Host dropdown popup
local HDrop=popup(200,200,30)
local HPROVS={{"HuggingFace","ico_hf"},{"Google","ico_google"},{"Anthropic","ico_anthropic"},{"OpenAI","ico_openai"},{"Grok","ico_grok"},{"DeepSeek","ico_deepseek"}}
pad(HDrop,8,8,8,8) ll(HDrop,nil,nil,nil,4)
for _,pv in ipairs(HPROVS) do
    local pr=Instance.new("Frame") pr.Size=UDim2.new(1,0,0,26) pr.BackgroundTransparency=1 pr.Parent=HDrop
    local pi=imgBtn(pr,pv[2],UDim2.new(0,20,0,20)) pi.Position=UDim2.new(0,0,0.5,-10)
    local pb=Instance.new("TextButton") pb.Size=UDim2.new(1,-28,1,0) pb.Position=UDim2.new(0,28,0,0)
    pb.Text=pv[1] pb.TextSize=12 pb.TextColor3=T.text pb.BackgroundTransparency=1 pb.FontFace=CF pb.TextXAlignment=Enum.TextXAlignment.Left pb.Parent=pr
    pb.MouseButton1Click:Connect(function() SelectedHost=pv[1] HBtn.Text="Host: "..pv[1] HDrop.Visible=false end)
end
popupClose(HDrop)
HBtn.MouseButton1Click:Connect(function() HDrop.Position=UDim2.new(0,HRow.AbsolutePosition.X-Win.AbsolutePosition.X+26,0,HRow.AbsolutePosition.Y-Win.AbsolutePosition.Y-200) HDrop.Visible=not HDrop.Visible end)

-- Model search popup
local MSPop=popup(260,300,30) popupClose(MSPop)
lbl(MSPop,"Model Database",14,T.text,Enum.TextXAlignment.Center).Position=UDim2.new(0,0,0,10)
local MSScroll=scroll(MSPop,UDim2.new(1,-16,1,-50),UDim2.new(0,8,40,0)) ll(MSScroll,nil,nil,nil,4) pad(MSScroll,4,4,0,0)
MSearch.MouseButton1Click:Connect(function()
    for _,ch in ipairs(MSScroll:GetChildren()) do if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end end
    task.spawn(function()
        local MODEL_DB_URL="https://raw.githubusercontent.com/DeflectEncrypt/xoajne/refs/heads/main/models"
        local ok2=pcall(function()
            local r=req({Url=MODEL_DB_URL,Method="GET"})
            if r and r.Body then
                for line in (r.Body.."\n"):gmatch("([^\n]*)\n") do
                    if line~="" then
                        local mb=Instance.new("TextButton") mb.Size=UDim2.new(1,0,0,20) mb.BackgroundTransparency=1
                        mb.Text=line mb.TextSize=11 mb.TextColor3=T.text mb.FontFace=CF mb.TextXAlignment=Enum.TextXAlignment.Left mb.Parent=MSScroll
                        mb.MouseButton1Click:Connect(function() MBox.Text=line MSPop.Visible=false end)
                    end
                end
            else lbl(MSScroll,"Could not fetch model list.",11,T.mute) end
        end)
        if not ok2 then print("url is gone") lbl(MSScroll,"Model DB unavailable.",11,T.mute) end
    end)
    MSPop.Visible=true
end)

-- Agent list
local AGListScroll=scroll(AIF,UDim2.new(1,-16,1,-210),UDim2.new(0,8,154,0)) ll(AGListScroll,nil,nil,nil,6) pad(AGListScroll,4,4,0,0)

-- Add AI button (only shows if at least 1 agent exists)
local AddAIBtn=btn(AIF,"+ Add AI",T.accent,T.white,12)
AddAIBtn.Size=UDim2.new(1,-16,0,30) AddAIBtn.Position=UDim2.new(0,8,1,-40)
AddAIBtn.Visible=false

local pendingDel2=nil
local ConfPop2=popup(280,110,25) popupClose(ConfPop2)
local cpLbl2=lbl(ConfPop2,"Delete this agent? Cannot be undone.",12,T.text,Enum.TextXAlignment.Center) cpLbl2.Position=UDim2.new(0,10,0,14) cpLbl2.Size=UDim2.new(1,-20,0,24)
local cpY2=btn(ConfPop2,"Delete",T.danger,T.white,12) cpY2.Size=UDim2.new(0.44,0,0,28) cpY2.Position=UDim2.new(0.04,0,0,56)
local cpN2=btn(ConfPop2,"Cancel",T.panel2,T.text,12) cpN2.Size=UDim2.new(0.44,0,0,28) cpN2.Position=UDim2.new(0.52,0,0,56)
cpN2.MouseButton1Click:Connect(function() ConfPop2.Visible=false end)

local function refreshAgList()
    for _,ch in ipairs(AGListScroll:GetChildren()) do if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end end
    AddAIBtn.Visible=#AgentData.list>0
    if #AgentData.list==0 then
        local el=lbl(AGListScroll,"No agents yet.",13,T.mute,Enum.TextXAlignment.Center) el.Size=UDim2.new(1,0,0,20) el.TextTransparency=0.4
        return
    end
    for i,ag in ipairs(AgentData.list) do
        local row=Instance.new("Frame") row.Size=UDim2.new(1,0,0,44) row.BackgroundColor3=T.panel2 c(row,8) s(row,1,T.border) row.Parent=AGListScroll
        local nl=lbl(row,"Agent"..ag.id.."  |  ["..ag.host.."]  "..ag.model,12,T.text) nl.Position=UDim2.new(0,10,0,6) nl.Size=UDim2.new(1,-50,0,18)
        local kl=lbl(row,(ag.apiKey and ag.apiKey~="" and "Key: ••••"..ag.apiKey:sub(-4) or "No key"),11,T.mute) kl.Position=UDim2.new(0,10,0,24) kl.Size=UDim2.new(1,-50,0,16)
        local del=Instance.new("TextButton") del.Size=UDim2.new(0,30,0,30) del.Position=UDim2.new(1,-38,0.5,-15) del.Text="✕" del.TextSize=13 del.TextColor3=T.danger del.BackgroundTransparency=1 del.FontFace=CF del.Parent=row
        local idx=i del.MouseButton1Click:Connect(function() pendingDel2=idx ConfPop2.Visible=true end)
        -- Long press for sort/delete panel (reuses convo overlay concept)
        local hthread2
        row.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.MouseButton1 then
                hthread2=task.delay(0.6,function()
                    local cp=popup(180,90,30) cp.Position=UDim2.new(0,row.AbsolutePosition.X-Win.AbsolutePosition.X,0,row.AbsolutePosition.Y-Win.AbsolutePosition.Y+44)
                    local mv=btn(cp,"Move Up",T.panel2,T.text,11) mv.Size=UDim2.new(1,-12,0,26) mv.Position=UDim2.new(0,6,0,8)
                    mv.MouseButton1Click:Connect(function() if idx>1 then local t=AgentData.list[idx] AgentData.list[idx]=AgentData.list[idx-1] AgentData.list[idx-1]=t saveAgents() cp:Destroy() refreshAgList() end end)
                    local dl3=btn(cp,"Delete",T.danger,T.white,11) dl3.Size=UDim2.new(1,-12,0,26) dl3.Position=UDim2.new(0,6,0,38)
                    dl3.MouseButton1Click:Connect(function() pendingDel2=idx ConfPop2.Visible=true cp:Destroy() end)
                    cp.Visible=true
                end)
            end
        end)
        row.InputEnded:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 then if hthread2 then task.cancel(hthread2) end end end)
    end
    updateAgentUI()
end

cpY2.MouseButton1Click:Connect(function()
    if not pendingDel2 then return end
    table.remove(AgentData.list,pendingDel2) pendingDel2=nil ConfPop2.Visible=false
    if #AgentData.list==0 then AgentData.nextId=1 end
    saveAgents() refreshAgList() updateAgentUI()
end)

-- Confirm dialogue when adding agent with existing creds
local function confirmAddAgent()
    local key=AKBox.Text local model=MBox.Text local host=SelectedHost
    if key=="" or model=="" or host=="" then
        -- highlight empty
        if key==""   then s(AKBox,2,T.danger) task.delay(1.5,function() s(AKBox,1,T.border) end) end
        if model=="" then s(MBox,2,T.danger)  task.delay(1.5,function() s(MBox,1,T.border) end) end
        if host==""  then HBtn.BackgroundColor3=T.danger task.delay(1.5,function() HBtn.BackgroundColor3=T.panel end) end
        return
    end
    local cdlg=popup(280,110,30) popupClose(cdlg)
    lbl(cdlg,"Add agent? ("..host.." / "..model..")",12,T.text,Enum.TextXAlignment.Center).Position=UDim2.new(0,10,0,14)
    local cy=btn(cdlg,"Confirm",T.accent,T.white,12) cy.Size=UDim2.new(0.44,0,0,28) cy.Position=UDim2.new(0.04,0,0,56)
    local cn=btn(cdlg,"Cancel",T.panel2,T.text,12) cn.Size=UDim2.new(0.44,0,0,28) cn.Position=UDim2.new(0.52,0,0,56)
    cn.MouseButton1Click:Connect(function() cdlg:Destroy() end)
    cy.MouseButton1Click:Connect(function()
        local id=AgentData.nextId AgentData.nextId=id+1
        AgentData.list[#AgentData.list+1]={id=id,host=host,apiKey=key,model=model,active=false}
        saveAgents() AKBox.Text="" MBox.Text="" HBtn.Text="Host: (select)" SelectedHost=""
        cdlg:Destroy() refreshAgList()
    end)
    cdlg.Visible=true
end
AKConfirm.MouseButton1Click:Connect(confirmAddAgent)
AddAIBtn.MouseButton1Click:Connect(confirmAddAgent)
refreshAgList()

--// ══════════════════════════════════════════
--// TAB: CHANGELOG
--// ══════════════════════════════════════════
local CLF=TabFrames["changelog"]
local CLScroll=scroll(CLF,UDim2.new(1,-16,1,-16),UDim2.new(0,8,8,0)) ll(CLScroll,nil,nil,nil,4) pad(CLScroll,6,6,0,0)
-- Non-interactable overlay
local CLBlock=Instance.new("Frame") CLBlock.Size=UDim2.new(1,0,1,0) CLBlock.BackgroundTransparency=1 CLBlock.Parent=CLF
task.spawn(function()
    local ok2=pcall(function()
        local r=req({Url=CHANGELOG_URL,Method="GET"})
        if r and r.Body then parseFormatted(CLScroll,r.Body)
        else lbl(CLScroll,"Could not load changelogs.",12,T.mute) end
    end)
    if not ok2 then print("credits url gone") lbl(CLScroll,"Changelogs unavailable.",12,T.mute) end
end)

--// ══════════════════════════════════════════
--// TAB: CREDITS
--// ══════════════════════════════════════════
local CRF=TabFrames["credits"]
local CRScroll=scroll(CRF,UDim2.new(1,-16,1,-16),UDim2.new(0,8,8,0)) ll(CRScroll,nil,nil,nil,4) pad(CRScroll,6,6,0,0)
local CRBlock=Instance.new("Frame") CRBlock.Size=UDim2.new(1,0,1,0) CRBlock.BackgroundTransparency=1 CRBlock.Parent=CRF
task.spawn(function()
    local ok2=pcall(function()
        local r=req({Url=CREDITS_URL,Method="GET"})
        if r and r.Body then parseFormatted(CRScroll,r.Body)
        else lbl(CRScroll,"Could not load credits.",12,T.mute) end
    end)
    if not ok2 then print("sigma url gone") lbl(CRScroll,"Credits unavailable.",12,T.mute) end
end)

--// ══════════════════════════════════════════
--// TAB: SETTINGS
--// ══════════════════════════════════════════
local STF=TabFrames["settings"]
local StScroll=scroll(STF,UDim2.new(1,-16,1,-30),UDim2.new(0,8,8,0)) ll(StScroll,nil,nil,nil,6) pad(StScroll,6,6,0,0)

local _,setAutoExec=toggle(StScroll,"Auto-Execute (queueonteleport)",Settings.autoExecute,function(v)
    Settings.autoExecute=v saveSetting()
    if v then pcall(function() local sc=rfs("zrxc/autoexec.lua") if sc then queueonteleport(sc) end end) end
end)

local autoSwitchToggle,setAutoSwitch=toggle(StScroll,"Auto-Switch on Rate Limit",Settings.autoSwitch,function(v)
    -- If no agents, disable and revert
    if v and #AgentData.list==0 then setAutoSwitch(false) return end
    Settings.autoSwitch=v saveSetting()
end)

local custBtn=btn(StScroll,"Customise Instructions",T.panel2,T.text,12)
custBtn.MouseButton1Click:Connect(function()
    print("[AIGui] Please go to zrxc/ai/instructions.txt and modify the Instructions.txt file directly.")
end)

local clrBtn=btn(StScroll,"Clear Cache",T.panel2,T.text,12)
clrBtn.MouseButton1Click:Connect(function()
    RemoteLog={} clrBtn.Text="Cleared!" task.delay(2,function() clrBtn.Text="Clear Cache" end)
end)

local dbgBtn=btn(StScroll,"Fetch Debug (Copy to Clipboard)",T.panel2,T.text,12)
dbgBtn.MouseButton1Click:Connect(function()
    local info={agents=#AgentData.list,remotes=#RemoteLog,spyActive=SpyActive,settings=Settings,t=os.clock()}
    local ok2,enc=pcall(jenc,info) if ok2 and enc then pcall(setclipboard,enc) end
    dbgBtn.Text="Copied!" task.delay(2,function() dbgBtn.Text="Fetch Debug (Copy to Clipboard)" end)
end)

local helloLbl=lbl(STF,"Hello..!",11,T.mute,Enum.TextXAlignment.Right)
helloLbl.TextTransparency=0.4 helloLbl.Position=UDim2.new(0,0,1,-22) helloLbl.Size=UDim2.new(1,-10,0,18)

-- Watch agent list for autoswitch guard
task.spawn(function()
    while task.wait(2) do
        if Settings.autoSwitch and #AgentData.list==0 then
            Settings.autoSwitch=false setAutoSwitch(false) saveSetting()
        end
    end
end)

--// Init
showTab("agent")
updateAgentUI()
