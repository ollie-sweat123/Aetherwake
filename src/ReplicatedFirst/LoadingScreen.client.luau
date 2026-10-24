-- LoadingScreen (ReplicatedFirst, client): the AETHERWAKE loading card.
--
-- ReplicatedFirst scripts run before the rest of the game has arrived, so this one only
-- uses built-in Roblox objects (no requires, no uploaded images). What it does:
--   1. hides Roblox's default loading screen straight away
--   2. shows the title on an animated aether background (a sweeping band of light, a
--      slowly turning sigil, drifting motes) with a progress bar that follows the REAL
--      loading stages: the world, your character, your save
--   3. fades out (0.5 s) the moment all of that is ready
--   4. sets the Player attribute LoadingDone = true, so the tutorial (QuestClient) and
--      anything else that waits for it can start
-- It never waits on assets more than ~8 s after your save is ready, and shows a small
-- Continue button if loading takes longer than 15 s.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TIMING = {
	fade = 0.5,          -- seconds for the fade out
	assetGrace = 8,      -- never wait for assets longer than this after the save is ready
	settle = 0.2,        -- a short breath once everything is ready, so the first frame isn't half-built
	continueAfter = 15,  -- the Continue button shows up if loading takes longer than this
	tipEvery = 4.5,      -- seconds per gameplay tip
}

local COLOR = {
	navy = Color3.fromRGB(16, 18, 42),      -- #10122A, the HUD's panel navy
	navy2 = Color3.fromRGB(32, 30, 78),
	violet = Color3.fromRGB(176, 107, 255), -- #B06BFF
	cyan = Color3.fromRGB(92, 242, 255),    -- #5CF2FF
	gold = Color3.fromRGB(255, 200, 61),    -- #FFC83D
	text = Color3.fromRGB(245, 247, 255),
	sub = Color3.fromRGB(170, 180, 228),
}
local WHITE = Color3.new(1, 1, 1)

-- (true facts about the game: keep them in sync if the rules change)
local TIPS = {
	"Only champions deal damage. Tap BEST to equip your strongest team.",
	"Fuse 3 copies of a champion at the Fusion Machine for a star: +50% power.",
	"Every new champion in your Index adds +2% damage.",
	"Defeat a world's boss to unlock the next world at the Teleporter.",
	"Bad luck protection: a Legendary is guaranteed within 75 summons in a world.",
	"Press Q (or tap the dash button) to dash, and jump again in mid-air.",
	"Hold the screen during a summon to fast-forward it.",
	"Bosses drop Gems. Spend them on passes and upgrades.",
}

-- tiny helper: an Instance with properties (Parent last, so it is set up before it shows)
local function make(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	for _, c in children or {} do c.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function roundCorner(): UICorner return make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) end
local function textLabel(props: { [string]: any }): TextLabel
	local base = { BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextColor3 = COLOR.text, TextScaled = true }
	for k, v in props do base[k] = v end
	return make("TextLabel", base)
end

----------------------------------------------------------------------------
-- the screen
----------------------------------------------------------------------------
local gui = make("ScreenGui", { Name = "LoadingScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 1000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
-- (Active: clicks on the loading screen don't reach the world behind it)
local bg = make("Frame", { Name = "Background", BackgroundColor3 = COLOR.navy, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
	Active = true, Parent = gui })

-- a deep violet glow rising from the bottom
local floorGlow = make("Frame", { Name = "FloorGlow", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bg })
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(COLOR.navy, COLOR.violet),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.72) }),
	Parent = floorGlow })
-- the aether: a soft diagonal band of violet-cyan light that keeps sweeping across
local sweep = make("Frame", { Name = "Sweep", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bg })
local sweepGradient = make("UIGradient", { Rotation = 18, Parent = sweep,
	Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, COLOR.violet), ColorSequenceKeypoint.new(0.5, COLOR.cyan), ColorSequenceKeypoint.new(1, COLOR.violet) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.94), NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(0.7, 0.94), NumberSequenceKeypoint.new(1, 1) }) })

-- drifting motes (made once and recycled: nothing is created while it animates)
local motes = {}
for i = 1, 18 do
	local size = math.random(3, 7)
	local dot = make("Frame", { Name = "Mote", BackgroundColor3 = if i % 3 == 0 then COLOR.gold elseif i % 2 == 0 then COLOR.violet else COLOR.cyan,
		BackgroundTransparency = 0.25, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), Parent = bg }, { roundCorner() })
	motes[i] = { frame = dot, x = math.random(), y = math.random(), speed = 0.02 + math.random() * 0.035,
		sway = 0.01 + math.random() * 0.02, phase = math.random() * 6 }
end

-- the sigil: soft halo discs, three rings with runes and a six-point star, turning slowly
local sigil = make("Frame", { Name = "Sigil", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36),
	Size = UDim2.fromScale(0.6, 0.6), SizeConstraint = Enum.SizeConstraint.RelativeYY, Parent = bg })
for i, s in { 1.05, 0.8, 0.55 } do
	make("Frame", { Name = "Halo", BackgroundColor3 = COLOR.violet:Lerp(COLOR.cyan, (i - 1) / 2), BackgroundTransparency = 0.93,
		BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(s, s), Parent = sigil }, { roundCorner() })
end
local function ring(scale: number, thickness: number, color: Color3, transparency: number): Frame
	local f = make("Frame", { Name = "Ring", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale, scale), Parent = sigil }, { roundCorner() })
	make("UIStroke", { Thickness = thickness, Color = color, Transparency = transparency, Parent = f })
	return f
end
local outerRing = ring(0.98, 2, COLOR.cyan, 0.5)
local middleRing = ring(0.84, 3, COLOR.violet, 0.2)
local innerRing = ring(0.6, 2, COLOR.cyan, 0.45)
-- dashes around the outer ring
for i = 1, 24 do
	local a = (i / 24) * math.pi * 2
	local long = i % 2 == 0
	make("Frame", { Name = "Dash", BackgroundColor3 = COLOR.cyan, BackgroundTransparency = 0.35, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)), Rotation = math.deg(a),
		Size = UDim2.fromScale(if long then 0.045 else 0.025, 0.006), Parent = outerRing })
end
-- diamond runes on the middle ring (every third one gold)
for i = 1, 12 do
	local a = (i / 12) * math.pi * 2
	local big = i % 3 == 0
	local s = if big then 0.05 else 0.03
	make("Frame", { Name = "Rune", BackgroundColor3 = if big then COLOR.gold else COLOR.violet, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + 0.5 * math.cos(a), 0.5 + 0.5 * math.sin(a)), Rotation = math.deg(a) + 45,
		Size = UDim2.fromScale(s, s), Parent = middleRing })
end
-- a six-point star inside the inner ring: six chords, each at half the radius from the centre
for i = 0, 5 do
	local a = math.rad(30 + i * 60)
	make("Frame", { Name = "StarLine", BackgroundColor3 = COLOR.cyan, BackgroundTransparency = 0.55, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + 0.25 * math.cos(a), 0.5 + 0.25 * math.sin(a)), Rotation = math.deg(a) + 90,
		Size = UDim2.fromScale(0.866, 0.007), Parent = innerRing })
end

-- the centre column (narrow on phones, at most 620 px wide on big screens)
local column = make("Frame", { Name = "Column", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.9, 1), Parent = bg }, { make("UISizeConstraint", { MaxSize = Vector2.new(620, math.huge) }) })
local columnScale = make("UIScale", { Parent = column })

local title = textLabel({ Name = "Title", Text = "AETHERWAKE", Font = Enum.Font.LuckiestGuy, TextColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.35), Size = UDim2.fromScale(1, 0.15), Parent = column })
make("UITextSizeConstraint", { MaxTextSize = 110, Parent = title })
make("UIStroke", { Thickness = 4, Color = COLOR.navy, Parent = title })
make("UIGradient", { Rotation = 90, Parent = title, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.55, COLOR.cyan:Lerp(WHITE, 0.3)), ColorSequenceKeypoint.new(1, COLOR.violet:Lerp(WHITE, 0.15)) }) })
local titleScale = make("UIScale", { Parent = title })
local subtitle = textLabel({ Name = "Subtitle", Text = "Summon champions  •  Conquer the rifts", TextColor3 = COLOR.sub,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.43), Size = UDim2.fromScale(0.9, 0.045), Parent = column })
make("UITextSizeConstraint", { MaxTextSize = 26, Parent = subtitle })

-- progress: what is loading now (left), the percentage (right), the bar, the three stages
local stageText = textLabel({ Name = "Stage", Text = "Loading the world...", TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromScale(0, 0.685), Size = UDim2.fromScale(0.75, 0.04), Parent = column })
make("UITextSizeConstraint", { MaxTextSize = 24, Parent = stageText })
local percentText = textLabel({ Name = "Percent", Text = "0%", TextColor3 = COLOR.gold, TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0.685), Size = UDim2.fromScale(0.25, 0.04), Parent = column })
make("UITextSizeConstraint", { MaxTextSize = 24, Parent = percentText })
local barBack = make("Frame", { Name = "Bar", BackgroundColor3 = COLOR.navy2, BorderSizePixel = 0, Position = UDim2.new(0, 0, 0.73, 0),
	Size = UDim2.new(1, 0, 0, 16), Parent = column }, { roundCorner(), make("UIStroke", { Thickness = 2, Color = COLOR.violet, Transparency = 0.35 }) })
local barFill = make("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ClipsDescendants = true,
	Parent = barBack }, { roundCorner(), make("UIGradient", { Color = ColorSequence.new(COLOR.violet, COLOR.cyan) }) })
-- a little shine that runs along the filled part
local shine = make("Frame", { Name = "Shine", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = barFill })
local shineGradient = make("UIGradient", { Parent = shine, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) }) })

local STAGES = {
	{ key = "world", text = "Loading the world", chip = "World" },
	{ key = "champions", text = "Waking your champions", chip = "Champions" },
	{ key = "save", text = "Syncing your save", chip = "Save" },
}
local chipRow = make("Frame", { Name = "Stages", BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0.73, 26), Size = UDim2.new(1, 0, 0.04, 0),
	Parent = column }, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.04, 0), SortOrder = Enum.SortOrder.LayoutOrder }) })
local chips = {}
for i, st in STAGES do
	local chip = textLabel({ Name = st.chip, Text = "○  " .. st.chip, TextColor3 = COLOR.sub, TextTransparency = 0.3, LayoutOrder = i,
		Size = UDim2.fromScale(0.28, 1), Parent = chipRow })
	make("UITextSizeConstraint", { MaxTextSize = 20, Parent = chip })
	chips[st.key] = chip
end

-- one gameplay tip at a time
local tipBox = make("Frame", { Name = "Tip", BackgroundColor3 = COLOR.navy2, BackgroundTransparency = 0.25, BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.95, 0), Size = UDim2.new(1, 0, 0.1, 0), Parent = column },
	{ make("UICorner", { CornerRadius = UDim.new(0, 12) }), make("UIStroke", { Thickness = 2, Color = COLOR.violet, Transparency = 0.5 }) })
local tipTag = textLabel({ Name = "Tag", Text = "TIP", TextColor3 = COLOR.gold, Position = UDim2.new(0, 12, 0.2, 0), Size = UDim2.new(0.11, 0, 0.6, 0), Parent = tipBox })
make("UITextSizeConstraint", { MaxTextSize = 22, Parent = tipTag })
local tipText = textLabel({ Name = "Text", Text = TIPS[math.random(1, #TIPS)], TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.new(0.11, 18, 0.12, 0), Size = UDim2.new(0.89, -30, 0.76, 0), Parent = tipBox })
make("UITextSizeConstraint", { MaxTextSize = 21, Parent = tipText })

-- the Continue button (only if loading takes unusually long)
local continueButton = make("TextButton", { Name = "Continue", Visible = false, Text = "Continue  ▶", Font = Enum.Font.FredokaOne, TextScaled = true,
	TextColor3 = COLOR.navy, BackgroundColor3 = COLOR.cyan, AutoButtonColor = true, AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(170, 46), Parent = bg },
	{ make("UICorner", { CornerRadius = UDim.new(0, 14) }), make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })

gui.Parent = playerGui

----------------------------------------------------------------------------
-- animation: ONE RenderStepped connection, disconnected when the screen goes away
----------------------------------------------------------------------------
local shownProgress = 0 -- what the bar shows (it eases towards the real progress)
local targetProgress = 0
local fading = false
local animConn = RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	sweepGradient.Offset = Vector2.new(((t * 0.18) % 2) - 1, 0) -- (moves -1 -> 1, then starts again)
	outerRing.Rotation = (t * 6) % 360
	middleRing.Rotation = (-t * 10) % 360
	innerRing.Rotation = (t * 16) % 360
	titleScale.Scale = 1 + 0.015 * math.sin(t * 1.6)
	shineGradient.Offset = Vector2.new(((t * 0.7) % 2) - 1, 0)
	for _, m in motes do
		m.y -= m.speed * dt * (if fading then 3 else 1)
		if m.y < -0.05 then m.y, m.x = 1.05, math.random() end
		m.frame.Position = UDim2.fromScale(m.x + math.sin(t * 0.8 + m.phase) * m.sway, m.y)
	end
	-- the bar eases towards the real progress (fast enough that it never holds anything up)
	shownProgress += (targetProgress - shownProgress) * math.min(1, dt * (if fading then 14 else 6))
	barFill.Size = UDim2.fromScale(math.clamp(shownProgress, 0, 1), 1)
	percentText.Text = math.floor(math.clamp(shownProgress, 0, 1) * 100 + 0.5) .. "%"
end)

-- tips rotate with a quick fade
task.spawn(function()
	local index = table.find(TIPS, tipText.Text) or 1
	while gui.Parent and not fading do
		task.wait(TIMING.tipEvery)
		if fading or not gui.Parent then break end
		TweenService:Create(tipText, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		task.wait(0.2)
		if fading or not gui.Parent then break end
		index = index % #TIPS + 1
		tipText.Text = TIPS[index]
		TweenService:Create(tipText, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	end
end)

----------------------------------------------------------------------------
-- finishing: fade everything out, then tell the other scripts
----------------------------------------------------------------------------
local finished = false
local function finish()
	if finished then return end
	finished = true
	fading = true
	targetProgress = 1
	local info = TweenInfo.new(TIMING.fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(columnScale, info, { Scale = 1.06 }):Play()
	-- fade every piece of the screen together (each one from wherever it is now to invisible)
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") then
			local goal: { [string]: any } = { BackgroundTransparency = 1 }
			if d:IsA("TextLabel") or d:IsA("TextButton") then goal.TextTransparency = 1 end
			TweenService:Create(d, info, goal):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(TIMING.fade, function()
		player:SetAttribute("LoadingDone", true)
		animConn:Disconnect()
		gui:Destroy()
	end)
end
continueButton.Activated:Connect(finish)

----------------------------------------------------------------------------
-- the real loading stages
----------------------------------------------------------------------------
local function setChip(key: string, done: boolean)
	local chip = chips[key]
	local st
	for _, s in STAGES do if s.key == key then st = s end end
	if not chip or not st then return end
	chip.Text = (if done then "✓  " else "○  ") .. st.chip
	chip.TextColor3 = if done then COLOR.cyan else COLOR.sub
	chip.TextTransparency = if done then 0 else 0.3
end

local function run()
	local startedAt = os.clock()
	local maxQueue = 1
	local savedAt: number? = nil -- os.clock() when the save arrived
	local readyAt: number? = nil -- os.clock() when everything was first ready
	local lastStage = ""
	while not finished do
		local now = os.clock()
		local queue = ContentProvider.RequestQueueSize
		maxQueue = math.max(maxQueue, queue)

		local worldDone = game:IsLoaded()
		local championsDone = player.Character ~= nil
		local saveDone = player:GetAttribute("DataLoaded") == true
		if saveDone and not savedAt then savedAt = now end
		-- assets still downloading: wait for them, but never longer than assetGrace after the save
		local assetsDone = saveDone and (queue == 0 or now - (savedAt :: number) >= TIMING.assetGrace)

		-- progress: the world counts most; while it loads, the download queue (and a slow
		-- creep, so it never looks stuck) moves it along
		local world = 1
		if not worldDone then
			local fromQueue = 1 - queue / maxQueue
			local creep = 1 - math.exp(-(now - startedAt) / 4)
			world = math.min(0.9, math.max(fromQueue * 0.9, creep * 0.7))
		end
		local assets = if assetsDone then 1 elseif saveDone then 1 - queue / maxQueue else 0
		targetProgress = 0.45 * world + 0.2 * (if championsDone then 1 else 0) + 0.27 * (if saveDone then 1 else 0) + 0.08 * assets

		-- the line above the bar names the first stage that isn't done yet
		local stage = if not worldDone then STAGES[1].text elseif not championsDone then STAGES[2].text
			elseif not saveDone then STAGES[3].text else "Almost there"
		if stage ~= lastStage then
			lastStage = stage
			stageText.Text = stage .. "..."
		end
		setChip("world", worldDone)
		setChip("champions", championsDone)
		setChip("save", saveDone)

		if worldDone and championsDone and saveDone and assetsDone then
			readyAt = readyAt or now
			if now - readyAt >= TIMING.settle then finish() break end
		else
			readyAt = nil
		end
		if not continueButton.Visible and now - startedAt > TIMING.continueAfter then
			continueButton.Visible = true -- (something is slow: let the player in anyway)
		end
		task.wait(0.05)
	end
end

-- If anything above ever errors, never leave the player stuck behind the loading screen.
local ok, err = pcall(run)
if not ok then
	warn("[LoadingScreen] " .. tostring(err))
	finish()
end
