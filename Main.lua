local stealCooldown = 0.1 -- Faster grabbing
local HOLD_DURATION = 0.3 -- Faster hold
local USE_TELEPORT = true -- Enable teleport for instant grabs
local GRAB_RADIUS = 1000 -- Extended range

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- GUI Creation - "sick grab" red theme
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SickGrabGUI"
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 200, 0, 60)
mainFrame.Position = UDim2.new(0.5, -100, 0.9, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
mainFrame.BackgroundTransparency = 0.3
mainFrame.BorderSizePixel = 2
mainFrame.BorderColor3 = Color3.fromRGB(255, 0, 0)
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 1, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "🔥 SICK GRAB 🔥"
statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.Bold
statusLabel.TextStrokeColor3 = Color3.fromRGB(100, 0, 0)
statusLabel.TextStrokeTransparency = 0.5
statusLabel.Parent = mainFrame

-- Pulse animation
local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local pulseTween = TweenService:Create(mainFrame, tweenInfo, {
    BackgroundTransparency = 0.1,
    Size = UDim2.new(0, 210, 0, 65)
})
pulseTween:Play()

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHRP()
    local char = getCharacter()
    return char:WaitForChild("HumanoidRootPart", 5)
end

local HRP = getHRP()
local Humanoid = getCharacter():WaitForChild("Humanoid")

LocalPlayer.CharacterAdded:Connect(function(newChar)
    HRP = newChar:WaitForChild("HumanoidRootPart", 5)
    Humanoid = newChar:WaitForChild("Humanoid")
end)

local function getPromptPart(prompt)
    local parent = prompt.Parent
    if parent:IsA("BasePart") then return parent end
    if parent:IsA("Model") then
        return parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
    end
    if parent:IsA("Attachment") then return parent.Parent end
    return parent:FindFirstChildWhichIsA("BasePart", true)
end

local function findNearestStealPrompt()
    local nearestPrompt = nil
    local minDist = math.huge
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end

    for _, desc in pairs(plots:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled and desc.ActionText == "Steal" then
            local part = getPromptPart(desc)
            if part then
                local dist = (HRP.Position - part.Position).Magnitude
                if dist < minDist and dist < GRAB_RADIUS then
                    minDist = dist
                    nearestPrompt = desc
                end
            end
        end
    end
    return nearestPrompt
end

local function triggerPrompt(prompt)
    if not prompt or not prompt:IsDescendantOf(workspace) then return end

    -- Bypass all restrictions
    prompt.MaxActivationDistance = 9e9
    prompt.RequiresLineOfSight = false
    prompt.ClickablePrompt = true
    
    -- Teleport to prompt if enabled
    if USE_TELEPORT then
        local part = getPromptPart(prompt)
        if part then
            HRP.CFrame = part.CFrame + Vector3.new(0, 3, 0)
            task.wait(0.05)
        end
    end

    local success, err = pcall(function()
        fireproximityprompt(prompt, 9e9, HOLD_DURATION)
    end)

    if not success then
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(HOLD_DURATION)
            prompt:InputHoldEnd()
        end)
    end
end

-- Status updater
local function updateStatus(text, color)
    statusLabel.Text = text
    statusLabel.TextColor3 = color or Color3.fromRGB(255, 0, 0)
end

-- Main loop with performance optimization
local grabCount = 0
local lastGrabTime = 0

while true do
    local prompt = findNearestStealPrompt()
    if prompt then
        local part = getPromptPart(prompt)
        if part then
            local dist = (HRP.Position - part.Position).Magnitude
            updateStatus("🎯 GRABBING! [" .. math.floor(dist) .. "u]", Color3.fromRGB(255, 50, 50))
            triggerPrompt(prompt)
            grabCount = grabCount + 1
            lastGrabTime = tick()
            
            -- Flash effect on grab
            mainFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
            task.wait(0.05)
            mainFrame.BackgroundColor3 = Color3.fromRGB(20, 0, 0)
        end
    else
        updateStatus("⏳ SEARCHING...", Color3.fromRGB(150, 0, 0))
    end
    task.wait(stealCooldown)
end
