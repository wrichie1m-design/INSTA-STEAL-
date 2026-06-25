local CONFIG = {
    AUTO_STEAL_ENABLED = true,
    HOLD_MIN = 1.3,
    HOLD_MAX = 2.6,
    ENTRY_DELAY = 0.3,
    COOLDOWN = 0.05,
    STEAL_RANGE = 25,
    PRIME_RANGE = 80,
}

local S = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    TweenService = game:GetService("TweenService"),
}

local Packages = S.ReplicatedStorage:WaitForChild("Packages")
local Datas = S.ReplicatedStorage:WaitForChild("Datas")

local AnimalsData = require(Datas:WaitForChild("Animals"))

S.LocalPlayer = S.Players.LocalPlayer

local plots = workspace:WaitForChild("Plots")

local syncRemotes = (function()
    local folder = Packages:WaitForChild("Synchronizer")
    return {
        channelFolder = folder:WaitForChild("Channel"),
        routeRemote = folder:WaitForChild("CommunicationRoute"),
        requestData = folder:FindFirstChild("RequestData"),
    }
end)()

local plotAnimalSync = {
    caches = {},
    connections = {},
}

local function splitSyncPath(path)
    if typeof(path) == "table" then return path end
    local out = {}
    for part in string.gmatch(tostring(path), "[^%.]+") do
        table.insert(out, tonumber(part) or part)
    end
    return out
end

local function resolveSyncPath(path, root)
    local current = root
    local parent = nil
    local key = nil
    for _, part in ipairs(splitSyncPath(path)) do
        parent = current
        key = part
        current = current and current[part] or nil
    end
    return current, parent, key
end

local function applyPlotSyncDiff(channelName, packet)
    local cache = plotAnimalSync.caches[channelName]
    if typeof(cache) ~= "table" then return end
    local path, action, a, b = packet[1], packet[2], packet[3], packet[4]
    local current, parent, key = resolveSyncPath(path, cache)
    if action == "Changed" then
        if parent ~= nil then parent[key] = a end
    elseif action == "ArrayInsert" then
        if current ~= nil then table.insert(current, b, a) end
    elseif action == "ArrayRemoved" then
        if current ~= nil then table.remove(current, b) end
    elseif action == "DictionaryInsert" then
        if current ~= nil then current[b] = a end
    elseif action == "DictionaryRemoved" then
        if current ~= nil then current[b] = nil end
    end
end

local function attachPlotChannel(remote)
    if plotAnimalSync.connections[remote] then return end
    local channelName = tostring(remote.Name)
    if not plots:FindFirstChild(channelName) then return end
    if syncRemotes.requestData and plotAnimalSync.caches[channelName] == nil then
        local ok, data = pcall(function()
            return syncRemotes.requestData:InvokeServer(channelName)
        end)
        if ok and typeof(data) == "table" then
            plotAnimalSync.caches[channelName] = data
        else
            plotAnimalSync.caches[channelName] = {}
        end
    elseif plotAnimalSync.caches[channelName] == nil then
        plotAnimalSync.caches[channelName] = {}
    end
    plotAnimalSync.connections[remote] = remote.OnClientEvent:Connect(function(queue)
        for _, packet in ipairs(queue) do
            applyPlotSyncDiff(channelName, packet)
        end
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
    if child:IsA("RemoteEvent") then
        attachPlotChannel(child)
    end
end
syncRemotes.channelFolder.ChildAdded:Connect(function(child)
    if child:IsA("RemoteEvent") then
        attachPlotChannel(child)
    end
end)
syncRemotes.routeRemote.OnClientEvent:Connect(function(actions)
    for _, action in ipairs(actions) do
        local kind, channelName = action[1], tostring(action[2])
        if not plots:FindFirstChild(channelName) then continue end
        if kind == "ListenerAdded" then
            local remote = syncRemotes.channelFolder:FindFirstChild(channelName)
            if remote and remote:IsA("RemoteEvent") then
                attachPlotChannel(remote)
            end
        elseif kind == "ListenerRemoved" then
            detachPlotChannel(channelName)
        end
    end
end)

local function getPlotChannelData(plotName)
    return plotAnimalSync.caches[plotName]
end

local allAnimalsCache = {}
local PromptMemoryCache = {}
local InternalStealCache = {}
local stealConnection = nil

local StealState = {
    active = false,
    startTime = 0,
    phase = "idle",
    label = "",
    lastResult = "",
    lastResultTime = 0,
    totalSteals = 0,
    failedSteals = 0,
}

local function getPlotOwner(plot)
    local sign = plot:FindFirstChild("PlotSign")
    local frame = sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Frame")
    local label = frame and frame:FindFirstChild("TextLabel")
    if not label or label.Text == "Empty Base" then
        return nil
    end
    return label.Text:gsub("'s [Bb]ase$", ""):gsub("%s+$", "")
end

local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    return getPlotOwner(plot) == S.LocalPlayer.DisplayName
end

local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local cached = PromptMemoryCache[animalData.uid]
    if cached and cached.Parent then return cached end

    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    local base = podium:FindFirstChild("Base")
    if not base then return nil end
    local spawn = base:FindFirstChild("Spawn")
    if not spawn then return nil end
    local attach = spawn:FindFirstChild("PromptAttachment")
    if not attach then return nil end

    for _, p in ipairs(attach:GetChildren()) do
        if p:IsA("ProximityPrompt") then
            PromptMemoryCache[animalData.uid] = p
            return p
        end
    end
    return nil
end

local function getAnimalPosition(animalData)
    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    return podium:GetPivot().Position
end

local function distToAnimal(animalData)
    local character = S.LocalPlayer.Character
    if not character then return math.huge end
    local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso")
    if not hrp then return math.huge end
    local pos = getAnimalPosition(animalData)
    if not pos then return math.huge end
    return (hrp.Position - pos).Magnitude
end

local function pickClosest()
    local character = S.LocalPlayer.Character
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso")
    if not hrp then return nil end

    local best, bestDist = nil, math.huge
    for _, animalData in ipairs(allAnimalsCache) do
        if isMyBaseAnimal(animalData) then continue end
        local pos = getAnimalPosition(animalData)
        if not pos then continue end
        local dist = (hrp.Position - pos).Magnitude
        if dist > CONFIG.PRIME_RANGE then continue end
        if dist < bestDist then
            bestDist = dist
            best = animalData
        end
    end
    return best
end

local function buildStealCallbacks(prompt)
    if InternalStealCache[prompt] then return end
    local data = { holdCallbacks = {}, triggerCallbacks = {}, ready = true }

    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(conns1) == "table" then
        for _, conn in ipairs(conns1) do
            if type(conn.Function) == "function" then
                table.insert(data.holdCallbacks, conn.Function)
            end
        end
    end

    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(conns2) == "table" then
        for _, conn in ipairs(conns2) do
            if type(conn.Function) == "function" then
                table.insert(data.triggerCallbacks, conn.Function)
            end
        end
    end

    if (#data.holdCallbacks > 0) or (#data.triggerCallbacks > 0) then
        InternalStealCache[prompt] = data
    end
end

local function executeStealAsync(prompt, animalData)
    local data = InternalStealCache[prompt]
    if not data or not data.ready then return false end
    data.ready = false

    local label = animalData.name or "Animal"
    StealState.active = true
    StealState.startTime = tick()
    StealState.phase = "holding"
    StealState.label = label

    task.spawn(function()
        for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end

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
                for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
                fired = true
                break
            end
            task.wait()
        end

        if fired then
            StealState.totalSteals = StealState.totalSteals + 1
            StealState.lastResult = "Stole " .. label
        else
            StealState.failedSteals = StealState.failedSteals + 1
            StealState.lastResult = "Missed window: " .. label
        end

        StealState.active = false
        StealState.phase = "idle"
        StealState.lastResultTime = tick()

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
                local animalName = animalData.Index
                local animalInfo = AnimalsData[animalName]
                if not animalInfo then continue end

                table.insert(newCache, {
                    name = animalInfo.DisplayName or animalName,
                    plot = plot.Name,
                    slot = tostring(slot),
                    uid = plot.Name .. "_" .. tostring(slot),
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
        if not prompt or not prompt.Parent then
            prompt = findProximityPromptForAnimal(target)
        end
        if prompt then attemptSteal(prompt, target) end
    end)
end

local function stopAutoSteal()
    if not stealConnection then return end
    stealConnection:Disconnect()
    stealConnection = nil
end

local THEME = {
    bg = Color3.fromRGB(45, 22, 35),
    panel = Color3.fromRGB(55, 28, 42),
    accent = Color3.fromRGB(255, 105, 180),
    accent2 = Color3.fromRGB(255, 182, 193),
    warn = Color3.fromRGB(255, 180, 60),
    good = Color3.fromRGB(255, 120, 200),
    bad = Color3.fromRGB(255, 70, 100),
    text = Color3.fromRGB(255, 228, 235),
    dim = Color3.fromRGB(180, 140, 160),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = p
end

local function stroke(p, color, t)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(60, 60, 80)
    s.Thickness = t or 1
    s.Parent = p
end

local function makeDraggable(frame, handle)
    handle = handle or frame
    local dragging, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    S.UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function createUI()
    local existing = S.LocalPlayer.PlayerGui:FindFirstChild("KawaiAutoGrab")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "KawaiAutoGrab"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = S.LocalPlayer:WaitForChild("PlayerGui")

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.new(0, 320, 0, 172)
    card.Position = UDim2.new(0.5, 0, 0, 120)
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.BackgroundColor3 = THEME.bg
    card.BorderSizePixel = 0
    card.Parent = screenGui
    corner(card, 12)
    stroke(card, THEME.accent, 1.5)

    local cardGrad = Instance.new("UIGradient")
    cardGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.bg),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 18, 28)),
    })
    cardGrad.Rotation = 135
    cardGrad.Parent = card

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(65, 32, 48)
    header.BackgroundTransparency = 0.3
    header.BorderSizePixel = 0
    header.Parent = card
    corner(header, 12)
    stroke(header, THEME.accent, 1)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Text = "Kawai Auto Grab"
    title.TextColor3 = THEME.text
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = header

    local titleGrad = Instance.new("UIGradient")
    titleGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.accent),
        ColorSequenceKeypoint.new(0.5, THEME.accent2),
        ColorSequenceKeypoint.new(1, THEME.accent),
    })
    titleGrad.Parent = title

    local row1 = Instance.new("Frame")
    row1.Size = UDim2.new(1, -20, 0, 30)
    row1.Position = UDim2.new(0, 10, 0, 46)
    row1.BackgroundTransparency = 1
    row1.Parent = card

    local lbl1 = Instance.new("TextLabel")
    lbl1.Size = UDim2.new(0, 130, 1, 0)
    lbl1.BackgroundTransparency = 1
    lbl1.Text = "AUTO STEAL"
    lbl1.TextColor3 = THEME.text
    lbl1.TextSize = 12
    lbl1.Font = Enum.Font.GothamBold
    lbl1.TextXAlignment = Enum.TextXAlignment.Left
    lbl1.Parent = row1

    local tglBtn = Instance.new("TextButton")
    tglBtn.Size = UDim2.new(0, 44, 0, 22)
    tglBtn.Position = UDim2.new(1, -44, 0.5, -11)
    tglBtn.AutoButtonColor = false
    tglBtn.Text = ""
    tglBtn.BackgroundColor3 = CONFIG.AUTO_STEAL_ENABLED and THEME.good or Color3.fromRGB(70, 40, 58)
    tglBtn.Parent = row1
    corner(tglBtn, 11)

    local tglKnob = Instance.new("Frame")
    tglKnob.Size = UDim2.new(0, 18, 0, 18)
    tglKnob.Position = CONFIG.AUTO_STEAL_ENABLED and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    tglKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    tglKnob.BorderSizePixel = 0
    tglKnob.Parent = tglBtn
    corner(tglKnob, 9)

    local function updateToggleVisual()
        local on = CONFIG.AUTO_STEAL_ENABLED
        S.TweenService:Create(tglKnob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
        }):Play()
        tglBtn.BackgroundColor3 = on and THEME.good or Color3.fromRGB(70, 40, 58)
    end

    tglBtn.MouseButton1Click:Connect(function()
        CONFIG.AUTO_STEAL_ENABLED = not CONFIG.AUTO_STEAL_ENABLED
        updateToggleVisual()
        if CONFIG.AUTO_STEAL_ENABLED then startAutoSteal() else stopAutoSteal() end
    end)

    local row2 = Instance.new("Frame")
    row2.Size = UDim2.new(1, -20, 0, 30)
    row2.Position = UDim2.new(0, 10, 0, 81)
    row2.BackgroundTransparency = 1
    row2.Parent = card

    local lbl2 = Instance.new("TextLabel")
    lbl2.Size = UDim2.new(0, 80, 1, 0)
    lbl2.BackgroundTransparency = 1
    lbl2.Text = "RADIUS"
    lbl2.TextColor3 = THEME.text
    lbl2.TextSize = 12
    lbl2.Font = Enum.Font.GothamBold
    lbl2.TextXAlignment = Enum.TextXAlignment.Left
    lbl2.Parent = row2

    local radVal = Instance.new("TextLabel")
    radVal.Size = UDim2.new(0, 40, 1, 0)
    radVal.Position = UDim2.new(1, -40, 0, 0)
    radVal.BackgroundTransparency = 1
    radVal.Text = tostring(CONFIG.STEAL_RANGE)
    radVal.TextColor3 = THEME.accent2
    radVal.TextSize = 12
    radVal.Font = Enum.Font.GothamBold
    radVal.TextXAlignment = Enum.TextXAlignment.Right
    radVal.Parent = row2

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -130, 0, 6)
    track.Position = UDim2.new(0, 90, 0.5, -3)
    track.BackgroundColor3 = Color3.fromRGB(40, 20, 32)
    track.BorderSizePixel = 0
    track.Parent = row2
    corner(track, 100)

    local trackFill = Instance.new("Frame")
    trackFill.Size = UDim2.new(0, 0, 1, 0)
    trackFill.BackgroundColor3 = THEME.accent
    trackFill.BorderSizePixel = 0
    trackFill.Parent = track
    corner(trackFill, 100)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = track
    corner(knob, 100)
    local ks = Instance.new("UIStroke")
    ks.Color = THEME.accent
    ks.Thickness = 2
    ks.Parent = knob

    local function updateRadius(px)
        local maxW = track.AbsoluteSize.X
        local clamped = math.clamp(px, 0, maxW)
        local pct = clamped / maxW
        CONFIG.STEAL_RANGE = math.floor(5 + (pct * 95))
        radVal.Text = tostring(CONFIG.STEAL_RANGE)
        trackFill.Size = UDim2.new(0, clamped, 1, 0)
        knob.Position = UDim2.new(0, clamped, 0.5, 0)
    end

    task.defer(function()
        task.wait(0.1)
        local maxW = track.AbsoluteSize.X
        local pct = (CONFIG.STEAL_RANGE - 5) / 95
        local clamped = pct * maxW
        trackFill.Size = UDim2.new(0, clamped, 1, 0)
        knob.Position = UDim2.new(0, clamped, 0.5, 0)
    end)

    local draggingRad = false
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingRad = true
            updateRadius(input.Position.X - track.AbsolutePosition.X)
        end
    end)
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingRad = true
        end
    end)
    S.UserInputService.InputChanged:Connect(function(input)
        if draggingRad and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateRadius(input.Position.X - track.AbsolutePosition.X)
        end
    end)
    S.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingRad = false
        end
    end)

    local bar = Instance.new("TextButton")
    bar.Name = "Bar"
    bar.Size = UDim2.new(1, -20, 0, 28)
    bar.Position = UDim2.new(0, 10, 0, 121)
    bar.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
    bar.BackgroundTransparency = 0.15
    bar.AutoButtonColor = false
    bar.Text = ""
    bar.Parent = card
    corner(bar, 14)

    local barStroke = Instance.new("UIStroke")
    barStroke.Color = Color3.fromRGB(80, 60, 75)
    barStroke.Thickness = 1
    barStroke.Transparency = 0.4
    barStroke.Parent = bar

    local inner = Instance.new("Frame")
    inner.Size = UDim2.new(1, -16, 1, -10)
    inner.Position = UDim2.new(0, 8, 0, 5)
    inner.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    inner.BackgroundTransparency = 0.2
    inner.BorderSizePixel = 0
    inner.Parent = bar
    corner(inner, 9)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = THEME.accent
    fill.BorderSizePixel = 0
    fill.Parent = inner
    corner(fill, 9)

    local fillGrad = Instance.new("UIGradient")
    fillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.accent),
        ColorSequenceKeypoint.new(1, THEME.accent2),
    })
    fillGrad.Parent = fill

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 6, 0, 6)
    dot.AnchorPoint = Vector2.new(0, 0.5)
    dot.Position = UDim2.new(0, 10, 0.5, 0)
    dot.BackgroundColor3 = Color3.fromRGB(80, 60, 70)
    dot.BorderSizePixel = 0
    dot.ZIndex = 3
    dot.Parent = inner
    corner(dot, 3)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -34, 1, 0)
    label.Position = UDim2.new(0, 22, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = "IDLE"
    label.TextColor3 = Color3.fromRGB(160, 140, 150)
    label.TextSize = 11
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextTransparency = 0.2
    label.ZIndex = 3
    label.Parent = inner

    local barDragging, barDragStart, barStartPos, barMoved
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            barDragging = true
            barMoved = false
            barDragStart = input.Position
            local abs = card.AbsolutePosition
            card.AnchorPoint = Vector2.new(0, 0)
            card.Position = UDim2.new(0, abs.X, 0, abs.Y)
            barStartPos = card.Position
        end
    end)
    bar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if barDragging and not barMoved then
                CONFIG.AUTO_STEAL_ENABLED = not CONFIG.AUTO_STEAL_ENABLED
                if CONFIG.AUTO_STEAL_ENABLED then startAutoSteal() else stopAutoSteal() end
                updateToggleVisual()
            end
            barDragging = false
        end
    end)
    S.UserInputService.InputChanged:Connect(function(input)
        if not barDragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - barDragStart
            if not barMoved and (math.abs(delta.X) > 4 or math.abs(delta.Y) > 4) then
                barMoved = true
            end
            if barMoved then
                card.Position = UDim2.new(barStartPos.X.Scale, barStartPos.X.Offset + delta.X, barStartPos.Y.Scale, barStartPos.Y.Offset + delta.Y)
            end
        end
    end)

    makeDraggable(card, header)

    local lastFillPct = 0
    S.RunService.RenderStepped:Connect(function(dt)
        local on = CONFIG.AUTO_STEAL_ENABLED
        local active = StealState.active
        local justFinished = StealState.lastResultTime > 0 and (tick() - StealState.lastResultTime) < 1.2
        local success = justFinished and string.find(StealState.lastResult, "Stole") ~= nil

        local dotTarget
        if active then
            dotTarget = StealState.phase == "waitingRange"
                and Color3.fromRGB(255, 180, 60)
                or Color3.fromRGB(255, 105, 180)
        elseif justFinished then
            dotTarget = success and Color3.fromRGB(255, 120, 200) or Color3.fromRGB(255, 70, 100)
        elseif on then
            dotTarget = Color3.fromRGB(255, 160, 200)
        else
            dotTarget = Color3.fromRGB(80, 60, 70)
        end
        dot.BackgroundColor3 = dot.BackgroundColor3:Lerp(dotTarget, math.min(dt * 8, 1))

        local targetPct, targetColor
        if active then
            targetPct = math.clamp((tick() - StealState.startTime) / CONFIG.HOLD_MAX, 0, 1)
            if StealState.phase == "waitingRange" then
                targetColor = Color3.fromRGB(255, 180, 60)
            else
                targetColor = THEME.accent
            end
        elseif justFinished then
            targetPct = 1
            targetColor = success and Color3.fromRGB(255, 120, 200) or Color3.fromRGB(255, 70, 100)
        else
            targetPct = 0
            targetColor = THEME.accent
        end

        lastFillPct = lastFillPct + (targetPct - lastFillPct) * math.min(dt * 14, 1)
        fill.Size = UDim2.new(lastFillPct, 0, 1, 0)
        fill.BackgroundColor3 = fill.BackgroundColor3:Lerp(targetColor, math.min(dt * 8, 1))

        if active then
            local elapsed = tick() - StealState.startTime
            label.Text = string.upper(StealState.label) .. "  ·  " .. string.format("%.2fs", elapsed)
            label.TextColor3 = Color3.fromRGB(245, 245, 255)
            label.TextTransparency = 0
        elseif justFinished then
            label.Text = string.upper(StealState.lastResult)
            label.TextColor3 = success and Color3.fromRGB(255, 220, 235) or Color3.fromRGB(255, 220, 220)
            label.TextTransparency = 0
        else
            label.Text = on and "READY" or "IDLE"
            label.TextColor3 = Color3.fromRGB(160, 140, 150)
            label.TextTransparency = 0.25
        end

        barStroke.Transparency = active and 0.1 or 0.45
        barStroke.Color = active
            and (StealState.phase == "waitingRange"
                and Color3.fromRGB(255, 180, 60)
                or Color3.fromRGB(255, 140, 200))
            or Color3.fromRGB(80, 60, 75)
    end)
end

task.spawn(function()
    while task.wait(5) do scanAllPlots() end
end)

createUI()
scanAllPlots()
if CONFIG.AUTO_STEAL_ENABLED then startAutoSteal() end
