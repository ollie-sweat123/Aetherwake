-- MapBuilder (dev tool): builds the hub city and every world map.
-- Run from the command bar:
--   require(game.ServerStorage.DevTools.MapBuilder).BuildAll(require(game.ReplicatedStorage.Shared.Config:Clone()))
-- WARNING: rebuilding replaces Workspace.Worlds, so hand-made edits inside it are lost.
--
-- Uses the AI-generated props in ServerStorage.Props (trees, huts, teleporter...).
-- World layout (north = -Z):
--   arrival + orb shrine (south) -> sand path ring with 3 enemy zones -> boss arena (center)
--   -> world gate to the next world (north). Cliffs ring the edge.

local ServerStorage = game:GetService("ServerStorage")
local Props = ServerStorage:WaitForChild("Props")

local M = {}
local Config
local rng = Random.new(42)

local CYL = Enum.PartType.Cylinder
local function P(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do (p :: any)[k] = v end
	p.Parent = parent
	return p
end
local function disc(parent, pos, diameter, thick, color, material, extra)
	local props = { Shape = CYL, Size = Vector3.new(thick, diameter, diameter), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color, Material = material or Enum.Material.SmoothPlastic }
	for k, v in extra or {} do props[k] = v end
	return P(parent, props)
end
local function segment(parent, a, b, width, thick, color, material, extra)
	local mid = (a + b) / 2
	local props = { Size = Vector3.new(width, thick, (b - a).Magnitude), CFrame = CFrame.lookAt(mid, b), Color = color, Material = material or Enum.Material.SmoothPlastic }
	for k, v in extra or {} do props[k] = v end
	return P(parent, props)
end
-- Smooth curve through control points (Catmull-Rom).
local function curve(ctrl, steps, closed)
	local pts = {}
	local n = #ctrl
	local function get(i)
		if closed then return ctrl[(i - 1) % n + 1] end
		return ctrl[math.clamp(i, 1, n)]
	end
	local last = closed and n or n - 1
	for i = 1, last do
		local p0, p1, p2, p3 = get(i - 1), get(i), get(i + 1), get(i + 2)
		for s = 0, steps - 1 do
			local t = s / steps
			local t2, t3 = t * t, t * t * t
			table.insert(pts, 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
		end
	end
	if not closed then table.insert(pts, ctrl[n]) end
	if closed then table.insert(pts, pts[1]) end
	return pts
end
-- Draws a winding path: rounded joints + straight pieces. Returns the points (for keeping decor off paths).
local allPathPoints = {}
local function path(parent, pts, width, color, material)
	for i, p in pts do
		disc(parent, p + Vector3.new(0, 0.12, 0), width, 0.25, color, material, { CanCollide = false })
		if i < #pts then
			segment(parent, p + Vector3.new(0, 0.12, 0), pts[i + 1] + Vector3.new(0, 0.12, 0), width, 0.25, color, material, { CanCollide = false })
		end
		table.insert(allPathPoints, { p = p, w = width })
	end
	return pts
end
local function farFromPaths(pos, margin)
	for _, pp in allPathPoints do
		local d = Vector3.new(pos.X - pp.p.X, 0, pos.Z - pp.p.Z).Magnitude
		if d < pp.w / 2 + margin then return false end
	end
	return true
end

local function label(parent, text, color, width, offsetY)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(width or 14, (width or 14) / 4)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 3, 0)
	bb.MaxDistance = 300
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color
	local s = Instance.new("UIStroke"); s.Thickness = 3; s.Parent = t
	t.Parent = bb
	bb.Parent = parent
	return bb
end

local function prompt(parent, name, action, object)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = name
	pp.ActionText = action
	pp.ObjectText = object or ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 16
	pp.RequiresLineOfSight = false
	pp.Parent = parent
	return pp
end

-- Clone a prop, scale it, put its bottom-center at pos.
local function prop(parent, name, pos, rotY, scale, tint)
	local t = Props:FindFirstChild(name)
	if not t then return nil end
	local c = t:Clone()
	if scale and scale ~= 1 then c:ScaleTo(scale) end
	c:PivotTo(CFrame.new(pos) * CFrame.Angles(0, rotY or 0, 0))
	if tint then
		for _, d in c:GetDescendants() do
			if d:IsA("MeshPart") then d.Color = tint end
		end
	end
	c.Parent = parent
	return c
end

-- A station = prop + glowing floor pad + floating name + prompt.
local function station(parent, name, propName, pos, rotY, scale, title, color, promptName, actionText, attrs)
	local m = Instance.new("Model")
	m.Name = name
	disc(m, pos + Vector3.new(0, 0.2, 0), 26, 0.4, color:Lerp(Color3.new(0, 0, 0), 0.4), Enum.Material.SmoothPlastic)
	disc(m, pos + Vector3.new(0, 0.25, 0), 27.5, 0.3, color, Enum.Material.Neon)
	local pr = prop(m, propName, pos + Vector3.new(0, 0.4, 0), rotY, scale)
	local anchor = P(m, { Name = "PromptAnchor", Size = Vector3.new(2, 2, 2), Transparency = 1, CanCollide = false, CanQuery = false,
		CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) })
	local height = pr and pr:GetExtentsSize().Y or 10
	label(anchor, title, color, 20, height + 3)
	prompt(anchor, promptName, actionText, title)
	for k, v in attrs or {} do m:SetAttribute(k, v) end
	m.PrimaryPart = anchor
	m.Parent = parent
	return m
end

local function lamp(parent, pos, color)
	P(parent, { Name = "LampPole", Size = Vector3.new(0.8, 14, 0.8), CFrame = CFrame.new(pos + Vector3.new(0, 7, 0)), Color = Color3.fromRGB(50, 52, 60), Material = Enum.Material.Metal })
	local bulb = P(parent, { Name = "LampLight", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, CFrame = CFrame.new(pos + Vector3.new(0, 14.5, 0)), Color = color, Material = Enum.Material.Neon, CanCollide = false })
	local l = Instance.new("PointLight"); l.Color = color; l.Range = 22; l.Brightness = 1.2; l.Parent = bulb
end

local function building(parent, pos, size, wall, accent, rotY)
	local m = Instance.new("Model"); m.Name = "Building"
	local cf = CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, rotY or 0, 0)
	P(m, { Name = "Walls", Size = size, CFrame = cf, Color = wall, Material = Enum.Material.SmoothPlastic })
	P(m, { Name = "Roof", Size = Vector3.new(size.X + 2, 1.5, size.Z + 2), CFrame = cf * CFrame.new(0, size.Y / 2 + 0.75, 0), Color = accent, Material = Enum.Material.SmoothPlastic })
	-- glowing window strips on all four sides
	local floors = math.floor(size.Y / 9)
	for f = 1, floors do
		local y = -size.Y / 2 + f * 9 - 3
		for _, face in { { 0, 0, -1, size.X }, { 0, 0, 1, size.X }, { 1, 0, 0, size.Z }, { -1, 0, 0, size.Z } } do
			local n = Vector3.new(face[1], 0, face[3])
			local along = face[4] - 4
			local half = (n.X ~= 0) and size.X / 2 or size.Z / 2
			local winSize = (n.X ~= 0) and Vector3.new(0.3, 3, along) or Vector3.new(along, 3, 0.3)
			P(m, { Name = "Windows", Size = winSize, CFrame = cf * CFrame.new(n * (half + 0.1) + Vector3.new(0, y, 0)),
				Color = Color3.fromRGB(255, 230, 140), Material = Enum.Material.Neon, CanCollide = false })
		end
	end
	P(m, { Name = "Trim", Size = Vector3.new(size.X + 0.6, 1, size.Z + 0.6), CFrame = cf * CFrame.new(0, -size.Y / 2 + 6, 0), Color = accent, Material = Enum.Material.SmoothPlastic })
	m.Parent = parent
	return m
end

------------------------------------------------------------------------------
-- HUB: Champion City (spawn + tutorial)
------------------------------------------------------------------------------
function M.BuildHub(root)
	local hub = Config.Hub
	local O = hub.origin
	local w = Instance.new("Model"); w.Name = "Hub"; w:SetAttribute("WorldId", 0)
	local env = Instance.new("Folder"); env.Name = "Environment"; env.Parent = w
	local zones = Instance.new("Folder"); zones.Name = "Zones"; zones.Parent = w
	local deco = Instance.new("Folder"); deco.Name = "Decor"; deco.Parent = w
	allPathPoints = {}

	local grass = Color3.fromRGB(105, 195, 85)
	local asphalt = Color3.fromRGB(58, 60, 68)
	local concrete = Color3.fromRGB(175, 178, 188)
	local yellow = Color3.fromRGB(255, 205, 50)

	disc(env, O + Vector3.new(0, -2, 0), 520, 4, grass, Enum.Material.Grass)
	disc(env, O + Vector3.new(0, -22, 0), 500, 36, Color3.fromRGB(120, 110, 100), Enum.Material.Rock)
	-- cross roads
	segment(env, O + Vector3.new(0, 0.1, -250), O + Vector3.new(0, 0.1, 250), 30, 0.2, asphalt, Enum.Material.Asphalt, { CanCollide = false })
	segment(env, O + Vector3.new(-250, 0.1, 0), O + Vector3.new(250, 0.1, 0), 30, 0.2, asphalt, Enum.Material.Asphalt, { CanCollide = false })
	-- sidewalks
	for _, s in { -1, 1 } do
		segment(env, O + Vector3.new(s * 18, 0.15, -250), O + Vector3.new(s * 18, 0.15, 250), 6, 0.3, concrete, Enum.Material.Concrete, { CanCollide = false })
		segment(env, O + Vector3.new(-250, 0.15, s * 18), O + Vector3.new(250, 0.15, s * 18), 6, 0.3, concrete, Enum.Material.Concrete, { CanCollide = false })
	end
	-- central plaza
	disc(env, O + Vector3.new(0, 0.2, 0), 120, 0.4, concrete, Enum.Material.Concrete)
	disc(env, O + Vector3.new(0, 0.25, 0), 112, 0.4, Color3.fromRGB(200, 202, 210), Enum.Material.Pavement)
	disc(env, O + Vector3.new(0, 0.3, 0), 36, 0.8, grass, Enum.Material.Grass)
	disc(env, O + Vector3.new(0, 0.45, 0), 37, 0.5, yellow, Enum.Material.Neon)
	prop(deco, "TealTree", O + Vector3.new(0, 0.6, 0), 0, 1.6)
	-- crosswalks at the plaza edges
	for _, dir in { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } do
		local side = Vector3.new(dir.Z, 0, -dir.X)
		for i = -3, 3 do
			local c = O + dir * 68 + side * (i * 4) + Vector3.new(0, 0.3, 0)
			P(env, { Name = "Crosswalk", Size = (dir.X ~= 0) and Vector3.new(8, 0.15, 2.2) or Vector3.new(2.2, 0.15, 8), CFrame = CFrame.new(c),
				Color = yellow, Material = Enum.Material.SmoothPlastic, CanCollide = false })
		end
	end

	-- spawn point
	local sl = Instance.new("SpawnLocation")
	sl.Name = "StartSpawn"; sl.Anchored = true; sl.Size = Vector3.new(10, 1, 10)
	sl.CFrame = CFrame.new(O + Vector3.new(0, 0.3, 30)); sl.Transparency = 1; sl.CanCollide = false; sl.Duration = 0
	sl.Parent = w
	P(w, { Name = "Spawn", Size = Vector3.new(6, 1, 6), CFrame = CFrame.new(O + Vector3.new(0, 1, 30)), Transparency = 1, CanCollide = false, CanQuery = false })
	local sign = P(env, { Name = "CitySign", Size = Vector3.one, CFrame = CFrame.new(O + Vector3.new(0, 26, 0)), Transparency = 1, CanCollide = false, CanQuery = false })
	label(sign, hub.name, Color3.new(1, 1, 1), 40)

	-- stations
	station(w, "Teleporter", "Teleporter", O + Vector3.new(110, 0, 0), math.rad(-90), 2.2, "Teleporter", Color3.fromRGB(90, 170, 255), "GatePrompt", "Travel")
	local orb = station(w, "OrbShrine", "OrbShrine", O + Vector3.new(62, 0, 78), math.rad(200), 1.6, hub.orb.name, Color3.fromRGB(110, 255, 210), "OrbPrompt", "Open", { WorldId = 1 })
	station(w, "CosmicChampions", "CosmicAltar", O + Vector3.new(-110, 0, 0), math.rad(90), 1.8, "Cosmic Champions", Color3.fromRGB(190, 110, 255), "ComingSoonPrompt", "Look", { Feature = "Cosmic Champions" })
	station(w, "ChampionUpgrades", "UpgradeStation", O + Vector3.new(-78, 0, -78), math.rad(45), 2.2, "Champion Upgrades", Color3.fromRGB(255, 150, 60), "ComingSoonPrompt", "Look", { Feature = "Champion Upgrades" })
	station(w, "Raids", "RaidGate", O + Vector3.new(0, 0, -120), 0, 3.2, "Raids", Color3.fromRGB(255, 80, 80), "ComingSoonPrompt", "Look", { Feature = "Raids" })
	station(w, "FusionMachine", "FusionMachine", O + Vector3.new(-78, 0, 78), math.rad(135), 2, "Fusion Machine", Color3.fromRGB(255, 200, 70), "ComingSoonPrompt", "Look", { Feature = "Fusion" })
	station(w, "ChampionIndex", "AcademyTower", O + Vector3.new(78, 0, -78), math.rad(-45), 0.7, "Champion Index", Color3.fromRGB(90, 230, 255), "IndexPrompt", "Open")

	-- training grounds (tutorial area) to the south
	local tg = O + Vector3.new(0, 0, 150)
	disc(env, tg + Vector3.new(0, 0.2, 0), 96, 0.4, Color3.fromRGB(190, 150, 100), Enum.Material.Ground)
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		if math.abs(math.sin(a) + 1) > 0.25 then -- leave a gap facing the plaza (north)
			P(env, { Name = "Fence", Size = Vector3.new(1, 3.5, 12), CFrame = CFrame.new(tg + Vector3.new(math.cos(a) * 48, 1.75, math.sin(a) * 48)) * CFrame.Angles(0, -a, 0),
				Color = Color3.fromRGB(140, 95, 60), Material = Enum.Material.WoodPlanks })
		end
	end
	local tsign = P(env, { Name = "TrainingSign", Size = Vector3.one, CFrame = CFrame.new(tg + Vector3.new(0, 16, -40)), Transparency = 1, CanCollide = false, CanQuery = false })
	label(tsign, "Training Grounds", Color3.fromRGB(255, 220, 120), 26)
	local tz = P(zones, { Name = "Zone1", Size = Vector3.new(60, 1, 50), CFrame = CFrame.new(tg + Vector3.new(0, 0.5, 4)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	tz:SetAttribute("WorldId", 0); tz:SetAttribute("Enemy", hub.zones[1].enemy); tz:SetAttribute("Count", hub.zones[1].count)
	segment(env, O + Vector3.new(0, 0.3, 60), tg + Vector3.new(0, 0.3, -48), 14, 0.2, concrete, Enum.Material.Concrete, { CanCollide = false })

	-- city buildings in the four corners
	local palette = {
		{ Color3.fromRGB(255, 200, 60), Color3.fromRGB(230, 80, 60) }, { Color3.fromRGB(230, 70, 70), Color3.fromRGB(255, 220, 90) },
		{ Color3.fromRGB(80, 120, 220), Color3.fromRGB(255, 210, 80) }, { Color3.fromRGB(150, 90, 220), Color3.fromRGB(90, 230, 255) },
		{ Color3.fromRGB(240, 240, 245), Color3.fromRGB(255, 120, 60) },
	}
	for _, q in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		for i = 1, 4 do
			local r = 165 + (i % 2) * 45
			local a = math.rad(25 + (i - 1) * 14)
			local x = q[1] * math.cos(a) * r
			local z = q[2] * math.sin(a) * r
			local pos = O + Vector3.new(x, 0, z)
			if not (q[2] == 1 and math.abs(x) < 70) then
				local pal = palette[rng:NextInteger(1, #palette)]
				building(deco, pos, Vector3.new(rng:NextNumber(30, 44), rng:NextNumber(30, 75), rng:NextNumber(30, 44)), pal[1], pal[2], math.atan2(x, z))
			end
		end
	end
	-- trees + lamps along the roads
	for d = 80, 230, 30 do
		for _, s in { -1, 1 } do
			lamp(deco, O + Vector3.new(s * 24, 0, d), Color3.fromRGB(255, 230, 160))
			lamp(deco, O + Vector3.new(s * 24, 0, -d), Color3.fromRGB(255, 230, 160))
			lamp(deco, O + Vector3.new(d, 0, s * 24), Color3.fromRGB(255, 230, 160))
			lamp(deco, O + Vector3.new(-d, 0, s * 24), Color3.fromRGB(255, 230, 160))
		end
	end
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2 + math.rad(11)
		if math.abs(math.cos(a)) > 0.25 and math.abs(math.sin(a)) > 0.25 then
			prop(deco, "TealTree", O + Vector3.new(math.cos(a) * 66, 0.3, math.sin(a) * 66), rng:NextNumber(0, 6), rng:NextNumber(1.1, 1.5), Color3.fromRGB(110, 200, 90))
		end
	end
	w.Parent = root
	return w
end

------------------------------------------------------------------------------
-- WORLDS
------------------------------------------------------------------------------
local RING_R = 95
local THEMES = {
	[1] = {
		ground = Color3.fromRGB(95, 185, 95), groundMat = Enum.Material.Grass,
		path = Color3.fromRGB(225, 185, 120), pathMat = Enum.Material.Sand,
		water = Color3.fromRGB(70, 170, 230), base = Color3.fromRGB(110, 100, 95),
		tree = "TealTree", treeTint = nil, hut = "DomeHut", extra = "Boulder", cliffs = true,
	},
	[2] = {
		ground = Color3.fromRGB(240, 220, 165), groundMat = Enum.Material.Sand,
		path = Color3.fromRGB(150, 105, 65), pathMat = Enum.Material.WoodPlanks,
		water = Color3.fromRGB(40, 170, 220), base = Color3.fromRGB(200, 170, 120),
		tree = "PalmTree", treeTint = nil, hut = "HarborHouse", extra = "Boulder", cliffs = false, ocean = true,
	},
	[3] = {
		ground = Color3.fromRGB(215, 222, 240), groundMat = Enum.Material.Marble,
		path = Color3.fromRGB(90, 110, 170), pathMat = Enum.Material.Slate,
		water = Color3.fromRGB(110, 200, 255), base = Color3.fromRGB(90, 95, 120),
		tree = "TealTree", treeTint = Color3.fromRGB(150, 190, 255), hut = "AcademyTower", hutScale = 0.55, extra = "Boulder", cliffs = false, floating = true,
	},
}

function M.BuildWorld(w, root)
	local O = w.origin
	local th = THEMES[w.id]
	local model = Instance.new("Model"); model.Name = w.key; model:SetAttribute("WorldId", w.id)
	local env = Instance.new("Folder"); env.Name = "Environment"; env.Parent = model
	local zones = Instance.new("Folder"); zones.Name = "Zones"; zones.Parent = model
	local deco = Instance.new("Folder"); deco.Name = "Decor"; deco.Parent = model
	allPathPoints = {}

	-- ground island
	disc(env, O + Vector3.new(0, -2, 0), 420, 4, th.ground, th.groundMat)
	disc(env, O + Vector3.new(0, -16, 0), 400, 24, th.base, Enum.Material.Rock)
	disc(env, O + Vector3.new(0, -36, 0), 300, 20, th.base:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Rock)
	if th.ocean then
		P(env, { Name = "Ocean", Size = Vector3.new(1400, 1, 1400), CFrame = CFrame.new(O + Vector3.new(0, -5, 0)), Color = th.water,
			Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
		disc(env, O + Vector3.new(0, -2.2, 0), 436, 3.6, Color3.fromRGB(250, 235, 190), Enum.Material.Sand)
	end
	if th.floating then
		disc(env, O + Vector3.new(0, -0.6, 0), 426, 1, w.theme.accent, Enum.Material.Neon) -- glowing edge peeking out under the floor
	end

	-- paths: ring + arrival spoke (south) + exit spoke (north) + boss spoke (east)
	local ringCtrl = {}
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local r = RING_R + math.sin(a * 3) * 7 -- gentle wobble so it feels hand-made
		table.insert(ringCtrl, O + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
	end
	path(env, curve(ringCtrl, 6, true), 14, th.path, th.pathMat)
	path(env, curve({ O + Vector3.new(0, 0, 170), O + Vector3.new(-14, 0, 140), O + Vector3.new(8, 0, 115), O + Vector3.new(0, 0, RING_R - 8) }, 6, false), 14, th.path, th.pathMat)
	path(env, curve({ O + Vector3.new(0, 0, -(RING_R - 8)), O + Vector3.new(12, 0, -125), O + Vector3.new(-8, 0, -150), O + Vector3.new(0, 0, -172) }, 6, false), 14, th.path, th.pathMat)
	path(env, curve({ O + Vector3.new(RING_R + 10, 0, 0), O + Vector3.new(70, 0, 12), O + Vector3.new(45, 0, -6), O + Vector3.new(30, 0, 0) }, 6, false), 12, th.path, th.pathMat)

	-- arrival + orb shrine + world gate
	P(model, { Name = "Spawn", Size = Vector3.new(6, 1, 6), CFrame = CFrame.new(O + Vector3.new(0, 1, 172)), Transparency = 1, CanCollide = false, CanQuery = false })
	station(model, "ReturnGate", "Teleporter", O + Vector3.new(-30, 0, 178), math.rad(30), 1.6, "Teleporter", Color3.fromRGB(90, 170, 255), "GatePrompt", "Travel")
	station(model, "OrbShrine", "OrbShrine", O + Vector3.new(32, 0, 160), math.rad(-30), 1.5, w.orb.name .. "  ($" .. w.orb.cost .. ")", w.theme.accent, "OrbPrompt", "Open", { WorldId = w.id })
	station(model, "WorldGate", "Teleporter", O + Vector3.new(0, 0, -180), 0, 2.2, "World Gate", Color3.fromRGB(190, 120, 255), "GatePrompt", "Travel")
	local sign = P(env, { Name = "WorldSign", Size = Vector3.one, CFrame = CFrame.new(O + Vector3.new(0, 18, 135)), Transparency = 1, CanCollide = false, CanQuery = false })
	label(sign, w.name, Color3.new(1, 1, 1), 34)

	-- enemy zones on the ring (south-west, north-west, north-east)
	local zoneAngles = { 135, 225, 315 }
	local zoneNames = {
		[1] = { "Legion Outpost", "Scout Camp", "Elite Barracks" },
		[2] = { "Smuggler Docks", "Raider Market", "Anchor Yard" },
		[3] = { "Trainee Courtyard", "Enforcer Hall", "Sentinel Forge" },
	}
	for i, deg in zoneAngles do
		local a = math.rad(deg)
		local center = O + Vector3.new(math.cos(a) * (RING_R + 4), 0.5, math.sin(a) * (RING_R + 4))
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local zone = P(zones, { Name = "Zone" .. i, Size = Vector3.new(70, 1, 44), CFrame = CFrame.fromMatrix(center, tangent, Vector3.yAxis),
			Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
		zone:SetAttribute("WorldId", w.id); zone:SetAttribute("Enemy", w.zones[i].enemy); zone:SetAttribute("Count", w.zones[i].count)
		-- zone sign + a camp of huts just outside the ring
		local signPos = O + Vector3.new(math.cos(a) * (RING_R - 26), 0, math.sin(a) * (RING_R - 26))
		local post = P(env, { Name = "ZonePost", Size = Vector3.new(1, 8, 1), CFrame = CFrame.new(signPos + Vector3.new(0, 4, 0)), Color = Color3.fromRGB(110, 80, 55), Material = Enum.Material.Wood })
		label(post, "Zone " .. i .. ": " .. zoneNames[w.id][i] .. "\n" .. Config.Enemies[w.zones[i].enemy].name .. "s", Color3.fromRGB(255, 240, 200), 11, 6).MaxDistance = 140
		for h = -1, 1 do
			local ha = a + h * 0.22
			local hp = O + Vector3.new(math.cos(ha) * (RING_R + 52), 0, math.sin(ha) * (RING_R + 52))
			prop(deco, th.hut, hp, -ha + math.pi / 2, (th.hutScale or 1) * rng:NextNumber(1.1, 1.4))
		end
	end

	-- boss arena (center)
	disc(env, O + Vector3.new(0, 0.2, 0), 64, 0.4, th.path:Lerp(Color3.new(0, 0, 0), 0.15), th.pathMat)
	disc(env, O + Vector3.new(0, 0.15, 0), 68, 0.3, Color3.fromRGB(255, 80, 70), Enum.Material.Neon)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		if math.abs(math.cos(a) - 1) > 0.3 then -- leave the east side open (entrance)
			prop(deco, "Boulder", O + Vector3.new(math.cos(a) * 40, 0, math.sin(a) * 40), rng:NextNumber(0, 6), rng:NextNumber(1.6, 2.4), th.base:Lerp(Color3.new(1, 1, 1), 0.2))
		end
	end
	local bossSpawn = P(zones, { Name = "BossSpawn", Size = Vector3.new(4, 1, 4), CFrame = CFrame.new(O + Vector3.new(-6, 0.5, 0)) * CFrame.Angles(0, math.rad(-90), 0),
		Transparency = 1, CanCollide = false, CanQuery = false })
	bossSpawn:SetAttribute("WorldId", w.id); bossSpawn:SetAttribute("Enemy", w.boss)
	local bs = P(env, { Name = "BossSign", Size = Vector3.one, CFrame = CFrame.new(O + Vector3.new(36, 22, 0)), Transparency = 1, CanCollide = false, CanQuery = false })
	label(bs, "BOSS: " .. Config.Enemies[w.boss].name, Color3.fromRGB(255, 110, 90), 26)

	-- grass/ground colour patches so the floor isn't one flat colour
	for _ = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(20, 190)
		local shade = th.ground:Lerp(rng:NextNumber() < 0.5 and Color3.new(1, 1, 1) or Color3.new(0, 0.15, 0), rng:NextNumber(0.06, 0.14))
		disc(env, O + Vector3.new(math.cos(a) * r, 0.03, math.sin(a) * r), rng:NextNumber(18, 40), 0.1, shade, th.groundMat, { CanCollide = false })
	end
	-- ponds
	for i = 1, 6 do
		for _ = 1, 30 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(125, 175)
			local c = O + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if farFromPaths(c, 18) then
				for k = 1, 3 do
					local off = Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8))
					disc(env, c + off + Vector3.new(0, 0.08, 0), rng:NextNumber(14, 24), 0.2, th.water, Enum.Material.Glass, { CanCollide = false, Transparency = 0.1 })
				end
				table.insert(allPathPoints, { p = c, w = 30 })
				break
			end
		end
	end

	-- trees + boulders scattered, kept off paths and away from zones/arena
	local placed = 0
	for _ = 1, 400 do
		if placed >= 55 then break end
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(48, 192)
		local pos = O + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local inZone = false
		for _, z in zones:GetChildren() do
			if z.Name ~= "BossSpawn" then
				local lp = z.CFrame:PointToObjectSpace(pos)
				if math.abs(lp.X) < z.Size.X / 2 + 4 and math.abs(lp.Z) < z.Size.Z / 2 + 4 then inZone = true end
			end
		end
		-- keep the inside of the ring fairly open (only some decor in there)
		local innerOk = r > RING_R + 12 or (r > 52 and r < RING_R - 14 and rng:NextNumber() < 0.35)
		if not inZone and innerOk and farFromPaths(pos, 6) then
			if rng:NextNumber() < 0.75 then
				prop(deco, th.tree, pos, rng:NextNumber(0, 6), rng:NextNumber(1.2, 1.9), th.treeTint)
			else
				prop(deco, th.extra, pos, rng:NextNumber(0, 6), rng:NextNumber(1, 1.8))
			end
			placed += 1
		end
	end

	-- edge: cliffs (world 1), pirate ships (world 2), glowing rail (world 3)
	if th.cliffs then
		for i = 0, 39 do
			local a = i / 40 * math.pi * 2
			if math.abs(math.sin(a) - 1) > 0.12 and math.abs(math.sin(a) + 1) > 0.12 then -- gaps at arrival + gate
				prop(env, "Cliff", O + Vector3.new(math.cos(a) * 212, -8, math.sin(a) * 212), -a + rng:NextNumber(-0.3, 0.3), rng:NextNumber(1.3, 1.8))
			end
		end
	end
	if th.ocean then
		prop(deco, "PirateShip", O + Vector3.new(250, -6, -40), math.rad(-10), 2.2)
		prop(deco, "PirateShip", O + Vector3.new(-255, -6, 60), math.rad(170), 2.0)
		for i = 0, 5 do
			local z = -100 + i * 40
			segment(env, O + Vector3.new(205, -0.2, z), O + Vector3.new(232, -0.2, z), 6, 0.6, Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
		end
	end
	if th.floating then
		for i = 0, 47 do
			local a = i / 48 * math.pi * 2
			P(env, { Name = "RailPost", Size = Vector3.new(1.2, 4, 1.2), CFrame = CFrame.new(O + Vector3.new(math.cos(a) * 208, 2, math.sin(a) * 208)),
				Color = Color3.fromRGB(230, 235, 250), Material = Enum.Material.Marble })
		end
		prop(deco, "AcademyTower", O + Vector3.new(-120, 0, -150), 0.3, 1.4)
		prop(deco, "AcademyTower", O + Vector3.new(130, 0, -140), -0.3, 1.2)
	end

	model.Parent = root
	return model
end

function M.BuildAll(freshConfig)
	Config = freshConfig or require(game:GetService("ReplicatedStorage").Shared.Config)
	local root = workspace:FindFirstChild("Worlds")
	if root then root:Destroy() end
	root = Instance.new("Folder")
	root.Name = "Worlds"
	root.Parent = workspace
	M.BuildHub(root)
	task.wait()
	for _, w in Config.Worlds do
		M.BuildWorld(w, root)
		task.wait()
	end
	workspace.FallenPartsDestroyHeight = -150
	return #root:GetDescendants()
end

return M
