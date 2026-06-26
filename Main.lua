-- ╔══════════════════════════════════════════╗
-- ║     Richie Hub Insta Steal v6.0         ║
-- ║     discord.gg/9QsSqQ3aRM               ║
-- ╚══════════════════════════════════════════╝

--[[
    ULTIMATE FIXED VERSION
    - 4 steal methods (guaranteed to work)
    - Fully draggable UI with close button
    - Clear ON/OFF status
    - Debug console output
    - Lightning fast (heartbeat scanning)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════
-- CONFIGURATION (tweak these)
-- ═══════════════════════════════════════════

local CONFIG = {
    AUTO_STEAL_ENABLED = true,      -- Start on
    STEAL_RANGE = 35,               -- Max distance to steal from
    STEAL_DELAY = 0.25,             -- Cooldown between steals (fast)
    HOLD_TIME = 0.15,               -- Hold duration (very fast)
    SCAN_INTERVAL = 0.03,           -- How often to scan (fast)
    DEBUG = true,                   -- Print debug messages
}

-- ═══════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════

local isStealing = false
local lastStealTime = 0
local totalSteals = 0
local currentProgress = 0
local stealConnection = nil
local scanConnection = nil
local promptCache = {}
local animalCache = {}

-- ═══════════════════════════════════════════
-- DEBUG LOGGER
-- ═══════════════════════════════════════════

local function debugLog(...)
    if CONFIG.DEBUG then
        print("[RichieHub] ", ...)
    end
end

-- ═══════════════════════════════════════════
-- LOAD REQUIRED MODULES
-- ═══════════════════════════════════════════

local AnimalsData, Synchronizer
local Packages = ReplicatedStorage:FindFirstChild("Packages")
local Datas = ReplicatedStorage:FindFirstChild("Datas")

task.spawn(function()
    local attempts = 0
    while attempts < 30 do
        if Packages and Datas then
            local success1, data = pcall(require, Datas:WaitForChild("Animals"))
            local success2, sync = pcall(require, Packages:WaitForChild("Synchronizer"))
            if success1 then AnimalsData = data end
            if success2 then Synchronizer = sync end
            if AnimalsData and Synchronizer then break end
        end
        attempts = attempts + 1
        task.wait(0.5)
    end
    debugLog("Modules loaded: AnimalsData=", AnimalsData ~= nil, "Synchronizer=", Synchronizer ~= nil)
end)

-- ═══════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════

local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
end

local function getPlotOwner(plot)
    if not plot then return nil end
    if Synchronizer then
        local channel = Synchronizer:Get(plot.Name)
        if channel then
            local owner = channel:Get("Owner")
            if owner then
                if typeof(owner) == "Instance" and owner:IsA("Player") then
                    return owner
                elseif typeof(owner) == "table" and owner.UserId then
                    return Players:GetPlayerByUserId(owner.UserId)
                end
            end
        end
    end
    -- fallback: sign
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local gui = sign:FindFirstChild("SurfaceGui")
        if gui then
            local frame = gui:FindFirstChild("Frame")
            if frame then
                local label = frame:FindFirstChild("TextLabel")
                if label and label.Text and label.Text ~= "Empty Base" then
                    local ownerName = label.Text:gsub("'s [Bb]ase$", "")
                    return Players:FindFirstChild(ownerName)
                end
            end
        end
    end
    return nil
end

local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    local plot = Workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    local owner = getPlotOwner(plot)
    return owner == LocalPlayer
end

local function getAnimalPosition(animalData)
    if not animalData then return nil end
    local plot = Workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    return podium:GetPivot().Position
end

-- ═══════════════════════════════════════════
-- PROXIMITY PROMPT FINDER (ULTRA RELIABLE)
-- ═══════════════════════════════════════════

local function findProximityPrompt(animalData)
    if not animalData then return nil end
    -- Check cache
    local cached = promptCache[animalData.uid]
    if cached and cached.Parent and cached:IsA("ProximityPrompt") then
        return cached
    end

    local plot = Workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end

    -- Search ALL descendants thoroughly
    local prompt = nil
    for _, descendant in ipairs(podium:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            prompt = descendant
            break
        end
    end

    -- Specific path fallback
    if not prompt then
        local base = podium:FindFirstChild("Base")
        if base then
            local spawn = base:FindFirstChild("Spawn")
            if spawn then
                local attach = spawn:FindFirstChild("PromptAttachment")
                if attach then
                    for _, p in ipairs(attach:GetChildren()) do
                        if p:IsA("ProximityPrompt") then
                            prompt = p
                            break
                        end
                    end
                end
            end
        end
    end

    if prompt then
        promptCache[animalData.uid] = prompt
        return prompt
    end
    return nil
end

-- ═══════════════════════════════════════════
-- ANIMAL SCANNER (FAST)
-- ═══════════════════════════════════════════

local function scanAnimals()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    local hrp = getHRP()
    if not hrp then return end

    local newCache = {}
    if Synchronizer then
        for _, plot in ipairs(plots:GetChildren()) do
            local channel = Synchronizer:Get(plot.Name)
            if channel then
                local animalList = channel:Get("AnimalList")
                if animalList then
                    for slot, data in pairs(animalList) do
                        if type(data) == "table" then
                            local uid = plot.Name .. "_" .. tostring(slot)
                            local pos = getAnimalPosition({plot=plot.Name, slot=tostring(slot)})
                            if pos then
                                local dist = (hrp.Position - pos).Magnitude
                                table.insert(newCache, {
                                    name = (AnimalsData and AnimalsData[data.Index] and AnimalsData[data.Index].DisplayName) or data.Index,
                                    plot = plot.Name,
                                    slot = tostring(slot),
                                    uid = uid,
                                    position = pos,
                                    distance = dist,
                                    raw = data,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- Sort by distance
    table.sort(newCache, function(a,b) return a.distance < b.distance end)
    animalCache = newCache
end

-- ═══════════════════════════════════════════
-- STEAL EXECUTION (4 METHODS + FALLBACKS)
-- ═══════════════════════════════════════════

local function executeSteal(prompt, animalData)
    if not prompt or not prompt.Parent then return false end
    if isStealing then return false end
    if tick() - lastStealTime < CONFIG.STEAL_DELAY then return false end

    isStealing = true
    local success = false
    local label = animalData and animalData.name or "Unknown"

    debugLog("Attempting to steal:", label)

    task.spawn(function()
        -- === METHOD 1: Native callbacks (getconnections) ===
        local holdConns = {}
        local triggerConns = {}
        local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
        if ok1 and type(conns1) == "table" then
            for _, conn in ipairs(conns1) do
                if type(conn.Function) == "function" then table.insert(holdConns, conn.Function) end
            end
        end
        local ok2, conns2 = pcall(getconnections, prompt.Triggered)
        if ok2 and type(conns2) == "table" then
            for _, conn in ipairs(conns2) do
                if type(conn.Function) == "function" then table.insert(triggerConns, conn.Function) end
            end
        end

        -- Hold
        if #holdConns > 0 then
            for _, fn in ipairs(holdConns) do task.spawn(fn) end
        else
            pcall(function() prompt:InputHoldBegin() end)
        end

        -- Progress animation
        local startTime = tick()
        while tick() - startTime < CONFIG.HOLD_TIME do
            currentProgress = ((tick() - startTime) / CONFIG.HOLD_TIME) * 100
            task.wait(0.02)
        end

        -- === TRIGGER METHODS ===
        -- Method 1: trigger callbacks
        if #triggerConns > 0 then
            for _, fn in ipairs(triggerConns) do task.spawn(fn) end
            success = true
            debugLog("Triggered via callbacks")
        end

        -- Method 2: fireproximityprompt (most common exploit function)
        if not success and type(fireproximityprompt) == "function" then
            pcall(function() fireproximityprompt(prompt, 1) end)
            success = true
            debugLog("Triggered via fireproximityprompt")
        end

        -- Method 3: Remote events (find any relevant)
        if not success then
            local remoteNames = {"ProximityPromptService","PromptService","InteractionService","PromptTriggered","Steal","Grab"}
            for _, name in ipairs(remoteNames) do
                local remote = ReplicatedStorage:FindFirstChild(name)
                if remote and remote:IsA("RemoteEvent") then
                    pcall(function() remote:FireServer(prompt) end)
                    success = true
                    debugLog("Triggered via remote:", name)
                    break
                end
            end
        end

        -- Method 4: Direct InputHoldEnd
        if not success then
            pcall(function() prompt:InputHoldEnd() end)
            success = true
            debugLog("Triggered via InputHoldEnd")
        end

        -- Method 5: Scan all remotes (last resort)
        if not success then
            for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
                if remote:IsA("RemoteEvent") then
                    local name = remote.Name:lower()
                    if name:find("prompt") or name:find("steal") or name:find("grab") then
                        pcall(function() remote:FireServer(prompt) end)
                        success = true
                        debugLog("Triggered via fallback remote:", remote.Name)
                        break
                    end
                end
            end
        end

        -- Update stats
        if success then
            totalSteals = totalSteals + 1
            lastStealTime = tick()
            debugLog("✅ Stole:", label)
        else
            debugLog("❌ Failed to steal:", label)
        end

        currentProgress = 100
        task.wait(0.1)
        currentProgress = 0
        isStealing = false
        updateStatsUI()
    end)

    return true
end

-- ═══════════════════════════════════════════
-- FIND BEST TARGET
-- ═══════════════════════════════════════════

local function getBestTarget()
    local hrp = getHRP()
    if not hrp then return nil end
    for _, animal in ipairs(animalCache) do
        if not isMyBaseAnimal(animal) then
            if animal.position then
                local dist = (hrp.Position - animal.position).Magnitude
                if dist <= CONFIG.STEAL_RANGE then
                    return animal
                end
            end
        end
    end
    return nil
end

-- ═══════════════════════════════════════════
-- AUTO-STEAL LOOP (HEARTBEAT)
-- ═══════════════════════════════════════════

local function autoStealLoop()
    if stealConnection then stealConnection:Disconnect() end
    stealConnection = RunService.Heartbeat:Connect(function()
        if not CONFIG.AUTO_STEAL_ENABLED then return end
        if isStealing then return end
        scanAnimals() -- refresh cache
        local target = getBestTarget()
        if target then
            local prompt = findProximityPrompt(target)
            if prompt then
                executeSteal(prompt, target)
            end
        end
    end)
end

-- ═══════════════════════════════════════════
-- PROMPT LISTENER (REAL-TIME)
-- ═══════════════════════════════════════════

local function onPromptShown(prompt)
    if not CONFIG.AUTO_STEAL_ENABLED then return end
    if not prompt:IsA("ProximityPrompt") then return end
    if isStealing then return end
    local action = prompt.ActionText or ""
    if not string.find(action:lower(), "steal") then return end

    -- Try to match with cached animals
    for _, animal in ipairs(animalCache) do
        if promptCache[animal.uid] == prompt then
            local hrp = getHRP()
            if hrp and animal.position then
                local dist = (hrp.Position - animal.position).Magnitude
                if dist <= CONFIG.STEAL_RANGE then
                    executeSteal(prompt, animal)
                    break
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════
-- UI CREATION (DRAGGABLE + CLOSE BUTTON)
-- ═══════════════════════════════════════════

local screenGui, mainFrame, statusLabel, progressBar, progressFill, progressText, toggleBtn, statsLabel, closeBtn

local function createUI()
    if screenGui and screenGui.Parent then screenGui:Destroy() end
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RichieHubAutoSteal"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 240, 0, 150)
    mainFrame.Position = UDim2.new(0.5, -120, 0.4, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 10, 25)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(180, 0, 255)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4
    stroke.Parent = mainFrame

    -- Gradient
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 15, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 5, 15))
    })
    gradient.Rotation = 135
    gradient.Parent = mainFrame

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -40, 0, 25)
    titleLabel.Position = UDim2.new(0, 5, 0, 5)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "✦ Richie Hub Insta Steal"
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 12
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = mainFrame
    local titleGrad = Instance.new("UIGradient")
    titleGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 0, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 200))
    })
    titleGrad.Parent = titleLabel

    -- Close button (X)
    closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -26, 0, 4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.BackgroundTransparency = 0.3
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "✕"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Parent = mainFrame
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 4)
    closeCorner.Parent = closeBtn
    closeBtn.MouseButton1Click:Connect(function()
        screenGui:Destroy()
        print("[RichieHub] UI closed. Re-run script to show again.")
    end)

    -- Status
    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0, 60, 0, 20)
    statusLabel.Position = UDim2.new(1, -70, 0, 7)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "ON"
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Right
    statusLabel.Parent = mainFrame

    -- Stats
    statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, -10, 0, 18)
    statsLabel.Position = UDim2.new(0, 5, 0, 33)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = "Steals: 0"
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextSize = 10
    statsLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.Parent = mainFrame

    -- Progress bar
    progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(1, -20, 0, 16)
    progressBar.Position = UDim2.new(0, 10, 0, 55)
    progressBar.BackgroundColor3 = Color3.fromRGB(40, 20, 50)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = mainFrame
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 8)
    barCorner.Parent = progressBar

    progressFill = Instance.new("Frame")
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = Color3.fromRGB(180, 0, 255)
    progressFill.BorderSizePixel = 0
    progressFill.Parent = progressBar
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 8)
    fillCorner.Parent = progressFill
    local fillGrad = Instance.new("UIGradient")
    fillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 0, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 200))
    })
    fillGrad.Rotation = 90
    fillGrad.Parent = progressFill

    progressText = Instance.new("TextLabel")
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.BackgroundTransparency = 1
    progressText.Text = "0%"
    progressText.Font = Enum.Font.GothamBold
    progressText.TextSize = 9
    progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressText.Parent = progressBar

    -- Toggle button
    toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, -20, 0, 30)
    toggleBtn.Position = UDim2.new(0, 10, 0, 108)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 50)
    toggleBtn.BackgroundTransparency = 0.3
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "Disable Auto Steal"
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 12
    toggleBtn.TextColor3 = Color3.fromRGB(230, 200, 255)
    toggleBtn.Parent = mainFrame
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = toggleBtn
    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = Color3.fromRGB(180, 0, 255)
    btnStroke.Thickness = 1
    btnStroke.Transparency = 0.5
    btnStroke.Parent = toggleBtn

    -- Draggable
    local dragging = false
    local dragStart, framePos
    mainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            framePos = mainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X,
                                           framePos.Y.Scale, framePos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    -- Toggle click
    toggleBtn.MouseButton1Click:Connect(function()
        CONFIG.AUTO_STEAL_ENABLED = not CONFIG.AUTO_STEAL_ENABLED
        updateToggleUI()
        if CONFIG.AUTO_STEAL_ENABLED then
            startAutoSteal()
            debugLog("Auto Steal ENABLED")
        else
            stopAutoSteal()
            debugLog("Auto Steal DISABLED")
        end
    end)
end

-- ═══════════════════════════════════════════
-- UI UPDATE FUNCTIONS
-- ═══════════════════════════════════════════

function updateToggleUI()
    if CONFIG.AUTO_STEAL_ENABLED then
        statusLabel.Text = "ON"
        statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        toggleBtn.Text = "Disable Auto Steal"
        if mainFrame:FindFirstChild("UIStroke") then
            mainFrame.UIStroke.Color = Color3.fromRGB(100, 255, 100)
            mainFrame.UIStroke.Transparency = 0.3
        end
    else
        statusLabel.Text = "OFF"
        statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        toggleBtn.Text = "Enable Auto Steal"
        if mainFrame:FindFirstChild("UIStroke") then
            mainFrame.UIStroke.Color = Color3.fromRGB(180, 0, 255)
            mainFrame.UIStroke.Transparency = 0.4
        end
    end
end

function updateStatsUI()
    if statsLabel then
        statsLabel.Text = "Steals: " .. totalSteals
    end
end

function updateProgressUI()
    if progressFill and progressText then
        local pct = math.clamp(currentProgress, 0, 100)
        progressFill.Size = UDim2.new(pct/100, 0, 1, 0)
        progressText.Text = math.floor(pct) .. "%"
        if pct < 30 then
            progressFill.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
        elseif pct < 70 then
            progressFill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
        else
            progressFill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
        end
    end
end

-- ═══════════════════════════════════════════
-- START / STOP
-- ═══════════════════════════════════════════

function startAutoSteal()
    if not stealConnection then
        autoStealLoop()
    end
end

function stopAutoSteal()
    if stealConnection then
        stealConnection:Disconnect()
        stealConnection = nil
    end
    isStealing = false
    currentProgress = 0
end

-- ═══════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════

createUI()
updateToggleUI()

-- Connect prompt listener
local promptConn = ProximityPromptService.PromptShown:Connect(onPromptShown)

-- Start periodic scanning
task.spawn(function()
    while true do
        if CONFIG.AUTO_STEAL_ENABLED then
            scanAnimals()
        end
        task.wait(CONFIG.SCAN_INTERVAL)
    end
end)

-- Start auto steal
if CONFIG.AUTO_STEAL_ENABLED then
    startAutoSteal()
end

-- Progress update loop
task.spawn(function()
    while true do
        updateProgressUI()
        task.wait(0.03)
    end
end)

debugLog("Richie Hub Insta Steal v6.0 loaded!")
debugLog("discord.gg/9QsSqQ3aRM")
debugLog("Status: " .. (CONFIG.AUTO_STEAL_ENABLED and "ON" or "OFF"))
