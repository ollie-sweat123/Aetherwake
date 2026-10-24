-- EnemyBuilder (dev tool): builds anime-style enemy fighters on a real R15 body.
-- Run from the command bar:  require(game.ServerStorage.DevTools.EnemyBuilder).BuildAll()
-- Looks come from Config.Enemies[...].look. Output goes to ServerStorage.EnemyModels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local M = {}
local BALL, BLOCK, CYL, WEDGE = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder, Enum.PartType.Wedge
local NEON, METAL, SMOOTH, FABRIC = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Fabric
local function C(x, y, z) return CFrame.new(x, y, z) end
-- Offsets are measured in the RIG's directions (R15 body parts have their own odd rotations).
local BASIS = CFrame.identity
local function R(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)) end

-- Welds a decorative part onto a body part. offset is relative to that body part.
local function add(model, bodyPart, name, shape, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or SMOOTH
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = CFrame.new(bodyPart.Position) * BASIS * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = bodyPart
	w.Part1 = p
	w.Parent = p
	p.Parent = model.Decor
	return p
end

local HAIR = {}
local function cap(m, head, col, extra)
	local h = head.Size
	return add(m, head, "HairCap", BALL, Vector3.new(h.X * 1.1, h.Y * 0.85, h.Z * 1.05) * (extra or 1), C(0, h.Y * 0.32, h.Z * 0.2), col)
end
HAIR.spiky = function(m, head, col)
	local h = head.Size
	cap(m, head, col)
	local spikes = {
		{ 0, 0.55, -0.15, -20, 0, 0 }, { -0.35, 0.5, -0.1, -15, 0, 30 }, { 0.35, 0.5, -0.1, -15, 0, -30 },
		{ -0.5, 0.25, 0.1, 0, 0, 60 }, { 0.5, 0.25, 0.1, 0, 0, -60 }, { 0, 0.4, 0.45, 50, 0, 0 },
		{ -0.25, 0.3, 0.5, 60, 0, 20 }, { 0.25, 0.3, 0.5, 60, 0, -20 },
	}
	for i, s in spikes do
		add(m, head, "Spike" .. i, BLOCK, Vector3.new(0.36, 1.15, 0.36) * h.X, C(s[1] * h.X, s[2] * h.Y + 0.35 * h.Y, s[3] * h.Z) * R(s[4], s[5], s[6]) * R(0, 45, 0), col)
	end
	-- front bangs
	for i, x in { -0.3, 0, 0.3 } do
		add(m, head, "Bang" .. i, WEDGE, Vector3.new(0.22, 0.45, 0.3) * h.X, C(x * h.X, 0.32 * h.Y, -0.45 * h.Z) * R(-160, 0, 0), col)
	end
end
HAIR.mohawk = function(m, head, col)
	local h = head.Size
	add(m, head, "Shave", BALL, Vector3.new(h.X * 1.04, h.Y * 0.9, h.Z * 1.06), C(0, h.Y * 0.12, 0.03), col:Lerp(Color3.new(0, 0, 0), 0.6))
	for i = 1, 5 do
		local z = -0.4 + (i - 1) * 0.22
		add(m, head, "Crest" .. i, BLOCK, Vector3.new(0.2, 0.8 - math.abs(i - 2.5) * 0.08, 0.3) * h.X, C(0, 0.7 * h.Y, z * h.Z) * R(-25 + i * 8, 0, 0), col)
	end
end
HAIR.long = function(m, head, col)
	local h = head.Size
	cap(m, head, col)
	add(m, head, "Back", BLOCK, Vector3.new(h.X * 1.0, h.Y * 1.7, h.Z * 0.35), C(0, -0.3 * h.Y, 0.5 * h.Z), col)
	for i, x in { -0.3, 0.3 } do
		add(m, head, "Strand" .. i, BLOCK, Vector3.new(0.25, 1.1, 0.25) * h.X, C(x * h.X * 1.6, -0.2 * h.Y, -0.15 * h.Z), col)
	end
end
HAIR.horns = function(m, head, col)
	local h = head.Size
	for i, s in { -1, 1 } do
		add(m, head, "HornBase" .. i, BLOCK, Vector3.new(0.25, 0.5, 0.25) * h.X, C(s * 0.35 * h.X, 0.55 * h.Y, 0) * R(0, 0, -s * 35), Color3.fromRGB(240, 235, 220))
		add(m, head, "HornTip" .. i, BLOCK, Vector3.new(0.18, 0.55, 0.18) * h.X, C(s * 0.62 * h.X, 0.9 * h.Y, 0.05 * h.Z) * R(0, 0, -s * 10), Color3.fromRGB(240, 235, 220))
	end
	add(m, head, "Crown", CYL, Vector3.new(0.18 * h.Y, h.X * 1.02, h.X * 1.02), C(0, 0.38 * h.Y, 0) * R(0, 0, 90), Color3.fromRGB(255, 200, 70), METAL)
end
HAIR.bandana = function(m, head, col)
	local h = head.Size
	cap(m, head, Color3.fromRGB(50, 35, 25))
	add(m, head, "Band", CYL, Vector3.new(0.3 * h.Y, h.X * 1.15, h.X * 1.15), C(0, 0.3 * h.Y, 0.02) * R(0, 0, 90), col, FABRIC)
	add(m, head, "Knot", BLOCK, Vector3.new(0.2, 0.55, 0.45) * h.X, C(0, 0.15 * h.Y, 0.65 * h.Z) * R(35, 0, 0), col, FABRIC)
end
HAIR.tricorn = function(m, head, col)
	local h = head.Size
	cap(m, head, col)
	add(m, head, "Brim", CYL, Vector3.new(0.12 * h.Y, h.X * 1.9, h.X * 1.9), C(0, 0.45 * h.Y, 0) * R(0, 0, 90), Color3.fromRGB(35, 30, 35))
	add(m, head, "Top", CYL, Vector3.new(0.55 * h.Y, h.X * 1.1, h.X * 1.1), C(0, 0.72 * h.Y, 0.03) * R(0, 0, 90), Color3.fromRGB(35, 30, 35))
	add(m, head, "Trim", CYL, Vector3.new(0.13 * h.Y, h.X * 1.92, h.X * 1.92), C(0, 0.44 * h.Y, 0) * R(0, 0, 90), Color3.fromRGB(220, 180, 70), METAL)
end
HAIR.captain = function(m, head, col)
	local h = head.Size
	cap(m, head, col)
	add(m, head, "Brim", CYL, Vector3.new(0.14 * h.Y, h.X * 2.3, h.X * 2.3), C(0, 0.5 * h.Y, 0) * R(0, 0, 90), Color3.fromRGB(30, 25, 30))
	add(m, head, "Top", BLOCK, Vector3.new(h.X * 1.6, 0.6 * h.Y, h.X * 0.9), C(0, 0.85 * h.Y, 0), Color3.fromRGB(30, 25, 30))
	add(m, head, "Skull", BALL, Vector3.one * 0.35 * h.X, C(0, 0.85 * h.Y, -0.46 * h.Z), Color3.fromRGB(245, 245, 245))
	add(m, head, "Feather", BLOCK, Vector3.new(0.12, 1.2, 0.35) * h.X, C(0.6 * h.X, 1.1 * h.Y, 0.1) * R(0, 0, -30), Color3.fromRGB(255, 255, 255))
end
HAIR.helmet = function(m, head, col)
	local h = head.Size
	add(m, head, "Helm", BALL, Vector3.new(h.X * 1.18, h.Y * 1.05, h.Z * 1.2), C(0, h.Y * 0.15, 0.05), Color3.fromRGB(110, 115, 130), METAL)
	add(m, head, "Fin", BLOCK, Vector3.new(0.15, 0.5, 1.0) * h.X, C(0, 0.65 * h.Y, 0.05), Color3.fromRGB(240, 140, 50))
end
HAIR.robot = function(m, head, col)
	local h = head.Size
	add(m, head, "Plate", BLOCK, Vector3.new(h.X * 1.12, h.Y * 1.0, h.Z * 1.12), C(0, 0.05, 0), Color3.fromRGB(150, 155, 170), METAL)
	add(m, head, "Antenna", CYL, Vector3.new(0.6 * h.Y, 0.12, 0.12), C(0.35 * h.X, 0.75 * h.Y, 0) * R(0, 0, 90), Color3.fromRGB(90, 90, 100), METAL)
	add(m, head, "AntennaTip", BALL, Vector3.one * 0.22 * h.X, C(0.35 * h.X, 1.05 * h.Y, 0), col, NEON)
end
HAIR.bald = function() end
HAIR.dummy = function(m, head, col)
	local h = head.Size
	add(m, head, "Straw", BALL, Vector3.new(h.X * 1.1, h.Y * 0.5, h.Z * 1.1), C(0, 0.4 * h.Y, 0), Color3.fromRGB(230, 200, 110), FABRIC)
	add(m, head, "Target", CYL, Vector3.new(0.05, 0.9, 0.9), C(0, -1.4, -0.55) * R(0, 90, 0), Color3.fromRGB(230, 60, 60))
end

local function face(m, head, look)
	local h = head.Size
	local z = -h.Z / 2 - 0.01
	if look.hairStyle == "robot" then
		add(m, head, "Visor", BLOCK, Vector3.new(h.X * 0.95, 0.22 * h.Y, 0.1), C(0, 0.05 * h.Y, z - 0.05), look.eye, NEON)
		return
	end
	if look.hairStyle == "dummy" then
		for _, x in { -0.2, 0.2 } do
			add(m, head, "Button", CYL, Vector3.new(0.05, 0.2, 0.2) * h.X * 1.4, C(x * h.X, 0.05 * h.Y, z) * R(0, 90, 0), look.eye)
		end
		add(m, head, "Stitch", BLOCK, Vector3.new(0.45 * h.X, 0.05, 0.05), C(0, -0.22 * h.Y, z), look.eye)
		return
	end
	for _, s in { -1, 1 } do
		add(m, head, "EyeWhite", BLOCK, Vector3.new(0.3, 0.26, 0.05) * h.X, C(s * 0.22 * h.X, 0.0, z), Color3.new(1, 1, 1))
		add(m, head, "Iris", BLOCK, Vector3.new(0.15, 0.22, 0.05) * h.X, C(s * 0.19 * h.X, -0.01 * h.Y, z - 0.02), look.eye, NEON)
		add(m, head, "Pupil", BLOCK, Vector3.new(0.06, 0.1, 0.05) * h.X, C(s * 0.19 * h.X, -0.01 * h.Y, z - 0.035), Color3.fromRGB(15, 10, 20))
		add(m, head, "Brow", BLOCK, Vector3.new(0.34, 0.08, 0.05) * h.X, C(s * 0.22 * h.X, 0.19 * h.Y, z - 0.01) * R(0, 0, s * 20), look.hair or Color3.fromRGB(25, 20, 25))
	end
	add(m, head, "Mouth", BLOCK, Vector3.new(0.22, 0.04, 0.05) * h.X, C(0, -0.25 * h.Y, z), Color3.fromRGB(70, 30, 30))
end

local GEAR = {}
GEAR.chest = function(m, b, look)
	local t = b.UpperTorso
	add(m, t, "ChestPlate", BLOCK, Vector3.new(t.Size.X * 1.06, t.Size.Y * 0.72, t.Size.Z * 1.25), C(0, t.Size.Y * 0.08, 0), look.armor or look.outfit2)
	add(m, t, "ChestStripe", BLOCK, Vector3.new(t.Size.X * 1.08, t.Size.Y * 0.12, t.Size.Z * 1.28), C(0, -t.Size.Y * 0.12, 0), look.outfit2 or look.outfit)
end
local function pads(m, b, look, big)
	for _, side in { "Left", "Right" } do
		local arm = b[side .. "UpperArm"]
		local s = side == "Left" and -1 or 1
		local size = big and Vector3.new(1.35, 0.4, 1.15) or Vector3.new(1.0, 0.32, 0.9)
		add(m, arm, side .. "Pad", BLOCK, size, C(s * 0.15, arm.Size.Y * 0.42, 0) * R(0, 0, -s * 18), look.armor or look.outfit2)
		if big then
			add(m, arm, side .. "PadRim", BLOCK, size + Vector3.new(0.1, -0.25, 0.1), C(s * 0.15, arm.Size.Y * 0.32, 0) * R(0, 0, -s * 18), look.outfit2 or look.outfit, METAL)
		end
	end
end
GEAR.pads = function(m, b, look) pads(m, b, look, false) end
GEAR.bigpads = function(m, b, look) pads(m, b, look, true) end
GEAR.belt = function(m, b, look)
	local t = b.LowerTorso
	add(m, t, "Belt", BLOCK, Vector3.new(t.Size.X * 1.06, 0.25, t.Size.Z * 1.15), C(0, t.Size.Y * 0.25, 0), Color3.fromRGB(40, 35, 35))
	add(m, t, "Buckle", BLOCK, Vector3.new(0.35, 0.28, 0.08), C(0, t.Size.Y * 0.25, -t.Size.Z * 0.6), Color3.fromRGB(240, 200, 80), METAL)
end
GEAR.visor = function(m, b, look)
	local h = b.Head
	add(m, h, "Scanner", BLOCK, Vector3.new(0.5, 0.25, 0.06) * h.Size.X, C(0.22 * h.Size.X, 0.02 * h.Size.Y, -h.Size.Z / 2 - 0.05), look.eye, NEON).Transparency = 0.3
	add(m, h, "ScannerArm", BLOCK, Vector3.new(0.06, 0.12, 0.6) * h.Size.X, C(0.52 * h.Size.X, 0.02 * h.Size.Y, -0.2 * h.Size.Z), Color3.fromRGB(80, 80, 90))
end
GEAR.cape = function(m, b, look)
	local t = b.UpperTorso
	add(m, t, "Cape", BLOCK, Vector3.new(t.Size.X * 1.1, t.Size.Y * 2.4, 0.15), C(0, -t.Size.Y * 0.75, t.Size.Z * 0.6) * R(-6, 0, 0), look.outfit2 or look.outfit, FABRIC)
	add(m, t, "Collar", BLOCK, Vector3.new(t.Size.X * 1.15, 0.35, t.Size.Z * 1.2), C(0, t.Size.Y * 0.45, 0.05), look.outfit2 or look.outfit, FABRIC)
end
GEAR.coat = function(m, b, look)
	local t = b.LowerTorso
	add(m, t, "CoatTail", BLOCK, Vector3.new(t.Size.X * 1.1, 1.6, 0.2), C(0, -0.7, t.Size.Z * 0.55), look.outfit, FABRIC)
	local u = b.UpperTorso
	add(m, u, "Lapel", BLOCK, Vector3.new(0.35, u.Size.Y * 0.9, 0.08), C(0, 0, -u.Size.Z * 0.55), look.armor or Color3.fromRGB(230, 190, 80))
end
GEAR.vest = function(m, b, look)
	local u = b.UpperTorso
	add(m, u, "Vest", BLOCK, Vector3.new(u.Size.X * 1.05, u.Size.Y * 0.95, u.Size.Z * 1.1), C(0, 0, 0), look.outfit, Enum.Material.Leather)
	add(m, u, "Chest", BLOCK, Vector3.new(u.Size.X * 0.35, u.Size.Y * 0.9, 0.06), C(0, 0, -u.Size.Z * 0.58), look.skin)
end
GEAR.stripes = function(m, b, look)
	local u = b.UpperTorso
	for i = -1, 1 do
		add(m, u, "Stripe", BLOCK, Vector3.new(u.Size.X * 1.03, 0.12, u.Size.Z * 1.06), C(0, i * u.Size.Y * 0.3, 0), look.outfit2)
	end
end
GEAR.beard = function(m, b, look)
	local h = b.Head
	add(m, h, "Beard", WEDGE, Vector3.new(h.Size.X * 0.9, h.Size.Y * 0.55, h.Size.Z * 0.5), C(0, -h.Size.Y * 0.45, -h.Size.Z * 0.3) * R(0, 180, 180), look.hair or Color3.fromRGB(80, 60, 40))
end
GEAR.tie = function(m, b, look)
	local u = b.UpperTorso
	add(m, u, "Tie", BLOCK, Vector3.new(0.25, u.Size.Y * 0.7, 0.06), C(0, 0, -u.Size.Z * 0.55), look.armor or Color3.fromRGB(220, 40, 50))
	add(m, u, "Collar", BLOCK, Vector3.new(u.Size.X * 0.7, 0.2, u.Size.Z * 1.08), C(0, u.Size.Y * 0.42, 0), Color3.fromRGB(245, 245, 250))
end

local WEAPON = {}
WEAPON.none = function() end
WEAPON.fists = function(m, b, look)
	for _, side in { "Left", "Right" } do
		add(m, b[side .. "Hand"], side .. "Glow", BALL, Vector3.one * 0.8, C(0, -0.1, 0), look.eye, NEON).Transparency = 0.35
	end
end
local function inHand(m, b) return b.RightHand end
WEAPON.blaster = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Gun", BLOCK, Vector3.new(0.45, 0.55, 1.4), C(0, -0.25, -0.45), Color3.fromRGB(60, 65, 75), METAL)
	add(m, h, "Barrel", CYL, Vector3.new(0.6, 0.3, 0.3), C(0, -0.15, -1.35) * R(0, 90, 0), look.eye, NEON)
end
WEAPON.sword = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Hilt", BLOCK, Vector3.new(0.2, 0.2, 0.7), C(0, -0.2, 0), Color3.fromRGB(40, 30, 30))
	add(m, h, "Blade", BLOCK, Vector3.new(0.12, 0.3, 3.0), C(0, -0.2, -1.8), Color3.fromRGB(220, 230, 240), METAL)
end
WEAPON.cutlass = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Guard", BLOCK, Vector3.new(0.6, 0.5, 0.15), C(0, -0.2, -0.3), Color3.fromRGB(230, 190, 80), METAL)
	add(m, h, "Blade", BLOCK, Vector3.new(0.1, 0.45, 2.6), C(0, -0.1, -1.7) * R(-6, 0, 0), Color3.fromRGB(225, 230, 240), METAL)
end
WEAPON.spear = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Shaft", CYL, Vector3.new(6, 0.22, 0.22), C(0, -0.1, 0) * R(0, 0, 90), Color3.fromRGB(70, 50, 40))
	add(m, h, "Tip", BLOCK, Vector3.new(0.12, 0.5, 1.0), C(0, 3.1, 0) * R(90, 0, 0), look.armor or look.eye, METAL)
end
WEAPON.greatsword = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Hilt", BLOCK, Vector3.new(0.25, 0.25, 1.0), C(0, -0.2, 0.2), Color3.fromRGB(40, 30, 35))
	add(m, h, "Guard", BLOCK, Vector3.new(0.3, 1.4, 0.3), C(0, -0.2, -0.35), look.armor or Color3.fromRGB(255, 200, 70), METAL)
	add(m, h, "Blade", BLOCK, Vector3.new(0.18, 0.75, 4.2), C(0, -0.2, -2.5), look.eye, NEON)
end
WEAPON.club = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Club", CYL, Vector3.new(2.4, 0.45, 0.45), C(0, -0.1, -1.0) * R(0, 90, 0), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
end
WEAPON.anchor = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Shank", BLOCK, Vector3.new(0.35, 0.35, 3.6), C(0, -0.2, -1.6), Color3.fromRGB(70, 75, 85), METAL)
	add(m, h, "Arms", BLOCK, Vector3.new(2.2, 0.35, 0.4), C(0, -0.2, -3.3), Color3.fromRGB(70, 75, 85), METAL)
	add(m, h, "Ring", CYL, Vector3.new(0.2, 0.8, 0.8), C(0, -0.2, 0.3) * R(0, 0, 90), Color3.fromRGB(70, 75, 85), METAL)
end
WEAPON.hammer = function(m, b, look)
	local h = inHand(m, b)
	add(m, h, "Handle", CYL, Vector3.new(2.6, 0.22, 0.22), C(0, -0.1, -0.8) * R(0, 90, 0), Color3.fromRGB(60, 60, 70), METAL)
	add(m, h, "Head", BLOCK, Vector3.new(1.4, 0.8, 0.8), C(0, -0.1, -2.0), look.armor or Color3.fromRGB(240, 140, 50), METAL)
end

function M.BuildEnemy(id, def)
	local look = def.look
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = look.skin
	d.LeftArmColor = look.outfit; d.RightArmColor = look.outfit
	d.TorsoColor = look.outfit
	d.LeftLegColor = look.outfit2 or look.outfit; d.RightLegColor = look.outfit2 or look.outfit
	if look.hairStyle == "robot" then
		d.LeftArmColor = look.skin; d.RightArmColor = look.skin
	end
	d.HeightScale = 1.05
	d.WidthScale = def.scale > 1.2 and 1 or 0.9
	d.HeadScale = 1.15
	local rig = Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	rig.Name = id
	local animate = rig:FindFirstChild("Animate")
	local idleId = animate and animate:FindFirstChild("idle") and animate.idle:FindFirstChildOfClass("Animation")
	rig:SetAttribute("IdleAnim", idleId and idleId.AnimationId or "rbxassetid://507766388")
	if animate then animate:Destroy() end
	local b = {}
	for _, p in rig:GetChildren() do
		if p:IsA("BasePart") then
			b[p.Name] = p
			p.CanCollide = false
			p.CanTouch = false
		end
	end
	-- hands match skin, remove default face
	b.LeftHand.Color = look.skin; b.RightHand.Color = look.skin
	if look.hairStyle == "robot" then b.LeftHand.Color = look.armor; b.RightHand.Color = look.armor end
	for _, dec in b.Head:GetChildren() do if dec:IsA("Decal") then dec:Destroy() end end
	local HEAD_GROW = 1.3
	b.Head.Size *= HEAD_GROW
	for _, a in b.Head:GetChildren() do
		if a:IsA("Attachment") then a.Position *= HEAD_GROW end
	end
	-- (the neck is an AnimationConstraint, so moving NeckRigAttachment above is enough)
	-- gloves and boots
	local glove = look.hairStyle == "robot" and look.armor or Color3.fromRGB(30, 28, 34)
	b.LeftHand.Color = glove; b.RightHand.Color = glove
	b.LeftLowerLeg.Color = Color3.fromRGB(35, 32, 38); b.RightLowerLeg.Color = Color3.fromRGB(35, 32, 38)
	if look.hairStyle == "dummy" then
		b.LeftHand.Color = look.skin; b.RightHand.Color = look.skin
		b.LeftLowerLeg.Color = look.outfit2; b.RightLowerLeg.Color = look.outfit2
	end
	b.LeftFoot.Color = Color3.fromRGB(35, 30, 35); b.RightFoot.Color = Color3.fromRGB(35, 30, 35)

	BASIS = b.HumanoidRootPart.CFrame.Rotation
	local decor = Instance.new("Folder"); decor.Name = "Decor"; decor.Parent = rig
	;(HAIR[look.hairStyle] or HAIR.bald)(rig, b.Head, look.hair or look.outfit)
	face(rig, b.Head, look)
	for _, g in look.gear or {} do if GEAR[g] then GEAR[g](rig, b, look) end end
	;(WEAPON[look.weapon] or WEAPON.none)(rig, b, look)

	local hum = rig:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.EvaluateStateMachine = false -- it's a statue that plays animations, no physics brain needed

	local hrp = b.HumanoidRootPart
	hrp.Anchored = true
	rig.PrimaryPart = hrp
	if def.scale ~= 1 then rig:ScaleTo(def.scale) end

	-- measurements the game uses (health bar height, ground placement, follower ring)
	local cf, size = rig:GetBoundingBox()
	rig:SetAttribute("GroundOffset", hrp.Position.Y - (cf.Position.Y - size.Y / 2))
	rig:SetAttribute("TopOffset", (cf.Position.Y + size.Y / 2) - hrp.Position.Y)
	rig:SetAttribute("Radius", math.max(size.X, size.Z) / 2)
	return rig
end

function M.BuildAll(freshConfig)
	if freshConfig then Config = freshConfig end -- the command bar caches modules; pass a fresh copy
	local folder = ServerStorage:FindFirstChild("EnemyModels")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "EnemyModels"
	for id, def in Config.Enemies do
		M.BuildEnemy(id, def).Parent = folder
	end
	folder.Parent = ServerStorage
	return #folder:GetChildren()
end

return M
