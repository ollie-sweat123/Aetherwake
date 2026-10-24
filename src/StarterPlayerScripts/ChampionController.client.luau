-- ChampionController (client): draws every player's equipped champions and
-- animates them: following, running to the target, basic attacks, abilities.
-- The server decides WHAT happens (Remotes.ChampionAction); this script only
-- decides how it LOOKS (and sounds). Each champion's ability lives in Shared.Abilities.<Id>.
-- Every ability is staged the same way around that module (Shared.AbilityTiming):
-- anticipation -> a safe step back in the champion's own style -> power-up -> the module
-- (movement, execution, impact synced with the server's damage) -> recovery to its guard.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Anim = require(Shared:WaitForChild("Anim"))
local Fx = require(Shared:WaitForChild("Fx"))
local AbilityInfo = require(Shared:WaitForChild("AbilityInfo"))
local AbilityTiming = require(Shared:WaitForChild("AbilityTiming"))
local Settings = require(Shared:WaitForChild("Settings"))
local Audio = require(Shared:WaitForChild("Audio"))
local AudioConfig = require(Shared:WaitForChild("AudioConfig"))
local AbilityFolder = Shared:WaitForChild("Abilities")
local Models = ReplicatedStorage:WaitForChild("ChampionModels")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local enemies = workspace:WaitForChild("Enemies")
local localPlayer = Players.LocalPlayer
local P, R, T = Anim.P, Anim.R, Anim.T

-- A setting's value (the server publishes them as Pref_<key>; the default until it has).
local function pref(key: string): any
	local v = localPlayer:GetAttribute("Pref_" .. key)
	if v == nil then
		local d = Settings.ByKey[key]
		return d and d.default
	end
	return v
end

local folder = Instance.new("Folder")
folder.Name = "ClientChampions"
folder.Parent = workspace

local RARITY_AURA = {
	Epic = { rate = 6 }, Legendary = { rate = 12, light = true }, Mythic = { rate = 22, light = true, rainbow = true },
}

type Champ = {
	id: string, owner: Player, slot: number, model: Model, rig: any, root: BasePart,
	cf: CFrame, vel: Vector3, phase: number, busy: boolean, actionUntil: number, placed: boolean,
	hits: number, bar: { Frame }, barTweens: { Tween }, barGui: BillboardGui, nameLabel: TextLabel?,
	style: string, accent: Color3,
	holdUntil: number, -- hit-stop: the pose stays frozen until this time (os.clock)
	castId: number,    -- bumps on every ability, so an old one can't end a newer one
}
local champs: { [Player]: { Champ } } = {}

----------------------------------------------------------------------------
-- building a champion
----------------------------------------------------------------------------
local function weaponPart(model: Model, hand: string): BasePart?
	local acc = model:FindFirstChild("Accessories")
	if not acc then return nil end
	local best, bestSize = nil, 0
	for _, p in acc:GetChildren() do
		if p:IsA("BasePart") and p:GetAttribute("Joint") == hand and p.Size.Magnitude > bestSize then
			best, bestSize = p, p.Size.Magnitude
		end
	end
	return best
end

local BAR_OFF = Color3.fromRGB(30, 30, 40) -- colour of an empty ability-bar segment

-- "Lumen Fox ★★": the nickname (or default name) + one star per fusion level.
-- EquippedNames ("|" list) and EquippedStars ("," list) use the same order as EquippedIds.
local function labelText(owner: Player, slot: number, def: any): string
	local names = string.split(tostring(owner:GetAttribute("EquippedNames") or ""), "|")
	local stars = string.split(tostring(owner:GetAttribute("EquippedStars") or ""), ",")
	local name = names[slot]
	if name == nil or name == "" then name = def.name end
	local count = math.clamp(math.floor(tonumber(stars[slot] or "0") or 0), 0, 10)
	if count > 0 then name ..= " " .. string.rep("★", count) end
	return name
end

local function makeAbilityBar(c: Champ, def: any)
	local head = c.model:FindFirstChild("AnimeHead") or c.model:FindFirstChild("Head")
	local bb = Instance.new("BillboardGui")
	bb.Name = "ChampionHud"
	bb.Size = UDim2.fromScale(6, 1.6) -- wide enough for long names
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	bb.Adornee = head
	-- the champion's name (+ stars), coloured by its rarity
	local rarity = Config.RarityById[def.rarity]
	local label = Instance.new("TextLabel")
	label.Name = "ChampName"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.55)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = rarity and rarity.color or Color3.new(1, 1, 1)
	label.Text = labelText(c.owner, c.slot, def)
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Parent = label
	label.Parent = bb
	c.nameLabel = label
	-- the ability bar sits under the name
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.2, 0.62)
	row.Size = UDim2.fromScale(0.6, 0.3)
	local list = Instance.new("UIListLayout"); list.FillDirection = Enum.FillDirection.Horizontal; list.Padding = UDim.new(0.03, 0); list.Parent = row
	row.Parent = bb
	local segs = {}
	for i = 1, Config.Combat.HitsPerAbility do
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(0.17, 1)
		f.BackgroundColor3 = BAR_OFF
		f.BorderSizePixel = 0
		local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0.4, 0); cr.Parent = f
		local sk = Instance.new("UIStroke"); sk.Thickness = 1.5; sk.Color = Color3.new(0, 0, 0); sk.Parent = f
		f.Parent = row
		segs[i] = f
	end
	bb.Parent = c.model
	c.bar = segs
	c.barGui = bb
end

-- Every bar tween is kept in c.barTweens so the next change can cancel it.
-- (Before, the "ready" pulse looped forever and the bar got stuck white/full.)
local function stopBarTweens(c: Champ)
	for _, tw in c.barTweens do tw:Cancel() end
	table.clear(c.barTweens)
end

local function playBarTween(c: Champ, f: Frame, info: TweenInfo, goal: { [string]: any })
	local tw = TweenService:Create(f, info, goal)
	table.insert(c.barTweens, tw)
	tw:Play()
end

-- Shows `hits` filled segments. Full = the ability is ready, so the bar pulses.
local function setBar(c: Champ, hits: number)
	stopBarTweens(c)
	c.hits = hits
	for i, f in c.bar do
		f.BackgroundColor3 = if i <= hits then c.accent else BAR_OFF
	end
	if hits >= Config.Combat.HitsPerAbility then
		local pulse = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		for _, f in c.bar do playBarTween(c, f, pulse, { BackgroundColor3 = Color3.new(1, 1, 1) }) end
	end
end

-- The ability just fired: flash the whole bar white, then empty it segment by
-- segment (right to left) so players SEE it go back to 0. Basic hits refill it.
local function drainBar(c: Champ)
	stopBarTweens(c)
	c.hits = 0
	local n = #c.bar
	for i, f in c.bar do
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		local startAfter = 0.12 + (n - i) * 0.06 -- short white flash, then the right end empties first
		playBarTween(c, f, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, startAfter), { BackgroundColor3 = BAR_OFF })
	end
end

local function addAura(c: Champ, rarity: any)
	local a = RARITY_AURA[rarity.id]
	if not a then return end
	local att = Instance.new("Attachment"); att.Position = Vector3.new(0, -2.6, 0); att.Parent = c.root
	local pe = Instance.new("ParticleEmitter")
	pe.Color = a.rainbow and ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 255, 140)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 180, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 100, 255)) }) or ColorSequence.new(rarity.color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0.2, 1)
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Rate = a.rate
	pe.Speed = NumberRange.new(2, 4)
	pe.SpreadAngle = Vector2.new(25, 25)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rotation = NumberRange.new(0, 360)
	pe.Parent = att
	if a.light then
		local l = Instance.new("PointLight"); l.Color = rarity.color; l.Range = 8; l.Brightness = 1.2; l.Parent = c.root
	end
end

local function build(owner: Player, id: string, slot: number): Champ?
	local template = Models:FindFirstChild(id)
	local def = Config.ChampionById[id]
	if not template or not def then return nil end
	local model = template:Clone()
	model.Name = owner.Name .. "_" .. id .. "_" .. slot
	model:SetAttribute("OwnerId", owner.UserId)
	model:SetAttribute("Slot", slot)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	-- champions are pure visuals: they must never collide with, push or block anyone
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false; d.CanTouch = false; d.CanCollide = false; d.Massless = true
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then hum.EvaluateStateMachine = false end -- (stops the Humanoid switching collisions back on)
	model.Parent = folder
	local info = AbilityInfo[id]
	local rarity = Config.RarityById[def.rarity]
	local start = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
	local c: Champ = {
		id = id, owner = owner, slot = slot, model = model, rig = Anim.Rig(model), root = root,
		cf = start and start.CFrame or CFrame.new(), vel = Vector3.zero, phase = 0, busy = false, actionUntil = 0,
		placed = false, -- first frame snaps it straight to its spot (never on top of the owner)
		hits = 0, bar = {}, barTweens = {}, barGui = nil :: any, nameLabel = nil, style = info and info.style or "punch",
		accent = info and Color3.fromHex(info.palette[1]) or rarity.color,
		holdUntil = 0, castId = 0,
	}
	makeAbilityBar(c, def)
	if pref("HideAuras") ~= true then addAura(c, rarity) end -- (Settings > Disable Champion Auras)
	return c
end

local function rebuild(p: Player)
	for _, c in champs[p] or {} do stopBarTweens(c); c.model:Destroy() end
	champs[p] = {}
	-- Settings > Render Other Champions off: other players' champions aren't drawn at all
	if p ~= localPlayer and pref("RenderOthers") == false then return end
	local ids = string.split((p:GetAttribute("EquippedIds") or "") :: string, ",")
	for i, id in ids do
		if id ~= "" then
			local c = build(p, id, i)
			if c then table.insert(champs[p], c) end
		end
	end
end

-- A rename or fusion changes names/stars but not the team: just redo the labels.
local function refreshLabels(p: Player)
	for _, c in champs[p] or {} do
		local def = Config.ChampionById[c.id]
		if def and c.nameLabel then c.nameLabel.Text = labelText(p, c.slot, def) end
	end
end

local function watch(p: Player)
	p:GetAttributeChangedSignal("EquippedIds"):Connect(function() rebuild(p) end)
	p:GetAttributeChangedSignal("EquippedNames"):Connect(function() refreshLabels(p) end)
	p:GetAttributeChangedSignal("EquippedStars"):Connect(function() refreshLabels(p) end)
	rebuild(p)
end
for _, p in Players:GetPlayers() do task.spawn(watch, p) end
Players.PlayerAdded:Connect(watch)
-- these two settings change how champions are built, so rebuild them all when they change
for _, key in { "RenderOthers", "HideAuras" } do
	localPlayer:GetAttributeChangedSignal("Pref_" .. key):Connect(function()
		for _, p in Players:GetPlayers() do task.spawn(rebuild, p) end
	end)
end
Players.PlayerRemoving:Connect(function(p)
	for _, c in champs[p] or {} do stopBarTweens(c); c.model:Destroy() end
	champs[p] = nil
end)

----------------------------------------------------------------------------
-- positioning helpers
----------------------------------------------------------------------------
local GROUND = 2.95 -- HRP height above the ground for these rigs (feet on the floor)

local function targetOf(p: Player): Model?
	local name = p:GetAttribute("Target")
	local t = name and enemies:FindFirstChild(name)
	if t and t.PrimaryPart and not t:GetAttribute("Dead") then return t end
	return nil
end

local function groundAt(pos: Vector3, fallbackY: number): number
	return fallbackY
end

-- where champion `slot` of `n` stands around an enemy
local function attackSpot(c: Champ, target: Model, n: number): Vector3
	local tr = target.PrimaryPart :: BasePart
	local radius = (target:GetAttribute("Radius") or 2) + 3.2
	local groundY = tr.Position.Y - (target:GetAttribute("GroundOffset") or 3)
	local owner = c.owner.Character and c.owner.Character:FindFirstChild("HumanoidRootPart")
	local base = owner and math.atan2(owner.Position.X - tr.Position.X, owner.Position.Z - tr.Position.Z) or 0
	local a = base + (c.slot - (n + 1) / 2) * 1.05
	return Vector3.new(tr.Position.X + math.sin(a) * radius, groundY + GROUND, tr.Position.Z + math.cos(a) * radius)
end

-- odd slots walk on the owner's left, even slots on the right
local function sideOf(c: Champ): number
	return if c.slot % 2 == 1 then -1 else 1
end

-- where champion `slot` stands while following: two columns beside/behind the
-- owner, about 6 studs out, so they never stand where the player walks
local function followSpot(c: Champ, root: BasePart): Vector3
	local side = sideOf(c)
	local row = math.ceil(c.slot / 2)
	local p = (root.CFrame * CFrame.new(side * 5.5, 0, (row - 1) * 4.5 + 2.5)).Position
	return Vector3.new(p.X, root.Position.Y - 3 + GROUND, p.Z)
end

local OWNER_GAP = 3.5 -- champions never come closer than this (flat studs) to their owner

-- If `pos` is inside the owner's personal space, push it straight out (flat distance only).
local function keepClearOfOwner(pos: Vector3, ownerPos: Vector3): Vector3
	local away = Vector3.new(pos.X - ownerPos.X, 0, pos.Z - ownerPos.Z)
	local d = away.Magnitude
	if d >= OWNER_GAP then return pos end
	local dir = if d > 0.01 then away / d else Vector3.xAxis
	return Vector3.new(ownerPos.X + dir.X * OWNER_GAP, pos.Y, ownerPos.Z + dir.Z * OWNER_GAP)
end

-- If the straight line from `pos` to `goal` cuts through the owner, aim for a point
-- beside the owner first, so the champion walks AROUND them instead of through them.
local function detour(pos: Vector3, goal: Vector3, ownerPos: Vector3, side: number): Vector3
	local path = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
	local len = path.Magnitude
	if len < 0.1 then return goal end
	local dir = path / len
	local toOwner = Vector3.new(ownerPos.X - pos.X, 0, ownerPos.Z - pos.Z)
	local along = toOwner:Dot(dir)
	if along <= 0 or along >= len then return goal end -- the owner isn't between us and the goal
	local miss = dir * along - toOwner -- closest point of the path, seen from the owner
	if miss.Magnitude >= OWNER_GAP then return goal end
	-- pass on the side we already lean to (or the champion's own side if dead-on)
	local out = if miss.Magnitude > 0.05 then miss.Unit else Vector3.new(-dir.Z, 0, dir.X) * side
	return Vector3.new(ownerPos.X + out.X * (OWNER_GAP + 1), goal.Y, ownerPos.Z + out.Z * (OWNER_GAP + 1))
end

----------------------------------------------------------------------------
-- hit reaction on enemies (flash, knockback wobble, sparks, damage number)
----------------------------------------------------------------------------
local function enemyTop(e: Model): Vector3
	local r = e.PrimaryPart :: BasePart
	return r.Position + Vector3.new(0, e:GetAttribute("TopOffset") or 3, 0)
end

local function damageNumber(pos: Vector3, amount: number, big: boolean, color: Color3?)
	Fx.Callout(pos + Vector3.new((math.random() - 0.5) * 2, 0.5, (math.random() - 0.5) * 2), Format.Short(amount), color or (big and Color3.fromRGB(255, 220, 80) or Color3.new(1, 1, 1)), big and 1.4 or 0.75, big and 1.1 or 0.7)
end

-- Where each enemy really stands while it's wobbling from hits. Overlapping hits all
-- return to this one spot, so enemies can't slowly drift away on the client.
local wobbleHome: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local wobbleCount: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function hitReact(c: Champ, target: Model, amount: number, big: boolean)
	if not target.Parent then return end
	local tr = target.PrimaryPart :: BasePart
	Fx.HitFlash(target, big and c.accent or Color3.new(1, 1, 1), big and 0.3 or 0.12)
	Fx.Burst(tr.Position + (c.cf.Position - tr.Position).Unit * 1.2, big and c.accent or Color3.fromRGB(255, 240, 200), big and 5 or 2.2, big and 0.35 or 0.18)
	-- other players' champions throw half the sparks, so crowded fights stay readable
	local sparks = (big and 24 or 6) * (if c.owner == localPlayer then 1 else 0.5)
	Fx.Particles(tr.Position, { color = c.accent, count = sparks, speed = big and 22 or 12, size = 0.35, lifetime = 0.35, spread = 70 })
	if c.owner == localPlayer then damageNumber(enemyTop(target), amount, big, nil) end
	-- knockback wobble (client-side visual only)
	local away = (tr.Position - c.cf.Position) * Vector3.new(1, 0, 1)
	away = away.Magnitude > 0 and away.Unit or Vector3.zero
	local push = (big and 1.6 or 0.45)
	local home = wobbleHome[target]
	if not home then
		home = target:GetPivot()
		wobbleHome[target] = home
	end
	wobbleCount[target] = (wobbleCount[target] or 0) + 1
	target:PivotTo(home + away * push)
	task.delay(big and 0.18 or 0.08, function()
		local left = (wobbleCount[target] or 1) - 1
		wobbleCount[target] = left
		if target.Parent and not target:GetAttribute("Dead") then target:PivotTo(home) end
		if left <= 0 then
			wobbleHome[target] = nil
			wobbleCount[target] = nil
		end
	end)
	target:SetAttribute("ClientHitAt", os.clock())
end

----------------------------------------------------------------------------
-- basic attacks by style
----------------------------------------------------------------------------
-- Hit-stop: right after one of YOUR champions lands an ability, its pose freezes for a
-- blink (c.holdUntil) so the hit feels solid. Only the pose waits: the damage and the
-- effects are never delayed, and the clip clock keeps running so the move ends on time.
local function isHeld(c: Champ): boolean
	return os.clock() < c.holdUntil
end
local function blendPose(c: Champ, pose: { [string]: CFrame }, alpha: number)
	if not isHeld(c) then Anim.Blend(c.rig, pose, alpha) end
end

local function runClip(c: Champ, clip: { any })
	local start = os.clock()
	local len = Anim.Length(clip)
	while os.clock() - start < len do
		blendPose(c, Anim.Sample(clip, os.clock() - start), 0.65)
		RunService.RenderStepped:Wait()
	end
end

local ATTACK = {}
ATTACK.punch = function(c, target, hitIndex)
	local left = hitIndex % 2 == 0
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.1, pose = left and P.punchLWind or P.punchRWind, ease = "out" }, { t = 0.2, pose = left and P.punchL or P.punchR, ease = "snap" }, { t = 0.42, pose = P.guard, ease = "inout" } })
end
ATTACK.claws = function(c, target, hitIndex)
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.12, pose = P.clawWind }, { t = 0.22, pose = P.claw, ease = "snap" }, { t = 0.45, pose = P.guard, ease = "inout" } })
end
ATTACK.sword = function(c, target, hitIndex)
	local w = weaponPart(c.model, "RightHand")
	if w then Fx.Trail(w, c.accent, 0.35, 0.8) end
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.12, pose = P.slashWind }, { t = 0.22, pose = P.slash, ease = "snap" }, { t = 0.5, pose = P.guard, ease = "inout" } })
end
ATTACK.hammer = function(c, target, hitIndex)
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.14, pose = P.overWind }, { t = 0.22, pose = P.overSlam, ease = "in" }, { t = 0.55, pose = P.guard, ease = "inout" } })
end
ATTACK.wrench = ATTACK.hammer
ATTACK.spear = function(c, target, hitIndex)
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.12, pose = P.thrustWind }, { t = 0.22, pose = P.thrust, ease = "snap" }, { t = 0.48, pose = P.guard, ease = "inout" } })
end
ATTACK.trident = ATTACK.spear
ATTACK.staff = function(c, target, hitIndex)
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.1, pose = P.castRaise }, { t = 0.2, pose = P.castPoint, ease = "snap" }, { t = 0.5, pose = P.guard, ease = "inout" } })
end
ATTACK.magic = ATTACK.staff
ATTACK.bow = function(c, target, hitIndex)
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.12, pose = P.bowDraw }, { t = 0.2, pose = P.bowRelease, ease = "snap" }, { t = 0.5, pose = P.guard, ease = "inout" } })
end
ATTACK.kick = function(c, target, hitIndex)
	runClip(c, { { t = 0, pose = P.guard }, { t = 0.12, pose = P.kickWind }, { t = 0.22, pose = P.kick, ease = "snap" }, { t = 0.5, pose = P.guard, ease = "inout" } })
end

-- the "landing" visuals of a basic attack, fired at the impact moment
local function attackImpactFx(c: Champ, target: Model)
	local tr = target.PrimaryPart :: BasePart
	local from = (c.model:FindFirstChild("RightHand") :: BasePart).Position
	if c.style == "sword" then
		Fx.Slash(CFrame.lookAt(c.cf.Position, tr.Position) * CFrame.new(0, 0.5, -1.5), c.accent, 2.6, 150, 0.22, 0.45, (c.hits % 2 == 0) and 25 or -25)
	elseif c.style == "staff" or c.style == "magic" then
		Fx.Beam(from, tr.Position, c.accent, 0.35, 0.18)
	elseif c.style == "bow" then
		Fx.Beam((c.model:FindFirstChild("LeftHand") :: BasePart).Position, tr.Position, c.accent, 0.15, 0.15)
	elseif c.style == "hammer" or c.style == "wrench" then
		Fx.Ring(CFrame.new(tr.Position.X, tr.Position.Y - (target:GetAttribute("GroundOffset") or 3) + 0.2, tr.Position.Z), c.accent, 1, 6, 0.3, 0.15)
	elseif c.style == "spear" or c.style == "trident" then
		Fx.Beam(c.cf.Position, tr.Position + (tr.Position - c.cf.Position).Unit * 2, c.accent, 0.25, 0.15)
	elseif c.style == "claws" then
		Fx.Slash(CFrame.lookAt(c.cf.Position, tr.Position) * CFrame.new(0, 0.5, -1.5), c.accent, 2, 90, 0.18, 0.25, 45)
		Fx.Slash(CFrame.lookAt(c.cf.Position, tr.Position) * CFrame.new(0, 0.5, -1.5), c.accent, 2, 90, 0.18, 0.25, -45)
	end
end

----------------------------------------------------------------------------
-- sounds (ids + layers: Shared.AudioConfig; played through Shared.Audio)
-- 3D at the champion, so nearby players hear each other's fights fade with distance.
-- Other players' champions are quieter, and their basic attacks are silent (crowds get loud).
----------------------------------------------------------------------------
local layerCache: { [string]: { [string]: string } } = {}
local function abilityLayers(id: string): { [string]: string }
	local cached = layerCache[id]
	if cached then return cached end
	local info = AbilityInfo[id] or {}
	local base = AudioConfig.StyleAbility[info.style or "punch"] or AudioConfig.StyleAbility.punch
	local layers: { [string]: any } = { windup = AudioConfig.DefaultWindup, move = base.move, impact = base.impact }
	local element = string.lower(tostring(info.element or ""))
	for _, e in AudioConfig.ElementAbility do
		if string.find(element, e.match, 1, true) then
			layers.windup = e.windup or layers.windup
			layers.impact2 = e.impact2
			layers.tail = e.tail
			break
		end
	end
	if AbilityTiming.IsUltimate(id) then
		layers.impact3 = AudioConfig.UltimateImpact
		layers.tail = layers.tail or AudioConfig.UltimateTail
	end
	for k, v in AudioConfig.ChampionAbility[id] or {} do
		layers[k] = if v == false then nil else v
	end
	layerCache[id] = layers
	return layers
end

local function abilitySound(c: Champ, layer: string, opts: { [string]: any }?)
	local name = abilityLayers(c.id)[layer]
	if not name then return end
	local o = if opts then table.clone(opts) else {}
	o.owner = c.owner
	Audio.PlayAt(name, c.root, o)
end

local function attackSound(c: Champ)
	if c.owner ~= localPlayer and not AudioConfig.OtherPlayersAttacks then return end
	local list = AudioConfig.StyleAttack[c.style]
	if not list then return end
	Audio.PlayAt(list[math.random(1, #list)], c.root, { owner = c.owner, volume = AudioConfig.AttackVolume })
end

----------------------------------------------------------------------------
-- abilities
----------------------------------------------------------------------------
local abilityCache = {}
local function abilityFor(id: string)
	if abilityCache[id] == nil then
		local mod = AbilityFolder:FindFirstChild(id)
		local ok, fn = false, nil
		if mod then ok, fn = pcall(require, mod) end
		abilityCache[id] = ok and fn or false
	end
	return abilityCache[id] or nil
end

-- Other players' champions get this dimmed copy of Fx, so a crowded fight stays readable
-- (and cheap): 40 % of the particles, no floating text, no screen flash/shake, lighter
-- lightning and spikes. Every other function is the normal Fx (looked up via __index).
-- Your own champions always get the full Fx.
local DimFx = setmetatable({}, { __index = Fx })
function DimFx.Particles(pos, opts)
	local dimmed = table.clone(opts or {})
	dimmed.count = math.max(1, math.round((dimmed.count or 12) * 0.4))
	return Fx.Particles(pos, dimmed)
end
function DimFx.Callout() end
function DimFx.Flash() end
function DimFx.Shake() end
function DimFx.Lightning(from, to, color, segments, duration, width)
	return Fx.Lightning(from, to, color, math.max(2, math.round((segments or 8) * 0.6)), duration, (width or 0.25) * 0.75)
end
function DimFx.Spikes(pos, color, count, height, duration, radius)
	return Fx.Spikes(pos, color, math.max(2, math.round((count or 6) * 0.5)), height, duration, radius)
end

-- "Gentle on the eyes" (animation brief): every screen shake and flash an ability asks for
-- goes through these two, so no module can overdo it: shake <= 0.35, flash <= 0.35 alpha and
-- <= 0.15 s, and never more than 3 flashes a second (no strobing).
local MAX_SHAKE = 0.35
local MAX_FLASH_ALPHA = 0.35
local MAX_FLASH_TIME = 0.15
local MIN_FLASH_GAP = 1 / 3 -- seconds between two flashes (= at most 3 per second)
local lastFlashAt = -math.huge
local function gentleShake(amount: number?, duration: number?)
	Fx.Shake(math.min(tonumber(amount) or 0.3, MAX_SHAKE), duration)
end
local function gentleFlash(color: any, alpha: number?, duration: number?)
	local now = os.clock()
	if now - lastFlashAt < MIN_FLASH_GAP then return end -- too soon after the last one: skip it
	lastFlashAt = now
	Fx.Flash(color, math.min(tonumber(alpha) or 0.4, MAX_FLASH_ALPHA), math.min(tonumber(duration) or 0.25, MAX_FLASH_TIME))
end

-- Each cast gets its own small Fx wrapper (ctx.Fx):
--  * your own champions: the full Fx, with flash/shake going through the gentle caps above
--  * other players' champions: the dimmed DimFx
--  * every Fx.Part the ability module makes is remembered in `made`, so if the module errors
--    halfway, its props (leaves, orbs, blades...) can still be swept away
local function makeCastFx(isMine: boolean)
	local base = if isMine then Fx else DimFx
	local made: { BasePart } = {}
	local castFx: any = setmetatable({}, { __index = base })
	function castFx.Part(props)
		local p = base.Part(props)
		table.insert(made, p)
		return p
	end
	if isMine then
		castFx.Flash = gentleFlash
		castFx.Shake = gentleShake
	end
	return castFx, made
end

-- Fades out and removes the parts a crashed ability module left behind.
local function sweepParts(parts: { BasePart })
	for _, p in parts do
		if p.Parent then
			TweenService:Create(p, TweenInfo.new(0.15), { Transparency = 1 }):Play()
			task.delay(0.2, function() p:Destroy() end)
		end
	end
end

local HIT_STOP = 0.06 -- seconds the caster's pose freezes when its ability lands (owner only)

local function makeCtx(c: Champ, target: Model, amount: number, impactTime: number)
	local info = AbilityInfo[c.id] or {}
	local palette = {}
	for _, h in info.palette or { "#ffffff" } do table.insert(palette, Color3.fromHex(h)) end
	local ctx = {}
	ctx.id = c.id
	ctx.rig = c.rig
	ctx.model = c.model
	ctx.root = c.root
	ctx.target = target
	ctx.palette = palette
	ctx.accent = palette[1] or c.accent
	ctx.isMine = c.owner == localPlayer
	-- other players' abilities use the dimmed effects; ctx.madeParts = the module's own props
	ctx.Fx, ctx.madeParts = makeCastFx(ctx.isMine)
	ctx.Anim, ctx.P, ctx.R, ctx.T = Anim, P, R, T
	ctx.impactTime = impactTime
	ctx.startedAt = os.clock() -- (the cast's start: impactTime counts from here)
	ctx.part = function(name: string) return c.model:FindFirstChild(name) end
	ctx.weapon = function() return weaponPart(c.model, "RightHand") or weaponPart(c.model, "LeftHand") end
	ctx.targetPos = function(): Vector3
		local tr = target.PrimaryPart
		return tr and tr.Position or c.cf.Position + c.cf.LookVector * 5
	end
	ctx.targetGround = function(): Vector3
		local p = ctx.targetPos()
		return Vector3.new(p.X, p.Y - (target:GetAttribute("GroundOffset") or 3), p.Z)
	end
	ctx.targetTop = function(): Vector3 return ctx.targetPos() + Vector3.new(0, target:GetAttribute("TopOffset") or 3, 0) end
	ctx.myPos = function(): Vector3 return c.cf.Position end
	ctx.ground = function(): Vector3 return c.cf.Position - Vector3.new(0, GROUND, 0) end
	ctx.wait = function(t: number) task.wait(t) end
	-- blend to a pose over `duration` seconds
	ctx.pose = function(pose, duration: number?, ease: string?)
		local from = table.clone(c.rig.current)
		local d = duration or 0.15
		local start = os.clock()
		local f = Anim.EASE[ease or "out"] or Anim.EASE.out
		while os.clock() - start < d do
			local k = f(math.clamp((os.clock() - start) / d, 0, 1))
			blendPose(c, Anim.Mix(from, pose, k), 1)
			RunService.RenderStepped:Wait()
		end
		while isHeld(c) do RunService.RenderStepped:Wait() end -- let a hit-stop finish before the final snap
		Anim.Blend(c.rig, pose, 1)
	end
	ctx.play = function(clip) runClip(c, clip) end
	-- move the champion (root position) to `pos` over `duration`, with an optional jump arc
	ctx.moveTo = function(pos: Vector3, duration: number?, arc: number?)
		local from = c.cf.Position
		local d = duration or 0.2
		local start = os.clock()
		while true do
			local k = math.clamp((os.clock() - start) / d, 0, 1)
			local e = 1 - (1 - k) ^ 2
			local p = from:Lerp(pos, e) + Vector3.new(0, math.sin(math.pi * k) * (arc or 0), 0)
			local look = ctx.targetPos()
			c.cf = CFrame.lookAt(p, Vector3.new(look.X, p.Y, look.Z))
			if k >= 1 then break end
			RunService.RenderStepped:Wait()
		end
	end
	ctx.home = function(): Vector3
		local list = champs[c.owner] or {}
		return attackSpot(c, target, #list)
	end
	ctx.face = function(pos: Vector3)
		c.cf = CFrame.lookAt(c.cf.Position, Vector3.new(pos.X, c.cf.Y, pos.Z))
	end
	ctx.spin = function(degrees: number, duration: number)
		local start, base = os.clock(), c.cf
		while os.clock() - start < duration do
			local k = (os.clock() - start) / duration
			c.cf = base * CFrame.Angles(0, math.rad(degrees * k), 0)
			RunService.RenderStepped:Wait()
		end
		c.cf = base * CFrame.Angles(0, math.rad(degrees), 0)
	end
	local impacted = false
	-- (ctx.telegraph = this cast's ground marker; startCastFx sets it)
	ctx.impact = function()
		if impacted then return end
		impacted = true
		-- the marker flashes white as the hit lands (first, so nothing below can stop it)
		if ctx.telegraph then ctx.telegraph.Impact() end
		hitReact(c, target, amount, true)
		-- impact sound layers, landing exactly with the damage (impact2/3 = element + ultimate weight)
		abilitySound(c, "impact")
		abilitySound(c, "impact2", { volume = 0.85 })
		abilitySound(c, "impact3", { volume = 0.8 })
		abilitySound(c, "tail", { volume = 0.7, delay = 0.18 })
		if ctx.isMine then
			-- bigger abilities shake a little more, but never past the gentle cap
			gentleShake(0.1 + (tonumber(info.shake) or 0.3) * 0.27, 0.3)
			-- impact frame (your own champions only): freeze the pose for a blink + a white star on the target
			c.holdUntil = os.clock() + HIT_STOP
			local tr = target.PrimaryPart
			if target.Parent and tr then
				local toward = (c.cf.Position - tr.Position) * Vector3.new(1, 0, 1)
				local front = if toward.Magnitude > 0.01 then toward.Unit * 1.2 else Vector3.zero
				Fx.ImpactStar(tr.Position + front, Color3.new(1, 1, 1))
			end
		end
	end
	ctx.callout = function(text: string?)
		-- through ctx.Fx, so other players' champions show no floating text (dimmed Fx)
		ctx.Fx.Callout(c.cf.Position + Vector3.new(0, 4.5, 0), text or info.name or "Ability!", ctx.accent, 1.2, 1.2)
	end
	-- screen shake / flash: your own champions only, always within the gentle caps
	ctx.shake = function(a: number, d: number?) if ctx.isMine then gentleShake(a, d) end end
	ctx.flash = function(color, alpha: number?, d: number?) if ctx.isMine then gentleFlash(color, alpha, d) end end
	return ctx
end

----------------------------------------------------------------------------
-- ability animation language (wraps ALL 21 ability modules, no module edits)
--   anticipation: a ground telegraph at the target + a glint at the weapon
--   ultimate (Legendary/Mythic champions, owner only): cut-in strip + tiny FOV punch
--   impact: see ctx.impact above (telegraph flash, hit-stop, impact star)
----------------------------------------------------------------------------
local TELEGRAPH_DEFAULT = { active = 5, ultimate = 8 } -- studs, if AbilityInfo has no telegraphRadius

-- One marker per enemy: when a whole team casts at once, 7 rings stacked on one target read
-- as noise. A new marker only appears when the target has none, the current one is about to
-- land, or the new one matters more (yours over other players', ultimate over active).
local TELEGRAPH_OVERLAP = 0.35 -- seconds: a marker this close to landing no longer blocks a new one
local activeTelegraph: { [Model]: { handle: any, landsAt: number, priority: number } } = setmetatable({}, { __mode = "k" }) :: any
local function claimTelegraph(target: Model, priority: number): boolean
	local cur = activeTelegraph[target]
	if not cur or not cur.handle.part.Parent then return true end
	if priority > cur.priority then
		cur.handle.Destroy() -- the more important cast takes the spot
		return true
	end
	return os.clock() >= cur.landsAt - TELEGRAPH_OVERLAP
end

-- Legendary and Mythic champions have "ultimates". Checked by rarity NAME (never rank
-- numbers), so adding a new tier later can't change who has one.
local function isUltimate(id: string): boolean
	local def = Config.ChampionById[id]
	if not def or type(Config.RarityAtLeast) ~= "function" then return false end
	return Config.RarityAtLeast(def.rarity, "Legendary")
end

-- Is a summon on screen? Then the summon owns the camera and the screen, so there is no
-- cut-in and no FOV punch. That is while SummonCinematic plays or holds its lineup, and while
-- the HUD's result screen is open (the HUD sets the "SummonResultsOpen" player attribute).
-- SummonCinematic may not exist yet, so it is required lazily and safely.
local summonCinematic: any = nil -- nil = not found yet, false = can't be used
local function askCinematic(fnName: string): boolean
	local fn = summonCinematic and summonCinematic[fnName]
	if type(fn) ~= "function" then return false end
	local ok, answer = pcall(fn)
	return ok and answer == true
end
local function summonBusy(): boolean
	if localPlayer:GetAttribute("SummonResultsOpen") == true then return true end
	if summonCinematic == nil then
		local mod = Shared:FindFirstChild("SummonCinematic")
		if not mod then return false end -- not built yet: nothing can be playing (we look again next time)
		local ok, result = pcall(require, mod)
		summonCinematic = if ok and type(result) == "table" then result else false
	end
	return askCinematic("IsPlaying") or askCinematic("IsHolding")
end

-- FOV punch: the camera zooms in 3 degrees over 0.15 s, then eases back over 0.35 s.
-- While a punch runs, the camera's true FOV is kept in its "FovPunchBase" attribute, so
-- anything that saves the FOV mid-punch can read the real value.
local FOV_PUNCH = { amount = 3, inTime = 0.15, outTime = 0.35 }
local fovPunchId = 0
local fovBase: number? = nil
local fovTween: Tween? = nil

local function tweenFov(cam: Camera, goal: number, t: number, style: Enum.EasingStyle, dir: Enum.EasingDirection)
	if fovTween then fovTween:Cancel() end
	local tw = TweenService:Create(cam, TweenInfo.new(t, style, dir), { FieldOfView = goal })
	fovTween = tw
	tw:Play()
end

-- A summon that starts DURING a punch saves the zoomed-in FOV and puts that back when it
-- ends. So once the summon is over, we put the true FOV back (only if it is still off by no
-- more than the punch, so we never undo anyone else's FOV change).
local function fixFovAfterSummon(cam: Camera, base: number)
	local waited = 0
	while summonBusy() and waited < 300 do waited += task.wait(0.25) end
	local off = base - cam.FieldOfView
	if off > 0.01 and off <= FOV_PUNCH.amount + 0.01 then cam.FieldOfView = base end
end

local function fovPunch()
	local cam = workspace.CurrentCamera
	if not cam then return end
	fovPunchId += 1
	local myId = fovPunchId
	fovBase = fovBase or cam.FieldOfView -- a punch that is still running keeps the TRUE base
	local base = fovBase :: number
	cam:SetAttribute("FovPunchBase", base)
	tweenFov(cam, base - FOV_PUNCH.amount, FOV_PUNCH.inTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- watch the punch frame by frame: ease back at the right moment, and get out of the
	-- way at once if a summon starts (it takes over the camera)
	local start, easingBack = os.clock(), false
	while os.clock() - start < FOV_PUNCH.inTime + FOV_PUNCH.outTime do
		if myId ~= fovPunchId then return end -- a newer punch took over (it keeps the true base)
		if summonBusy() then
			if fovTween then fovTween:Cancel() end
			fixFovAfterSummon(cam, base)
			break
		end
		if not easingBack and os.clock() - start >= FOV_PUNCH.inTime then
			easingBack = true
			tweenFov(cam, base, FOV_PUNCH.outTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
		RunService.RenderStepped:Wait()
	end
	if myId == fovPunchId then
		fovBase = nil
		cam:SetAttribute("FovPunchBase", nil)
	end
end

-- Ultimate cut-in (owner only): a thin diagonal band in the ability's colours with the
-- champion name and the ability name. It slides in from the left, holds, slides back out
-- (0.6 s in total). It sits top-left, well away from the screen centre, in its own
-- ScreenGui drawn BELOW the HUD and the summon UI (DisplayOrder -1, the HUD is 0).
-- Only one at a time: a newer cut-in replaces the older one.
local CUT_IN = { y = 0.16, width = 0.38, height = 0.085, tilt = -5, slideIn = 0.12, hold = 0.33, slideOut = 0.15 }
local cutInGui: ScreenGui? = nil

local function showCutIn(c: Champ, ctx: any)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	if not cutInGui or not cutInGui.Parent then
		local g = Instance.new("ScreenGui")
		g.Name = "AbilityCutIn"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = -1 -- below the HUD (0) and the summon UI, so those always win
		g.Parent = playerGui
		cutInGui = g
	end
	local gui = cutInGui :: ScreenGui
	gui:ClearAllChildren() -- a newer cut-in replaces the older one

	local info = AbilityInfo[c.id] or {}
	local def = Config.ChampionById[c.id]
	local main = ctx.palette[1] or ctx.accent
	local edgeColor = ctx.palette[3] or Color3.new(1, 1, 1)
	local dark = main:Lerp(Color3.new(0, 0, 0), 0.45)
	-- the band (and its edges) fade out toward the screen centre
	local fadeRight = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.75, 0.1), NumberSequenceKeypoint.new(1, 1) })

	local hidden = UDim2.fromScale(-CUT_IN.width - 0.1, CUT_IN.y)
	local shown = UDim2.fromScale(-0.02, CUT_IN.y)
	local band = Instance.new("Frame")
	band.Name = "CutIn"
	band.AnchorPoint = Vector2.new(0, 0.5)
	band.Position = hidden
	band.Size = UDim2.fromScale(CUT_IN.width, CUT_IN.height)
	band.Rotation = CUT_IN.tilt
	band.BackgroundColor3 = Color3.new(1, 1, 1)
	band.BorderSizePixel = 0
	local minSize = Instance.new("UISizeConstraint") -- stays readable on small phone screens
	minSize.MinSize = Vector2.new(230, 42)
	minSize.Parent = band
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(dark, main)
	grad.Transparency = fadeRight
	grad.Parent = band
	for _, y in { 0, 1 } do -- thin bright edges, top and bottom
		local edge = Instance.new("Frame")
		edge.AnchorPoint = Vector2.new(0, y)
		edge.Position = UDim2.fromScale(0, y)
		edge.Size = UDim2.fromScale(1, 0.08)
		edge.BackgroundColor3 = edgeColor
		edge.BorderSizePixel = 0
		local eg = Instance.new("UIGradient")
		eg.Transparency = fadeRight
		eg.Parent = edge
		edge.Parent = band
	end
	-- a soft white sheen sweeps across it once
	local sheen = Instance.new("Frame")
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BorderSizePixel = 0
	local sheenGrad = Instance.new("UIGradient")
	sheenGrad.Rotation = 20
	sheenGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) })
	sheenGrad.Offset = Vector2.new(-0.7, 0)
	sheenGrad.Parent = sheen
	sheen.Parent = band
	-- champion name (small) above the ability name (big)
	local function text(name: string, str: string, y: number, h: number, color: Color3)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.1, y)
		t.Size = UDim2.fromScale(0.8, h)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = color
		t.Text = str
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Color = Color3.new(0, 0, 0)
		s.Transparency = 0.25
		s.Parent = t
		t.Parent = band
	end
	text("Champion", if def then labelText(c.owner, c.slot, def) else c.id, 0.1, 0.32, edgeColor:Lerp(Color3.new(1, 1, 1), 0.6))
	text("Ability", string.upper(info.name or "Ultimate"), 0.4, 0.5, Color3.new(1, 1, 1))
	band.Parent = gui

	-- slide in, hold, slide back out, then remove it
	TweenService:Create(band, TweenInfo.new(CUT_IN.slideIn, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = shown }):Play()
	TweenService:Create(sheenGrad, TweenInfo.new(CUT_IN.slideIn + CUT_IN.hold, Enum.EasingStyle.Sine), { Offset = Vector2.new(0.7, 0) }):Play()
	task.delay(CUT_IN.slideIn + CUT_IN.hold, function()
		if band.Parent then
			TweenService:Create(band, TweenInfo.new(CUT_IN.slideOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = hidden }):Play()
		end
	end)
	task.delay(CUT_IN.slideIn + CUT_IN.hold + CUT_IN.slideOut + 0.05, function() band:Destroy() end)
end

-- The owner's "ultimate!" moment: cut-in strip + FOV punch (skipped while a summon or
-- its result screen is on screen).
local function playUltimateIntro(c: Champ, ctx: any)
	if summonBusy() then return end
	showCutIn(c, ctx)
	fovPunch()
end

-- Called once when an ability starts: telegraph + glint (+ the ultimate intro).
local function startCastFx(c: Champ, ctx: any, impactTime: number)
	local info = AbilityInfo[c.id] or {}
	local ultimate = isUltimate(c.id)
	local style = if ultimate then "ultimate" else "active"
	-- 1) telegraph at the target: the ring says WHERE, the filling disc says WHEN
	local radius = tonumber(info.telegraphRadius) or TELEGRAPH_DEFAULT[style]
	local enemyRadius = tonumber(ctx.target:GetAttribute("Radius")) or 2
	radius = math.max(radius, enemyRadius + 1.5) -- never hidden under a big enemy (bosses)
	local priority = (if ctx.isMine then 2 else 0) + (if ultimate then 1 else 0)
	if claimTelegraph(ctx.target, priority) then
		ctx.telegraph = Fx.Telegraph(ctx.targetGround(), radius, ctx.accent, impactTime, style, { dim = not ctx.isMine })
		activeTelegraph[ctx.target] = { handle = ctx.telegraph, landsAt = os.clock() + impactTime, priority = priority }
	end
	-- 2) anticipation glint at the weapon (or the hand): "something's coming"
	Fx.Glint(ctx.weapon() or ctx.part("RightHand") or c.root, ctx.accent)
	-- 3) ultimates: cut-in + FOV punch, only on the owner's own screen
	--    (own thread: the first call may have to require SummonCinematic)
	if ultimate and ctx.isMine and not ctx.lite then task.spawn(playUltimateIntro, c, ctx) end
end

----------------------------------------------------------------------------
-- ability staging (Shared.AbilityTiming): anticipation -> step back -> power-up, then the
-- module, then recovery. All of it is visual: the server already decided the hit and its time.
----------------------------------------------------------------------------
local STAGE_POSE = {
	antic = Anim.Mix(P.guard, P.crouch, 0.45),
	step = { Root = T(0, -0.25, 0, 6), Waist = R(8), RightHip = R(-28), RightKnee = R(-30), LeftHip = R(35), LeftKnee = R(-45),
		RightShoulder = R(35, 0, 10), RightElbow = R(70), LeftShoulder = R(35, 0, -10), LeftElbow = R(70) },
	hopUp = P.jump,
	hopLand = P.land,
	slide = { Root = T(0, -0.9, 0, 14), Waist = R(-10), RightHip = R(70), RightKnee = R(-95), LeftHip = R(-10), LeftKnee = R(-20),
		RightShoulder = R(40, 0, 40), LeftShoulder = R(70, 0, -50), LeftElbow = R(30) },
	dash = { Root = T(0, -0.4, 0, 16), Waist = R(-12), RightShoulder = R(-30, 0, 20), LeftShoulder = R(-30, 0, -20),
		RightHip = R(30), RightKnee = R(-50), LeftHip = R(-25) },
	tuck = { Root = T(0, 0.3, 0), RightHip = R(90), LeftHip = R(90), RightKnee = R(-110), LeftKnee = R(-110),
		RightShoulder = R(60, 0, 10), LeftShoulder = R(60, 0, -10), RightElbow = R(60), LeftElbow = R(60) },
	glide = { Root = T(0, 0.25, 0, 6), Neck = R(-8), RightShoulder = R(20, 0, 50), LeftShoulder = R(20, 0, -50),
		RightHip = R(10), LeftHip = R(-5), RightKnee = R(-25), LeftKnee = R(-10) },
	blink = P.crouch,
}
-- the power-up stance, by weapon style
local POWER_POSE = {
	punch = { Root = T(0, -0.5, 0, -6), Waist = R(-8), RightShoulder = R(20, 0, 25), RightElbow = R(120), LeftShoulder = R(20, 0, -25), LeftElbow = R(120),
		RightHip = R(40), LeftHip = R(40), RightKnee = R(-60), LeftKnee = R(-60) },
	sword = P.slashWind, claws = P.clawWind, hammer = P.overWind, wrench = P.overWind,
	spear = P.thrustWind, trident = P.thrustWind, staff = P.castRaise, magic = P.castRaise, bow = P.bowDraw,
}
POWER_POSE.kick = POWER_POSE.punch

local function flatUnit(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.05 then f.Unit else nil
end

-- What the safety rays may hit: the world only (never champions, players, enemies or effects).
local function stageRayParams(): RaycastParams
	local ignore: { Instance } = { folder, enemies }
	local fx = workspace:FindFirstChild("ClientEffects")
	if fx then table.insert(ignore, fx) end
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.IgnoreWater = false
	return rp
end

-- Where to step back to, or nil when there's no safe spot (then the champion braces in place).
-- Safe = no wall in the way, ground under the new spot at about the same height, not inside
-- its owner's personal space and not on top of a teammate.
local function safeRetreat(c: Champ, target: Model, back: number): Vector3?
	local pos = c.cf.Position
	local tp = target.PrimaryPart and target.PrimaryPart.Position or pos + c.cf.LookVector * 5
	local away = flatUnit(pos - tp) or flatUnit(-c.cf.LookVector) or Vector3.zAxis
	local rp = stageRayParams()
	local owner = c.owner.Character and c.owner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local mates = champs[c.owner] or {}
	local feetY = pos.Y - GROUND
	local best: Vector3? = nil
	local bestDist = 0
	for _, angle in { 0, 30, -30, 55, -55 } do
		local dir = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(away)
		local dist = back
		-- 1) walls: a ray at chest height, then shorten to stop short of what it hits
		local wall = workspace:Raycast(pos + Vector3.new(0, 0.5, 0), dir * (back + 1), rp)
		if wall then dist = math.min(dist, wall.Distance - 1.2) end
		-- 2) ground: shrink the step until there's floor under it at about the same height
		local spot: Vector3? = nil
		while dist >= 1.5 do
			local candidate = pos + dir * dist
			local floor = workspace:Raycast(candidate + Vector3.new(0, 3, 0), Vector3.new(0, -(GROUND + 6), 0), rp)
			if floor and math.abs(floor.Position.Y - feetY) <= 2 then
				spot = candidate
				break
			end
			dist -= 0.75
		end
		if spot then
			-- 3) keep out of the owner's space and off teammates
			if owner then spot = keepClearOfOwner(spot, owner.Position) end
			local crowded = false
			for _, m in mates do
				if m ~= c and (Vector3.new(m.cf.X, 0, m.cf.Z) - Vector3.new(spot.X, 0, spot.Z)).Magnitude < 2.2 then crowded = true end
			end
			if not crowded and dist > bestDist then
				best, bestDist = spot, dist
				if dist >= back - 0.01 then break end -- the full step straight back: perfect
			end
		end
	end
	return best
end

-- the step back itself: path, body pose and a little dust / light per style
local function retreatMove(c: Champ, ctx: any, dest: Vector3, style: string, duration: number)
	local from = c.cf.Position
	local arc = ({ hop = 1.3, leap = 2.6, glide = 0.8 } :: any)[style] or 0
	local ease = if style == "dash" or style == "blink" then Anim.EASE.snap elseif style == "glide" then Anim.EASE.inout else Anim.EASE.out
	local Fx_ = ctx.Fx
	local feet = ctx.ground() + Vector3.new(0, 0.3, 0)
	if style == "slide" or style == "step" or style == "hop" or style == "leap" then
		Fx_.Particles(feet, { color = Color3.fromRGB(216, 203, 176), count = if style == "slide" then 12 else 6, speed = 7, size = 0.6, lifetime = 0.4, spread = 70, light = 0 })
	end
	if style == "dash" then Fx_.Trail(c.root, ctx.accent, duration + 0.15, 0.9) end
	if style == "glide" then Fx_.Particles(c.cf.Position, { color = ctx.accent, count = 10, speed = 3, size = 0.35, lifetime = 0.6, spread = 180, gravity = -3 }) end
	if style == "blink" then Fx_.Burst(c.cf.Position, ctx.accent, 4, 0.25) end
	local start = os.clock()
	while true do
		local k = math.clamp((os.clock() - start) / duration, 0, 1)
		local e = ease(k)
		local p = from:Lerp(dest, e) + Vector3.new(0, math.sin(math.pi * k) * arc, 0)
		local look = ctx.targetPos()
		local cf = CFrame.lookAt(p, Vector3.new(look.X, p.Y, look.Z))
		if style == "leap" then cf *= CFrame.Angles(Anim.EASE.inout(k) * math.pi * 2, 0, 0) end -- a backflip
		c.cf = cf
		local pose = if style == "hop" then (if k < 0.55 then STAGE_POSE.hopUp else STAGE_POSE.hopLand)
			elseif style == "leap" then (if k < 0.85 then STAGE_POSE.tuck else STAGE_POSE.hopLand)
			else STAGE_POSE[style] or STAGE_POSE.step
		blendPose(c, pose, 0.3)
		if k >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	if style == "hop" or style == "leap" then Fx_.Ring(CFrame.new(ctx.ground() + Vector3.new(0, 0.15, 0)), Color3.new(1, 1, 1), 1.5, 5, 0.3, 0.12) end
	if style == "blink" then Fx_.Burst(c.cf.Position, ctx.accent, 4, 0.25) end
	if style == "slide" then Fx_.Particles(ctx.ground() + Vector3.new(0, 0.3, 0), { color = Color3.fromRGB(216, 203, 176), count = 8, speed = 5, size = 0.6, lifetime = 0.35, spread = 60, light = 0 }) end
end

-- energy gathers in the champion's colours (lite = the ring only)
local function powerUpFx(c: Champ, ctx: any, timing: any)
	local Fx_ = ctx.Fx
	local d = timing.powerUp
	local accent = ctx.accent
	Fx_.Ring(CFrame.new(ctx.ground() + Vector3.new(0, 0.12, 0)), accent, if timing.ultimate then 10 else 7, 1.5, d * 0.85, 0.14)
	if ctx.lite then return end
	local focusPart = ctx.weapon() or ctx.part("RightHand") or c.root
	local count = (if timing.ultimate then 12 else 7) * (if ctx.isMine then 1 else 0.5)
	for i = 1, math.max(2, math.floor(count)) do
		local dir = CFrame.Angles(0, math.random() * math.pi * 2, 0):VectorToWorldSpace(Vector3.new(0, 0, 1))
		local from = c.cf.Position + dir * (3 + math.random() * 1.5) + Vector3.new(0, math.random() * 3 - 1, 0)
		local orb = Fx_.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.35, Color = ctx.palette[(i % #ctx.palette) + 1] or accent, CFrame = CFrame.new(from) })
		local delay = (i / count) * d * 0.4
		task.delay(delay, function()
			if not orb.Parent then return end
			local to = if focusPart and focusPart.Parent then focusPart.Position else c.cf.Position
			Fx.Tween(orb, math.max(0.12, d * 0.55), { CFrame = CFrame.new(to), Size = Vector3.one * 0.12, Transparency = 0.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(math.max(0.12, d * 0.55), function() orb:Destroy() end)
		end)
	end
	Fx_.Light(c.cf.Position, accent, if timing.ultimate then 14 else 9, if timing.ultimate then 3 else 1.8, d)
	task.delay(d * 0.5, function() if c.model.Parent then Fx_.HitFlash(c.model, accent, 0.15) end end)
	if timing.ultimate then
		task.delay(d * 0.8, function()
			if not c.model.Parent then return end
			Fx_.Pillar(ctx.ground(), accent, 14, 1.4, 0.45)
			Fx_.Shockwave(ctx.ground(), accent, 4, 0.4)
			ctx.shake(0.12, 0.25)
		end)
	end
	task.delay(d * 0.85, function() if focusPart and focusPart.Parent then Fx_.Glint(focusPart, ctx.palette[3] or Color3.new(1, 1, 1)) end end)
end

-- 1-3: anticipation, step back, power-up. Takes `lead` seconds (the server's timing).
local function prelude(c: Champ, ctx: any, timing: any, lead: number)
	local t0 = os.clock()
	local function untilT(t: number) local d = t - (os.clock() - t0); if d > 0 then task.wait(d) end end
	local scale = if timing.lead > 0 then lead / timing.lead else 1
	-- 1) anticipation: face the target and coil
	ctx.face(ctx.targetPos())
	task.spawn(ctx.pose, STAGE_POSE.antic, timing.anticipation * scale * 0.9, "out")
	untilT(timing.anticipation * scale)
	-- 2) the step back (or a brace in place when there's no safe spot)
	local retreatTime = timing.retreat * scale
	local dest = if retreatTime > 0.05 then safeRetreat(c, ctx.target, timing.back) else nil
	if dest then
		abilitySound(c, "move", { volume = 0.8 })
		retreatMove(c, ctx, dest, timing.approach, retreatTime)
	else
		task.spawn(ctx.pose, STAGE_POSE.step, retreatTime, "out")
	end
	untilT((timing.anticipation + timing.retreat) * scale)
	-- 3) power-up
	task.spawn(ctx.pose, POWER_POSE[c.style] or P.castRaise, math.min(0.25, timing.powerUp * scale), "out")
	powerUpFx(c, ctx, { powerUp = timing.powerUp * scale, ultimate = timing.ultimate })
	untilT(lead)
end

-- 5: settle into the guard and walk back to the attack spot
local function recover(c: Champ, ctx: any, timing: any)
	task.spawn(ctx.pose, P.guard, 0.3, "inout")
	local ok, home = pcall(ctx.home)
	if ok and typeof(home) == "Vector3" and (home - c.cf.Position).Magnitude > 0.6 then
		ctx.moveTo(home, timing.recover * 0.85)
	else
		task.wait(timing.recover * 0.6)
	end
end

-- "Lite" or no module: a simple, readable move: power pose, close in, one strong strike.
local function simpleMove(c: Champ, ctx: any, untilImpact: number)
	ctx.callout()
	local t0 = os.clock()
	local closeIn = math.max(0, untilImpact - 0.45)
	if closeIn > 0 then task.wait(closeIn) end
	local ok, home = pcall(ctx.home)
	if ok and typeof(home) == "Vector3" then ctx.moveTo(home, 0.22) end
	local left = untilImpact - (os.clock() - t0) - 0.2
	if left > 0 then task.wait(left) end
	local clip = ATTACK[c.style] or ATTACK.punch
	clip(c, ctx.target, 1)
end

-- Abilities hidden by Settings (Show My / Other Abilities off): it looks like a normal hit
-- at the same moment the damage lands.
local function plainAbility(c: Champ, target: Model, amount: number, impactTime: number)
	local clip = ATTACK[c.style] or ATTACK.punch
	task.wait(math.max(0, impactTime - Config.Combat.AttackImpact))
	task.delay(Config.Combat.AttackImpact, function()
		if target.Parent then
			attackImpactFx(c, target)
			hitReact(c, target, amount, false)
			attackSound(c)
		end
	end)
	clip(c, target, 1)
end

----------------------------------------------------------------------------
-- server events
----------------------------------------------------------------------------
Remotes:WaitForChild("ChampionAction").OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" or typeof(msg.u) ~= "number" then return end
	local owner = Players:GetPlayerByUserId(msg.u)
	local list = owner and champs[owner]
	local c = list and list[msg.s]
	if not c or c.id ~= msg.c then return end
	-- update the ability bar first, even if this client can't see the enemy right now
	if msg.k == "attack" then
		setBar(c, tonumber(msg.h) or 0) -- server sends h = hits so far (1..5)
	else
		drainBar(c) -- ability: the bar visibly empties; basic hits refill it one segment each
	end
	local target = typeof(msg.tg) == "string" and enemies:FindFirstChild(msg.tg)
	if not target or not target.PrimaryPart then return end
	if msg.k == "attack" then
		if c.busy then return end
		c.busy = true
		task.spawn(function()
			local style = ATTACK[c.style] or ATTACK.punch
			task.delay(msg.it, function()
				if target.Parent then
					attackImpactFx(c, target)
					hitReact(c, target, msg.a, false)
					attackSound(c)
				end
			end)
			style(c, target, msg.h)
			c.busy = false
		end)
	else -- ability
		local timing = AbilityTiming.For(c.id)
		-- msg.it = when the server lands the hit. It wins: if it ever disagrees with our timing,
		-- the step back and power-up shrink (or grow) so the module's impact still lines up.
		local impactTime = math.clamp(tonumber(msg.it) or timing.impact, 0.05, 8)
		local lead = math.clamp(impactTime - timing.moduleImpact, 0, timing.lead * 1.5)
		c.busy = true
		c.castId += 1
		local castId = c.castId
		c.actionUntil = os.clock() + (impactTime - timing.impact) + timing.duration + 0.25
		local function done()
			if c.castId == castId then c.busy = false end
		end
		task.spawn(function()
			local isMine = c.owner == localPlayer
			local show = if isMine then pref("ShowMyAbilities") ~= false else pref("ShowOtherAbilities") ~= false
			if not show then
				pcall(plainAbility, c, target, msg.a, impactTime)
				done()
				return
			end
			local ctxOk, ctx = pcall(makeCtx, c, target, msg.a, impactTime)
			if not ctxOk then
				warn("[Ability " .. c.id .. "] " .. tostring(ctx))
				done() -- never leave the champion stuck in "busy"
				return
			end
			ctx.lite = pref("LiteAbilityVfx") == true -- (Settings > Disable Ability VFX)
			-- the shared animation language (telegraph, glint, ultimate cut-in) for every ability;
			-- in a pcall so a visual hiccup can never stop the ability itself
			local castOk, castErr = pcall(startCastFx, c, ctx, impactTime)
			if not castOk then warn("[Ability FX " .. c.id .. "] " .. tostring(castErr)) end
			task.delay(impactTime + 0.05, function() ctx.impact() end) -- safety: the hit always lands on time
			abilitySound(c, "windup")
			local preOk, preErr = pcall(prelude, c, ctx, timing, lead)
			if not preOk then warn("[Ability prelude " .. c.id .. "] " .. tostring(preErr)) end
			local fn = if ctx.lite then nil else abilityFor(c.id)
			local untilImpact = math.max(0, impactTime - (os.clock() - (ctx.startedAt or os.clock())))
			if fn then
				local ok, err = pcall(fn, ctx)
				if not ok then
					warn("[Ability " .. c.id .. "] " .. tostring(err))
					-- the module crashed halfway: remove its props now (the telegraph removes
					-- itself, and the safety timer above still lands the hit on time)
					sweepParts(ctx.madeParts)
				end
			else
				pcall(simpleMove, c, ctx, untilImpact)
			end
			pcall(recover, c, ctx, timing)
			-- (no setBar(0) here: the bar was drained at the start, and the next hit may
			-- already have refilled a segment)
			done()
		end)
	end
end)

----------------------------------------------------------------------------
-- per-frame movement + idle/run animation
----------------------------------------------------------------------------
-- A champion right next to the camera would show its name + bar huge, covering the
-- screen (the back-row followers stand close to where the camera sits), so its
-- label is hidden while it is closer than this to the camera.
local HUD_HIDE_NEAR_CAMERA = 9
-- (hideAll = a summon is on screen: every champion label goes away, or the name tags would
-- float over the altar and the summoned champion. Checked once per frame below.)
local function updateHud(c: Champ, camPos: Vector3, hideAll: boolean)
	local show = not hideAll and (c.cf.Position - camPos).Magnitude > HUD_HIDE_NEAR_CAMERA
	if c.barGui and c.barGui.Enabled ~= show then c.barGui.Enabled = show end
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local camPos = workspace.CurrentCamera.CFrame.Position
	local summonOnScreen = summonBusy()
	for owner, list in champs do
		local char = owner.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local target = targetOf(owner)
			local n = #list
			for _, c in list do
				if c.busy and os.clock() < c.actionUntil then
					-- ability code is driving the champion
					c.model:PivotTo(c.cf)
					updateHud(c, camPos, summonOnScreen)
					continue
				end
				local spot = if target then attackSpot(c, target, n) else followSpot(c, root)
				local goal = keepClearOfOwner(spot, root.Position)
				local pos = c.cf.Position
				if not c.placed or (goal - pos).Magnitude > 80 then
					-- just built, or left far behind (teleport/respawn): appear at the spot
					c.cf = CFrame.new(goal) * c.cf.Rotation; pos = goal; c.placed = true
				end
				local aim = detour(pos, goal, root.Position, sideOf(c)) -- around the owner, not through
				local delta = (aim - pos)
				local dist = delta.Magnitude
				local speed = math.clamp(dist * 6, 0, target and 42 or 34)
				local step = dist > 0.05 and delta.Unit * math.min(speed * dt, dist) or Vector3.zero
				-- final safety: never step into the owner's personal space
				local newPos = keepClearOfOwner(pos + step, root.Position)
				step = newPos - pos
				-- face the enemy once close, otherwise face where we're running
				local lookDir
				if target and (dist < 6 or c.busy) then
					lookDir = (target.PrimaryPart.Position - newPos) * Vector3.new(1, 0, 1)
				elseif step.Magnitude > 0.01 then
					lookDir = step * Vector3.new(1, 0, 1)
				end
				local rot = c.cf.Rotation
				if lookDir and lookDir.Magnitude > 0.01 then
					local want = CFrame.lookAt(Vector3.zero, lookDir.Unit)
					rot = rot:Lerp(want, math.min(1, dt * 14))
				end
				c.cf = CFrame.new(newPos) * rot
				c.model:PivotTo(c.cf)
				updateHud(c, camPos, summonOnScreen)
				if not c.busy then
					local moving = math.clamp(step.Magnitude / math.max(dt, 1e-3) / 20, 0, 1)
					c.phase += dt * (6 + 8 * moving)
					local base = if target then P.guard else Anim.Idle(t + c.slot)
					local pose = moving > 0.08 and Anim.Mix(base, Anim.Walk(c.phase, moving), math.min(1, moving * 2)) or base
					Anim.Blend(c.rig, pose, math.min(1, dt * 12))
				end
			end
		end
	end
end)
