local whitelist = {
    "tapynx",
    "MythicPlayZ19",
    "Snivex_973",
    "bossMO532",
    "LEAVING7777",
    "Nahmilopro"
}

local function isWhitelisted(name)
	for _, v in ipairs(whitelist) do
		if string.lower(v) == string.lower(name) then
			return true
		end
	end
	return false
end

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if not isWhitelisted(player.Name) then
	player:Kick("Not Whitelisted")
	return
end

if _G.NexHubInstantStealLoaded then return end
_G.NexHubInstantStealLoaded = true

local pos1, pos2 = nil, nil
local beam1, beam2
local part1, part2
local visualPart1, visualPart2

-- Desync Variables
local desyncActive = false
local firstActivation = true
local unwalkActive = false

local FFlags = {
    GameNetPVHeaderRotationalVelocityZeroCutoffExponent = -5000,
    LargeReplicatorWrite5 = true,
    LargeReplicatorEnabled9 = true,
    AngularVelociryLimit = 360,
    TimestepArbiterVelocityCriteriaThresholdTwoDt = 2147483646,
    S2PhysicsSenderRate = 15000,
    DisableDPIScale = true,
    MaxDataPacketPerSend = 2147483647,
    PhysicsSenderMaxBandwidthBps = 20000,
    TimestepArbiterHumanoidLinearVelThreshold = 21,
    MaxMissedWorldStepsRemembered = -2147483648,
    PlayerHumanoidPropertyUpdateRestrict = true,
    SimDefaultHumanoidTimestepMultiplier = 0,
    StreamJobNOUVolumeLengthCap = 2147483647,
    DebugSendDistInSteps = -2147483648,
    GameNetDontSendRedundantNumTimes = 1,
    CheckPVLinearVelocityIntegrateVsDeltaPositionThresholdPercent = 1,
    CheckPVDifferencesForInterpolationMinVelThresholdStudsPerSecHundredth = 1,
    LargeReplicatorSerializeRead3 = true,
    ReplicationFocusNouExtentsSizeCutoffForPauseStuds = 2147483647,
    CheckPVCachedVelThresholdPercent = 10,
    CheckPVDifferencesForInterpolationMinRotVelThresholdRadsPerSecHundredth = 1,
    GameNetDontSendRedundantDeltaPositionMillionth = 1,
    InterpolationFrameVelocityThresholdMillionth = 5,
    StreamJobNOUVolumeCap = 2147483647,
    InterpolationFrameRotVelocityThresholdMillionth = 5,
    CheckPVCachedRotVelThresholdPercent = 10,
    WorldStepMax = 30,
    InterpolationFramePositionThresholdMillionth = 5,
    TimestepArbiterHumanoidTurningVelThreshold = 1,
    SimOwnedNOUCountThresholdMillionth = 2147483647,
    GameNetPVHeaderLinearVelocityZeroCutoffExponent = -5000,
    NextGenReplicatorEnabledWrite4 = true,
    TimestepArbiterOmegaThou = 1073741823,
    MaxAcceptableUpdateDelay = 1,
    LargeReplicatorSerializeWrite4 = true
}

local defaultFFlags = {
    GameNetPVHeaderRotationalVelocityZeroCutoffExponent = 8,
    LargeReplicatorWrite5 = false,
    LargeReplicatorEnabled9 = false,
    AngularVelociryLimit = 180,
    TimestepArbiterVelocityCriteriaThresholdTwoDt = 100,
    S2PhysicsSenderRate = 60,
    DisableDPIScale = false,
    MaxDataPacketPerSend = 1024,
    PhysicsSenderMaxBandwidthBps = 10000,
    TimestepArbiterHumanoidLinearVelThreshold = 10,
    MaxMissedWorldStepsRemembered = 10,
    PlayerHumanoidPropertyUpdateRestrict = false,
    SimDefaultHumanoidTimestepMultiplier = 1,
    StreamJobNOUVolumeLengthCap = 1000,
    DebugSendDistInSteps = 10,
    GameNetDontSendRedundantNumTimes = 10,
    CheckPVLinearVelocityIntegrateVsDeltaPositionThresholdPercent = 50,
    CheckPVDifferencesForInterpolationMinVelThresholdStudsPerSecHundredth = 100,
    LargeReplicatorSerializeRead3 = false,
    ReplicationFocusNouExtentsSizeCutoffForPauseStuds = 100,
    CheckPVCachedVelThresholdPercent = 50,
    CheckPVDifferencesForInterpolationMinRotVelThresholdRadsPerSecHundredth = 100,
    GameNetDontSendRedundantDeltaPositionMillionth = 100,
    InterpolationFrameVelocityThresholdMillionth = 100,
    StreamJobNOUVolumeCap = 1000,
    InterpolationFrameRotVelocityThresholdMillionth = 100,
    CheckPVCachedRotVelThresholdPercent = 50,
    WorldStepMax = 60,
    InterpolationFramePositionThresholdMillionth = 100,
    TimestepArbiterHumanoidTurningVelThreshold = 10,
    SimOwnedNOUCountThresholdMillionth = 1000,
    GameNetPVHeaderLinearVelocityZeroCutoffExponent = 8,
    NextGenReplicatorEnabledWrite4 = false,
    TimestepArbiterOmegaThou = 1000,
    MaxAcceptableUpdateDelay = 10,
    LargeReplicatorSerializeWrite4 = false
}

local function applyFFlags(flags)
    for name, value in pairs(flags) do
        pcall(function()
            setfflag(tostring(name), tostring(value))
        end)
    end
end

local function respawn(plr)
    local char = plr.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Dead)
        end
        char:ClearAllChildren()
        local newChar = Instance.new("Model")
        newChar.Parent = workspace
        plr.Character = newChar
        task.wait()
        plr.Character = char
        newChar:Destroy()
    end
end

-- Target positions for the auto-finder
local targetPositions = {
	Vector3.new(-481.88, -3.79, 138.02),
	Vector3.new(-481.75, -3.79, 89.18),
	Vector3.new(-481.82, -3.79, 30.95),
	Vector3.new(-481.75, -3.79, -17.79),
	Vector3.new(-481.80, -3.79, -76.06),
	Vector3.new(-481.72, -3.79, -124.70),
	Vector3.new(-337.45, -3.85, -124.72),
	Vector3.new(-337.37, -3.85, -76.07),
	Vector3.new(-337.46, -3.79, -17.72),
	Vector3.new(-337.41, -3.79, 30.92),
	Vector3.new(-337.32, -3.79, 89.02),
	Vector3.new(-337.27, -3.79, 137.90),
	Vector3.new(-337.45, -3.79, 196.29),
	Vector3.new(-337.37, -3.79, 244.91),
	Vector3.new(-481.72, -3.79, 196.21),
	Vector3.new(-481.76, -3.79, 244.92)
}

-- UI Setup
local gui = Instance.new("ScreenGui")
gui.Name = "NexHubUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.fromOffset(220, 290) 
frame.Position = UDim2.new(0.5, 0, -0.5, 0)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.BackgroundColor3 = Color3.fromRGB(25, 10, 10)
frame.BackgroundTransparency = 0.15
frame.Active = true
frame.Draggable = true
frame.ClipsDescendants = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,10)
Instance.new("UIStroke", frame).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
frame.UIStroke.Color = Color3.fromRGB(80, 20, 20)

-- Drop animation from top
task.wait(0.1)
TweenService:Create(frame, TweenInfo.new(0.6, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
	Position = UDim2.fromScale(0.5, 0.5)
}):Play()

local minimized = false
local minButton = Instance.new("TextButton", frame)
minButton.Size = UDim2.fromOffset(24, 24)
minButton.Position = UDim2.new(1, -30, 0, 6)
minButton.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
minButton.Text = "-"
minButton.Font = Enum.Font.GothamBold
minButton.TextSize = 18
minButton.TextColor3 = Color3.fromRGB(255, 150, 150)
Instance.new("UICorner", minButton).CornerRadius = UDim.new(0, 4)

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, -12, 0, 28)
title.Position = UDim2.fromOffset(6, 6)
title.BackgroundTransparency = 1
title.Text = "🔥2nd Hub | INSTANT STEAL🔥"
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = Color3.fromRGB(255, 100, 100)
title.TextXAlignment = Enum.TextXAlignment.Center

local status = Instance.new("TextLabel", frame)
status.Size = UDim2.new(1, -12, 0, 22)
status.Position = UDim2.fromOffset(6, 42)
status.BackgroundTransparency = 1
status.Text = "Premium"
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(200, 120, 120)
status.TextXAlignment = Enum.TextXAlignment.Center

task.spawn(function()
	while true do
		TweenService:Create(status, TweenInfo.new(1.2), {TextTransparency = 0.4}):Play()
		task.wait(1.2)
		TweenService:Create(status, TweenInfo.new(1.2), {TextTransparency = 0}):Play()
		task.wait(1.2)
	end
end)

local function makeButton(text, y)
	local b = Instance.new("TextButton", frame)
	b.Size = UDim2.new(1, -24, 0, 36)
	b.Position = UDim2.fromOffset(12, y)
	b.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
	b.BackgroundTransparency = 0.05
	b.Text = text
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.TextColor3 = Color3.fromRGB(255, 150, 150)
	b.AutoButtonColor = false
	Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)

	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(80, 20, 20)}):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(60, 15, 15)}):Play()
	end)

	return b
end

local instantStealEnabled = false
local btn0 = makeButton("Instant Steal: OFF", 80)
local btn1 = makeButton("Set TP", 124)
local btn2 = makeButton("Unwalk: OFF", 168)
local btn3 = makeButton("Desync: OFF", 212)

local function pressAnim(button)
	local origSize = button.Size
	local origPos = button.Position

	TweenService:Create(button, TweenInfo.new(0.08), {
		Size = UDim2.new(origSize.X.Scale, origSize.X.Offset - 4, origSize.Y.Scale, origSize.Y.Offset - 3),
		Position = UDim2.new(origPos.X.Scale, origPos.X.Offset + 2, origPos.Y.Scale, origPos.Y.Offset + 1)
	}):Play()

	task.wait(0.08)

	TweenService:Create(button, TweenInfo.new(0.12), {
		Size = origSize,
		Position = origPos
	}):Play()
end

local function createVisualBox(position, index)
	local box = Instance.new("Part")
	box.Size = Vector3.new(2, 3, 1)
	box.Anchored = true
	box.CanCollide = false
	box.Transparency = 0.5
	box.Material = Enum.Material.Neon
	box.Color = Color3.fromRGB(255, 50, 50)
	box.CFrame = CFrame.new(position)
	box.Parent = workspace
	
	local selectionBox = Instance.new("SelectionBox", box)
	selectionBox.Adornee = box
	selectionBox.LineThickness = 0.05
	selectionBox.Color3 = Color3.fromRGB(255, 100, 100)
	
	if index == 1 then
		if visualPart1 then visualPart1:Destroy() end
		visualPart1 = box
	else
		if visualPart2 then visualPart2:Destroy() end
		visualPart2 = box
	end
end

local function createBeam(position, color, index)
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local part = Instance.new("Part")
	part.Size = Vector3.new(1,1,1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = workspace

	local a0 = Instance.new("Attachment", part)
	local a1 = Instance.new("Attachment", char.HumanoidRootPart)

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(color)
	beam.Parent = workspace

	if index == 1 then
		if beam1 then beam1:Destroy() end
		if part1 then part1:Destroy() end
		beam1, part1 = beam, part
	else
		if beam2 then beam2:Destroy() end
		if part2 then part2:Destroy() end
		beam2, part2 = beam, part
	end
end

-- Minimize Button Handler
local isAnimating = false
minButton.MouseButton1Click:Connect(function()
	if isAnimating then return end
	isAnimating = true
	minimized = not minimized
	
	-- Disable dragging during animation
	frame.Draggable = false
	
	if minimized then
		-- Get current position
		local currentPos = frame.Position
		
		-- Minimize - shrink height and move up while keeping X position
		local tween = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(220, 40),
			Position = UDim2.new(currentPos.X.Scale, currentPos.X.Offset, currentPos.Y.Scale, currentPos.Y.Offset - 125)
		})
		tween:Play()
		minButton.Text = "+"
		
		tween.Completed:Wait()
	else
		-- Get current position
		local currentPos = frame.Position
		
		-- Expand - restore size and move down while keeping X position
		local tween = TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(220, 290),
			Position = UDim2.new(currentPos.X.Scale, currentPos.X.Offset, currentPos.Y.Scale, currentPos.Y.Offset + 125)
		})
		tween:Play()
		minButton.Text = "-"
		
		tween.Completed:Wait()
	end
	
	-- Re-enable dragging after animation
	frame.Draggable = true
	isAnimating = false
end)

-- Instant Steal Toggle Button
btn0.MouseButton1Click:Connect(function()
	pressAnim(btn0)
	instantStealEnabled = not instantStealEnabled
	
	if instantStealEnabled then
		btn0.Text = "Instant Steal: ON"
		btn0.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
	else
		btn0.Text = "Instant Steal: OFF"
		btn0.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
	end
end)

-- Set TP Button
btn1.MouseButton1Click:Connect(function()
	pressAnim(btn1)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		pos1 = hrp.CFrame
		createBeam(pos1.Position, Color3.fromRGB(255, 50, 50), 1)
		createVisualBox(pos1.Position, 1)
	end
end)

-- Unwalk Button
btn2.MouseButton1Click:Connect(function()
	pressAnim(btn2)
	unwalkActive = not unwalkActive
	
	if unwalkActive then
		btn2.Text = "Unwalk: ON"
		btn2.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
		
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = 0
			end
		end
	else
		btn2.Text = "Unwalk: OFF"
		btn2.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
		
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = 16
			end
		end
	end
end)

-- Desync Button
btn3.MouseButton1Click:Connect(function()
	pressAnim(btn3)
	desyncActive = not desyncActive
	
	if desyncActive then
		applyFFlags(FFlags)
		if firstActivation then
			respawn(player)
			firstActivation = false
		end
		btn3.Text = "Desync: ON"
		btn3.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
	else
		applyFFlags(defaultFFlags)
		btn3.Text = "Desync: OFF"
		btn3.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
	end
end)

-- Continuous check for closest target
task.spawn(function()
	while true do
		task.wait(1)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local closestDist = math.huge
			local closestPos = nil
			for _, v in ipairs(targetPositions) do
				local dist = (hrp.Position - v).Magnitude
				if dist < closestDist then
					closestDist = dist
					closestPos = v
				end
			end
			if closestPos then
				pos2 = CFrame.new(closestPos)
				createBeam(pos2.Position, Color3.fromRGB(200, 30, 30), 2)
			end
		end
	end
end)

-- Instant Steal Logic
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, who)
	if who ~= player then return end
	if not instantStealEnabled then return end
	if prompt.Name ~= "Steal" and prompt.ActionText ~= "Steal" then return end

	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		local carpet = backpack:FindFirstChild("Flying Carpet")
		if carpet and player.Character and player.Character:FindFirstChild("Humanoid") then
			player.Character.Humanoid:EquipTool(carpet)
		end
	end

	if pos1 then hrp.CFrame = pos1 end
	if pos2 then task.wait(0.05); hrp.CFrame = pos2 end
end)

local discord = Instance.new("TextLabel", frame)
discord.Size = UDim2.new(1,0,0,16)
discord.Position = UDim2.fromOffset(0,270)
discord.BackgroundTransparency = 1
discord.Text = "discord.gg/7fShQy7ySy"
discord.Font = Enum.Font.GothamMedium
discord.TextSize = 10
discord.TextXAlignment = Enum.TextXAlignment.Center
discord.TextColor3 = Color3.fromRGB(180,180,180)

-- Snow effect
local snowContainer = Instance.new("Frame", frame)
snowContainer.Size = UDim2.new(1, 0, 1, 0)
snowContainer.BackgroundTransparency = 1
snowContainer.ClipsDescendants = true
snowContainer.ZIndex = 0

local function createSnowflake()
	local snow = Instance.new("TextLabel", snowContainer)
	snow.Size = UDim2.fromOffset(math.random(3, 6), math.random(3, 6))
	snow.Position = UDim2.new(math.random(0, 100) / 100, 0, 0, math.random(-20, 0))
	snow.BackgroundTransparency = 1
	snow.Text = "🔥"
	snow.TextSize = math.random(10, 16)
	snow.TextTransparency = math.random(0, 30) / 100
	snow.ZIndex = 0
	
	local fallTime = math.random(30, 50) / 10
	local endY = math.random(280, 320)
	
	local tween = TweenService:Create(snow, TweenInfo.new(fallTime, Enum.EasingStyle.Linear), {
		Position = UDim2.new(snow.Position.X.Scale + math.random(-10, 10) / 100, 0, 0, endY)
	})
	tween:Play()
	
	tween.Completed:Connect(function()
		snow:Destroy()
	end)
end

local function createWhiteCircle()
	local circle = Instance.new("Frame", snowContainer)
	circle.Size = UDim2.fromOffset(math.random(4, 8), math.random(4, 8))
	circle.Position = UDim2.new(math.random(0, 100) / 100, 0, 0, math.random(-20, 0))
	circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	circle.BackgroundTransparency = 0
	circle.BorderSizePixel = 0
	circle.ZIndex = 0
	
	local corner = Instance.new("UICorner", circle)
	corner.CornerRadius = UDim.new(1, 0)
	
	local fallTime = math.random(25, 45) / 10
	local endY = math.random(280, 320)
	
	local tween = TweenService:Create(circle, TweenInfo.new(fallTime, Enum.EasingStyle.Linear), {
		Position = UDim2.new(circle.Position.X.Scale + math.random(-15, 15) / 100, 0, 0, endY)
	})
	tween:Play()
	
	tween.Completed:Connect(function()
		circle:Destroy()
	end)
end

task.spawn(function()
	while true do
		if not minimized then
			createSnowflake()
		end
		task.wait(math.random(10, 30) / 100)
	end
end)

task.spawn(function()
	while true do
		if not minimized then
			createWhiteCircle()
		end
		task.wait(math.random(8, 25) / 100)
	end
end)

local h = 0
RunService.RenderStepped:Connect(function(dt)
	h = (h + dt * 0.3) % 1
	discord.TextColor3 = Color3.fromHSV(h,1,1)
end)
