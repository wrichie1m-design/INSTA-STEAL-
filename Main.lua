if not fireproximityprompt then
    fireproximityprompt = (getgenv and getgenv().fireproximityprompt)
        or (genv and genv().fireproximityprompt)
        or function(prompt)
            pcall(function()
                prompt:InputHoldBegin()
                task.wait(0.05)
                prompt:InputHoldEnd()
            end)
        end
end

local UIS          = game:GetService("UserInputService")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui      = game:GetService("CoreGui")
local HttpService  = game:GetService("HttpService")

local lp = Players.LocalPlayer

pcall(function()
    if CoreGui:FindFirstChild("GARAMA_AUTO_GRAB") then
        CoreGui:FindFirstChild("GARAMA_AUTO_GRAB"):Destroy()
    end
    local pg = lp:FindFirstChild("PlayerGui")
    if pg and pg:FindFirstChild("GaramaBarGui") then
        pg:FindFirstChild("GaramaBarGui"):Destroy()
    end
end)

local CONFIG_FILE = "GaramaAutoGrab_Config.json"
local cfg = {}

local function saveConfig()
    if writefile then
        pcall(writefile, CONFIG_FILE, HttpService:JSONEncode(cfg))
    end
end

local function loadConfig()
    if isfile and isfile(CONFIG_FILE) then
        local ok, raw = pcall(readfile, CONFIG_FILE)
        if ok and raw then
            local ok2, d = pcall(HttpService.JSONDecode, HttpService, raw)
            if ok2 and d then cfg = d; return end
        end
    end
    cfg = {
        hubPos   = { px = 60,  py = 120 },
        barPos   = { px = -1,  py = -1  },
        radius   = 12,
        duration = 0.15,
        active   = true,
    }
    saveConfig()
end

loadConfig()

task.spawn(function()
    while true do task.wait(8); saveConfig() end
end)

local Screen = Instance.new("ScreenGui")
Screen.Name           = "GARAMA_AUTO_GRAB"
Screen.ResetOnSpawn   = false
Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Screen.Parent         = CoreGui

local C = {
    Black     = Color3.fromRGB(15, 0, 0),
    Gray      = Color3.fromRGB(120, 40, 40),
    LightGray = Color3.fromRGB(180, 60, 60),
    White     = Color3.fromRGB(255, 240, 240),
    Dim       = Color3.fromRGB(60, 10, 10),
    TogOff    = Color3.fromRGB(35, 15, 15),
    Green     = Color3.fromRGB(255, 40, 40), -- RED THEME
    Red       = Color3.fromRGB(80, 0, 0),
    MainRed   = Color3.fromRGB(220, 20, 20),
}

local STROKE_ACTIVE = Color3.fromRGB(255, 50, 50)
local STROKE_IDLE   = Color3.fromRGB(120, 20, 20)

local function New(class, props)
    local o = Instance.new(class)
    for k, v in pairs(props) do if k ~= "Parent" then o[k] = v end end
    o.Parent = props.Parent
    return o
end

local function applyHubGradient(frame)
    local g = Instance.new("UIGradient", frame)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 0, 0)),
    })
    g.Rotation = 135
    RunService.Heartbeat:Connect(function(dt)
        if not g or not g.Parent then return end
        g.Rotation = (g.Rotation + 15 * dt) % 360
    end)
    return g
end

local ghostReg = {}
local ghostT   = 0

RunService.Heartbeat:Connect(function(dt)
    if #ghostReg == 0 then return end
    ghostT = ghostT + 1
    if ghostT < 2 then return end
    ghostT = 0
    local dt2 = dt * 2
    local i = 1
    while i <= #ghostReg do
        local g = ghostReg[i]
        if not g.f or not g.f.Parent then
            pcall(function() g.l:Destroy() end)
            table.remove(ghostReg, i)
        else
            g.wp = g.wp + g.ws
            g.y  = g.y  + g.sp * 60 * dt2
            g.l.Position = UDim2.new(g.x + math.sin(g.wp) * g.wa, 0, g.y, 0)
            if g.y < 0.05 then g.l.TextTransparency = 1 - g.op*(g.y+0.15)/0.20
            elseif g.y > 0.75 then g.l.TextTransparency = 1 - g.op*(1-(g.y-0.75)/0.30)
            else g.l.TextTransparency = 1 - g.op end
            if g.y > 1.1 then
                g.y=-.15; g.x=math.random(0,90)/100
                g.sp=.0008+math.random()*.0012
                g.wa=.03+math.random()*.04
                g.op=.35+math.random()*.45
                local sz=math.random(10,18)
                g.l.TextSize=sz; g.l.Size=UDim2.new(0,sz+4,0,sz+4)
            end
            i = i + 1
        end
    end
end)

local function Ghost(frame, n)
    frame.ClipsDescendants = true
    for k = 1, (n or 5) do
        task.delay((k-1)*0.3, function()
            if not frame.Parent then return end
            local l = Instance.new("TextLabel", frame)
            l.BackgroundTransparency = 1
            l.Text = "🔥"
            l.TextColor3 = C.MainRed
            l.ZIndex = (frame.ZIndex or 5) + 1
            l.BorderSizePixel = 0
            local sz = math.random(10, 18)
            l.TextSize = sz
            l.Size = UDim2.new(0, sz+4, 0, sz+4)
            l.TextTransparency = 1
            local g = {
                f  = frame, l = l,
                x  = math.random(0,90)/100,
                y  = -.15 - math.random()*.5,
                sp = .0008 + math.random()*.0012,
                wa = .03   + math.random()*.04,
                ws = .04   + math.random()*.03,
                wp = math.random()*math.pi*2,
                op = .35   + math.random()*.45,
            }
            l.Position = UDim2.new(g.x, 0, g.y, 0)
            table.insert(ghostReg, g)
        end)
    end
end

local function spawnScreenGhosts()
    local overlay = Instance.new("Frame", Screen)
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundTransparency = 1
    overlay.ZIndex = 100
    for i = 1, 15 do
        task.delay((i-1) * 0.1, function()
            if not overlay.Parent then return end
            local lbl = Instance.new("TextLabel", overlay)
            lbl.BackgroundTransparency = 1
            lbl.Text = "🔥"
            lbl.TextColor3 = C.MainRed
            lbl.TextSize = math.random(20, 40)
            lbl.Position = UDim2.new(math.random(), 0, -0.1, 0)
            local speed = 0.6 + math.random() * 0.5
            local startTime = tick()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                if not lbl or not lbl.Parent then conn:Disconnect(); return end
                local elapsed = tick() - startTime
                local progress = elapsed / speed
                lbl.Position = UDim2.new(lbl.Position.X.Scale, 0, -0.1 + progress * 1.2, 0)
                lbl.TextTransparency = progress > 0.8 and (progress-0.8)/0.2 or 0
                if progress >= 1 then conn:Disconnect(); lbl:Destroy() end
            end)
        end)
    end
    task.delay(4, function() pcall(function() overlay:Destroy() end) end)
end

local _dragJustHappened = false
local function MakeDrag(frame, onDrop)
    local dragging, didMove, activeInput, startPos, frameStart = false, false, nil, Vector2.zero, Vector2.zero
    local function beginDrag(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging, didMove, activeInput = true, false, input
        startPos = Vector2.new(input.Position.X, input.Position.Y)
        frameStart = Vector2.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y)
    end
    local function hookObj(obj) if obj:IsA("GuiObject") and not obj:IsA("TextBox") then obj.InputBegan:Connect(beginDrag) end end
    hookObj(frame)
    for _, d in ipairs(frame:GetDescendants()) do hookObj(d) end
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - startPos
        if delta.Magnitude > 5 then didMove = true; _dragJustHappened = true end
        frame.Position = UDim2.new(0, frameStart.X + delta.X, 0, frameStart.Y + delta.Y)
    end)
    UIS.InputEnded:Connect(function(input)
        if not dragging or input ~= activeInput then return end
        dragging = false
        if didMove then if onDrop then onDrop(frame) end task.delay(0.1, function() _dragJustHappened = false end) end
    end)
end

local isStealing, stealStartTime, STEAL_RADIUS, STEAL_DURATION = false, 0, cfg.radius or 12, cfg.duration or 0.15
local stealConn, progressConn, stealActive_ = nil, nil, cfg.active == true
local animalCache, promptCache, stealCache = {}, {}, {}
local grabBarFill, grabBarPercent, gbStroke = nil, nil, nil

local function resetStealBar()
    if grabBarFill then grabBarFill.Size = UDim2.fromScale(0, 1) end
    if grabBarPercent then grabBarPercent.Text = "SYSTEM READY" end
    if gbStroke then gbStroke.Color = STROKE_IDLE end
end

local function isMyPlot(plotName)
    local plot = workspace.Plots and workspace.Plots:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if not sign then return false end
    local yb = sign:FindFirstChild("YourBase")
    return yb and yb:IsA("BillboardGui") and yb.Enabled == true
end

local function scanPlot(plot)
    if not plot or not plot:IsA("Model") or isMyPlot(plot.Name) then return end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return end
    for _, pod in ipairs(podiums:GetChildren()) do
        if pod:IsA("Model") and pod:FindFirstChild("Base") then
            local uid = plot.Name .. "_" .. pod.Name
            local exists = false
            for _, ex in ipairs(animalCache) do if ex.uid == uid then exists = true; break end end
            if not exists then
                table.insert(animalCache, {
                    name = pod.Name, plot = plot.Name, slot = pod.Name,
                    worldPosition = pod:GetPivot().Position, uid = uid,
                })
            end
        end
    end
end

local function findPromptCached(ad)
    if not ad then return nil end
    if promptCache[ad.uid] and promptCache[ad.uid].Parent then return promptCache[ad.uid] end
    local plots = workspace:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild(ad.plot)
    local pods = plot and plot:FindFirstChild("AnimalPodiums")
    local pod = pods and pods:FindFirstChild(ad.slot)
    local base = pod and pod:FindFirstChild("Base")
    local sp = base and base:FindFirstChild("Spawn")
    if not sp then return nil end
    local prompt = nil
    for _, ch in ipairs(sp:GetDescendants()) do if ch:IsA("ProximityPrompt") then prompt = ch; break end end
    if prompt then promptCache[ad.uid] = prompt end
    return prompt
end

local function buildCallbacks(prompt)
    if stealCache[prompt] then return end
    local data = { holdCallbacks = {}, triggerCallbacks = {}, ready = true }
    local ok1, c1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 then for _, c in ipairs(c1) do if type(c.Function) == "function" then table.insert(data.holdCallbacks, c.Function) end end end
    local ok2, c2 = pcall(getconnections, prompt.Triggered)
    if ok2 then for _, c in ipairs(c2) do if type(c.Function) == "function" then table.insert(data.triggerCallbacks, c.Function) end end end
    if #data.holdCallbacks > 0 or #data.triggerCallbacks > 0 then stealCache[prompt] = data end
end

local function execSteal(prompt, animalName)
    local data = stealCache[prompt]
    if not data or not data.ready then return false end
    data.ready, isStealing, stealStartTime = false, true, tick()
    if grabBarPercent then grabBarPercent.Text = "GRABBING " .. (animalName or "ITEM") end
    if gbStroke then gbStroke.Color = STROKE_ACTIVE end
    if progressConn then progressConn:Disconnect() end
    progressConn = RunService.Heartbeat:Connect(function()
        if not isStealing then progressConn:Disconnect(); return end
        local prog = math.clamp((tick() - stealStartTime) / STEAL_DURATION, 0, 1)
        if grabBarFill then grabBarFill.Size = UDim2.fromScale(prog, 1) end
        if grabBarPercent then grabBarPercent.Text = math.floor(prog*100).."% COMPLETED" end
    end)
    task.spawn(function()
        for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end
        task.wait(STEAL_DURATION)
        for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
        task.wait(0.02)
        if progressConn then progressConn:Disconnect(); progressConn = nil end
        resetStealBar()
        data.ready, isStealing = true, false
    end)
    return true
end

local function startAutoSteal()
    if stealConn then return end
    stealConn = RunService.Heartbeat:Connect(function()
        if not stealActive_ or isStealing then return end
        local char = lp.Character
        local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
        if not hrp then return end
        for _, ad in ipairs(animalCache) do
            local dist = (hrp.Position - ad.worldPosition).Magnitude
            if dist <= STEAL_RADIUS then
                local prompt = findPromptCached(ad)
                if prompt then buildCallbacks(prompt); execSteal(prompt, ad.name); break end
            end
        end
    end)
end

local function stopAutoSteal()
    if stealConn then stealConn:Disconnect(); stealConn = nil end
    isStealing = false
    resetStealBar()
end

task.spawn(function()
    task.wait(2)
    local plots = workspace:WaitForChild("Plots", 10)
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do if plot:IsA("Model") then scanPlot(plot) end end
        plots.ChildAdded:Connect(function(plot) task.wait(0.5); if plot:IsA("Model") then scanPlot(plot) end end)
        while task.wait(5) do
            animalCache = {}; promptCache = {}
            for _, plot in ipairs(plots:GetChildren()) do if plot:IsA("Model") then scanPlot(plot) end end
        end
    end
end)

local BarGui = Instance.new("ScreenGui", lp:WaitForChild("PlayerGui"))
BarGui.Name = "GaramaBarGui"
BarGui.ResetOnSpawn = false
local botFrame = New("Frame", {
    Name = "GrabBarFrame", Size = UDim2.new(0, 240, 0, 35),
    BackgroundColor3 = Color3.fromRGB(0,0,0), Parent = BarGui, Active = true
})
Instance.new("UICorner", botFrame).CornerRadius = UDim.new(0, 8)
applyHubGradient(botFrame)
local botStroke = New("UIStroke", {Thickness = 2, Color = STROKE_IDLE, Parent = botFrame})
gbStroke = botStroke
botFrame.Position = UDim2.new(0.5, -120, 1, -100)

local readyLbl = New("TextLabel", {
    Size = UDim2.new(1, -40, 1, -10), Position = UDim2.new(0, 10, 0, 0),
    BackgroundTransparency = 1, Text = "SYSTEM READY", TextColor3 = C.White,
    Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 2, Parent = botFrame
})
grabBarPercent = readyLbl
local barBg = New("Frame", {
    Size = UDim2.new(1, -20, 0, 4), Position = UDim2.new(0, 10, 1, -8),
    BackgroundColor3 = Color3.fromRGB(40, 10, 10), Parent = botFrame, ZIndex = 2
})
grabBarFill = New("Frame", {
    Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.MainRed, Parent = barBg, ZIndex = 3
})

do
    local dragging, dragStart, startPos
    botFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = input.Position; startPos = botFrame.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            botFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
end

local HUB_W, HUB_H_FULL, HUB_H_MINI = 250, 150, 35
local HubFrame = New("Frame", {
    Name = "GaramaHub", Size = UDim2.new(0, HUB_W, 0, HUB_H_FULL),
    Position = UDim2.new(0, cfg.hubPos.px, 0, cfg.hubPos.py),
    BackgroundColor3 = Color3.fromRGB(10, 0, 0), Parent = Screen, Active = true, ClipsDescendants = true
})
Instance.new("UICorner", HubFrame).CornerRadius = UDim.new(0, 10)
local hubStroke = New("UIStroke", {Thickness = 2, Color = C.Gray, Parent = HubFrame})
applyHubGradient(HubFrame)
Ghost(HubFrame, 6)
MakeDrag(HubFrame, function(f) cfg.hubPos = {px = f.AbsolutePosition.X, py = f.AbsolutePosition.Y}; saveConfig() end)

local Header = New("Frame", {Size = UDim2.new(1, 0, 0, HUB_H_MINI), BackgroundTransparency = 1, Parent = HubFrame})
New("TextLabel", {
    Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 12, 0, 0),
    Text = "GARAMA AUTO GRAB unparched", Font = Enum.Font.GothamBlack,
    TextColor3 = C.White, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = Header
})

local Body = New("Frame", {Size = UDim2.new(1, 0, 1, -HUB_H_MINI), Position = UDim2.new(0, 0, 0, HUB_H_MINI), BackgroundTransparency = 1, Parent = HubFrame})

local ToggContainer = New("Frame", {
    Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 10),
    BackgroundColor3 = Color3.fromRGB(25, 5, 5), Parent = Body
})
Instance.new("UICorner", ToggContainer)

local StatusLbl = New("TextLabel", {
    Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0),
    Text = "AUTO GRAB SYSTEM", Font = Enum.Font.GothamBold, TextSize = 12,
    TextColor3 = C.White, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Parent = ToggContainer
})

local Pill = New("Frame", {
    Size = UDim2.new(0, 40, 0, 20), Position = UDim2.new(1, -50, 0.5, -10),
    BackgroundColor3 = stealActive_ and C.MainRed or C.TogOff, Parent = ToggContainer
})
Instance.new("UICorner", Pill).CornerRadius = UDim.new(1, 0)
local Dot = New("Frame", {
    Size = UDim2.new(0, 14, 0, 14), Position = stealActive_ and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
    BackgroundColor3 = C.White, Parent = Pill
})
Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)

local function setToggle(val)
    stealActive_, cfg.active = val, val
    saveConfig()
    TweenService:Create(Pill, TweenInfo.new(0.2), {BackgroundColor3 = val and C.MainRed or C.TogOff}):Play()
    TweenService:Create(Dot, TweenInfo.new(0.2), {Position = val and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)}):Play()
    if val then startAutoSteal() else stopAutoSteal() end
end

New("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = ToggContainer}).MouseButton1Click:Connect(function()
    setToggle(not stealActive_)
end)

local Settings = New("Frame", {
    Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 0, 60),
    BackgroundColor3 = Color3.fromRGB(20, 5, 5), Parent = Body
})
Instance.new("UICorner", Settings)

local RadBox = New("TextBox", {
    Size = UDim2.new(0.45, -5, 0, 25), Position = UDim2.new(0, 5, 0.5, -12),
    Text = "RAD: "..STEAL_RADIUS, BackgroundColor3 = Color3.fromRGB(40, 10, 10), TextColor3 = C.White,
    Font = Enum.Font.GothamBold, TextSize = 10, Parent = Settings
})
RadBox.FocusLost:Connect(function()
    local n = tonumber(RadBox.Text:match("%d+"))
    if n then STEAL_RADIUS = math.clamp(n, 1, 100); cfg.radius = STEAL_RADIUS; saveConfig() end
    RadBox.Text = "RAD: "..STEAL_RADIUS
end)

local DurBox = New("TextBox", {
    Size = UDim2.new(0.45, -5, 0, 25), Position = UDim2.new(0.5, 5, 0.5, -12),
    Text = "DUR: "..STEAL_DURATION, BackgroundColor3 = Color3.fromRGB(40, 10, 10), TextColor3 = C.White,
    Font = Enum.Font.GothamBold, TextSize = 10, Parent = Settings
})
DurBox.FocusLost:Connect(function()
    local n = tonumber(DurBox.Text:match("[%d%.]+"))
    if n then STEAL_DURATION = math.clamp(n, 0.01, 2); cfg.duration = STEAL_DURATION; saveConfig() end
    DurBox.Text = "DUR: "..STEAL_DURATION
end)

setToggle(stealActive_)
spawnScreenGhosts()
print("GARAMA AUTO GRAB LOADED!")
