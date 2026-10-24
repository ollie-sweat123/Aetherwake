-- ModelBuilder (dev tool): builds champion + enemy models out of parts.
-- Run from the command bar:  require(game.ServerStorage.DevTools.ModelBuilder).BuildAll()
-- Re-run any time you change looks in Config. Later we can swap these for real 3D models.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local M = {}

local function part(model, root, name, shape, size, offset, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = true
	p.CFrame = root.CFrame * offset
	if extra then for k, v in extra do (p :: any)[k] = v end end
	p.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = root; w.Part1 = p; w.Parent = p
	return p
end

local function newRoot(model, size, y)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = size
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = CFrame.new(0, y, 0)
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local BALL, BLOCK, CYL = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
local NEON, METAL = Enum.Material.Neon, Enum.Material.Metal
local function C(x, y, z) return CFrame.new(x, y, z) end
local function R(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)) end

local HAIR = {}
local function cap(m, r, col, scale)
	return part(m, r, "HairCap", BALL, Vector3.one * (2.35 * (scale or 1)), C(0, 1.6, 0.28), col)
end
HAIR.spiky = function(m, r, col)
	cap(m, r, col)
	for i, a in { -50, -25, 0, 25, 50 } do
		part(m, r, "Spike" .. i, BLOCK, Vector3.new(0.5, 1.3, 0.5), C(0, 1.6, 0.28) * R(-20, a, 0) * C(0, 1.25, 0) * R(0, 0, 45 - i * 15), col)
	end
	part(m, r, "SpikeBack", BLOCK, Vector3.new(0.6, 1.2, 0.6), C(0, 1.9, 1.0) * R(55, 0, 0), col)
end
HAIR.leaf = function(m, r, col)
	cap(m, r, col)
	part(m, r, "Leaf", BLOCK, Vector3.new(0.9, 0.12, 1.4), C(0.2, 3.0, 0) * R(0, 30, 25), Color3.fromRGB(120, 230, 90))
	part(m, r, "Stem", CYL, Vector3.new(0.5, 0.15, 0.15), C(0, 2.85, 0) * R(0, 0, 90), Color3.fromRGB(80, 140, 50))
end
HAIR.messy = function(m, r, col)
	cap(m, r, col, 1.05)
	for i = 1, 4 do
		part(m, r, "Tuft" .. i, BALL, Vector3.one * 0.8, C(math.cos(i * 1.6) * 0.8, 2.55, math.sin(i * 1.6) * 0.6 + 0.2), col)
	end
end
HAIR.ears = function(m, r, col)
	cap(m, r, col)
	part(m, r, "EarL", BLOCK, Vector3.new(0.55, 0.9, 0.25), C(-0.75, 2.75, 0.1) * R(0, 0, 20), col)
	part(m, r, "EarR", BLOCK, Vector3.new(0.55, 0.9, 0.25), C(0.75, 2.75, 0.1) * R(0, 0, -20), col)
	part(m, r, "Tail", BALL, Vector3.new(0.9, 0.9, 1.8), C(0, -0.9, 1.2) * R(-30, 0, 0), col)
end
HAIR.long = function(m, r, col)
	cap(m, r, col)
	part(m, r, "Back", BLOCK, Vector3.new(2.0, 2.2, 0.6), C(0, 0.6, 0.85), col)
end
HAIR.flame = function(m, r, col)
	cap(m, r, col)
	for i, a in { -30, 0, 30 } do
		local p = part(m, r, "Flame" .. i, BLOCK, Vector3.new(0.7, 1.6, 0.7), C(0, 1.8, 0.35) * R(-25, 0, a) * C(0, 1.3, 0) * R(0, 45, 0), col)
		p.Material = NEON
	end
end
HAIR.bandana = function(m, r, col)
	cap(m, r, Color3.fromRGB(60, 40, 30))
	part(m, r, "Band", CYL, Vector3.new(0.45, 2.38, 2.38), C(0, 1.75, 0.05) * R(0, 0, 90), col)
	part(m, r, "Knot", BLOCK, Vector3.new(0.3, 0.6, 0.8), C(0, 1.6, 1.25) * R(30, 0, 0), col)
end
HAIR.hat = function(m, r, col)
	cap(m, r, Color3.fromRGB(40, 30, 30))
	part(m, r, "Brim", CYL, Vector3.new(0.2, 3.2, 3.2), C(0, 2.3, 0.1) * R(0, 0, 90), col)
	part(m, r, "Crown", CYL, Vector3.new(1.0, 2.0, 2.0), C(0, 2.8, 0.15) * R(0, 0, 90), col)
	part(m, r, "Feather", BLOCK, Vector3.new(0.2, 1.4, 0.4), C(0.9, 3.2, 0.4) * R(0, 0, -25), Color3.fromRGB(255, 255, 255))
end
HAIR.crown = function(m, r, col)
	cap(m, r, col)
	part(m, r, "Back", BLOCK, Vector3.new(2.0, 2.4, 0.6), C(0, 0.5, 0.85), col)
	local gold = Color3.fromRGB(255, 210, 80)
	part(m, r, "Crown", CYL, Vector3.new(0.5, 1.6, 1.6), C(0, 2.85, 0.1) * R(0, 0, 90), gold, METAL)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		part(m, r, "Point" .. i, BLOCK, Vector3.new(0.25, 0.6, 0.25), C(math.cos(a) * 0.7, 3.25, math.sin(a) * 0.7 + 0.1) * R(0, 0, 0), gold, METAL)
	end
end
HAIR.antenna = function(m, r, col)
	cap(m, r, col)
	part(m, r, "Ant", CYL, Vector3.new(1.0, 0.15, 0.15), C(0, 3.1, 0) * R(0, 0, 90), col, METAL)
	part(m, r, "AntTip", BALL, Vector3.one * 0.45, C(0, 3.65, 0), Color3.fromRGB(255, 80, 80), NEON)
end
HAIR.twin = function(m, r, col)
	cap(m, r, col)
	part(m, r, "TailL", BALL, Vector3.new(0.9, 1.6, 0.9), C(-1.3, 1.2, 0.4), col)
	part(m, r, "TailR", BALL, Vector3.new(0.9, 1.6, 0.9), C(1.3, 1.2, 0.4), col)
end
HAIR.helmet = function(m, r, col)
	part(m, r, "Helm", BALL, Vector3.one * 2.45, C(0, 1.55, 0.15), Color3.fromRGB(230, 235, 245), METAL)
	part(m, r, "Plume", BLOCK, Vector3.new(0.35, 0.9, 1.8), C(0, 2.85, 0.4), col, NEON)
end

local WEAPON = {}
WEAPON.none = function() end
WEAPON.stick = function(m, r, accent)
	part(m, r, "Weapon", CYL, Vector3.new(2.4, 0.25, 0.25), C(1.2, -0.3, -0.5) * R(0, 90, 70), Color3.fromRGB(130, 90, 50))
end
WEAPON.sword = function(m, r, accent)
	part(m, r, "Hilt", BLOCK, Vector3.new(0.25, 0.7, 0.25), C(1.25, -0.6, -0.3), Color3.fromRGB(60, 40, 30))
	part(m, r, "Guard", BLOCK, Vector3.new(0.9, 0.18, 0.3), C(1.25, -0.2, -0.3), Color3.fromRGB(255, 210, 80), METAL)
	part(m, r, "Blade", BLOCK, Vector3.new(0.3, 2.4, 0.12), C(1.25, 1.05, -0.3), accent, NEON)
end
WEAPON.staff = function(m, r, accent)
	part(m, r, "Shaft", CYL, Vector3.new(3.6, 0.22, 0.22), C(1.25, 0.4, -0.2) * R(0, 0, 90), Color3.fromRGB(110, 80, 60))
	part(m, r, "Orb", BALL, Vector3.one * 0.7, C(1.25, 2.3, -0.2), accent, NEON)
end
WEAPON.bow = function(m, r, accent)
	for i, a in { -35, 0, 35 } do
		part(m, r, "Bow" .. i, BLOCK, Vector3.new(0.18, 1.0, 0.18), C(-1.25, 0, -0.4) * R(a, 0, 0) * C(0, 0, -0.35 + math.abs(a) / 100), accent, NEON)
	end
end
WEAPON.spear = function(m, r, accent)
	part(m, r, "Shaft", CYL, Vector3.new(4.0, 0.2, 0.2), C(1.25, 0.6, -0.2) * R(0, 0, 90), Color3.fromRGB(90, 70, 60))
	part(m, r, "Tip", BLOCK, Vector3.new(0.35, 0.9, 0.12), C(1.25, 2.9, -0.2) * R(0, 0, 45), accent, NEON)
end
WEAPON.trident = function(m, r, accent)
	part(m, r, "Shaft", CYL, Vector3.new(4.0, 0.2, 0.2), C(1.25, 0.6, -0.2) * R(0, 0, 90), Color3.fromRGB(255, 210, 80), METAL)
	for i, x in { -0.35, 0, 0.35 } do
		part(m, r, "Prong" .. i, BLOCK, Vector3.new(0.15, 0.8, 0.15), C(1.25 + x, 2.95, -0.2), accent, NEON)
	end
end
WEAPON.wrench = function(m, r, accent)
	part(m, r, "Handle", BLOCK, Vector3.new(0.25, 1.8, 0.25), C(1.25, 0, -0.3), Color3.fromRGB(150, 155, 165), METAL)
	part(m, r, "Head", BLOCK, Vector3.new(0.8, 0.5, 0.25), C(1.25, 1.0, -0.3), Color3.fromRGB(150, 155, 165), METAL)
end

function M.BuildChampion(def)
	local look = def.look
	local rarity = Config.RarityById[def.rarity]
	local m = Instance.new("Model")
	m.Name = def.id
	-- Root sits at the chest; the model's feet are ~2 studs below it.
	local r = newRoot(m, Vector3.new(2, 4.5, 2), 2.2)
	local dark = look.outfit:Lerp(Color3.new(0, 0, 0), 0.35)
	part(m, r, "LegL", BLOCK, Vector3.new(0.6, 1.0, 0.6), C(-0.4, -1.7, 0), dark)
	part(m, r, "LegR", BLOCK, Vector3.new(0.6, 1.0, 0.6), C(0.4, -1.7, 0), dark)
	part(m, r, "Body", BLOCK, Vector3.new(1.6, 1.4, 1.0), C(0, -0.5, 0), look.outfit)
	part(m, r, "Belt", BLOCK, Vector3.new(1.65, 0.25, 1.05), C(0, -1.05, 0), dark)
	part(m, r, "ArmL", BLOCK, Vector3.new(0.45, 1.2, 0.45), C(-1.05, -0.45, 0) * R(0, 0, -10), look.skin)
	part(m, r, "ArmR", BLOCK, Vector3.new(0.45, 1.2, 0.45), C(1.05, -0.45, 0) * R(0, 0, 10), look.skin)
	part(m, r, "Head", BALL, Vector3.one * 2.2, C(0, 1.3, 0), look.skin)
	-- eyes (front of the model is -Z)
	for _, x in { -0.42, 0.42 } do
		part(m, r, "Eye", BLOCK, Vector3.new(0.28, 0.5, 0.1), C(x, 1.2, -1.02), Color3.fromRGB(25, 25, 35))
		part(m, r, "Shine", BLOCK, Vector3.new(0.1, 0.12, 0.05), C(x + 0.05, 1.35, -1.08), Color3.new(1, 1, 1), NEON)
	end
	part(m, r, "Blush", BLOCK, Vector3.new(1.5, 0.12, 0.05), C(0, 0.85, -0.98), look.skin:Lerp(Color3.fromRGB(255, 120, 140), 0.45))
	;(HAIR[look.hairStyle] or HAIR.messy)(m, r, look.hair)
	;(WEAPON[look.weapon] or WEAPON.none)(m, r, rarity.color)

	-- Legendary and better get a sparkle aura, Mythic also a light (by NAME, so new tiers are safe)
	if Config.RarityAtLeast(def.rarity, "Legendary") then
		local att = Instance.new("Attachment"); att.Parent = r
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(rarity.color)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0.2, 1)
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Rate = if Config.RarityAtLeast(def.rarity, "Mythic") then 18 else 8
		pe.Speed = NumberRange.new(1, 2.5)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = att
		if Config.RarityAtLeast(def.rarity, "Mythic") then
			local l = Instance.new("PointLight"); l.Color = rarity.color; l.Range = 8; l.Brightness = 1.5; l.Parent = r
		end
	end
	m:SetAttribute("ChampionId", def.id)
	return m
end

local ENEMY = {}
local function eyes(m, r, s, y, z, col)
	for _, x in { -0.22 * s, 0.22 * s } do
		part(m, r, "Eye", BALL, Vector3.one * 0.22 * s, C(x, y, z), col or Color3.fromRGB(255, 240, 120), NEON)
	end
end
ENEMY.imp = function(m, r, def)
	local s = def.size
	part(m, r, "Body", BALL, Vector3.one * s, C(0, 0, 0), def.color)
	eyes(m, r, s, 0.1 * s, -0.45 * s)
	part(m, r, "HornL", BLOCK, Vector3.new(0.2, 0.5, 0.2) * s, C(-0.25 * s, 0.5 * s, -0.05 * s) * R(0, 0, 25), def.color:Lerp(Color3.new(0, 0, 0), 0.4))
	part(m, r, "HornR", BLOCK, Vector3.new(0.2, 0.5, 0.2) * s, C(0.25 * s, 0.5 * s, -0.05 * s) * R(0, 0, -25), def.color:Lerp(Color3.new(0, 0, 0), 0.4))
	part(m, r, "FootL", BALL, Vector3.new(0.35, 0.2, 0.45) * s, C(-0.22 * s, -0.48 * s, -0.05 * s), def.color:Lerp(Color3.new(0, 0, 0), 0.25))
	part(m, r, "FootR", BALL, Vector3.new(0.35, 0.2, 0.45) * s, C(0.22 * s, -0.48 * s, -0.05 * s), def.color:Lerp(Color3.new(0, 0, 0), 0.25))
end
ENEMY.golem = function(m, r, def)
	local s = def.size
	local dark = def.color:Lerp(Color3.new(0, 0, 0), 0.3)
	part(m, r, "Body", BLOCK, Vector3.new(0.8, 0.7, 0.6) * s, C(0, 0, 0), def.color, Enum.Material.Slate)
	part(m, r, "Head", BLOCK, Vector3.new(0.5, 0.4, 0.45) * s, C(0, 0.55 * s, -0.05 * s), def.color, Enum.Material.Slate)
	eyes(m, r, s * 0.8, 0.58 * s, -0.29 * s)
	part(m, r, "ArmL", BLOCK, Vector3.new(0.25, 0.7, 0.25) * s, C(-0.55 * s, -0.1 * s, 0), dark, Enum.Material.Slate)
	part(m, r, "ArmR", BLOCK, Vector3.new(0.25, 0.7, 0.25) * s, C(0.55 * s, -0.1 * s, 0), dark, Enum.Material.Slate)
	part(m, r, "LegL", BLOCK, Vector3.new(0.25, 0.35, 0.3) * s, C(-0.22 * s, -0.5 * s, 0), dark, Enum.Material.Slate)
	part(m, r, "LegR", BLOCK, Vector3.new(0.25, 0.35, 0.3) * s, C(0.22 * s, -0.5 * s, 0), dark, Enum.Material.Slate)
end
ENEMY.brute = function(m, r, def)
	local s = def.size
	local dark = def.color:Lerp(Color3.new(0, 0, 0), 0.35)
	part(m, r, "Body", BALL, Vector3.new(1.0, 0.9, 0.8) * s, C(0, 0, 0), def.color)
	part(m, r, "Belly", BALL, Vector3.new(0.6, 0.55, 0.3) * s, C(0, -0.1 * s, -0.3 * s), def.color:Lerp(Color3.new(1, 1, 1), 0.3))
	eyes(m, r, s, 0.25 * s, -0.36 * s, Color3.fromRGB(255, 90, 60))
	part(m, r, "ArmL", BALL, Vector3.new(0.35, 0.8, 0.35) * s, C(-0.6 * s, -0.1 * s, -0.05 * s) * R(0, 0, -15), dark)
	part(m, r, "ArmR", BALL, Vector3.new(0.35, 0.8, 0.35) * s, C(0.6 * s, -0.1 * s, -0.05 * s) * R(0, 0, 15), dark)
	for i = -1, 1 do
		part(m, r, "Spike" .. i, BLOCK, Vector3.new(0.12, 0.35, 0.12) * s, C(i * 0.25 * s, 0.45 * s, 0.1 * s) * R(-20, 0, i * -20), dark)
	end
end
ENEMY.boss = function(m, r, def)
	ENEMY.brute(m, r, def)
	local s = def.size
	local gold = Color3.fromRGB(255, 200, 70)
	part(m, r, "Crown", CYL, Vector3.new(0.18, 0.4, 0.4) * s, C(0, 0.55 * s, 0) * R(0, 0, 90), gold, METAL)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		part(m, r, "CrownPt" .. i, BLOCK, Vector3.new(0.05, 0.14, 0.05) * s, C(math.cos(a) * 0.18 * s, 0.68 * s, math.sin(a) * 0.18 * s), gold, METAL)
	end
	local l = Instance.new("PointLight"); l.Color = Color3.fromRGB(255, 100, 80); l.Range = s * 1.5; l.Brightness = 2; l.Parent = r
end

function M.BuildEnemy(id, def)
	local m = Instance.new("Model")
	m.Name = id
	local s = def.size
	-- The Root is the clickable hitbox (slightly bigger than the visuals).
	local r = newRoot(m, Vector3.new(1.1, 1.1, 1.1) * s, s / 2)
	r.CanQuery = true
	;(ENEMY[def.style] or ENEMY.imp)(m, r, def)
	return m
end

function M.BuildAll()
	local champs = ReplicatedStorage:FindFirstChild("ChampionModels")
	if champs then champs:Destroy() end
	champs = Instance.new("Folder"); champs.Name = "ChampionModels"
	for _, def in Config.Champions do M.BuildChampion(def).Parent = champs end
	champs.Parent = ReplicatedStorage

	local enemies = ServerStorage:FindFirstChild("EnemyModels")
	if enemies then enemies:Destroy() end
	enemies = Instance.new("Folder"); enemies.Name = "EnemyModels"
	for id, def in Config.Enemies do M.BuildEnemy(id, def).Parent = enemies end
	enemies.Parent = ServerStorage
	return #champs:GetChildren(), #enemies:GetChildren()
end

return M
