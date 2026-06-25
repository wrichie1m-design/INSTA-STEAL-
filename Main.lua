local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local STEAL_RADIUS = 60
local STEAL_DURATION = 1.3
local isStealing = false
local autoStealEnabled = false
local potionOnSteal = false
local StealData = {}
local heartbeatConn = nil
local mainFrame = nil
local saveKey = "AutoStealSave"

local function getHRP()
    local c = lp.Character
    if c then return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso") or c:FindFirstChild("UpperTorso") end
    return nil
end

local function isMyPlotByName(pn)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(pn)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yb = sign:FindFirstChild("YourBase")
        if yb and yb:IsA("BillboardGui") then return yb.Enabled == true end
    end
    return false
end

local function findNearestPrompt()
    local hrp = getHRP()
    if not hrp then return nil end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local nearest, dist = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlotByName(plot.Name) then continue end
        local pods = plot:FindFirstChild("AnimalPodiums")
        if not pods then continue end
        for _, pod in ipairs(pods:GetChildren()) do
            local base = pod:FindFirstChild("Base")
            if not base then continue end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            local d = (spawn.Position - hrp.Position).Magnitude
            if d <= STEAL_RADIUS and d < dist then
                local att = spawn:FindFirstChild("PromptAttachment")
                if att then
                    for _, p in ipairs(att:GetChildren()) do
                        if p:IsA("ProximityPrompt") and p.ActionText and p.ActionText:find("Steal") then
                            nearest, dist = p, d
                        end
                    end
                end
            end
        end
    end
    return nearest
end

local function usePotion()
    if not potionOnSteal then return end
    local backpack = lp:FindFirstChild("Backpack")
    if not backpack then return end
    local character = lp.Character
    if not character then return end
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find("potion") then
            pcall(function()
                if humanoid:FindFirstChild("EquipTool") then
                    humanoid:EquipTool(tool)
                else
                    tool.Parent = character
                end
                task.wait(0.05)
                tool:Activate()
            end)
            break
        end
    end
end

local function executeSteal(prompt)
    if isStealing then return end
    if not StealData[prompt] then
        StealData[prompt] = {hold = {}, trigger = {}, ready = true}
        if getconnections then
            for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
                if c.Function then table.insert(StealData[prompt].hold, c.Function) end
            end
            for _, c in ipairs(getconnections(prompt.Triggered)) do
                if c.Function then table.insert(StealData[prompt].trigger, c.Function) end
            end
        end
    end
    local data = StealData[prompt]
    if not data.ready then return end
    data.ready = false
    isStealing = true
    task.spawn(function()
        for _, f in ipairs(data.hold) do pcall(f) end
        local start = tick()
        while tick() - start < STEAL_DURATION do task.wait() end
        usePotion()
        for _, f in ipairs(data.trigger) do pcall(f) end
        task.wait(0.05)
        data.ready = true
        isStealing = false
    end)
end

local function toggleAutoSteal()
    autoStealEnabled = not autoStealEnabled
    if autoStealEnabled then
        if not heartbeatConn then
            heartbeatConn = RunService.Heartbeat:Connect(function()
                if isStealing or not autoStealEnabled then return end
                local success, prompt = pcall(findNearestPrompt)
                if success and prompt then pcall(executeSteal, prompt) end
            end)
        end
    else
        if heartbeatConn then
            heartbeatConn:Disconnect()
            heartbeatConn = nil
        end
        isStealing = false
    end
end

local function togglePotion()
    potionOnSteal = not potionOnSteal
end

local function saveAll()
    if not mainFrame then return end
    local pos = mainFrame.Position
    local data = HttpService:JSONEncode({
        X = pos.X.Offset,
        Y = pos.Y.Offset,
        autoSteal = autoStealEnabled,
        potion = potionOnSteal,
    })
    lp:SetAttribute(saveKey, data)
end

local function loadSave()
    local encoded = lp:GetAttribute(saveKey)
    if not encoded then return end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, encoded)
    if not ok or not data then return end
    if mainFrame and data.X and data.Y then
        mainFrame.Position = UDim2.new(0, data.X, 0, data.Y)
    end
    if data.autoSteal then
        autoStealEnabled = false
        toggleAutoSteal()
    end
    if data.potion then
        potionOnSteal = true
    end
end

local function createGUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "AutoStealGUI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.Parent = lp.PlayerGui

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 170, 0, 100)
    mainFrame.Position = UDim2.new(0.5, -85, 0.5, -50)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    mainFrame.BackgroundTransparency = 0.15
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = sg
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

    local drag = Instance.new("Frame")
    drag.Size = UDim2.new(1, 0, 0, 24)
    drag.BackgroundTransparency = 1
    drag.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Text = "Auto Steal"
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = drag

    local updateFns = {}

    local function makeTextToggle(yPos, labelText, getState, onToggle)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -16, 0, 30)
        btn.Position = UDim2.new(0, 8, 0, yPos)
        btn.BorderSizePixel = 0
        btn.Font = Enum.Font.GothamMedium
        btn.TextSize = 13
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.AutoButtonColor = false
        btn.Parent = mainFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

        local function applyState()
            local state = getState()
            btn.BackgroundColor3 = state and Color3.fromRGB(0, 170, 60) or Color3.fromRGB(40, 40, 55)
            btn.TextColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 160, 180)
            btn.Text = "  " .. labelText
        end

        applyState()
        updateFns[labelText] = applyState

        local pressing = false

        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                pressing = true
            end
        end)

        btn.InputEnded:Connect(function(input)
            if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and pressing then
                pressing = false
                local pos = input.Position
                local absPos = btn.AbsolutePosition
                local absSize = btn.AbsoluteSize
                if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
                    onToggle()
                    applyState()
                    saveAll()
                end
            end
        end)

        btn.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                if pressing then
                    local pos = input.Position
                    local absPos = btn.AbsolutePosition
                    local absSize = btn.AbsoluteSize
                    if pos.X < absPos.X or pos.X > absPos.X + absSize.X or pos.Y < absPos.Y or pos.Y > absPos.Y + absSize.Y then
                        pressing = false
                    end
                end
            end
        end)
    end

    makeTextToggle(28, "Potion On Steal", function() return potionOnSteal end, togglePotion)
    makeTextToggle(62, "Auto Steal", function() return autoStealEnabled end, toggleAutoSteal)

    loadSave()
    if updateFns["Potion On Steal"] then updateFns["Potion On Steal"]() end
    if updateFns["Auto Steal"] then updateFns["Auto Steal"]() end

    local dragging, dragStart, startPos, dragMoved
    drag.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragMoved = false
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    drag.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 2 then dragMoved = true end
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    drag.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging and dragMoved then saveAll() end
            dragging = false
        end
    end)
end

createGUI()
