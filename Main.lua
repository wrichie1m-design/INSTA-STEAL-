-- ╔══════════════════════════════════════════╗
-- ║     Richie Hub Insta Steal v8.0         ║
-- ║         ULTRA AGGRESSIVE                ║
-- ║     discord.gg/9QsSqQ3aRM               ║
-- ╚══════════════════════════════════════════╝

-- This WILL grab. It uses every trick in the book.
-- If it still doesn't, the game's steal mechanic is NOT based on ProximityPrompt.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- CONFIG
local ENABLED = true
local MAX_RANGE = 30
local COOLDOWN = 0.15
local SCAN_RATE = 0.02

-- STATE
local isGrabbing = false
local lastGrab = 0
local stealCount = 0
local runConnection = nil
local promptConnection = nil

-- ============================================================
-- TRIGGER FUNCTIONS (ALL KNOWN METHODS)
-- ============================================================

local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if not prompt:IsA("ProximityPrompt") then return false end
    if not prompt.Enabled then return false end

    local success = false

    -- Method 1: fireproximityprompt (most common exploit function)
    if type(fireproximityprompt) == "function" then
        pcall(function() fireproximityprompt(prompt) end)
        success = true
    end

    -- Method 2: InputHoldBegin/End (simulate hold)
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.05)
        prompt:InputHoldEnd()
    end)
    success = true

    -- Method 3: Triggered event callbacks (if accessible)
    local ok, conns = pcall(getconnections, prompt.Triggered)
    if ok and type(conns) == "table" then
        for _, conn in ipairs(conns) do
            if type(conn.Function) == "function" then
                task.spawn(conn.Function)
                success = true
            end
        end
    end

    -- Method 4: Direct RemoteEvent (try all likely remotes)
    local remoteNames = {"PromptTriggered","ProximityPromptService","Steal","Grab","PromptService","Interaction"}
    for _, name in ipairs(remoteNames) do
        local remote = ReplicatedStorage:FindFirstChild(name)
        if remote and remote:IsA("RemoteEvent") then
            pcall(function() remote:FireServer(prompt) end)
            success = true
        end
    end

    -- Method 5: Search all RemoteEvents with "prompt" or "steal" in name
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local n = obj.Name:lower()
            if n:find("prompt") or n:find("steal") or n:find("grab") then
                pcall(function() obj:FireServer(prompt) end)
                success = true
            end
        end
    end

    -- Method 6: Fire the prompt's own "Triggered" event directly (if possible)
    pcall(function()
        prompt.Triggered:Fire()
    end)

    return success
end

-- ============================================================
-- SCANNER – finds nearest "Steal" prompt
-- ============================================================

local function findNearestStealPrompt()
    local hrp = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("UpperTorso"))
    if not hrp then return nil end

    local bestPrompt = nil
    local bestDist = MAX_RANGE + 1

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local action = obj.ActionText or ""
            if action:lower():find("steal") then
                -- Get position
                local pos = nil
                local parent = obj.Parent
                if parent:IsA("BasePart") then
                    pos = parent.Position
                elseif parent:IsA("Attachment") then
                    pos = parent.WorldPosition
                elseif parent:IsA("Model") then
                    local primary = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
                    if primary then pos = primary.Position end
                end
                if pos then
                    local dist = (hrp.Position - pos).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestPrompt = obj
                    end
                end
            end
        end
    end

    return bestPrompt, bestDist
end

-- ============================================================
-- MAIN GRAB LOOP
-- ============================================================

local function grabLoop()
    if not ENABLED then return end
    if isGrabbing then return end
    if tick() - lastGrab < COOLDOWN then return end

    local prompt, dist = findNearestStealPrompt()
    if prompt and dist <= MAX_RANGE then
        isGrabbing = true
        local success = triggerPrompt(prompt)
        if success then
            stealCount = stealCount + 1
            lastGrab = tick()
            -- Update UI steal count
            if statsLabel then statsLabel.Text = "Grabs: " .. stealCount end
        end
        isGrabbing = false
    end
end

-- ============================================================
-- PROMPT SHOWN EVENT (instant catch)
-- ============================================================

local function onPromptShown(prompt)
    if not ENABLED then return end
    if isGrabbing then return end
    if tick() - lastGrab < COOLDOWN then return end
    if not prompt:IsA("ProximityPrompt") then return end
    if not prompt.Enabled then return end
    local action = prompt.ActionText or ""
    if not action:lower():find("steal") then return end

    -- Check range instantly
    local hrp = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("UpperTorso"))
    if not hrp then return end
    local pos = nil
    local parent = prompt.Parent
    if parent:IsA("BasePart") then pos = parent.Position
    elseif parent:IsA("Attachment") then pos = parent.WorldPosition
    elseif parent:IsA("Model") then
        local primary = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
        if primary then pos = primary.Position end
    end
    if pos and (hrp.Position - pos).Magnitude <= MAX_RANGE then
        isGrabbing = true
        local success = triggerPrompt(prompt)
        if success then
            stealCount = stealCount + 1
            lastGrab = tick()
            if statsLabel then statsLabel.Text = "Grabs: " .. stealCount end
        end
        isGrabbing = false
    end
end

-- ============================================================
-- UI (minimal, draggable, with close)
-- ============================================================

local screenGui, mainFrame, toggleBtn, statsLabel

local function createUI()
    if screenGui then screenGui:Destroy() end
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RichieHubUI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 200, 0, 100)
    mainFrame.Position = UDim2.new(0.5, -100, 0.4, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 5, 20)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(180, 0, 255)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.5
    stroke.Parent = mainFrame

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -30, 0, 22)
    title.Position = UDim2.new(0, 5, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = "✦ Richie Hub"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = mainFrame

    local titleGrad = Instance.new("UIGradient")
    titleGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 0, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 200))
    })
    titleGrad.Parent = title

    -- Discord
    local discord = Instance.new("TextLabel")
    discord.Size = UDim2.new(1, -10, 0, 16)
    discord.Position = UDim2.new(0, 5, 0, 28)
    discord.BackgroundTransparency = 1
    discord.Text = "discord.gg/9QsSqQ3aRM"
    discord.Font = Enum.Font.Gotham
    discord.TextSize = 10
    discord.TextColor3 = Color3.fromRGB(180, 150, 200)
    discord.TextXAlignment = Enum.TextXAlignment.Left
    discord.Parent = mainFrame

    -- Stats
    statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(0, 80, 0, 18)
    statsLabel.Position = UDim2.new(1, -85, 0, 48)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = "Grabs: 0"
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.TextSize = 11
    statsLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
    statsLabel.TextXAlignment = Enum.TextXAlignment.Right
    statsLabel.Parent = mainFrame

    -- Toggle button
    toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 80, 0, 28)
    toggleBtn.Position = UDim2.new(0.5, -40, 0, 64)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 50)
    toggleBtn.BackgroundTransparency = 0.3
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "ON"
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 13
    toggleBtn.TextColor3 = Color3.fromRGB(100, 255, 100)
    toggleBtn.Parent = mainFrame
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = toggleBtn

    -- Close (X)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -26, 0, 3)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.BackgroundTransparency = 0.2
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
        -- Also stop the loop
        if runConnection then runConnection:Disconnect() end
        if promptConnection then promptConnection:Disconnect() end
    end)

    -- Toggle click
    toggleBtn.MouseButton1Click:Connect(function()
        ENABLED = not ENABLED
        if ENABLED then
            toggleBtn.Text = "ON"
            toggleBtn.TextColor3 = Color3.fromRGB(100, 255, 100)
        else
            toggleBtn.Text = "OFF"
            toggleBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
        end
    end)

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
end

-- ============================================================
-- START / STOP
-- ============================================================

local function start()
    if runConnection then return end
    runConnection = RunService.Heartbeat:Connect(grabLoop)
    promptConnection = ProximityPromptService.PromptShown:Connect(onPromptShown)
    print("[RichieHub] Started – ready to steal!")
end

local function stop()
    if runConnection then
        runConnection:Disconnect()
        runConnection = nil
    end
    if promptConnection then
        promptConnection:Disconnect()
        promptConnection = nil
    end
end

-- ============================================================
-- INIT
-- ============================================================

createUI()
start()

print("✦ Richie Hub Insta Steal v8.0 LOADED")
print("✦ discord.gg/9QsSqQ3aRM")
