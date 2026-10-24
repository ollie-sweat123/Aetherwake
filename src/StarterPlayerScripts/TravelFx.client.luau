-- TravelFx (client): makes travelling between worlds feel like travelling.
--
-- 1. LIVING PORTALS. The Hub Teleporter and every world's WorldGate / ReturnGate have a
--    PortalFx model (built in Studio: a glowing Surface, a Core, a ring of Runes, a ring of
--    Dots, a soft light and a swirl of motes). This script turns the rings, lets the surface
--    breathe and glows the portal up as you walk close. ONE Heartbeat loop for all portals;
--    a portal further than 120 studs is skipped and its motes are switched off.
-- 2. THE TRAVEL TRANSITION. When your World attribute changes (not the first time it is set
--    when you join), a quick swirling iris in the destination world's colour opens over the
--    new world (~0.85 s) with a whoosh, then a name card ("Coral Harbor") fades in and out.
--    It is only visual: the server has already moved you, and the overlay never sinks taps.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Config has the world names and colours, SummonTiers the verified whoosh sound.
-- (pcall: if either module breaks, the portals still animate.)
local okConfig, Config = pcall(require, Shared:WaitForChild("Config"))
if not okConfig or type(Config) ~= "table" then Config = nil end
local okTiers, SummonTiers = pcall(require, Shared:WaitForChild("SummonTiers"))
local WHOOSH_ID = if okTiers and type(SummonTiers) == "table" and type(SummonTiers.SFX) == "table" then SummonTiers.SFX.sparkleWhoosh else nil

----------------------------------------------------------------------------
-- 1. LIVING PORTALS
----------------------------------------------------------------------------
local PORTAL = {
	range = 120,      -- studs: portals further away than this are not animated
	nearStart = 30,   -- the glow-up starts this close...
	nearFull = 12,    -- ...and is full this close
	rescan = 1.5,     -- seconds between looks for portals that streamed in or out
	runeSpin = 0.35,  -- radians per second for the rune ring
	dotSpin = -0.8,   -- the dot ring turns the other way, a bit faster
	swirlSpin = 2.2,  -- the motes' emitter turns fast, so the motes spiral outwards
}
local GATE_NAMES = { "Teleporter", "WorldGate", "ReturnGate" }

local portals = {} -- [PortalFx model] = its record (built once, when it streams in)

-- Reads one PortalFx model: which parts spin, where they sit, and the resting look
-- (so the glow-up always returns to exactly what was built in Studio).
local function buildPortal(fx: Model)
	local surface = fx:FindFirstChild("Surface")
	if not surface or not surface:IsA("BasePart") then return nil end
	local core = fx:FindFirstChild("Core")
	local light = surface:FindFirstChildOfClass("PointLight")
	local swirl = surface:FindFirstChild("Swirl")
	local motes = swirl and swirl:FindFirstChildOfClass("ParticleEmitter")
	local rec = {
		surface = surface,
		core = if core and core:IsA("BasePart") then core else nil,
		light = light,
		swirl = if swirl and swirl:IsA("Attachment") then swirl else nil,
		motes = motes,
		-- the Surface's X axis points out of the portal, so turning around X spins the rings
		center = surface.CFrame,
		parts = {}, offsets = {}, isRune = {}, cfs = {},
		runeAngle = 0, dotAngle = 0, swirlAngle = 0,
		near = 0, boost = 0, active = nil :: boolean?, -- (nil: the first frame always sets the motes on/off)
		phase = math.random() * 6, -- (so two portals never breathe in sync)
	}
	-- The resting look is stored on the PortalFx model as attributes (BaseSurface, BaseCore,
	-- BaseLight, BaseRange, BaseRate), so a portal that was saved mid-glow still rests at the
	-- right look. (No attribute: use what the part has now.)
	local function baseOf(attr: string, now: number): number
		local v = fx:GetAttribute(attr)
		return if type(v) == "number" then v else now
	end
	rec.base = {
		surface = baseOf("BaseSurface", surface.Transparency),
		core = baseOf("BaseCore", if rec.core then rec.core.Transparency else 0),
		lightBrightness = baseOf("BaseLight", if light then light.Brightness else 0),
		lightRange = baseOf("BaseRange", if light then light.Range else 0),
		motesRate = baseOf("BaseRate", if motes then motes.Rate else 0),
		swirl = if rec.swirl then rec.swirl.CFrame else CFrame.identity,
	}
	for _, p in fx:GetChildren() do
		if p:IsA("BasePart") and (p.Name == "Rune" or p.Name == "Dot") then
			table.insert(rec.parts, p)
			table.insert(rec.offsets, rec.center:ToObjectSpace(p.CFrame))
			table.insert(rec.isRune, p.Name == "Rune")
			table.insert(rec.cfs, p.CFrame)
		end
	end
	return rec
end

-- Finds the portals that exist right now. (With streaming, a far-away gate can be missing;
-- PortalFx is an Atomic model, so it is either all there or not there at all.)
local function rescan()
	local worlds = workspace:FindFirstChild("Worlds")
	local seen = {}
	if worlds then
		for _, world in worlds:GetChildren() do
			for _, name in GATE_NAMES do
				local gate = world:FindFirstChild(name)
				local fx = gate and gate:FindFirstChild("PortalFx")
				if fx and fx:IsA("Model") then
					seen[fx] = true
					if not portals[fx] then portals[fx] = buildPortal(fx) end
				end
			end
		end
	end
	for fx in portals do
		if not seen[fx] then portals[fx] = nil end
	end
end

-- One frame of one nearby portal.
local function animatePortal(rec, dt: number, dist: number, now: number)
	-- 0 = far away, 1 = right next to it (smoothed, so it glows up and down gently)
	local want = math.clamp((PORTAL.nearStart - dist) / (PORTAL.nearStart - PORTAL.nearFull), 0, 1)
	rec.near += (want - rec.near) * math.min(1, dt * 4)
	rec.boost = math.max(0, rec.boost - dt * 1.2) -- (the flare after you use the gate fades out)
	local glow = math.min(1, rec.near + rec.boost)
	local speed = 1 + 1.5 * glow + 2 * rec.boost

	-- spin the two rings (opposite ways) around the portal's axis
	rec.runeAngle = (rec.runeAngle + PORTAL.runeSpin * speed * dt) % (math.pi * 2)
	rec.dotAngle = (rec.dotAngle + PORTAL.dotSpin * speed * dt) % (math.pi * 2)
	for i, offset in rec.offsets do
		local angle = if rec.isRune[i] then rec.runeAngle else rec.dotAngle
		rec.cfs[i] = rec.center * CFrame.Angles(angle, 0, 0) * offset
	end
	if #rec.parts > 0 then
		workspace:BulkMoveTo(rec.parts, rec.cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- the motes' emitter turns fast: the motes are locked to it, so they swirl outwards
	if rec.swirl then
		rec.swirlAngle = (rec.swirlAngle + PORTAL.swirlSpin * speed * dt) % (math.pi * 2)
		rec.swirl.CFrame = rec.base.swirl * CFrame.Angles(rec.swirlAngle, 0, 0)
	end

	-- the surface breathes slowly and gets brighter as you come close
	local breathe = 0.5 + 0.5 * math.sin(now * 2.2 + rec.phase)
	rec.surface.Transparency = math.clamp(rec.base.surface - 0.22 * glow - 0.06 * breathe, 0, 1)
	if rec.core then
		rec.core.Transparency = math.clamp(rec.base.core - 0.25 * glow - 0.08 * (1 - breathe), 0, 1)
	end
	if rec.light then
		rec.light.Brightness = rec.base.lightBrightness * (1 + 1.6 * glow + 0.15 * breathe)
		rec.light.Range = rec.base.lightRange * (1 + 0.6 * glow)
	end
	if rec.motes then
		-- (4/s resting, 8/s when you're close; never above the 8/s ambient budget)
		rec.motes.Rate = math.min(8, rec.base.motesRate * (1 + glow))
	end
end

-- (cache the root part: no searching every frame)
local rootPart: BasePart? = nil
local function onCharacter(char: Model)
	rootPart = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

local lastScan = -math.huge
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	if now - lastScan > PORTAL.rescan then
		lastScan = now
		rescan()
	end
	local from = if rootPart and rootPart.Parent then rootPart.Position else workspace.CurrentCamera.CFrame.Position
	for _, rec in portals do
		local dist = (rec.center.Position - from).Magnitude
		local active = dist <= PORTAL.range
		if active ~= rec.active then
			rec.active = active
			if rec.motes then rec.motes.Enabled = active end
		end
		if active then animatePortal(rec, dt, dist, now) end
	end
end)

-- Using a gate makes its portal flare up for a moment.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name ~= "GatePrompt" then return end
	local node = prompt.Parent
	while node and node ~= workspace do
		local fx = node:FindFirstChild("PortalFx")
		if fx and portals[fx] then
			portals[fx].boost = 1
			return
		end
		node = node.Parent
	end
end)

----------------------------------------------------------------------------
-- 2. THE TRAVEL TRANSITION
----------------------------------------------------------------------------
local TRAVEL = {
	hold = 0.18,      -- the iris stays shut this long (hides the camera jump)...
	open = 0.67,      -- ...then opens over this long (0.85 s in all)
	spin = math.rad(75), -- how far the iris blades swirl while opening
	cardIn = 0.3,     -- the world name card fades in this far into the transition
	cardHold = 1.5,
	cardOut = 0.45,
}
local NAVY = Color3.fromRGB(16, 18, 42)
local WHITE = Color3.new(1, 1, 1)
local BLADES = 8

local gui = Instance.new("ScreenGui")
gui.Name = "TravelFx"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 900 -- (above the HUD, below the loading screen)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- the iris: 8 big blades, each covering everything past one edge of an octagon. Pushing the
-- edges outwards opens an octagonal hole in the middle; turning them makes it swirl.
local iris = Instance.new("Frame")
iris.Name = "Iris"
iris.BackgroundTransparency = 1
iris.Size = UDim2.fromScale(1, 1)
iris.Visible = false
iris.Parent = gui
local blades = {}
for i = 1, BLADES do
	local b = Instance.new("Frame")
	b.Name = "Blade"
	b.BorderSizePixel = 0
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BackgroundColor3 = WHITE
	local grad = Instance.new("UIGradient")
	grad.Parent = b
	-- a bright line on the blade's inner edge: together they draw the rim of the hole
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.BorderSizePixel = 0
	rim.BackgroundColor3 = WHITE
	rim.BackgroundTransparency = 0.2
	rim.Size = UDim2.new(0, 5, 1, 0)
	rim.Parent = b
	b.Parent = iris
	blades[i] = { frame = b, grad = grad }
end
-- a soft white burst in the middle as the iris opens
local burst = Instance.new("Frame")
burst.Name = "Burst"
burst.AnchorPoint = Vector2.new(0.5, 0.5)
burst.Position = UDim2.fromScale(0.5, 0.5)
burst.BackgroundColor3 = WHITE
burst.BorderSizePixel = 0
burst.ZIndex = 2
local burstCorner = Instance.new("UICorner")
burstCorner.CornerRadius = UDim.new(0.5, 0)
burstCorner.Parent = burst
burst.Parent = iris

-- the world name card
local card = Instance.new("Frame")
card.Name = "WorldCard"
card.BackgroundTransparency = 1
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.38)
card.Size = UDim2.fromOffset(700, 150)
card.Visible = false
card.Parent = gui
local cardScale = Instance.new("UIScale")
cardScale.Parent = card
local kicker = Instance.new("TextLabel")
kicker.Name = "Kicker"
kicker.BackgroundTransparency = 1
kicker.Font = Enum.Font.FredokaOne
kicker.TextScaled = true
kicker.Size = UDim2.new(1, 0, 0, 30)
kicker.TextColor3 = WHITE
kicker.Parent = card
local kickerStroke = Instance.new("UIStroke")
kickerStroke.Thickness = 2
kickerStroke.Color = NAVY
kickerStroke.Parent = kicker
local title = Instance.new("TextLabel")
title.Name = "WorldName"
title.BackgroundTransparency = 1
title.Font = Enum.Font.LuckiestGuy
title.TextScaled = true
title.Position = UDim2.fromOffset(0, 32)
title.Size = UDim2.new(1, 0, 0, 84)
title.TextColor3 = WHITE
title.Parent = card
local titleStroke = Instance.new("UIStroke")
titleStroke.Thickness = 4
titleStroke.Color = NAVY
titleStroke.Parent = title
local line = Instance.new("Frame")
line.Name = "Line"
line.BorderSizePixel = 0
line.AnchorPoint = Vector2.new(0.5, 0)
line.Position = UDim2.new(0.5, 0, 0, 126)
line.Size = UDim2.new(0, 0, 0, 5)
line.Parent = card
local lineCorner = Instance.new("UICorner")
lineCorner.CornerRadius = UDim.new(0.5, 0)
lineCorner.Parent = line

-- (nothing in this overlay may catch a click or a tap)
for _, g in { iris, card } do
	pcall(function() (g :: any).Interactable = false end)
end

local whoosh: Sound? = nil
if type(WHOOSH_ID) == "string" then
	whoosh = Instance.new("Sound")
	whoosh.Name = "Whoosh"
	whoosh.SoundId = WHOOSH_ID
	whoosh.Volume = 0.45
	whoosh.Parent = gui
	-- (in the Sound Effects volume group, so the Settings sliders apply to it)
	local okAudio, Audio = pcall(require, Shared:WaitForChild("Audio"))
	if okAudio then Audio.Adopt(whoosh, "Sfx") end
end

gui.Parent = player:WaitForChild("PlayerGui")

local function rescaleCard()
	local vp = workspace.CurrentCamera.ViewportSize
	cardScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.5)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleCard)
rescaleCard()

-- Puts the blades so the hole in the middle has inner radius `r` pixels, turned by `spin`.
local function layoutIris(r: number, spin: number): number
	local size = iris.AbsoluteSize
	local cx, cy = size.X / 2, size.Y / 2
	local halfDiagonal = math.sqrt(cx * cx + cy * cy)
	local side = halfDiagonal * 2.2 -- (big enough to reach every corner of the screen)
	for i, blade in blades do
		local angle = (i - 1) * (math.pi * 2 / BLADES) + spin
		local d = r + side / 2
		blade.frame.Size = UDim2.fromOffset(side, side)
		blade.frame.Position = UDim2.fromOffset(cx + d * math.cos(angle), cy + d * math.sin(angle))
		blade.frame.Rotation = math.deg(angle)
	end
	return halfDiagonal
end

local function worldInfo(worldId: number): (string, string, Color3)
	local w = Config and Config.WorldById and Config.WorldById(worldId)
	local color = if w and w.theme and typeof(w.theme.accent) == "Color3" then w.theme.accent else Color3.fromRGB(176, 107, 255)
	local name = if w and w.name then tostring(w.name) else "Somewhere new"
	local kickerText = if worldId == 0 then "HOME" else "WORLD " .. tostring(worldId)
	return name, kickerText, color
end

local playToken = 0
local irisConn: RBXScriptConnection? = nil

local function showCard(token: number, name: string, kickerText: string, color: Color3)
	kicker.Text = kickerText
	kicker.TextColor3 = color
	title.Text = name
	line.BackgroundColor3 = color
	for _, l in { kicker, title } do l.TextTransparency = 1 end
	kickerStroke.Transparency, titleStroke.Transparency = 1, 1
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(0, 0, 0, 5)
	card.Position = UDim2.fromScale(0.5, 0.40)
	card.Visible = true
	local inInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(card, inInfo, { Position = UDim2.fromScale(0.5, 0.38) }):Play()
	for _, l in { kicker, title } do TweenService:Create(l, inInfo, { TextTransparency = 0 }):Play() end
	for _, s in { kickerStroke, titleStroke } do TweenService:Create(s, inInfo, { Transparency = 0 }):Play() end
	TweenService:Create(line, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0, Size = UDim2.new(0.42, 0, 0, 5) }):Play()
	task.delay(TRAVEL.cardHold, function()
		if token ~= playToken then return end
		local outInfo = TweenInfo.new(TRAVEL.cardOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, l in { kicker, title } do TweenService:Create(l, outInfo, { TextTransparency = 1 }):Play() end
		for _, s in { kickerStroke, titleStroke } do TweenService:Create(s, outInfo, { Transparency = 1 }):Play() end
		TweenService:Create(line, outInfo, { BackgroundTransparency = 1 }):Play()
		task.wait(TRAVEL.cardOut)
		if token == playToken then card.Visible = false end
	end)
end

local function playTravel(worldId: number)
	playToken += 1
	local token = playToken
	local name, kickerText, color = worldInfo(worldId)

	-- paint the blades in the destination colour (every other one a touch darker)
	for i, blade in blades do
		local c = if i % 2 == 0 then color:Lerp(NAVY, 0.14) else color
		blade.grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, c:Lerp(WHITE, 0.45)),
			ColorSequenceKeypoint.new(0.04, c),
			ColorSequenceKeypoint.new(0.45, c:Lerp(NAVY, 0.55)),
			ColorSequenceKeypoint.new(1, NAVY),
		})
	end
	burst.BackgroundTransparency = 1
	burst.Size = UDim2.fromOffset(0, 0)
	layoutIris(0, 0)
	iris.Visible = true

	if whoosh then
		whoosh.Volume = 0.45
		whoosh.TimePosition = 0
		whoosh:Play()
		task.delay(1.2, function()
			if token ~= playToken or not whoosh then return end
			TweenService:Create(whoosh, TweenInfo.new(0.6), { Volume = 0 }):Play()
			task.wait(0.65)
			if token == playToken and whoosh then whoosh:Stop() end
		end)
	end

	if irisConn then irisConn:Disconnect() end
	local t0 = os.clock()
	local cardShown = false
	irisConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if not cardShown and t >= TRAVEL.cardIn then
			cardShown = true
			showCard(token, name, kickerText, color)
		end
		local k = math.clamp((t - TRAVEL.hold) / TRAVEL.open, 0, 1)
		local eased = k * k * (3 - 2 * k) -- (smoothstep: starts and ends gently)
		local halfDiagonal = iris.AbsoluteSize.Magnitude / 2
		layoutIris(eased * halfDiagonal * 1.05, eased * TRAVEL.spin)
		-- the burst grows and fades while the iris opens
		local b = math.clamp((t - TRAVEL.hold) / 0.45, 0, 1)
		burst.Size = UDim2.fromOffset(b * halfDiagonal * 1.1, b * halfDiagonal * 1.1)
		burst.BackgroundTransparency = if b <= 0 then 1 else 0.25 + 0.75 * b
		if k >= 1 then
			iris.Visible = false
			if irisConn then irisConn:Disconnect(); irisConn = nil end
		end
	end)
end

-- Only real trips get the transition: the first World value (set when you join) doesn't,
-- and nothing plays while the loading screen is still up.
local lastWorld = player:GetAttribute("World")
player:GetAttributeChangedSignal("World"):Connect(function()
	local now = player:GetAttribute("World")
	local before = lastWorld
	lastWorld = now
	if type(before) ~= "number" or type(now) ~= "number" or now == before then return end
	local loading = ReplicatedFirst:FindFirstChild("LoadingScreen") ~= nil and player:GetAttribute("LoadingDone") ~= true
	if loading then return end
	playTravel(now)
end)
