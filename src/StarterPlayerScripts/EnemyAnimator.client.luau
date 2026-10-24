-- EnemyAnimator (client): makes nearby enemies feel alive. Purely visual: the server
-- owns every enemy and where it stands, so this script only POSES the rig (the Motor6D
-- Transforms) and never moves the model itself. (The small knockback wobble on each hit
-- comes from ChampionController.)
--   * an idle personality per enemy tier: grunts bounce on their toes, scouts sway with
--     their weapon, elites and bosses breathe heavily, training dummies just wobble
--   * enemies turn (from the hips) to face the champion attacking them
--   * a short drop-in when an enemy (re)spawns near you
--   * a flinch on every hit, and a much bigger one for big hits (abilities)
--   * bosses roar every ~10 s while nobody is hitting them, with a ring on the ground
--   * a cleaner defeat: knocked back, then a fade-out with sparkles
-- One RenderStepped loop, and only enemies within 120 studs of you are animated.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Anim = require(Shared:WaitForChild("Anim"))
local Fx = require(Shared:WaitForChild("Fx"))
local Config = require(Shared:WaitForChild("Config"))
local R, T = Anim.R, Anim.T
local EASE = Anim.EASE

local enemies = workspace:WaitForChild("Enemies")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local RANGE = 120              -- only enemies this close (studs) are animated
local SCAN_EVERY = 0.2         -- how often an enemy looks for its attacker (seconds)
local FACE_HOLD = 1.5          -- keep facing the same champion at least this long (seconds)
local FLINCH_TIME = 0.25       -- normal hit
local BIG_FLINCH_TIME = 0.5    -- big hit (ability)
local BIG_PUSH = 1.0           -- knockback (studs) that marks a big hit: see onHit
local DEATH_FADE_AT = 0.4      -- seconds into the defeat when the fade + sparkles start
local TAUNT_TIME = 1.6         -- boss roar length
local DROP_FALL, DROP_LAND = 0.3, 0.32 -- drop-in: falling time, then landing time

----------------------------------------------------------------------------
-- personality per enemy type
----------------------------------------------------------------------------
-- Every world lists its zones weakest first (grunt, scout, elite) and names its boss,
-- so a new world in Config gets personalities for free.
local KIND: { [string]: string } = { TrainingDummy = "dummy" }
local TIERS = { "grunt", "scout", "elite" }
for _, w in Config.Worlds do
	for i, z in w.zones or {} do KIND[z.enemy] = TIERS[i] or "elite" end
	if w.boss then KIND[w.boss] = "boss" end
end
-- heavy enemies flinch less (a boss barely rocks on a normal hit)
local STURDY = { dummy = 1, grunt = 1, scout = 1, elite = 0.75, boss = 0.55 }

----------------------------------------------------------------------------
-- poses (joint rotations relative to standing; Shared.Anim explains the axes)
----------------------------------------------------------------------------
local FLINCH = { Waist = R(16), Neck = R(18), RightShoulder = R(-10, 0, 30), LeftShoulder = R(-10, 0, -30), RightKnee = R(-10), LeftKnee = R(-10) }
local FLINCH_ROOT = T(0, -0.1, 0.3, 8)
local BIG_FLINCH = { Waist = R(26, 0, 6), Neck = R(30, 0, -8), RightShoulder = R(-20, 0, 65), RightElbow = R(35), LeftShoulder = R(-20, 0, -65),
	LeftElbow = R(35), RightHip = R(-12), LeftHip = R(22), RightKnee = R(-22), LeftKnee = R(-38) }
local BIG_FLINCH_ROOT = T(0, -0.3, 1.0, 14)
-- boss taunt: hunch down and gather... then ROAR with the arms thrown wide
local WIND = { Waist = R(-22), Neck = R(-18), RightShoulder = R(35, 0, 8), RightElbow = R(95), LeftShoulder = R(35, 0, -8), LeftElbow = R(95),
	RightHip = R(30, 0, 6), LeftHip = R(30, 0, -6), RightKnee = R(-45), LeftKnee = R(-45), RightAnkle = R(15), LeftAnkle = R(15), Root = T(0, -0.45, 0, -10) }
-- (only a small head tilt back: tipped further, the face disappears behind the boss's
-- shoulders from the player's camera, and the roar reads better with the face showing)
local ROAR = { Waist = R(8), Neck = R(12), RightShoulder = R(20, 0, 110), RightElbow = R(30), LeftShoulder = R(20, 0, -110), LeftElbow = R(30),
	RightHip = R(4, 0, 10), LeftHip = R(4, 0, -10), RightKnee = R(-18), LeftKnee = R(-18), RightAnkle = R(0, 0, -10), LeftAnkle = R(0, 0, 10),
	Root = T(0, -0.15, 0.15, 4) }
-- drop-in: tucked up in the air, then a crouched landing
local TUCK = { RightHip = R(45), RightKnee = R(-70), LeftHip = R(25), LeftKnee = R(-50), RightShoulder = R(-10, 0, 55), LeftShoulder = R(-10, 0, -55),
	Waist = R(-8), Neck = R(-6) }
local LAND = { Root = T(0, -0.5, 0, -12), RightHip = R(40), LeftHip = R(40), RightKnee = R(-60), LeftKnee = R(-60), RightAnkle = R(20), LeftAnkle = R(20),
	RightShoulder = R(10, 0, 35), LeftShoulder = R(10, 0, -35), Waist = R(-10) }
-- defeat: thrown onto its back, arms and legs flung up (the root move is worked out below)
local DEFEAT = { Waist = R(14), Neck = R(24), RightShoulder = R(70, 0, 55), RightElbow = R(20), LeftShoulder = R(70, 0, -55), LeftElbow = R(20),
	RightHip = R(40), LeftHip = R(18), RightKnee = R(-35), LeftKnee = R(-20) }

-- The idle loop for each personality. `t` = seconds (each enemy has its own offset).
local function idlePose(kind: string, t: number): { [string]: CFrame }
	if kind == "grunt" then
		-- light on their toes: a quick little bounce with the fists up
		local hop = (math.sin(t * 5.2) + 1) / 2
		local sway = math.sin(t * 2.6)
		return {
			Root = T(sway * 0.05, -0.16 + hop * 0.14, 0, -4),
			Waist = R(-2, sway * 6, 0), Neck = R(4, -sway * 5, 0),
			RightShoulder = R(42 + hop * 6, 0, 12), RightElbow = R(85 - hop * 8),
			LeftShoulder = R(48 + hop * 6, 0, -12), LeftElbow = R(92 - hop * 8),
			RightHip = R(20 - hop * 8), LeftHip = R(6 - hop * 8),
			RightKnee = R(-30 + hop * 16), LeftKnee = R(-20 + hop * 16),
			RightAnkle = R(10 - hop * 16), LeftAnkle = R(14 - hop * 16),
		}
	elseif kind == "scout" then
		-- a loose sway from the hips, the weapon arm swinging along
		local sw = math.sin(t * 1.8)
		local arm = math.sin(t * 1.8 + 0.7)
		return {
			Root = T(sw * 0.12, -0.1, 0),
			Waist = R(-3, sw * 14, sw * 2), Neck = R(0, -sw * 10, 0),
			RightShoulder = R(34 + arm * 16, 0, 16 + arm * 6), RightElbow = R(55 - arm * 14), RightWrist = R(arm * 10),
			LeftShoulder = R(28, 0, -14 - sw * 4), LeftElbow = R(70),
			RightHip = R(10, 0, 4), LeftHip = R(-6, 0, -4), RightKnee = R(-14), LeftKnee = R(-10),
		}
	elseif kind == "elite" or kind == "boss" then
		-- slow, heavy breathing: the chest heaves, the shoulders rise and fall
		local boss = kind == "boss"
		local inhale = (math.sin(t * (if boss then 1.2 else 1.5)) + 1) / 2
		return {
			Root = T(0, -0.18 + inhale * 0.08, 0, -3),
			Waist = R(-7 + inhale * 8, 0, 0),
			Neck = R(-2 - inhale * 5, math.sin(t * 0.45) * (if boss then 18 else 8), 0),
			RightShoulder = R(8 - inhale * 5, 0, 18 + inhale * 7), RightElbow = R(26),
			LeftShoulder = R(8 - inhale * 5, 0, -18 - inhale * 7), LeftElbow = R(26),
			RightHip = R(6, 0, 7), LeftHip = R(6, 0, -7), RightKnee = R(-14), LeftKnee = R(-14),
			RightAnkle = R(6, 0, -7), LeftAnkle = R(6, 0, 7),
		}
	end
	-- training dummy: just a gentle wobble, like it's on a spring
	local w = math.sin(t * 2.4)
	return { Waist = R(w * 2, 0, w * 3), Neck = R(0, 0, -w * 3), RightShoulder = R(0, 0, 18 + w * 3), LeftShoulder = R(0, 0, -18 + w * 3) }
end

-- turn from angle a toward angle b by fraction k, the short way round
local function turnToward(a: number, b: number, k: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * k
end

-- a root joint move scaled to the enemy's size (big enemies move further)
local function scaleMove(cf: CFrame, s: number): CFrame
	return (cf - cf.Position) + cf.Position * s
end

----------------------------------------------------------------------------
-- champions (ChampionController draws everyone's in workspace.ClientChampions)
----------------------------------------------------------------------------
local champs: { [Instance]: { root: BasePart, owner: Player? } } = {}
task.spawn(function()
	local folder = workspace:WaitForChild("ClientChampions", 60)
	if not folder then return end
	local function add(m: Instance)
		local root = m:IsA("Model") and m:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local ownerId = m:GetAttribute("OwnerId")
		champs[m] = { root = root :: BasePart, owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil }
	end
	for _, m in folder:GetChildren() do add(m) end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(m) champs[m] = nil end)
end)

----------------------------------------------------------------------------
-- enemies we know about
----------------------------------------------------------------------------
type Foe = {
	model: Model, root: BasePart, rig: any, kind: string, scale: number, sturdy: number, seed: number,
	accent: Color3, groundOffset: number, radius: number,
	yaw: number, wantYaw: number?, nextScan: number, facing: Instance?, facingUntil: number,
	hitAt: number, bigHit: boolean, flinchRoot: CFrame, pushAngle: number, home: Vector3,
	spawnAt: number?, landed: boolean,
	nextTaunt: number, tauntAt: number?, roared: boolean,
	dieAt: number?, deathAngle: number, faded: boolean,
}
local all: { [Model]: boolean } = {}   -- every enemy model streamed to this client
local foes: { [Model]: Foe } = {}      -- the ones we've animated (made when they first come near)

-- When each enemy model appeared, so a (re)spawn near you can drop in. Joining, a
-- teleport or walking into a new area streams in lots of enemies at once: those just
-- appear (they didn't really spawn), so bursts and the first seconds in a place are skipped.
local spawnedAt: { [Model]: number } = {}
local quietUntil = os.clock() + 4
local recentAdds = 0
local function settle() quietUntil = os.clock() + 3 end
player:GetAttributeChangedSignal("World"):Connect(settle)

local myRoot: BasePart? = nil
local function onCharacter(c: Model)
	settle()
	myRoot = c:WaitForChild("HumanoidRootPart", 10) :: BasePart?
end
if player.Character then task.spawn(onCharacter, player.Character) end
player.CharacterAdded:Connect(onCharacter)

local function addEnemy(m: Instance)
	if not m:IsA("Model") then return end
	all[m] = true
	recentAdds += 1
	task.delay(0.5, function() recentAdds -= 1 end)
	if os.clock() > quietUntil then spawnedAt[m] = os.clock() end
end
for _, m in enemies:GetChildren() do
	if m:IsA("Model") then all[m] = true end
end
enemies.ChildAdded:Connect(addEnemy)
enemies.ChildRemoved:Connect(function(m)
	all[m :: Model] = nil
	foes[m :: Model] = nil
	spawnedAt[m :: Model] = nil
end)

----------------------------------------------------------------------------
-- effects
----------------------------------------------------------------------------
local function groundUnder(f: Foe): Vector3
	return f.root.Position - Vector3.new(0, f.groundOffset, 0)
end

-- landing from the drop-in: a ring and a puff of dust (bosses shake the ground)
local function landFx(f: Foe)
	local g = groundUnder(f)
	local s = f.scale
	Fx.Ring(CFrame.new(g + Vector3.new(0, 0.15, 0)), f.accent, 1.5 * s, 7 * s, 0.4, 0.15)
	Fx.Particles(g + Vector3.new(0, 0.4, 0), { color = "#e8dcc0", count = math.floor(8 * s), speed = 7 * s, size = 0.6 * s, lifetime = 0.4, spread = 180 })
	if f.kind == "boss" then Fx.Shockwave(g, f.accent, 9, 0.5) end
end

-- the boss roar: a wide ring in the boss's colour rolling out over the arena floor
local function roarFx(f: Foe)
	local g = groundUnder(f)
	Fx.Ring(CFrame.new(g + Vector3.new(0, 0.2, 0)), f.accent, 4, 30, 0.8, 0.3)
	Fx.Ring(CFrame.new(g + Vector3.new(0, 0.35, 0)), "#ffffff", 2, 20, 0.55, 0.15)
end

-- the end of a defeat: the body fades away in a burst of sparkles
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local function fadeOut(f: Foe)
	local model = f.model
	if f.faded or not model.Parent then return end
	f.faded = true
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			TweenService:Create(d, FADE, { Transparency = 1 }):Play()
		end
	end
	local torso = model:FindFirstChild("UpperTorso")
	local pos = if torso and torso:IsA("BasePart") then torso.Position else f.root.Position
	local s = f.scale
	Fx.Particles(pos, { color = f.accent, count = math.floor(14 * s), speed = 6 * s, size = 0.45 * s, lifetime = 0.8, spread = 180, gravity = -8, light = true })
	Fx.Particles(pos, { color = "#ffffff", count = math.floor(10 * s), speed = 9 * s, size = 0.3 * s, lifetime = 0.5, spread = 180, light = true })
	Fx.Glint(pos, f.accent, 2.6 * s, 0.4)
end

----------------------------------------------------------------------------
-- reactions
----------------------------------------------------------------------------
-- A champion's hit just landed (ChampionController sets ClientHitAt right after it nudges
-- the model back: 0.45 studs for a normal hit, 1.6 for an ability). How far the model
-- sits from where it normally stands tells us which way, and how hard, it was hit.
local function onHit(f: Foe)
	local now = os.clock()
	local push = (f.root.Position - f.home) * Vector3.new(1, 0, 1)
	local big = push.Magnitude > BIG_PUSH
	-- a normal hit straight after a big one doesn't cut the big flinch short
	if not big and f.bigHit and now - f.hitAt < BIG_FLINCH_TIME * 0.6 then return end
	f.bigHit = big
	f.hitAt = now
	-- the push direction in the enemy's own space (angle from its back, +Z)
	if push.Magnitude > 0.05 then
		local v = f.root.CFrame:VectorToObjectSpace(push)
		f.pushAngle = math.atan2(v.X, v.Z)
	else
		f.pushAngle = f.yaw -- unknown: straight back from where it's facing
	end
	local lean = scaleMove(if big then BIG_FLINCH_ROOT else FLINCH_ROOT, f.scale)
	local around = CFrame.Angles(0, f.pushAngle, 0)
	f.flinchRoot = around * lean * around:Inverse()
	f.tauntAt = nil -- getting hit interrupts a boss's roar
end

local function onDefeat(f: Foe)
	if f.dieAt then return end
	f.dieAt = os.clock()
	f.tauntAt = nil
	-- thrown away from whoever hit it last (or straight backwards)
	f.deathAngle = if os.clock() - f.hitAt < 1.5 then f.pushAngle else f.yaw
	-- the fade starts while it's still flying; the server removes the model ~0.9 s after
	task.delay(DEATH_FADE_AT, fadeOut, f)
end

local function track(model: Model): Foe?
	local root = model.PrimaryPart
	if not root then return nil end
	local key = model:GetAttribute("EnemyType")
	local def = if typeof(key) == "string" then Config.Enemies[key] else nil
	local look = def and def.look or {}
	local kind = if def and def.boss then "boss" elseif typeof(key) == "string" and KIND[key] then KIND[key] else "grunt"
	local now = os.clock()
	local f: Foe = {
		model = model, root = root, rig = Anim.Rig(model), kind = kind, scale = def and def.scale or 1,
		sturdy = STURDY[kind] or 1, seed = math.random() * 10,
		accent = if kind == "dummy" then Color3.fromRGB(255, 220, 140) else (look.eye or look.outfit2 or Color3.new(1, 1, 1)),
		groundOffset = model:GetAttribute("GroundOffset") or root.Size.Y * 1.5,
		radius = model:GetAttribute("Radius") or 2,
		yaw = 0, wantYaw = nil, nextScan = 0, facing = nil, facingUntil = 0,
		hitAt = -math.huge, bigHit = false, flinchRoot = CFrame.identity, pushAngle = 0, home = root.Position,
		spawnAt = nil, landed = true,
		nextTaunt = now + 4 + math.random() * 6, tauntAt = nil, roared = false,
		dieAt = nil, deathAngle = 0, faded = false,
	}
	-- it (re)spawned a moment ago, right here, on its own (not in a streaming burst): drop in
	local born = spawnedAt[model]
	if born and now - born < 0.4 and recentAdds <= 3 then f.spawnAt = now; f.landed = false end
	foes[model] = f
	model:GetAttributeChangedSignal("ClientHitAt"):Connect(function() onHit(f) end)
	model:GetAttributeChangedSignal("Dead"):Connect(function()
		if model:GetAttribute("Dead") then onDefeat(f) end
	end)
	if model:GetAttribute("Dead") then
		-- already down when it came near: leave it alone
		f.dieAt = now - 10
		f.faded = true
	end
	return f
end

-- Which way the enemy should face (a turn from its hips, in radians): toward the champion
-- attacking it. Champions whose owner targets this enemy win; once it has been hit
-- recently, any champion right next to it counts too. nil = nobody, look ahead.
local function attackerYaw(f: Foe, recentlyHit: boolean, now: number): number?
	if f.kind == "dummy" then return nil end -- training dummies don't turn
	local pos = f.root.Position
	local reach = f.radius + 10
	local name = f.model.Name
	-- how good a champion is as "the one attacking me" (lower = better, nil = not attacking)
	local function score(c: { root: BasePart, owner: Player? }): number?
		local cr = c.root
		if not cr.Parent then return nil end
		local p = cr.Position
		local d = Vector3.new(p.X - pos.X, 0, p.Z - pos.Z).Magnitude
		if d >= reach then return nil end
		local targeting = c.owner ~= nil and c.owner:GetAttribute("Target") == name
		if not (targeting or recentlyHit) then return nil end
		return if targeting then d else d + 8
	end
	-- With a whole team around it, the nearest champion changes all the time; switching
	-- every scan made enemies spin back and forth. So stick with one for FACE_HOLD seconds.
	local chosen: Instance? = nil
	local held = f.facing and champs[f.facing]
	if held and now < f.facingUntil and score(held) then
		chosen = f.facing
	else
		local bestScore = math.huge
		for m, c in champs do
			local s = score(c)
			if s and s < bestScore then chosen, bestScore = m, s end
		end
		if chosen ~= f.facing then f.facingUntil = now + FACE_HOLD end
		f.facing = chosen
	end
	local info = chosen and champs[chosen]
	if not info then return nil end
	local v = f.root.CFrame:PointToObjectSpace(info.root.Position)
	if v.X * v.X + v.Z * v.Z < 0.01 then return nil end
	return math.atan2(-v.X, -v.Z)
end

----------------------------------------------------------------------------
-- per-frame posing
----------------------------------------------------------------------------
local function defeatPose(f: Foe, now: number, dt: number)
	local u = now - (f.dieAt :: number)
	if u > 0.9 then return end -- (the server removes the model about now)
	local k = math.clamp(u / 0.38, 0, 1)
	local e = EASE.out(k)
	local s = f.scale
	-- an arc: up a little, then down onto its back, sliding away from the hit
	local lift = math.sin(math.pi * k) * 0.7 - 1.5 * e * e
	local away = CFrame.Angles(0, f.deathAngle, 0)
	local knock = away * CFrame.new(0, lift * s, 2.2 * s * e) * CFrame.Angles(math.rad(75 * e), 0, 0) * away:Inverse()
	local pose = table.clone(DEFEAT)
	pose.Root = knock * CFrame.Angles(0, f.yaw, 0)
	Anim.Blend(f.rig, pose, math.min(1, dt * 25))
end

local function animate(f: Foe, now: number, dt: number)
	if f.dieAt then
		defeatPose(f, now, dt)
		return
	end
	local t = now + f.seed
	local pose = idlePose(f.kind, t)
	local hitAgo = now - f.hitAt
	-- where it normally stands (ChampionController's wobble always returns it here)
	if hitAgo > 0.3 then f.home = f.root.Position end

	-- 1) face the champion attacking it (the turn happens in the root joint, so the
	--    server's model never moves or rotates)
	if now >= f.nextScan then
		f.nextScan = now + SCAN_EVERY
		f.wantYaw = attackerYaw(f, hitAgo < 4, now)
	end
	local turnRate = if f.wantYaw then (if f.kind == "boss" then 3 else 6) else 1.2
	f.yaw = turnToward(f.yaw, f.wantYaw or 0, math.min(1, dt * turnRate))

	-- 2) bosses: a roar every ~10 s while nobody is hitting them
	if f.kind == "boss" then
		if f.tauntAt then
			local u = now - f.tauntAt
			if u >= TAUNT_TIME then
				f.tauntAt = nil
			else
				local w = math.min(1, u / 0.3) * math.min(1, (TAUNT_TIME - u) / 0.4)
				local roar = EASE.snap(math.clamp((u - 0.4) / 0.15, 0, 1))
				local tp = Anim.Mix(WIND, ROAR, roar)
				if roar > 0.5 then tp.Neck = tp.Neck * R(0, math.sin(now * 40) * 4, 0) end -- the head shakes as it roars
				pose = Anim.Mix(pose, tp, w)
				if not f.roared and u >= 0.45 then
					f.roared = true
					roarFx(f)
				end
			end
		elseif hitAgo > 3 and now >= f.nextTaunt and not f.spawnAt then
			f.tauntAt = now
			f.roared = false
			f.nextTaunt = now + 9 + math.random() * 3
		end
	end

	-- 3) the drop-in after a (re)spawn: fall (speeding up), then land in a crouch
	local drop = CFrame.identity
	if f.spawnAt then
		local u = now - f.spawnAt
		if u < DROP_FALL then
			local k = u / DROP_FALL
			drop = CFrame.new(0, (1 - k * k) * 5 * f.scale, 0)
			pose = Anim.Mix(pose, TUCK, 1 - k * 0.3)
		elseif u < DROP_FALL + DROP_LAND then
			if not f.landed then
				f.landed = true
				landFx(f)
			end
			pose = Anim.Mix(pose, LAND, 1 - EASE.inout((u - DROP_FALL) / DROP_LAND))
		else
			f.spawnAt = nil
		end
	end

	-- 4) the flinch: snaps in, then eases back (bigger and longer for big hits)
	local flinchRoot = CFrame.identity
	local len = if f.bigHit then BIG_FLINCH_TIME else FLINCH_TIME
	if hitAgo < len then
		local k
		if f.bigHit then
			k = if hitAgo < 0.05 then hitAgo / 0.05 else (1 - (hitAgo - 0.05) / (len - 0.05)) ^ 2
		else
			k = 1 - hitAgo / len
		end
		k *= f.sturdy
		pose = Anim.Mix(pose, if f.bigHit then BIG_FLINCH else FLINCH, k)
		flinchRoot = CFrame.identity:Lerp(f.flinchRoot, k)
	end

	-- 5) the root joint: drop + flinch (in the enemy's own space), the turn, then the pose's own move
	pose.Root = drop * flinchRoot * CFrame.Angles(0, f.yaw, 0) * scaleMove(pose.Root or CFrame.identity, f.scale)
	local snappy = f.spawnAt ~= nil or hitAgo < 0.1
	Anim.Blend(f.rig, pose, math.min(1, dt * (if snappy then 30 else 14)))
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local root = myRoot
	local center = if root and root.Parent then root.Position else camera.CFrame.Position
	for model in all do
		local pr = model.PrimaryPart
		if pr and (pr.Position - center).Magnitude < RANGE then
			local f = foes[model] or track(model)
			if f then animate(f, now, dt) end
		end
	end
end)
