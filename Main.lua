-- ╔══════════════════════════════════════════╗
-- ║       Richie Hub Auto Grab               ║
-- ║       discord.gg/9QsSqQ3aRM             ║
-- ╚══════════════════════════════════════════╝
 
local CONFIG = {
    AUTO_STEAL_ENABLED = true,
    HOLD_MIN    = 0.4,
    HOLD_MAX    = 0.9,
    ENTRY_DELAY = 0.05,
    COOLDOWN    = 0.02,
    STEAL_RANGE = 25,
    PRIME_RANGE = 80,
}
 
local SAVE_FILE = "RichieHub_pos.json"
 
-- ─── Services ────────────────────────────────────────────────────────────────
local S = {
    Players          = game:GetService("Players"),
    ReplicatedStorage= game:GetService("ReplicatedStorage"),
    RunService       = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    TweenService     = game:GetService("TweenService"),
}
S.LocalPlayer = S.Players.LocalPlayer
 
local plots = workspace:WaitForChild("Plots")
 
-- ─── Sync layer ──────────────────────────────────────────────────────────────
local Packages   = S.ReplicatedStorage:WaitForChild("Packages")
local Datas      = S.ReplicatedStorage:WaitForChild("Datas")
local AnimalsData= require(Datas:WaitForChild("Animals"))
 
local syncRemotes = (function()
    local folder = Packages:WaitForChild("Synchronizer")
    return {
        channelFolder = folder:WaitForChild("Channel"),
        routeRemote   = folder:WaitForChild("CommunicationRoute"),
        requestData   = folder:FindFirstChild("RequestData"),
    }
end)()
 
local plotAnimalSync = { caches = {}, connections = {} }
 
local function splitSyncPath(path)
    if typeof(path) == "table" then return path end
    local out = {}
    for part in string.gmatch(tostring(path), "[^%.]+") do
        table.insert(out, tonumber(part) or part)
    end
    return out
end
 
local function resolveSyncPath(path, root)
    local current, parent, key = root, nil, nil
    for _, part in ipairs(splitSyncPath(path)) do
        parent  = current
        key     = part
        current = current and current[part] or nil
    end
    return current, parent, key
end
 
local function applyPlotSyncDiff(channelName, packet)
    local cache = plotAnimalSync.caches[channelName]
    if typeof(cache) ~= "table" then return end
    local path, action, a, b = packet[1], packet[2], packet[3], packet[4]
    local current, parent, key = resolveSyncPath(path, cache)
    if     action == "Changed"           then if parent  then parent[key]     = a   end
    elseif action == "ArrayInsert"       then if current then table.insert(current, b, a) end
    elseif action == "ArrayRemoved"      then if current then table.remove(current, b)    end
    elseif action == "DictionaryInsert"  then if current then current[b]      = a   end
    elseif action == "DictionaryRemoved" then if current then current[b]      = nil end
    end
end
 
local function attachPlotChannel(remote)
    if plotAnimalSync.connections[remote] then return end
    local channelName = tostring(remote.Name)
    if not plots:FindFirstChild(channelName) then return end
    if syncRemotes.requestData and plotAnimalSync.caches[channelName] == nil then
        local ok, data = pcall(function() return syncRemotes.requestData:InvokeServer(channelName) end)
        plotAnimalSync.caches[channelName] = (ok and typeof(data) == "table") and data or {}
    elseif plotAnimalSync.caches[channelName] == nil then
        plotAnimalSync.caches[channelName] = {}
    end
    plotAnimalSync.connections[remote] = remote.OnClientEvent:Connect(function(queue)
        for _, packet in ipairs(queue) do applyPlotSyncDiff(channelName, packet) end
    end)
end
 
local function detachPlotChannel(channelName)
    for remote, conn in pairs(plotAnimalSync.connections) do
        if tostring(remote.Name) == tostring(channelName) then
            conn:Disconnect()
            plotAnimalSync.connections[remote] = nil
            plotAnimalSync.caches[tostring(channelName)] = nil
            break
        end
    end
end
 
for _, child in ipairs(syncRemotes.channelFolder:GetChildren()) do
    if child:IsA("RemoteEvent") then attachPlotChannel(child) end
end
syncRemotes.channelFolder.ChildAdded:Connect(function(child)
    if child:IsA("RemoteEvent") then attachPlotChannel(child) end
end)
syncRemotes.routeRemote.OnClientEvent:Connect(function(actions)
    for _, action in ipairs(actions) do
        local kind, channelName = action[1], tostring(action[2])
        if not plots:FindFirstChild(channelName) then continue end
        if kind == "ListenerAdded" then
            local remote = syncRemotes.channelFolder:FindFirstChild(channelName)
            if remote and remote:IsA("RemoteEvent") then attachPlotChannel(remote) end
        elseif kind == "ListenerRemoved" then
            detachPlotChannel(channelName)
        end
    end
end)
 
local function getPlotChannelData(plotName) return plotAnimalSync.caches[plotName] end
 
-- ─── State ───────────────────────────────────────────────────────────────────
local allAnimalsCache  = {}
local PromptMemoryCache= {}
local InternalStealCache={}
local stealConnection  = nil
 
local StealState = {
    active=false, startTime=0, phase="idle", label="",
    lastResult="", lastResultTime=0, totalSteals=0, failedSteals=0,
}
 
-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function getPlotOwner(plot)
    local sign  = plot:FindFirstChild("PlotSign")
    local frame = sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Frame")
    local lbl   = frame and frame:FindFirstChild("TextLabel")
    if not lbl or lbl.Text == "Empty Base" then return nil end
    return lbl.Text:gsub("'s [Bb]ase$",""):gsub("%s+$","")
end
 
local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    return getPlotOwner(plot) == S.LocalPlayer.DisplayName
end
 
local function getPodium(animalData)
    local plot    = workspace.Plots:FindFirstChild(animalData.plot)    if not plot    then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")               if not podiums then return nil end
    return podiums:FindFirstChild(animalData.slot)
end
 
local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local cached = PromptMemoryCache[animalData.uid]
    if cached and cached.Parent then return cached end
 
    local podium = getPodium(animalData)       if not podium then return nil end
    local base   = podium:FindFirstChild("Base") if not base   then return nil end
    local spawn  = base:FindFirstChild("Spawn")  if not spawn  then return nil end
    local attach = spawn:FindFirstChild("PromptAttachment") if not attach then return nil end
 
    for _, p in ipairs(attach:GetChildren()) do
        if p:IsA("ProximityPrompt") then
            PromptMemoryCache[animalData.uid] = p
            return p
        end
    end
    return nil
end
 
local function getAnimalPosition(animalData)
    local podium = getPodium(animalData)
    return podium and podium:GetPivot().Position or nil
end
 
local function distToAnimal(animalData)
    local char = S.LocalPlayer.Character
    if not char then return math.huge end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
    if not hrp then return math.huge end
    local pos = getAnimalPosition(animalData)
    if not pos then return math.huge end
    return (hrp.Position - pos).Magnitude
end
 
local function pickClosest()
    local char = S.LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
    if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, a in ipairs(allAnimalsCache) do
        if isMyBaseAnimal(a) then continue end
        local pos = getAnimalPosition(a)
        if not pos then continue end
        local d = (hrp.Position - pos).Magnitude
        if d > CONFIG.PRIME_RANGE then continue end
        if d < bestDist then bestDist=d; best=a end
    end
    return best
end
 
-- ─── Steal engine (multi-method for patched games) ───────────────────────────
--  Method 1: getconnections callback fire (original approach)
--  Method 2: fireproximityprompt (exploit function available in most executors)
--  Method 3: FireServer on the remote directly
 
local function tryFireMethod2(prompt)
    -- fireproximityprompt is a common executor global
    if type(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, prompt)
        return true
    end
    return false
end
 
local function tryFireMethod3(prompt)
    -- Try to fire the underlying RemoteEvent that ProximityPrompts use
    local ok = pcall(function()
        local remote = S.ReplicatedStorage:FindFirstChild("ProximityPrompts")
            or S.ReplicatedStorage:FindFirstChild("PromptService")
        -- fallback: iterate children for the trigger remote
        if not remote then
            for _, v in ipairs(S.ReplicatedStorage:GetDescendants()) do
                if v:IsA("RemoteEvent") and (v.Name:lower():find("prompt") or v.Name:lower():find("steal")) then
                    v:FireServer(prompt)
                    break
                end
            end
        end
    end)
    return ok
end
 
local function buildStealCallbacks(prompt)
    if InternalStealCache[prompt] then return end
    local data = { holdCallbacks={}, triggerCallbacks={}, ready=true }
 
    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(conns1)=="table" then
        for _, conn in ipairs(conns1) do
            if type(conn.Function)=="function" then table.insert(data.holdCallbacks, conn.Function) end
        end
    end
 
    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(conns2)=="table" then
        for _, conn in ipairs(conns2) do
            if type(conn.Function)=="function" then table.insert(data.triggerCallbacks, conn.Function) end
        end
    end
 
    -- Always store so method 2/3 can still fire even if getconnections returned nothing
    data.hasNativeCallbacks = (#data.holdCallbacks > 0) or (#data.triggerCallbacks > 0)
    InternalStealCache[prompt] = data
end
 
local function executeStealAsync(prompt, animalData)
    local data = InternalStealCache[prompt]
    if not data or not data.ready then return false end
    data.ready = false
 
    local lbl = animalData.name or "Brainrot"
    StealState.active    = true
    StealState.startTime = tick()
    StealState.phase     = "holding"
    StealState.label     = lbl
 
    task.spawn(function()
        -- Phase 1: hold begin
        if data.hasNativeCallbacks then
            for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end
        end
 
        task.wait(CONFIG.HOLD_MIN)
        StealState.phase = "waitingRange"
 
        local alreadyInRange = distToAnimal(animalData) <= CONFIG.STEAL_RANGE
        local fired = false
 
        while true do
            local elapsed = tick() - StealState.startTime
            if elapsed > CONFIG.HOLD_MAX then break end
            if not prompt.Parent then break end
            if distToAnimal(animalData) <= CONFIG.STEAL_RANGE then
                if not alreadyInRange then task.wait(CONFIG.ENTRY_DELAY) end
 
                -- Try all methods in order
                if data.hasNativeCallbacks and #data.triggerCallbacks > 0 then
                    for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
                    fired = true
                elseif tryFireMethod2(prompt) then
                    fired = true
                else
                    tryFireMethod3(prompt)
                    fired = true -- optimistic
                end
                break
            end
            task.wait()
        end
 
        -- If native callbacks gave nothing but prompt exists, try method 2 anyway
        if not fired and prompt.Parent then
            fired = tryFireMethod2(prompt)
            if not fired then tryFireMethod3(prompt); fired = true end
        end
 
        if fired then
            StealState.totalSteals = StealState.totalSteals + 1
            StealState.lastResult  = "Stole " .. lbl
        else
            StealState.failedSteals = StealState.failedSteals + 1
            StealState.lastResult   = "Missed: " .. lbl
        end
 
        StealState.active        = false
        StealState.phase         = "idle"
        StealState.lastResultTime= tick()
 
        task.wait(CONFIG.COOLDOWN)
        data.ready = true
    end)
    return true
end
 
local function attemptSteal(prompt, animalData)
    if not prompt or not prompt.Parent then return false end
    buildStealCallbacks(prompt)
    if not InternalStealCache[prompt] then return false end
    return executeStealAsync(prompt, animalData)
end
 
local function scanAllPlots()
    local newCache = {}
    for _, plot in ipairs(plots:GetChildren()) do
        local cache = getPlotChannelData(plot.Name)
        if not cache then continue end
        local animalList = cache.AnimalList
        if typeof(animalList) ~= "table" then continue end
        for slot, animalData in pairs(animalList) do
            if type(animalData) == "table" then
                local animalInfo = AnimalsData[animalData.Index]
                if not animalInfo then continue end
                table.insert(newCache, {
                    name = animalInfo.DisplayName or animalData.Index,
                    plot = plot.Name,
                    slot = tostring(slot),
                    uid  = plot.Name .. "_" .. tostring(slot),
                })
            end
        end
    end
    allAnimalsCache = newCache
    return #allAnimalsCache
end
 
local function startAutoSteal()
    if stealConnection then return end
    stealConnection = S.RunService.Heartbeat:Connect(function()
        if not CONFIG.AUTO_STEAL_ENABLED then return end
        if StealState.active then return end
        local target = pickClosest()
        if not target then return end
        local prompt = PromptMemoryCache[target.uid]
        if not prompt or not prompt.Parent then prompt = findProximityPromptForAnimal(target) end
        if prompt then attemptSteal(prompt, target) end
    end)
end
 
local function stopAutoSteal()
    if not stealConnection then return end
    stealConnection:Disconnect()
    stealConnection = nil
end
 
-- ─── Position persistence ─────────────────────────────────────────────────────
local function loadSavedPos()
    local ok, raw = pcall(readfile, SAVE_FILE)
    if ok and raw and raw ~= "" then
        local ok2, t = pcall(game.HttpService and
            function() return game:GetService("HttpService"):JSONDecode(raw) end
            or function() return nil end)
        if ok2 and t and t.x and t.y then
            return t.x, t.y
        end
    end
    return nil, nil
end
 
local function savePos(x, y)
    pcall(function()
        local json = ('{"x":%d,"y":%d}'):format(math.floor(x), math.floor(y))
        writefile(SAVE_FILE, json)
    end)
end
 
-- ─── Theme ───────────────────────────────────────────────────────────────────
local THEME = {
    bg      = Color3.fromRGB(28, 14, 22),
    header  = Color3.fromRGB(50, 24, 38),
    accent  = Color3.fromRGB(255, 105, 180),
    accent2 = Color3.fromRGB(255, 182, 193),
    warn    = Color3.fromRGB(255, 180, 60),
    good    = Color3.fromRGB(255, 120, 200),
    bad     = Color3.fromRGB(255, 70, 100),
    text    = Color3.fromRGB(255, 228, 235),
    dim     = Color3.fromRGB(160, 120, 145),
    border  = Color3.fromRGB(255, 105, 180),
}
 
local function mkCorner(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=p end
local function mkStroke(p, col, t) local s=Instance.new("UIStroke"); s.Color=col or THEME.border; s.Thickness=t or 1; s.Parent=p; return s end
 
-- ─── Drag helper: drags `card` when ANY part of `targets` list is held ────────
local function makeFullDraggable(card, targets)
    local dragging, dragStartMouse, dragStartCardPos = false, Vector2.new(), UDim2.new()
 
    local function beginDrag(input)
        dragging = true
        dragStartMouse = Vector2.new(input.Position.X, input.Position.Y)
        local abs = card.AbsolutePosition
        card.AnchorPoint = Vector2.new(0, 0)
        card.Position = UDim2.new(0, abs.X, 0, abs.Y)
        dragStartCardPos = card.Position
    end
 
    for _, target in ipairs(targets) do
        target.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
                beginDrag(input)
            end
        end)
    end
 
    S.UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStartMouse
        card.Position = UDim2.new(0, dragStartCardPos.X.Offset+delta.X, 0, dragStartCardPos.Y.Offset+delta.Y)
    end)
 
    S.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                -- Auto-save position on drag release
                savePos(card.AbsolutePosition.X, card.AbsolutePosition.Y)
            end
            dragging = false
        end
    end)
end
 
-- ─── UI ──────────────────────────────────────────────────────────────────────
local function createUI()
    local existing = S.LocalPlayer.PlayerGui:FindFirstChild("RichieHubAutoGrab")
    if existing then existing:Destroy() end
 
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name           = "RichieHubAutoGrab"
    screenGui.ResetOnSpawn   = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent         = S.LocalPlayer:WaitForChild("PlayerGui")
 
    -- Load saved position
    local savedX, savedY = loadSavedPos()
 
    -- ── Main card ──
    local card = Instance.new("Frame")
    card.Name             = "Card"
    card.Size             = UDim2.new(0, 248, 0, 152)
    card.BackgroundColor3 = THEME.bg
    card.BorderSizePixel  = 0
    card.Parent           = screenGui
    mkCorner(card, 11)
    mkStroke(card, THEME.border, 1.5)
 
    if savedX and savedY then
        card.AnchorPoint = Vector2.new(0, 0)
        card.Position    = UDim2.new(0, savedX, 0, savedY)
    else
        card.AnchorPoint = Vector2.new(0.5, 0)
        card.Position    = UDim2.new(0.5, 0, 0, 100)
    end
 
    -- Subtle gradient on card bg
    local cGrad = Instance.new("UIGradient")
    cGrad.Color    = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.bg),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 10, 16)),
    })
    cGrad.Rotation = 135
    cGrad.Parent   = card
 
    -- ── Header ──
    local header = Instance.new("Frame")
    header.Size                  = UDim2.new(1, 0, 0, 32)
    header.BackgroundColor3      = THEME.header
    header.BackgroundTransparency= 0.2
    header.BorderSizePixel       = 0
    header.Parent                = card
    mkCorner(header, 11)
    mkStroke(header, THEME.accent, 1)
 
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size               = UDim2.new(1, -32, 1, 0)
    titleLbl.Position           = UDim2.new(0, 10, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text               = "✦ Richie Hub Auto Grab"
    titleLbl.TextColor3         = THEME.text
    titleLbl.TextSize           = 11
    titleLbl.Font               = Enum.Font.GothamBold
    titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
    titleLbl.Parent             = header
    -- Pink gradient on title
    local tGrad = Instance.new("UIGradient")
    tGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   THEME.accent),
        ColorSequenceKeypoint.new(0.5, THEME.accent2),
        ColorSequenceKeypoint.new(1,   THEME.accent),
    })
    tGrad.Parent = titleLbl
 
    -- ── Close button (X) ──
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size             = UDim2.new(0, 22, 0, 22)
    closeBtn.Position         = UDim2.new(1, -26, 0.5, -11)
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 48)
    closeBtn.AutoButtonColor  = false
    closeBtn.Text             = "✕"
    closeBtn.TextColor3       = THEME.dim
    closeBtn.TextSize         = 11
    closeBtn.Font             = Enum.Font.GothamBold
    closeBtn.ZIndex           = 10
    closeBtn.Parent           = header
    mkCorner(closeBtn, 6)
 
    -- ── Body (everything below header) ──
    local body = Instance.new("Frame")
    body.Name             = "Body"
    body.Size             = UDim2.new(1, 0, 1, -32)
    body.Position         = UDim2.new(0, 0, 0, 32)
    body.BackgroundTransparency = 1
    body.Parent           = card
 
    -- Row 1: AUTO STEAL toggle
    local row1 = Instance.new("Frame")
    row1.Size                  = UDim2.new(1, -16, 0, 28)
    row1.Position              = UDim2.new(0, 8, 0, 6)
    row1.BackgroundTransparency= 1
    row1.Parent                = body
 
    local lbl1 = Instance.new("TextLabel")
    lbl1.Size               = UDim2.new(0.55, 0, 1, 0)
    lbl1.BackgroundTransparency = 1
    lbl1.Text               = "AUTO STEAL"
    lbl1.TextColor3         = THEME.text
    lbl1.TextSize           = 11
    lbl1.Font               = Enum.Font.GothamBold
    lbl1.TextXAlignment     = Enum.TextXAlignment.Left
    lbl1.Parent             = row1
 
    local tglBtn = Instance.new("TextButton")
    tglBtn.Size             = UDim2.new(0, 40, 0, 20)
    tglBtn.Position         = UDim2.new(1, -40, 0.5, -10)
    tglBtn.AutoButtonColor  = false
    tglBtn.Text             = ""
    tglBtn.BackgroundColor3 = CONFIG.AUTO_STEAL_ENABLED and THEME.good or Color3.fromRGB(60, 35, 50)
    tglBtn.Parent           = row1
    mkCorner(tglBtn, 10)
 
    local tglKnob = Instance.new("Frame")
    tglKnob.Size             = UDim2.new(0, 16, 0, 16)
    tglKnob.Position         = CONFIG.AUTO_STEAL_ENABLED
                               and UDim2.new(1,-18,0.5,-8)
                               or  UDim2.new(0,2,0.5,-8)
    tglKnob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    tglKnob.BorderSizePixel  = 0
    tglKnob.Parent           = tglBtn
    mkCorner(tglKnob, 8)
 
    local function updateToggleVisual()
        local on = CONFIG.AUTO_STEAL_ENABLED
        S.TweenService:Create(tglKnob, TweenInfo.new(0.12), {
            Position = on and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
        }):Play()
        tglBtn.BackgroundColor3 = on and THEME.good or Color3.fromRGB(60,35,50)
    end
 
    tglBtn.MouseButton1Click:Connect(function()
        CONFIG.AUTO_STEAL_ENABLED = not CONFIG.AUTO_STEAL_ENABLED
        updateToggleVisual()
        if CONFIG.AUTO_STEAL_ENABLED then startAutoSteal() else stopAutoSteal() end
    end)
 
    -- Row 2: RADIUS slider
    local row2 = Instance.new("Frame")
    row2.Size                  = UDim2.new(1,-16, 0, 28)
    row2.Position              = UDim2.new(0, 8, 0, 38)
    row2.BackgroundTransparency= 1
    row2.Parent                = body
 
    local lbl2 = Instance.new("TextLabel")
    lbl2.Size               = UDim2.new(0, 55, 1, 0)
    lbl2.BackgroundTransparency = 1
    lbl2.Text               = "RADIUS"
    lbl2.TextColor3         = THEME.text
    lbl2.TextSize           = 11
    lbl2.Font               = Enum.Font.GothamBold
    lbl2.TextXAlignment     = Enum.TextXAlignment.Left
    lbl2.Parent             = row2
 
    local radVal = Instance.new("TextLabel")
    radVal.Size             = UDim2.new(0, 30, 1, 0)
    radVal.Position         = UDim2.new(1,-30, 0, 0)
    radVal.BackgroundTransparency = 1
    radVal.Text             = tostring(CONFIG.STEAL_RANGE)
    radVal.TextColor3       = THEME.accent2
    radVal.TextSize         = 11
    radVal.Font             = Enum.Font.GothamBold
    radVal.TextXAlignment   = Enum.TextXAlignment.Right
    radVal.Parent           = row2
 
    local track = Instance.new("Frame")
    track.Size              = UDim2.new(1,-92, 0, 5)
    track.Position          = UDim2.new(0, 60, 0.5,-2)
    track.BackgroundColor3  = Color3.fromRGB(35, 18, 28)
    track.BorderSizePixel   = 0
    track.Parent            = row2
    mkCorner(track, 100)
 
    local trackFill = Instance.new("Frame")
    trackFill.Size            = UDim2.new(0,0,1,0)
    trackFill.BackgroundColor3= THEME.accent
    trackFill.BorderSizePixel = 0
    trackFill.Parent          = track
    mkCorner(trackFill, 100)
 
    local sliderKnob = Instance.new("Frame")
    sliderKnob.Size             = UDim2.new(0,12,0,12)
    sliderKnob.AnchorPoint      = Vector2.new(0.5,0.5)
    sliderKnob.Position         = UDim2.new(0,0,0.5,0)
    sliderKnob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    sliderKnob.BorderSizePixel  = 0
    sliderKnob.Parent           = track
    mkCorner(sliderKnob, 100)
    mkStroke(sliderKnob, THEME.accent, 1.5)
 
    local function updateRadius(px)
        local maxW   = track.AbsoluteSize.X
        local clamped= math.clamp(px, 0, maxW)
        local pct    = clamped / maxW
        CONFIG.STEAL_RANGE        = math.floor(5 + pct * 95)
        radVal.Text               = tostring(CONFIG.STEAL_RANGE)
        trackFill.Size            = UDim2.new(0, clamped, 1, 0)
        sliderKnob.Position       = UDim2.new(0, clamped, 0.5, 0)
    end
 
    task.defer(function()
        task.wait(0.1)
        local maxW   = track.AbsoluteSize.X
        local clamped= ((CONFIG.STEAL_RANGE - 5) / 95) * maxW
        trackFill.Size      = UDim2.new(0, clamped, 1, 0)
        sliderKnob.Position = UDim2.new(0, clamped, 0.5, 0)
    end)
 
    local draggingRad = false
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            draggingRad = true
            updateRadius(input.Position.X - track.AbsolutePosition.X)
        end
    end)
    sliderKnob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            draggingRad = true
        end
    end)
    S.UserInputService.InputChanged:Connect(function(input)
        if draggingRad and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            updateRadius(input.Position.X - track.AbsolutePosition.X)
        end
    end)
    S.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            draggingRad = false
        end
    end)
 
    -- Status bar
    local bar = Instance.new("Frame")
    bar.Size              = UDim2.new(1,-16, 0, 26)
    bar.Position          = UDim2.new(0, 8, 0, 70)
    bar.BackgroundColor3  = Color3.fromRGB(14,8,12)
    bar.BackgroundTransparency = 0.1
    bar.BorderSizePixel   = 0
    bar.Parent            = body
    mkCorner(bar, 13)
    local barStroke = mkStroke(bar, Color3.fromRGB(70,50,65), 1)
    barStroke.Transparency = 0.5
 
    local inner = Instance.new("Frame")
    inner.Size              = UDim2.new(1,-12, 1,-8)
    inner.Position          = UDim2.new(0,6, 0,4)
    inner.BackgroundColor3  = Color3.fromRGB(22,12,18)
    inner.BackgroundTransparency = 0.15
    inner.BorderSizePixel   = 0
    inner.Parent            = bar
    mkCorner(inner, 9)
 
    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new(0,0,1,0)
    fill.BackgroundColor3 = THEME.accent
    fill.BorderSizePixel  = 0
    fill.Parent           = inner
    mkCorner(fill, 9)
    local fGrad = Instance.new("UIGradient")
    fGrad.Color  = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.accent),
        ColorSequenceKeypoint.new(1, THEME.accent2),
    })
    fGrad.Parent = fill
 
    local dot = Instance.new("Frame")
    dot.Size             = UDim2.new(0,5,0,5)
    dot.AnchorPoint      = Vector2.new(0,0.5)
    dot.Position         = UDim2.new(0,8,0.5,0)
    dot.BackgroundColor3 = Color3.fromRGB(80,60,70)
    dot.BorderSizePixel  = 0
    dot.ZIndex           = 3
    dot.Parent           = inner
    mkCorner(dot, 3)
 
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size               = UDim2.new(1,-28,1,0)
    statusLbl.Position           = UDim2.new(0,18,0,0)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text               = "IDLE"
    statusLbl.TextColor3         = THEME.dim
    statusLbl.TextSize           = 10
    statusLbl.Font               = Enum.Font.GothamBold
    statusLbl.TextXAlignment     = Enum.TextXAlignment.Center
    statusLbl.TextTransparency   = 0.2
    statusLbl.ZIndex             = 3
    statusLbl.Parent             = inner
 
    -- Discord watermark across card bottom
    local discordLbl = Instance.new("TextLabel")
    discordLbl.Size               = UDim2.new(1,0,0,14)
    discordLbl.Position           = UDim2.new(0,0,1,-16)
    discordLbl.BackgroundTransparency = 1
    discordLbl.Text               = "discord.gg/9QsSqQ3aRM"
    discordLbl.TextColor3         = THEME.dim
    discordLbl.TextSize           = 9
    discordLbl.Font               = Enum.Font.Gotham
    discordLbl.TextXAlignment     = Enum.TextXAlignment.Center
    discordLbl.TextTransparency   = 0.3
    discordLbl.ZIndex             = 5
    discordLbl.Parent             = card
    local dGrad = Instance.new("UIGradient")
    dGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(100,80,120)),
        ColorSequenceKeypoint.new(0.5, THEME.accent2),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(100,80,120)),
    })
    dGrad.Parent = discordLbl
 
    -- ── Mini pill (shown when closed) ─────────────────────────────────────
    local pill = Instance.new("Frame")
    pill.Name             = "Pill"
    pill.Size             = UDim2.new(0, 220, 0, 36)
    pill.BackgroundColor3 = THEME.bg
    pill.BorderSizePixel  = 0
    pill.Visible          = false
    pill.Parent           = screenGui
    mkCorner(pill, 18)
    mkStroke(pill, THEME.accent, 1.5)
 
    -- Pill will appear at same position as card when closed
    local pillNameLbl = Instance.new("TextLabel")
    pillNameLbl.Size               = UDim2.new(1, 0, 0, 16)
    pillNameLbl.Position           = UDim2.new(0, 0, 0, 2)
    pillNameLbl.BackgroundTransparency = 1
    pillNameLbl.Text               = "✦ Richie Hub Auto Grab"
    pillNameLbl.TextColor3         = THEME.text
    pillNameLbl.TextSize           = 10
    pillNameLbl.Font               = Enum.Font.GothamBold
    pillNameLbl.TextXAlignment     = Enum.TextXAlignment.Center
    pillNameLbl.Parent             = pill
    local pGrad = Instance.new("UIGradient")
    pGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   THEME.accent),
        ColorSequenceKeypoint.new(0.5, THEME.accent2),
        ColorSequenceKeypoint.new(1,   THEME.accent),
    })
    pGrad.Parent = pillNameLbl
 
    local pillDiscordLbl = Instance.new("TextLabel")
    pillDiscordLbl.Size               = UDim2.new(1, 0, 0, 14)
    pillDiscordLbl.Position           = UDim2.new(0, 0, 0, 18)
    pillDiscordLbl.BackgroundTransparency = 1
    pillDiscordLbl.Text               = "discord.gg/9QsSqQ3aRM"
    pillDiscordLbl.TextColor3         = THEME.dim
    pillDiscordLbl.TextSize           = 9
    pillDiscordLbl.Font               = Enum.Font.Gotham
    pillDiscordLbl.TextXAlignment     = Enum.TextXAlignment.Center
    pillDiscordLbl.TextTransparency   = 0.2
    pillDiscordLbl.Parent             = pill
 
    -- Pill is also draggable and click to reopen
    makeFullDraggable(pill, {pill, pillNameLbl, pillDiscordLbl})
 
    local pillOpen = Instance.new("TextButton")
    pillOpen.Size                  = UDim2.new(1,0,1,0)
    pillOpen.BackgroundTransparency= 1
    pillOpen.Text                  = ""
    pillOpen.ZIndex                = 5
    pillOpen.Parent                = pill
 
    -- ── Close / reopen logic ──────────────────────────────────────────────
    local isOpen = true
 
    local function closeUI()
        isOpen = false
        -- Position pill where card was
        local abs = card.AbsolutePosition
        pill.AnchorPoint = Vector2.new(0,0)
        pill.Position    = UDim2.new(0, abs.X, 0, abs.Y)
        card.Visible     = false
        pill.Visible     = true
        savePos(abs.X, abs.Y)
    end
 
    local function openUI()
        isOpen = true
        local abs = pill.AbsolutePosition
        card.AnchorPoint = Vector2.new(0,0)
        card.Position    = UDim2.new(0, abs.X, 0, abs.Y)
        card.Visible     = true
        pill.Visible     = false
    end
 
    closeBtn.MouseButton1Click:Connect(closeUI)
    pillOpen.MouseButton1Click:Connect(openUI)
 
    -- ── Full-card drag (all surfaces) ─────────────────────────────────────
    -- Collect all draggable surfaces: header, body, bar, inner — everything
    makeFullDraggable(card, {header, body, bar, inner, card})
 
    -- ── RenderStepped: animate status bar ─────────────────────────────────
    local lastFillPct = 0
    S.RunService.RenderStepped:Connect(function(dt)
        if not isOpen then return end
        local on          = CONFIG.AUTO_STEAL_ENABLED
        local active      = StealState.active
        local justFinished= StealState.lastResultTime > 0 and (tick()-StealState.lastResultTime) < 1.5
        local success     = justFinished and StealState.lastResult:find("Stole") ~= nil
 
        local dotTarget
        if active then
            dotTarget = StealState.phase == "waitingRange"
                and Color3.fromRGB(255,180,60)
                or  Color3.fromRGB(255,105,180)
        elseif justFinished then
            dotTarget = success and Color3.fromRGB(255,120,200) or Color3.fromRGB(255,70,100)
        elseif on then
            dotTarget = Color3.fromRGB(255,160,200)
        else
            dotTarget = Color3.fromRGB(80,60,70)
        end
        dot.BackgroundColor3 = dot.BackgroundColor3:Lerp(dotTarget, math.min(dt*8,1))
 
        local targetPct, targetColor
        if active then
            targetPct   = math.clamp((tick()-StealState.startTime)/CONFIG.HOLD_MAX, 0, 1)
            targetColor = StealState.phase == "waitingRange"
                and Color3.fromRGB(255,180,60)
                or  THEME.accent
        elseif justFinished then
            targetPct   = 1
            targetColor = success and Color3.fromRGB(255,120,200) or Color3.fromRGB(255,70,100)
        else
            targetPct   = 0
            targetColor = THEME.accent
        end
 
        lastFillPct = lastFillPct + (targetPct-lastFillPct)*math.min(dt*14,1)
        fill.Size             = UDim2.new(lastFillPct, 0, 1, 0)
        fill.BackgroundColor3 = fill.BackgroundColor3:Lerp(targetColor, math.min(dt*8,1))
 
        if active then
            statusLbl.Text          = string.upper(StealState.label).."  "..string.format("%.2fs", tick()-StealState.startTime)
            statusLbl.TextColor3    = Color3.fromRGB(245,245,255)
            statusLbl.TextTransparency = 0
        elseif justFinished then
            statusLbl.Text          = string.upper(StealState.lastResult)
            statusLbl.TextColor3    = success and Color3.fromRGB(255,220,235) or Color3.fromRGB(255,200,200)
            statusLbl.TextTransparency = 0
        else
            statusLbl.Text          = on and "READY" or "IDLE"
            statusLbl.TextColor3    = THEME.dim
            statusLbl.TextTransparency = 0.25
        end
 
        barStroke.Transparency = active and 0.05 or 0.5
        barStroke.Color = active
            and (StealState.phase == "waitingRange"
                and Color3.fromRGB(255,180,60)
                or  Color3.fromRGB(255,140,200))
            or Color3.fromRGB(70,50,65)
    end)
end
 
-- ─── Boot ────────────────────────────────────────────────────────────────────
task.spawn(function()
    while task.wait(5) do scanAllPlots() end
end)
 
createUI()
scanAllPlots()
if CONFIG.AUTO_STEAL_ENABLED then startAutoSteal() end
