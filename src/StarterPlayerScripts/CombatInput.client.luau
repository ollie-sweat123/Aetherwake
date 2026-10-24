-- CombatInput (client): click or tap an enemy to make your champions attack it.
-- Holding the button keeps the target. The client only tells the server
-- WHICH enemy - the server decides if that's allowed (players deal no damage
-- themselves; only champions do).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer
local enemies = workspace:WaitForChild("Enemies")
local HOLD_RATE = 1 / 6 -- clicks per second while holding
local PICK_RADIUS = 90 -- pixels: a tap this close to an enemy's centre on screen still picks it

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { enemies }

-- same limit the server uses (Config.Combat.MaxTargetDistance)
local function maxDistance(): number
	return Config.Combat.MaxTargetDistance or 140
end

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function closeEnough(model: Model): boolean
	local root, pr = myRoot(), model.PrimaryPart
	return root ~= nil and pr ~= nil and (pr.Position - root.Position).Magnitude <= maxDistance()
end

-- 1) exact: the enemy right under the cursor/finger
local function enemyUnder(screenPos: Vector2): Model?
	local cam = workspace.CurrentCamera
	-- input positions don't include the top-bar inset, so use ScreenPointToRay (not Viewport)
	local ray = cam:ScreenPointToRay(screenPos.X, screenPos.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if not hit then return nil end
	local inst: Instance? = hit.Instance
	while inst and inst.Parent ~= enemies do inst = inst.Parent end
	if not inst or not inst:IsA("Model") or inst:GetAttribute("Dead") then return nil end
	return inst
end

-- 2) forgiving: far-away enemies are tiny on screen, so if the ray missed, pick the
-- enemy whose centre is closest to the tap on screen (within PICK_RADIUS pixels)
local function enemyNear(screenPos: Vector2): Model?
	local cam = workspace.CurrentCamera
	local best, bestPx = nil, PICK_RADIUS
	for _, m in enemies:GetChildren() do
		local pr = m:IsA("Model") and m.PrimaryPart
		if pr and not m:GetAttribute("Dead") and closeEnough(m) then
			-- WorldToScreenPoint matches the input's coordinate space (no top-bar inset)
			local sp, onScreen = cam:WorldToScreenPoint(pr.Position)
			if onScreen and sp.Z > 0 then
				local px = (Vector2.new(sp.X, sp.Y) - screenPos).Magnitude
				if px < bestPx then best, bestPx = m, px end
			end
		end
	end
	return best
end

local function enemyAt(screenPos: Vector2): Model?
	local e = enemyUnder(screenPos)
	if e and closeEnough(e) then return e end
	return enemyNear(screenPos)
end

local holding = false
local holdPos = Vector2.zero
local held: Model? = nil

local function attack(pos: Vector2)
	local e = enemyAt(pos)
	if e then
		held = e
		Remotes.Attack:FireServer(e)
	elseif held and held.Parent == enemies then
		Remotes.Attack:FireServer(held)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		holding = true
		holdPos = Vector2.new(input.Position.X, input.Position.Y)
		held = nil
		attack(holdPos)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if holding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		holdPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		holding = false
		held = nil
	end
end)

task.spawn(function()
	while true do
		task.wait(HOLD_RATE)
		if holding and held then attack(holdPos) end
	end
end)

-- highlight whatever you're targeting
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(255, 230, 90)
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
highlight.Parent = workspace
local function updateHighlight()
	local name = player:GetAttribute("Target")
	highlight.Adornee = name and enemies:FindFirstChild(name) or nil
end
player:GetAttributeChangedSignal("Target"):Connect(updateHighlight)

----------------------------------------------------------------------------
-- CONTROLLER: LB / RB pick an enemy without a mouse
-- A press picks the enemy you can see that's closest to the middle of the screen; with one
-- already targeted, RB moves to the next one to the right on screen and LB to the left.
-- Only living enemies in this world, within the attack range and not behind a wall count.
-- The client only says WHICH enemy (Remotes.Attack): the server checks range and world again.
----------------------------------------------------------------------------
local ContextActionService = game:GetService("ContextActionService")
local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD", 30)

-- something solid between the camera and the enemy? (see-through and walk-through parts like
-- spawn zones don't count)
local losParams = RaycastParams.new()
local function blocked(to: Vector3): boolean
	local ignore = { enemies, player.Character }
	for _, name in { "ClientEffects", "ClientChampions" } do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end
	local from = workspace.CurrentCamera.CFrame.Position
	for _ = 1, 6 do -- (skips up to 6 see-through parts on the way)
		losParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(from, to - from, losParams)
		if not hit then return false end
		local part = hit.Instance
		if part:IsA("BasePart") and part.CanCollide and part.Transparency < 0.6 then return true end
		table.insert(ignore, part)
	end
	return false
end

-- every enemy you could target right now, with where it is on screen
local function targetable(): { { model: Model, x: number, centre: number } }
	local list = {}
	local root = myRoot()
	if not root then return list end
	local cam = workspace.CurrentCamera
	local vp = cam.ViewportSize
	local myWorld = player:GetAttribute("World")
	for _, m in enemies:GetChildren() do
		local pr = m:IsA("Model") and m.PrimaryPart
		if pr and not m:GetAttribute("Dead") and closeEnough(m)
			and (myWorld == nil or m:GetAttribute("WorldId") == nil or m:GetAttribute("WorldId") == myWorld) then
			local sp, onScreen = cam:WorldToViewportPoint(pr.Position)
			if onScreen and sp.Z > 0 and not blocked(pr.Position) then
				table.insert(list, { model = m, x = sp.X, centre = (Vector2.new(sp.X, sp.Y) - vp / 2).Magnitude })
			end
		end
	end
	table.sort(list, function(a, b) return a.x < b.x end)
	return list
end

local function say(text: string)
	local cmd = hud and hud:FindFirstChild("Command")
	if cmd then pcall(function() cmd:Invoke("toast", text) end) end
end

local lastNoTarget = 0
local function cycleTarget(step: number)
	local list = targetable()
	if #list == 0 then
		if os.clock() - lastNoTarget > 1.5 then -- (one message, not one per press)
			lastNoTarget = os.clock()
			say("No enemies in range. Walk closer or turn the camera!")
		end
		return
	end
	local current = player:GetAttribute("Target")
	local index: number? = nil
	for i, e in list do
		if e.model.Name == current then index = i end
	end
	local pick
	if index then
		pick = list[(index - 1 + step) % #list + 1].model
	else
		-- nothing targeted (or it's off screen): the one nearest the middle of the screen
		table.sort(list, function(a, b) return a.centre < b.centre end)
		pick = list[1].model
	end
	Remotes.Attack:FireServer(pick)
end

-- (bound once for the whole session; menus get the buttons back: see the Pass below)
ContextActionService:BindAction("AetherwakeTargetPrev", function(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if hud and (hud:GetAttribute("OpenPanel") or (hud:GetAttribute("SummonPhase") or "idle") ~= "idle") then return Enum.ContextActionResult.Pass end
	cycleTarget(-1)
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonL1)
ContextActionService:BindAction("AetherwakeTargetNext", function(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if hud and (hud:GetAttribute("OpenPanel") or (hud:GetAttribute("SummonPhase") or "idle") ~= "idle") then return Enum.ContextActionResult.Pass end
	cycleTarget(1)
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.ButtonR1)

----------------------------------------------------------------------------
-- TARGET CARD (top of the screen): the enemy you're fighting, its health, big enough to read
-- on a TV. It mirrors the enemy's own health bar (the server keeps that one up to date).
----------------------------------------------------------------------------
local cardGui = Instance.new("ScreenGui")
cardGui.Name = "TargetUI"
cardGui.ResetOnSpawn = false
cardGui.IgnoreGuiInset = true
cardGui.DisplayOrder = 1
cardGui.Parent = player:WaitForChild("PlayerGui")
local card = Instance.new("Frame")
card.Name = "TargetCard"
card.Visible = false
card.AnchorPoint = Vector2.new(0.5, 0)
card.BackgroundColor3 = Color3.fromRGB(24, 26, 44)
card.BackgroundTransparency = 0.15
card.Parent = cardGui
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
local cardStroke = Instance.new("UIStroke")
cardStroke.Thickness = 2.5
cardStroke.Color = Color3.fromRGB(255, 230, 90)
cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
cardStroke.Parent = card
local cardScale = Instance.new("UIScale")
cardScale.Parent = card
local function text(name: string, pos: UDim2, size: UDim2, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = align
	l.Position, l.Size = pos, size
	local s = Instance.new("UIStroke"); s.Thickness = 1.5; s.Parent = l
	l.Parent = card
	return l
end
card.Size = UDim2.fromOffset(340, 64)
local nameText = text("EnemyName", UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 24), Enum.TextXAlignment.Left)
local barBack = Instance.new("Frame")
barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
barBack.Position = UDim2.fromOffset(14, 34)
barBack.Size = UDim2.new(1, -28, 0, 20)
barBack.Parent = card
Instance.new("UICorner", barBack).CornerRadius = UDim.new(0.5, 0)
local barFill = Instance.new("Frame")
barFill.BackgroundColor3 = Color3.fromRGB(110, 230, 90)
barFill.Size = UDim2.fromScale(1, 1)
barFill.Parent = barBack
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0.5, 0)
local hpText = text("Health", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
hpText.Parent = barBack
hpText.ZIndex = 2
-- with a controller: "LB / RB switch" on the card (Roblox picks Xbox or PlayStation pictures)
local switchHint = Instance.new("Frame")
switchHint.BackgroundTransparency = 1
switchHint.AnchorPoint = Vector2.new(1, 0)
switchHint.Position = UDim2.new(1, -12, 0, 6)
switchHint.Size = UDim2.fromOffset(110, 24)
switchHint.Parent = card
for i, key in { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 } do
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(24, 24)
	icon.Position = UDim2.fromOffset((i - 1) * 28, 0)
	pcall(function() icon.Image = UserInputService:GetImageForKeyCode(key) end)
	icon.Parent = switchHint
end
local switchText = Instance.new("TextLabel")
switchText.BackgroundTransparency = 1
switchText.Font = Enum.Font.FredokaOne
switchText.TextScaled = true
switchText.Text = "switch"
switchText.TextColor3 = Color3.fromRGB(180, 190, 230)
switchText.Position = UDim2.fromOffset(58, 3)
switchText.Size = UDim2.fromOffset(52, 18)
switchText.Parent = switchHint

-- same scaling as the HUD (designed at 1280 x 720), kept inside the TV safe area on consoles
local function placeCard()
	local vp = workspace.CurrentCamera.ViewportSize
	local tv = game:GetService("GuiService"):IsTenFootInterface()
	local margin = if tv then 0.05 else 0
	local sc = math.clamp(math.min(vp.X * (1 - margin * 2) / 1280, vp.Y * (1 - margin * 2) / 720), 0.5, 2)
	cardScale.Scale = sc
	-- under the world name pill (12 + 46 canvas px from the top of the safe area)
	card.Position = UDim2.new(0.5, 0, 0, vp.Y * margin + 66 * sc)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeCard)
placeCard()

-- refreshed 10 times a second, and only while there's a target (cheap with lots of enemies)
task.spawn(function()
	while true do
		task.wait(0.1)
		local name = player:GetAttribute("Target")
		local m = name and enemies:FindFirstChild(name)
		local busy = hud ~= nil and (hud:GetAttribute("OpenPanel") ~= nil or (hud:GetAttribute("SummonPhase") or "idle") ~= "idle")
		local bar = m and m.PrimaryPart and m.PrimaryPart:FindFirstChild("HealthBar")
		if not m or busy or m:GetAttribute("Dead") or not bar then
			card.Visible = false
		else
			card.Visible = true
			local labels = {}
			for _, d in bar:GetDescendants() do
				if d:IsA("TextLabel") then table.insert(labels, d) end
			end
			local fill = bar:FindFirstChild("Fill", true)
			nameText.Text = if labels[1] then labels[1].Text else m.Name
			nameText.TextColor3 = if labels[1] then labels[1].TextColor3 else Color3.new(1, 1, 1)
			hpText.Text = if labels[2] then labels[2].Text else ""
			if fill then
				barFill.Size = UDim2.fromScale(math.clamp(fill.Size.X.Scale, 0, 1), 1)
				barFill.BackgroundColor3 = fill.BackgroundColor3
			end
			local pad = player:GetAttribute("InputMode") == "Gamepad"
			switchHint.Visible = pad
			nameText.Size = UDim2.new(1, if pad then -140 else -28, 0, 24)
		end
	end
end)
