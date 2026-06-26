-- ╔══════════════════════════════════════════╗
-- ║     Richie Hub Insta Steal v4.0         ║
-- ║     discord.gg/9QsSqQ3aRM               ║
-- ╚══════════════════════════════════════════╝

--[[
    ULTIMATE AUTO-STEAL SCRIPT
    Combines the fastest methods from multiple scripts
    - Ultra-fast proximity prompt detection
    - Multiple steal methods (callback, fireproximityprompt, remote events)
    - Smart animal targeting with priority system
    - Minimal cooldown for maximum speed
    - Clean, draggable GUI with progress tracking
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
-- CONFIGURATION
-- ═══════════════════════════════════════════

local CONFIG = {
    AUTO_STEAL_ENABLED = true,
    STEAL_DELAY = 0.5,          -- Minimum delay between steals
    HOLD_TIME = 0.3,            -- How long to hold before triggering
    MAX_RANGE = 35,             -- Maximum range to steal from
    SCAN_INTERVAL = 0.05,       -- How often to scan for prompts
    PRIORITY_MODE = "nearest",  -- "nearest" or "highest"
}

-- ═══════════════════════════════════════════
-- SERVICES & MODULES
-- ═══════════════════════════════════════════

local Packages = ReplicatedStorage:FindFirstChild("Packages")
local Datas = ReplicatedStorage:FindFirstChild("Datas")
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local Utils = ReplicatedStorage:FindFirstChild("Utils")

local AnimalsData, AnimalsShared, NumberUtils, Synchronizer

-- Load modules safely
task.spawn(function()
    local attempts = 0
    while attempts < 20 do
        if Packages and Datas and Shared and Utils then
            local success1, data = pcall(require, Datas:WaitForChild("Animals"))
            local success2, shared = pcall(require, Shared:WaitForChild("Animals"))
            local success3, utils = pcall(require, Utils:WaitForChild("NumberUtils"))
            local success4, sync = pcall(require, Packages:WaitForChild("Synchronizer"))
            
            if success1 then AnimalsData = data end
            if success2 then AnimalsShared = shared end
            if success3 then NumberUtils = utils end
            if success4 then Synchronizer = sync end
            
            if AnimalsData and AnimalsShared and NumberUtils and Synchronizer then
                break
            end
        end
        attempts = attempts + 1
        task.wait(0.5)
    end
end)

-- ═══════════════════════════════════════════
-- STATE VARIABLES
-- ═══════════════════════════════════════════

local animalCache = {}
local promptCache = {}
local stealCallbacks = {}
local isStealing = false
local lastStealTime = 0
local totalSteals = 0
local failedSteals = 0
local currentProgress = 0
local stealConnection = nil
local scanConnection = nil
local promptConnections = {}

-- ═══════════════════════════════════════════
-- CORE FUNCTIONS
-- ═══════════════════════════════════════════

-- Get HRP position
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
end

-- Check if animal is in player's own base
local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    
    if Synchronizer then
        local channel = Synchronizer:Get(plot.Name)
        if channel then
            local owner = channel:Get("Owner")
            if owner then
                if typeof(owner) == "Instance" and owner:IsA("Player") then
                    return owner.UserId == LocalPlayer.UserId
                elseif typeof(owner) == "table" and owner.UserId then
                    return owner.UserId == LocalPlayer.UserId
                end
            end
        end
    end
    
    -- Fallback: check PlotSign
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") then
            return yourBase.Enabled == true
        end
    end
    
    return false
end

-- Get animal position
local function getAnimalPosition(animalData)
    local plot = Workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    
    return podium:GetPivot().Position
end

-- Find proximity prompt for animal
local function findProximityPrompt(animalData)
    if not animalData then return nil end
    
    -- Check cache first
    local cached = promptCache[animalData.uid]
    if cached and cached.Parent and cached:IsA("ProximityPrompt") then
        return cached
    end
    
    local plot = Workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    
    -- Search for prompt
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    
    -- Search through all descendants
    for _, descendant in ipairs(podium:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            promptCache[animalData.uid] = descendant
            return descendant
        end
    end
    
    -- Try specific path
    local base = podium:FindFirstChild("Base")
    if base then
        local spawn = base:FindFirstChild("Spawn")
        if spawn then
            local attach = spawn:FindFirstChild("PromptAttachment")
            if attach then
                for _, p in ipairs(attach:GetChildren()) do
                    if p:IsA("ProximityPrompt") then
                        promptCache[animalData.uid] = p
                        return p
                    end
                end
            end
        end
    end
    
    return nil
end

-- Build steal callbacks for a prompt
local function buildStealCallbacks(prompt)
    if stealCallbacks[prompt] then return end
    
    local data = {
        holdCallbacks = {},
        triggerCallbacks = {},
        ready = true,
    }
    
    -- Get hold callbacks
    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(conns1) == "table" then
        for _, conn in ipairs(conns1) do
            if type(conn.Function) == "function" then
                table.insert(data.holdCallbacks, conn.Function)
            end
        end
    end
    
    -- Get trigger callbacks
    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(conns2) == "table" then
        for _, conn in ipairs(conns2) do
            if type(conn.Function) == "function" then
                table.insert(data.triggerCallbacks, conn.Function)
            end
        end
    end
    
    if (#data.holdCallbacks > 0) or (#data.triggerCallbacks > 0) then
        stealCallbacks[prompt] = data
    end
end

-- Execute steal with multiple methods
local function executeSteal(prompt, animalData)
    if not prompt or not prompt.Parent then return false end
    if isStealing then return false end
    
    local currentTime = tick()
    if currentTime - lastStealTime < CONFIG.STEAL_DELAY then
        return false
    end
    
    isStealing = true
    local success = false
    local label = animalData and animalData.name or "Unknown"
    
    -- Build callbacks if not done
    buildStealCallbacks(prompt)
    local data = stealCallbacks[prompt]
    
    task.spawn(function()
        -- Method 1: Native callbacks
        if data and data.holdCallbacks and #data.holdCallbacks > 0 then
            for _, fn in ipairs(data.holdCallbacks) do
                task.spawn(fn)
            end
        end
        
        task.wait(CONFIG.HOLD_TIME)
        
        -- Progress animation
        local startTime = tick()
        local duration = CONFIG.HOLD_TIME + 0.3
        
        while tick() - startTime < duration do
            currentProgress = ((tick() - startTime) / duration) * 100
            task.wait(0.02)
        end
        
        -- Method 2: Trigger callbacks
        if data and data.triggerCallbacks and #data.triggerCallbacks > 0 then
            for _, fn in ipairs(data.triggerCallbacks) do
                task.spawn(fn)
            end
            success = true
        end
        
        -- Method 3: fireproximityprompt
        if not success and type(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, prompt, 1)
            success = true
        end
        
        -- Method 4: Remote events
        if not success then
            local remotes = {
                ReplicatedStorage:FindFirstChild("ProximityPromptService"),
                ReplicatedStorage:FindFirstChild("PromptService"),
                ReplicatedStorage:FindFirstChild("InteractionService"),
                ReplicatedStorage:FindFirstChild("PromptTriggered"),
            }
            
            for _, remote in ipairs(remotes) do
                if remote and remote:IsA("RemoteEvent") then
                    pcall(remote.FireServer, remote, prompt)
                    success = true
                    break
                end
            end
        end
        
        -- Method 5: Direct InputHold
        if not success then
            pcall(function()
                prompt:InputHoldBegin()
                task.wait(0.1)
                prompt:InputHoldEnd()
            end)
            success = true
        end
        
        -- Update stats
        if success then
            totalSteals = totalSteals + 1
            lastStealTime = tick()
        else
            failedSteals = failedSteals + 1
        end
        
        currentProgress = 0
        isStealing = false
        
        -- Update UI
        updateStatsUI()
    end)
    
    return true
end

-- Scan for animals
local function scanAnimals()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    
    local newCache = {}
    local hrp = getHRP()
    local charPos = hrp and hrp.Position or Vector3.new(0, 0, 0)
    
    for _, plot in ipairs(plots:GetChildren()) do
        if Synchronizer then
            local channel = Synchronizer:Get(plot.Name)
            if not channel then continue end
            
            local animalList = channel:Get("AnimalList")
            if not animalList then continue end
            
            for slot, animalData in pairs(animalList) do
                if type(animalData) == "table" then
                    local animalName = animalData.Index
                    local animalInfo = AnimalsData and AnimalsData[animalName]
                    if not animalInfo then continue end
                    
                    local genValue = 0
                    if AnimalsShared and animalData.Mutation then
                        genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits or {}, nil) or 0
                    end
                    
                    local uid = plot.Name .. "_" .. tostring(slot)
                    local pos = getAnimalPosition({
                        plot = plot.Name,
                        slot = tostring(slot)
                    })
                    
                    local dist = pos and (charPos - pos).Magnitude or math.huge
                    
                    table.insert(newCache, {
                        name = animalInfo.DisplayName or animalName,
                        plot = plot.Name,
                        slot = tostring(slot),
                        uid = uid,
                        genValue = genValue,
                        position = pos,
                        distance = dist,
                        rawData = animalData,
                    })
                end
            end
        end
    end
    
    -- Sort by priority
    if CONFIG.PRIORITY_MODE == "nearest" then
        table.sort(newCache, function(a, b)
            return (a.distance or math.huge) < (b.distance or math.huge)
        end)
    else
        table.sort(newCache, function(a, b)
            return (a.genValue or 0) > (b.genValue or 0)
        end)
    end
    
    animalCache = newCache
end

-- Get best target
local function getBestTarget()
    local hrp = getHRP()
    if not hrp then return nil end
    
    for _, animal in ipairs(animalCache) do
        if not isMyBaseAnimal(animal) then
            local pos = animal.position or getAnimalPosition(animal)
            if pos then
                local dist = (hrp.Position - pos).Magnitude
                if dist <= CONFIG.MAX_RANGE then
                    return animal
                end
            end
        end
    end
    
    return nil
end

-- ═══════════════════════════════════════════
-- UI CREATION
-- ═══════════════════════════════════════════

local screenGui, mainFrame, statusLabel, progressBar, progressFill, progressText, toggleBtn, statsLabel

local function createUI()
    -- Remove existing GUI
    if screenGui and screenGui.Parent then
        screenGui:Destroy()
    end
    
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RichieHubAutoSteal"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui
    
    -- Main frame
    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 240, 0, 145)
    mainFrame.Position = UDim2.new(0.5, -120, 0, 100)
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
    
    -- Gradient background
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 15, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 5, 15))
    })
    gradient.Rotation = 135
    gradient.Parent = mainFrame
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -10, 0, 25)
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
    
    -- Status label
    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0, 60, 0, 20)
    statusLabel.Position = UDim2.new(1, -65, 0, 7)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "ON"
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Right
    statusLabel.Parent = mainFrame
    
    -- Stats label
    statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, -10, 0, 18)
    statsLabel.Position = UDim2.new(0, 5, 0, 33)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = "Steals: 0 | Failed: 0"
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
    toggleBtn.Position = UDim2.new(0, 10, 0, 105)
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
    
    -- Drag system
    local dragging = false
    local dragInput, mousePos, framePos
    
    mainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            mousePos = input.Position
            framePos = mainFrame.Position
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
            local delta = input.Position - mousePos
            mainFrame.Position = UDim2.new(
                framePos.X.Scale,
                framePos.X.Offset + delta.X,
                framePos.Y.Scale,
                framePos.Y.Offset + delta.Y
            )
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    -- Toggle button click
    toggleBtn.MouseButton1Click:Connect(function()
        CONFIG.AUTO_STEAL_ENABLED = not CONFIG.AUTO_STEAL_ENABLED
        updateToggleUI()
        
        if CONFIG.AUTO_STEAL_ENABLED then
            startAutoSteal()
        else
            stopAutoSteal()
        end
    end)
end

-- ═══════════════════════════════════════════
-- UI UPDATE FUNCTIONS
-- ═══════════════════════════════════════════

local function updateToggleUI()
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

local function updateStatsUI()
    if statsLabel then
        statsLabel.Text = "Steals: " .. totalSteals .. " | Failed: " .. failedSteals
    end
end

local function updateProgressUI()
    if progressFill and progressText then
        local pct = math.clamp(currentProgress, 0, 100)
        progressFill.Size = UDim2.new(pct / 100, 0, 1, 0)
        progressText.Text = math.floor(pct) .. "%"
        
        -- Color changes based on progress
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
-- AUTO-STEAL LOOP
-- ═══════════════════════════════════════════

local function autoStealLoop()
    if stealConnection then
        stealConnection:Disconnect()
        stealConnection = nil
    end
    
    stealConnection = RunService.Heartbeat:Connect(function()
        if not CONFIG.AUTO_STEAL_ENABLED then return end
        if isStealing then return end
        
        local target = getBestTarget()
        if not target then return end
        
        local prompt = findProximityPrompt(target)
        if prompt then
            executeSteal(prompt, target)
        end
    end)
end

local function startAutoSteal()
    if not stealConnection then
        autoStealLoop()
    end
end

local function stopAutoSteal()
    if stealConnection then
        stealConnection:Disconnect()
        stealConnection = nil
    end
end

-- ═══════════════════════════════════════════
-- PROXIMITY PROMPT LISTENER
-- ═══════════════════════════════════════════

local function onPromptShown(prompt)
    if not CONFIG.AUTO_STEAL_ENABLED then return end
    if not prompt:IsA("ProximityPrompt") then return end
    
    local actionText = prompt.ActionText or ""
    if not string.find(actionText:lower(), "steal") then return end
    
    -- Check if we should steal this immediately
    if not isStealing then
        local hrp = getHRP()
        if hrp then
            -- Find the animal associated with this prompt
            local parent = prompt.Parent
            while parent and not parent:IsA("Model") do
                parent = parent.Parent
            end
            
            if parent then
                local plot = parent.Parent
                while plot and plot.Name ~= "AnimalPodiums" do
                    plot = plot.Parent
                end
                
                if plot then
                    local plotName = plot.Parent and plot.Parent.Name or "Unknown"
                    for _, animal in ipairs(animalCache) do
                        if animal.plot == plotName then
                            local pos = getAnimalPosition(animal)
                            if pos then
                                local dist = (hrp.Position - pos).Magnitude
                                if dist <= CONFIG.MAX_RANGE then
                                    executeSteal(prompt, animal)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════
-- SCANNER SYSTEM
-- ═══════════════════════════════════════════

local function startScanner()
    if scanConnection then return end
    
    scanConnection = RunService.Heartbeat:Connect(function()
        if not CONFIG.AUTO_STEAL_ENABLED then return end
        scanAnimals()
    end)
end

-- ═══════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════

-- Create UI
createUI()
updateToggleUI()

-- Start systems
startScanner()
if CONFIG.AUTO_STEAL_ENABLED then
    startAutoSteal()
end

-- Connect prompt service
local promptConnection = ProximityPromptService.PromptShown:Connect(onPromptShown)
table.insert(promptConnections, promptConnection)

-- Initial scan
task.wait(0.5)
scanAnimals()

-- Animation update loop
task.spawn(function()
    while task.wait(0.03) do
        updateProgressUI()
    end
end)

-- Print startup message
print("✦ Richie Hub Insta Steal v4.0 loaded!")
print("✦ discord.gg/9QsSqQ3aRM")
print("✦ Auto steal is " .. (CONFIG.AUTO_STEAL_ENABLED and "ON" or "OFF"))

-- Cleanup on disable
task.spawn(function()
    while true do
        task.wait(1)
        if not CONFIG.AUTO_STEAL_ENABLED and isStealing then
            isStealing = false
            currentProgress = 0
        end
    end
end)
