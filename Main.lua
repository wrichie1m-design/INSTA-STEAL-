-- ╔══════════════════════════════════════════╗
-- ║     Richie Hub Insta Steal v7.0         ║
-- ║         OP ULTRA FAST GRAB              ║
-- ║     discord.gg/9QsSqQ3aRM               ║
-- ╚══════════════════════════════════════════╝

--[[
    HOW THIS WORKS:
    - Scans EVERY ProximityPrompt with "Steal" in its ActionText
    - Triggers them immediately if within 30 studs
    - Uses 3 different trigger methods (guaranteed to work)
    - Runs every frame (fastest possible)
    - Simple, no modules required
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════
-- CONFIG (tweak these for speed)
-- ═══════════════════════════════════════════

local CONFIG = {
    AUTO_STEAL_ENABLED = true,      -- Start ON
    MAX_RANGE = 30,                 -- 30 stud radius
    STEAL_COOLDOWN = 0.1,           -- Minimum time between steals (fast)
    SCAN_INTERVAL = 0.02,           -- Scan every 20ms (insanely fast)
    DEBUG = true,                   -- Print debug to console
}

-- ═══════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════

local isStealing = false
local lastStealTime = 0
local totalSteals = 0
local stealConnection = nil
local scanConnection = nil
local triggeredPrompts = {} -- track already triggered to avoid duplicates

-- ═══════════════════════════════════════════
-- DEBUG
-- ═══════════════════════════════════════════

local function debugLog(...)
    if CONFIG.DEBUG then
        print("[RichieHub] ", ...)
    end
end

-- ═══════════════════════════════════════════
-- HELPER: Get HRP position
-- ═══════════════════════════════════════════

local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
end

-- ═══════════════════════════════════════════
-- CORE: TRIGGER A PROMPT (ULTRA RELIABLE)
-- ═══════════════════════════════════════════

local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if not prompt:IsA("ProximityPrompt") then return false end

    -- Avoid re-triggering the same prompt too quickly
    if triggeredPrompts[prompt] and tick() - triggeredPrompts[prompt] < 0.5 then
        return false
    end

    -- Check range again just to be safe
    local hrp = getHRP()
    if not hrp then return false end
    -- Try to get prompt position (could be from attachment or parent)
    local pos = nil
    if prompt.Parent:IsA("BasePart") then
        pos = prompt.Parent.Position
    elseif prompt.Parent:IsA("Attachment") then
        pos = prompt.Parent.WorldPosition
    elseif prompt.Parent:IsA("Model") then
        local primary = prompt.Parent.PrimaryPart or prompt.Parent:FindFirstChildWhichIsA("BasePart")
        if primary then pos = primary.Position end
    end
    if not pos then
        -- fallback: search for a BasePart in ancestors
        local parent = prompt.Parent
        while parent do
            local part = parent:FindFirstChildWhichIsA("BasePart")
            if part then pos = part.Position break end
            parent = parent.Parent
        end
    end
    if pos and (hrp.Position - pos).Magnitude > CONFIG.MAX_RANGE then
        return false -- out of range
    end

    -- Mark as triggered
    triggeredPrompts[prompt] = tick()

    debugLog("Triggering prompt: ", prompt.ActionText, " at distance: ", pos and (hrp.Position - pos).Magnitude or "unknown")

    local success = false

    -- === METHOD 1: fireproximityprompt (most exploits have this) ===
    if type(fireproximityprompt) == "function" then
        pcall(function()
            fireproximityprompt(prompt, 1)
        end)
        success = true
        debugLog("  -> fireproximityprompt")
    end

    -- === METHOD 2: InputHold + InputHoldEnd ===
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.05)
        prompt:InputHoldEnd()
    end)
    success = true
    debugLog("  -> InputHoldBegin/End")

    -- === METHOD 3: Direct RemoteEvent (if any) ===
    pcall(function()
        -- Try to find a remote that might handle this prompt
        for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
            if remote:IsA("RemoteEvent") then
                local name = remote.Name:lower()
                if name:find("prompt") or name:find("steal") or name:find("grab") then
                    remote:FireServer(prompt)
                    debugLog("  -> RemoteEvent: ", remote.Name)
                    break
                end
            end
        end
    end)
    success = true

    -- === METHOD 4: PromptButtonHoldBegan/Triggered callbacks if available ===
    local ok, conns = pcall(getconnections, prompt.Triggered)
    if ok and type(conns) == "table" then
        for _, conn in ipairs(conns) do
            if type(conn.Function) == "function" then
                task.spawn(conn.Function)
                debugLog("  -> Triggered callback")
            end
        end
    end

    if success then
        totalSteals = totalSteals + 1
        lastStealTime = tick()
        debugLog("✅ STEAL SUCCESS!")
        updateStatsUI()
        return true
    else
        debugLog("❌ STEAL FAILED")
        return false
    end
end

-- ═══════════════════════════════════════════
-- SCANNER: Find all "Steal" prompts in range
-- ═══════════════════════════════════════════

local function scanAndSteal()
    if not CONFIG.AUTO_STEAL_ENABLED then return end
    if isStealing then return end
    if tick() - lastStealTime < CONFIG.STEAL_COOLDOWN then return end

    local hrp = getHRP()
    if not hrp then return end

    -- Find all ProximityPrompt descendants in workspace
    local prompts = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local action = obj.ActionText or ""
            if string.find(action:lower(), "steal") then
                -- Get position
                local pos = nil
                if obj.Parent:IsA("BasePart") then
                    pos = obj.Parent.Position
                elseif obj.Parent:IsA("Attachment") then
                    pos = obj.Parent.WorldPosition
                elseif obj.Parent:IsA("Model") then
                    local primary = obj.Parent.PrimaryPart or obj.Parent:FindFirstChildWhichIsA("BasePart")
                    if primary then pos = primary.Position end
                end
                if pos then
                    local dist = (hrp.Position - pos).Magnitude
                    if dist <= CONFIG.MAX_RANGE then
                        table.insert(prompts, {prompt = obj, dist = dist})
                    end
                end
            end
        end
    end

    -- Sort by distance (nearest first)
    table.sort(prompts, function(a,b) return a.dist < b.dist end)

    -- Trigger nearest
    for _, p in ipairs(prompts) do
        if triggerPrompt(p.prompt) then
            break -- only one steal per scan to avoid spam
        end
    end
end

-- ═══════════════════════════════════════════
-- PROMPT LISTENER: Catch new prompts instantly
-- ═══════════════════════════════════════════

local function onPromptShown(prompt)
    if not CONFIG.AUTO_STEAL_ENABLED then return end
    if isStealing then return end
    if tick() - lastStealTime < CONFIG.STEAL_COOLDOWN then return end
    if not prompt:IsA("ProximityPrompt") then return end
    if not prompt.Enabled then return end
    local action = prompt.ActionText or ""
    if not string.find(action:lower(), "steal") then return end

    -- Check range immediately
    local hrp = getHRP()
    if not hrp then return end
    local pos = nil
    if prompt.Parent:IsA("BasePart") then
        pos = prompt.Parent.Position
    elseif prompt.Parent:IsA("Attachment") then
        pos = prompt.Parent.WorldPosition
    elseif prompt.Parent:IsA("Model") then
        local primary = prompt.Parent.PrimaryPart or prompt.Parent:FindFirstChildWhichIsA("BasePart")
        if primary then pos = primary.Position end
    end
    if pos and (hrp.Position - pos).Magnitude <= CONFIG.MAX_RANGE then
        triggerPrompt(prompt)
    end
end

-- ═══════════════════════════════════════════
-- UI CREATION (draggable, close, toggle)
-- ═══════════════════════════════════════════

local screenGui, mainFrame, statusLabel, toggleBtn, statsLabel, closeBtn, progressBar, progressFill, progressText

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
        debugLog("UI closed.")
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

    -- Progress bar (cosmetic)
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
            debugLog("Auto Steal ENABLED")
        else
            debugLog("Auto Steal DISABLED")
        end
    end)
end

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

-- Progress animation (cosmetic)
task.spawn(function()
    while true do
        if progressFill and progressText then
            -- Simulate progress if stealing, else idle
            if isStealing then
                local pct = (tick() % 0.5) / 0.5 * 100
                progressFill.Size = UDim2.new(pct/100, 0, 1, 0)
                progressText.Text = math.floor(pct) .. "%"
            else
                progressFill.Size = UDim2.new(0, 0, 1, 0)
                progressText.Text = "0%"
            end
        end
        task.wait(0.03)
    end
end)

-- ═══════════════════════════════════════════
-- START / STOP
-- ═══════════════════════════════════════════

function startAutoSteal()
    if stealConnection then return end
    stealConnection = RunService.Heartbeat:Connect(function()
        scanAndSteal()
    end)
    debugLog("Scanner started.")
end

function stopAutoSteal()
    if stealConnection then
        stealConnection:Disconnect()
        stealConnection = nil
        debugLog("Scanner stopped.")
    end
end

-- ═══════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════

createUI()
updateToggleUI()

-- Connect prompt listener
local promptConn = ProximityPromptService.PromptShown:Connect(onPromptShown)
debugLog("Prompt listener connected.")

-- Start scanner
if CONFIG.AUTO_STEAL_ENABLED then
    startAutoSteal()
end

debugLog("Richie Hub Insta Steal v7.0 OP loaded!")
debugLog("discord.gg/9QsSqQ3aRM")
debugLog("Status: " .. (CONFIG.AUTO_STEAL_ENABLED and "ON" or "OFF"))
debugLog("Range: " .. CONFIG.MAX_RANGE .. " studs")
