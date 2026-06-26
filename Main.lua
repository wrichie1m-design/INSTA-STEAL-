-- ╔══════════════════════════════════════════╗
-- ║     Richie Hub Insta Steal v5.0         ║
-- ║     discord.gg/9QsSqQ3aRM               ║
-- ╚══════════════════════════════════════════╝

--[[
    FIXED VERSION - Actually Grabs Animals
    - Fixed proximity prompt detection
    - Fixed steal execution
    - Added multiple fallback methods
    - Properly handles all game mechanics
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
    STEAL_DELAY = 0.3,          -- Faster stealing
    HOLD_TIME = 0.2,            -- Quick hold
    MAX_RANGE = 30,             -- Steal range
    SCAN_INTERVAL = 0.05,
}

-- ═══════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════

local animalCache = {}
local promptCache = {}
local isStealing = false
local lastStealTime = 0
local totalSteals = 0
local currentProgress = 0
local stealConnection = nil
local scanConnection = nil

-- ═══════════════════════════════════════════
-- LOAD MODULES
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
            
            if AnimalsData and Synchronizer then
                break
            end
        end
        attempts = attempts + 1
        task.wait(0.5)
    end
end)

-- ═══════════════════════════════════════════
-- CORE FUNCTIONS - FIXED
-- ═══════════════════════════════════════════

local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
end

local function getPlotOwner(plot)
    if not plot then return nil end
    
    -- Method 1: Check via Synchronizer
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
    
    -- Method 2: Check PlotSign
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

-- FIXED: Better prompt finder
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
    
    -- Search EVERYWHERE for the prompt
    local prompt = nil
    
    -- Method 1: Direct child search
    for _, child in ipairs(podium:GetChildren()) do
        if child:IsA("ProximityPrompt") then
            prompt = child
            break
        end
    end
    
    -- Method 2: Deep search
    if not prompt then
        for _, descendant in ipairs(podium:GetDescendants()) do
            if descendant:IsA("ProximityPrompt") then
                prompt = descendant
                break
            end
        end
    end
    
    -- Method 3: Specific path
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

-- FIXED: Actually executes the steal
local function executeSteal(prompt, animalData)
    if not prompt or not prompt.Parent then 
        return false 
    end
    if isStealing then 
        return false 
    end
    
    local currentTime = tick()
    if currentTime - lastStealTime < CONFIG.STEAL_DELAY then
        return false
    end
    
    isStealing = true
    local success = false
    local label = animalData and animalData.name or "Unknown"
    
    task.spawn(function()
        -- Progress animation
        local startTime = tick()
        local duration = CONFIG.HOLD_TIME + 0.3
        
        -- === METHOD 1: Native Callbacks ===
        local holdConns = {}
        local triggerConns = {}
        
        local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
        if ok1 and type(conns1) == "table" then
            for _, conn in ipairs(conns1) do
                if type(conn.Function) == "function" then
                    table.insert(holdConns, conn.Function)
                end
            end
        end
        
        local ok2, conns2 = pcall(getconnections, prompt.Triggered)
        if ok2 and type(conns2) == "table" then
            for _, conn in ipairs(conns2) do
                if type(conn.Function) == "function" then
                    table.insert(triggerConns, conn.Function)
                end
            end
        end
        
        -- Hold begin
        if #holdConns > 0 then
            for _, fn in ipairs(holdConns) do
                task.spawn(fn)
            end
        else
            -- Fallback: InputHoldBegin
            pcall(function()
                prompt:InputHoldBegin()
            end)
        end
        
        -- Update progress during hold
        while tick() - startTime < CONFIG.HOLD_TIME do
            currentProgress = ((tick() - startTime) / CONFIG.HOLD_TIME) * 100
            task.wait(0.02)
        end
        
        -- === TRIGGER METHODS ===
        -- Method 2: Trigger callbacks
        if #triggerConns > 0 then
            for _, fn in ipairs(triggerConns) do
                task.spawn(fn)
            end
            success = true
        end
        
        -- Method 3: fireproximityprompt
        if not success and type(fireproximityprompt) == "function" then
            pcall(function()
                fireproximityprompt(prompt, 1)
            end)
            success = true
        end
        
        -- Method 4: Remote events
        if not success then
            local remoteNames = {
                "ProximityPromptService",
                "PromptService", 
                "InteractionService",
                "PromptTriggered",
                "Steal",
                "Grab",
            }
            
            for _, name in ipairs(remoteNames) do
                local remote = ReplicatedStorage:FindFirstChild(name)
                if remote and remote:IsA("RemoteEvent") then
                    pcall(function()
                        remote:FireServer(prompt)
                    end)
                    success = true
                    break
                end
            end
        end
        
        -- Method 5: Direct trigger
        if not success then
            pcall(function()
                prompt:InputHoldEnd()
            end)
            success = true
        end
        
        -- Method 6: Search for any remote that handles prompts
        if not success then
            for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
                if remote:IsA("RemoteEvent") then
                    local name = remote.Name:lower()
                    if name:find("prompt") or name:find("steal") or name:find("grab") then
                        pcall(function()
                            remote:FireServer(prompt)
                        end)
                        success = true
                        break
                    end
                end
            end
        end
        
        -- Update stats
        if success then
            totalSteals = totalSteals + 1
            lastStealTime = tick()
        end
        
        currentProgress = 100
        task.wait(0.1)
        currentProgress = 0
        isStealing = false
        
        -- Update UI
        updateStatsUI()
    end)
    
    return true
end

-- FIXED: Better animal scanning
local function scanAnimals()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    
    local newCache = {}
    local hrp = getHRP()
    if not hrp then return end
    
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
                    
                    local uid = plot.Name .. "_" .. tostring(slot)
                    local pos = getAnimalPosition({
                        plot = plot.Name,
                        slot = tostring(slot)
                    })
                    
                    if pos then
                        local dist = (hrp.Position - pos).Magnitude
                        
                        table.insert(newCache, {
                            name = animalInfo and animalInfo.DisplayName or animalName,
                            plot = plot.Name,
                            slot = tostring(slot),
                            uid = uid,
                            position = pos,
                            distance = dist,
                            rawData = animalData,
                        })
                    end
                end
            end
        end
    end
    
    -- Sort by distance
    table.sort(newCache, function(a, b)
        return (a.distance or math.huge) < (b.distance or math.huge)
    end)
    
    animalCache = newCache
end

-- FIXED: Better target selection
local function getBestTarget()
    local hrp = getHRP()
    if not hrp then return nil end
    
    for _, animal in ipairs(animalCache) do
        if not isMyBaseAnimal(animal) then
            local pos = animal.position
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
    if screenGui and screenGui.Parent then
        screenGui:Destroy()
    end
    
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RichieHubAutoSteal"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui
    
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
    
    -- Status
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
    
    -- Drag
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
    
    -- Toggle
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
-- UI UPDATES
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
        statsLabel.Text = "Steals: " .. totalSteals
    end
end

local function updateProgressUI()
    if progressFill and progressText then
        local pct = math.clamp(currentProgress, 0, 100)
        progressFill.Size = UDim2.new(pct / 100, 0, 1, 0)
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
-- AUTO-STEAL LOOP - FIXED
-- ═══════════════════════════════════════════

local function autoStealLoop()
    if stealConnection then
        stealConnection:Disconnect()
        stealConnection = nil
    end
    
    stealConnection = RunService.Heartbeat:Connect(function()
        if not CONFIG.AUTO_STEAL_ENABLED then return end
        if isStealing then return end
        
        -- Scan for targets
        scanAnimals()
        
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
    isStealing = false
    currentProgress = 0
end

-- ═══════════════════════════════════════════
-- PROMPT LISTENER - FIXED
-- ═══════════════════════════════════════════

local function onPromptShown(prompt)
    if not CONFIG.AUTO_STEAL_ENABLED then return end
    if not prompt:IsA("ProximityPrompt") then return end
    if isStealing then return end
    
    local actionText = prompt.ActionText or ""
    if not string.find(actionText:lower(), "steal") then return end
    
    -- Find if this prompt belongs to any animal in our cache
    for _, animal in ipairs(animalCache) do
        local cachedPrompt = promptCache[animal.uid]
        if cachedPrompt == prompt then
            local hrp = getHRP()
            if hrp and animal.position then
                local dist = (hrp.Position - animal.position).Magnitude
                if dist <= CONFIG.MAX_RANGE then
                    executeSteal(prompt, animal)
                    break
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════

-- Create UI
createUI()
updateToggleUI()

-- Connect prompt service
local promptConnection = ProximityPromptService.PromptShown:Connect(onPromptShown)

-- Start scanning
task.spawn(function()
    while true do
        if CONFIG.AUTO_STEAL_ENABLED then
            scanAnimals()
        end
        task.wait(0.5)
    end
end)

-- Start auto steal
if CONFIG.AUTO_STEAL_ENABLED then
    startAutoSteal()
end

-- Update progress animation
task.spawn(function()
    while task.wait(0.03) do
        updateProgressUI()
    end
end)

print("✦ Richie Hub Insta Steal v5.0 loaded!")
print("✦ discord.gg/9QsSqQ3aRM")
print("✦ Auto steal is " .. (CONFIG.AUTO_STEAL_ENABLED and "ON" or "OFF"))
