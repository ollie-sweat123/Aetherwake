-- SummonCinematic (CLIENT ONLY): the anime-style summon at the altar.
--
-- The beats of one summon (lengths come from Shared.SummonTiers: Common ~1.8 s ... Mythic ~8 s):
--   1. CHARGE  the altar wakes up: rings spin up, the sigil lights, energy flows from the floor
--              into the crystal, the scene darkens. Every tier starts the SAME way (so a low roll
--              isn't spoiled); the tier colour creeps in from ~40 % of the charge.
--   2. BUILD   an energy sphere forms in front of the altar, fed by a beam from the crystal, and
--              grows: rings, lightning, runes, light shafts, pillars... depending on the tier.
--   3. REVEAL  the sphere bursts (shockwave + flash per tier) and the champion appears, posed and
--              lit. Rarity pill / name / power appear in fixed screen spots.
--   4. OUTRO   captions fade. The champion(s) stay posed (the "hold") under the HUD's result screen
--              until it closes, then everything is cleaned up.
-- Multi-summon: ONE shared build-up at the best rarity, then one "aether seed" per result flies
-- into a lineup in front of the altar; they bloom from the lowest rarity to the highest.
--
-- API
--   SummonCinematic.Play(results, altar?, opts?) -> "finished" | "skipped" | "aborted" | "error" | "empty"
--       Yields until the presentation ends. results = OpenOrb results { {uid, id, new, rarity, power}, ... }
--       altar = the shrine Model (or its SummonAltar). opts.quick = true: Common/Uncommon single
--       summons play a 1.2 s version. opts.hold = false: clean up right away (no hold).
--   SummonCinematic.Skip() -> boolean        jump to the end (only once CanSkip() is true)
--   SummonCinematic.IsPlaying() / CanSkip() / IsHolding()
--   SummonCinematic.SetSpeed(multiplier) / GetSpeed()   1 = normal, 3 = fast-forward, any moment
--   SummonCinematic.Clear()                  end the hold now: the lineup / posed champion goes away and
--                                            camera + controls come back (the HUD calls it when the result
--                                            screen closes and right before the next summon). Release() and
--                                            ClearLineup() do the same.
--   SummonCinematic.Pulse(altar, rarityId)   cheap 0.6 s altar flash (Auto Hatch; no camera, no UI)
--   SummonCinematic.PlayUiSound("click")
--   SummonCinematic.DebugPreview(rarityId or {rarityIds}, altar?, opts?)   Studio only, fake results
--   SummonCinematic.PhaseChanged             signal(phase): charge, build, reveal, outro, hold, done
--
-- Safety: camera, player controls, lighting, sounds and every effect are put back by ONE cleanup
-- function on finish, skip, death, respawn, teleport or error. Nothing here trusts the results
-- for anything but looks (the server already gave the champions).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local Shared = script.Parent
local SummonTiers = require(Shared:WaitForChild("SummonTiers"))
local Config = require(Shared:WaitForChild("Config"))
local Anim = require(Shared:WaitForChild("Anim"))
local Format = require(Shared:WaitForChild("Format"))

local SummonCinematic = {}

----------------------------------------------------------------------------
-- tuning
----------------------------------------------------------------------------
local CAN_SKIP_AFTER = 0.4  -- seconds into the sequence before Skip() works
local HOLD_MAX = 14         -- the champions stay posed at most this long after Play returns
local HOLD_SCREEN_MAX = 90  -- ...but longer while the HUD says its result screen is open (taps keep it open)
local HOLD_NO_SCREEN = 3    -- ...or only this long if no result screen ever showed up
local LINEUP_GAP = 4        -- studs between champions in a multi-summon lineup
local BLOOM_GAP = 0.35      -- seconds between blooms (Epic+ wait twice as long, low duplicates half)
local SEED_FLIGHT = 0.45    -- seconds a seed flies from the sphere to its spot
local QUICK_TIMES = { charge = 0.35, build = 0.25, reveal = 0.5, outro = 0.1 } -- opts.quick (1.2 s)
local MAX_VOLUME = 0.6
local MAX_FLASH = 0.35      -- screen flash opacity cap (gentle on the eyes)
local MAX_SHAKE = 0.35
local MAX_RESULTS = 10
local STOP = "SummonCinematic:stop" -- thrown by waits when the sequence was skipped/aborted

local EASE = Anim.EASE
local P = Anim.P
local JOINTS = Anim.JOINTS
local ID = CFrame.identity
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GOLD = Color3.fromRGB(255, 205, 70)
local ROLES = { "main", "light", "dark", "glow" }
local NEUTRAL = SummonTiers.neutral or {
	main = Color3.fromRGB(190, 225, 255), light = WHITE, dark = Color3.fromRGB(42, 58, 88), glow = Color3.fromRGB(227, 243, 255),
}
-- tilt (degrees) of each energy ring around the sphere
local RING_TILTS = { { 74, 0, 12 }, { -16, 0, 18 }, { 40, 64, 0 }, { -54, -36, 22 } }
local rng = Random.new()

local speed = 1      -- SetSpeed multiplier
local current = nil  -- the running (or holding) sequence
local counter = 0
local finish         -- (defined further down; used by the frame loop and events)

local phaseEvent = Instance.new("BindableEvent")
SummonCinematic.PhaseChanged = phaseEvent.Event

----------------------------------------------------------------------------
-- tiny helpers
----------------------------------------------------------------------------
local function lerp(a, b, k) return a + (b - a) * k end
local function clamp01(k) return math.clamp(k, 0, 1) end
local function rotY(v, angle) return CFrame.Angles(0, angle, 0) * v end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function easeFn(name) return EASE[name or "out"] or EASE.out end

local function try(what, fn)
	local ok, err = pcall(fn)
	if not ok then warn("[SummonCinematic] " .. what .. ": " .. tostring(err)) end
end

-- name-based tier checks ("is this Epic or better?") so adding tiers never shifts behaviour
local function atLeast(rarityId, threshold)
	local need = SummonTiers.rank(threshold)
	return need > 0 and SummonTiers.rank(rarityId) >= need
end

local function paletteCopy(p)
	return { main = p.main, light = p.light, dark = p.dark, glow = p.glow }
end
local function paletteFrom(c)
	return { main = c, light = c:Lerp(WHITE, 0.65), dark = c:Lerp(BLACK, 0.6), glow = c:Lerp(WHITE, 0.3) }
end

local function effectsRoot()
	local f = workspace:FindFirstChild("ClientEffects")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ClientEffects"
		f.Parent = workspace
	end
	return f
end

-- every effect part is a pure visual: anchored, no collisions, no raycasts, no touches
local function visualOnly(inst)
	local all = inst:GetDescendants()
	table.insert(all, inst)
	for _, d in all do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	return inst
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do (p :: any)[k] = v end
	return visualOnly(p)
end

-- clone ReplicatedStorage.SummonFx/<path> (e.g. "Emitters/Burst"), or build a stand-in if it's missing
local function clone(path, fallback)
	local node = ReplicatedStorage:FindFirstChild("SummonFx")
	for name in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	return visualOnly(if node then node:Clone() else fallback())
end

-- GUI builder: make("TextLabel", { props }, parent)
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do (o :: any)[k] = v end
	if parent then o.Parent = parent end
	return o
end

----------------------------------------------------------------------------
-- the sequence clock: tweens, waits, "later" (all scale with SetSpeed)
----------------------------------------------------------------------------
-- fn(k) is called every frame with the eased progress 0..1 (last call is exactly 1)
local function tween(seq, duration, fn, easeName, delay)
	local a = { start = seq.t + (delay or 0), dur = math.max(duration or 0, 1e-3), fn = fn, ease = easeFn(easeName) }
	table.insert(if seq.iterating then seq.pending else seq.anims, a)
end

-- run fn once, `delay` seconds of sequence time from now
local function later(seq, delay, fn)
	tween(seq, 1e-3, function(k)
		if k >= 1 then fn() end
	end, "linear", delay)
end

-- wait `seconds` of sequence time; throws STOP if the sequence was skipped/aborted meanwhile
local function waitFor(seq, seconds)
	local target = seq.t + seconds
	local realLimit = os.clock() + seconds * 4 + 3 -- safety net in case the frame loop ever died
	while seq.t < target do
		if seq.stop then error(STOP, 0) end
		if os.clock() > realLimit then break end
		task.wait()
	end
	if seq.stop then error(STOP, 0) end
end

local function setPhase(seq, name)
	seq.phase = name
	phaseEvent:Fire(name)
end

-- remember a property of something we don't own, so cleanup can put it back exactly
local function remember(seq, inst, prop)
	local saved = seq.saved[inst]
	if not saved then
		saved = {}
		seq.saved[inst] = saved
	end
	if saved[prop] == nil then saved[prop] = (inst :: any)[prop] end
end

local function move(seq, part, cf)
	local n = #seq.moveParts + 1
	seq.moveParts[n] = part
	seq.moveCFrames[n] = cf
end

local function kick(seq, amount)
	seq.kick = math.max(seq.kick, amount or 0)
end

----------------------------------------------------------------------------
-- colour theme: every effect has a role (main/light/dark/glow) and follows the theme
----------------------------------------------------------------------------
local function applyColor(entry, theme)
	local c = theme[entry.role]
	local inst = entry.inst
	if entry.kind == "seq" then
		inst.Color = ColorSequence.new(c)
	elseif entry.kind == "seq2" then
		inst.Color = ColorSequence.new(theme.light, c)
	else
		inst.Color = c
	end
end

local function paint(seq, inst, role, kind)
	local entry = { inst = inst, role = role, kind = kind or "color" }
	table.insert(seq.paintables, entry)
	applyColor(entry, seq.theme)
end

local function setTheme(seq, palette, duration)
	seq.themeFrom = paletteCopy(seq.theme)
	seq.themeTo = paletteCopy(palette)
	seq.themeStart = seq.t
	seq.themeDur = math.max(duration or 0, 1e-3)
end

local function updateTheme(seq)
	if not seq.themeTo then return end
	local k = clamp01((seq.t - seq.themeStart) / seq.themeDur)
	for _, role in ROLES do
		seq.theme[role] = seq.themeFrom[role]:Lerp(seq.themeTo[role], k)
	end
	for _, e in seq.paintables do
		if e.inst.Parent then applyColor(e, seq.theme) end
	end
	-- the altar follows too (throttled: the SummonAltars script recolours ~120 parts per change)
	local d = seq.dressing
	if d and d.Parent and (os.clock() - seq.lastTint > 0.08 or k >= 1) then
		seq.lastTint = os.clock()
		d:SetAttribute("Tint", seq.theme.main)
		for _, b in seq.altarBeams do b.Color = ColorSequence.new(seq.theme.glow) end
	end
	if k >= 1 then seq.themeTo = nil end
end

----------------------------------------------------------------------------
-- lighting: a dedicated ColorCorrection ("SummonGrade") + a gentle exposure change
----------------------------------------------------------------------------
local function setDarken(seq, d)
	seq.dark = d
	local g = seq.grade
	if g then
		g.Brightness = -0.3 * d
		g.Contrast = 0.3 * d
		g.Saturation = -0.75 * d
		g.TintColor = WHITE:Lerp(seq.theme.light, math.min(d * 0.5, 0.25))
	end
	if seq.savedExposure ~= nil then
		Lighting.ExposureCompensation = seq.savedExposure - 1.5 * d -- Mythic (0.5) = -0.75: dark, never black
	end
end

local function darkenTo(seq, d, duration, easeName, delay)
	local from
	tween(seq, duration, function(k)
		from = from or seq.dark
		setDarken(seq, lerp(from, d, k))
	end, easeName or "inout", delay)
end

----------------------------------------------------------------------------
-- sounds: SoundService.SummonSounds (made once in Studio, reused; created here if missing)
----------------------------------------------------------------------------
local soundCache = {}

local function soundFolder()
	local f = SoundService:FindFirstChild("SummonSounds")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SummonSounds"
		f.Parent = SoundService
	end
	return f
end

local function soundFor(id)
	local s = soundCache[id]
	if s and s.Parent then return s end
	local folder = soundFolder()
	for _, c in folder:GetChildren() do
		if c:IsA("Sound") and c.SoundId == id then
			soundCache[id] = c
			return c
		end
	end
	s = Instance.new("Sound")
	s.Name = "Sfx" .. (string.match(id, "%d+") or "")
	s.SoundId = id
	s.Parent = folder
	soundCache[id] = s
	return s
end

local function isUiSound(id)
	for _, v in SummonTiers.ui or {} do
		if v == id then return true end
	end
	return false
end

-- "stop previous before starting": nothing from an older summon keeps playing
local function stopAllSounds()
	local f = SoundService:FindFirstChild("SummonSounds")
	if not f then return end
	for _, s in f:GetChildren() do
		if s:IsA("Sound") and s.IsPlaying and not isUiSound(s.SoundId) then s:Stop() end
	end
end

-- play one of the tier's sound hooks (charge, build, reveal, impact, ambience, banner, lightning)
local function playHook(seq, tier, hook, volumeMul)
	local id = tier.sounds and tier.sounds[hook]
	if type(id) ~= "string" or id == "" then return nil, 0 end
	local tweak = (tier.soundTweaks and tier.soundTweaks[hook]) or {}
	local volume = math.min(tweak.volume or 0.45, MAX_VOLUME)
	local s = soundFor(id)
	s:Stop()
	s.Looped = hook == "ambience"
	s.PlaybackSpeed = tweak.pitch or 1
	s.Volume = math.min(volume * (volumeMul or 1), MAX_VOLUME)
	s.TimePosition = 0
	s:Play()
	seq.sounds[s] = true
	return s, volume
end

local function fadeSound(seq, s, toVolume, duration)
	if not s then return end
	local from
	tween(seq, duration, function(k)
		from = from or s.Volume
		s.Volume = math.min(lerp(from, toVolume, k), MAX_VOLUME)
		if k >= 1 and toVolume <= 0 then s:Stop() end
	end, "inout")
end

----------------------------------------------------------------------------
-- player controls (PlayerModule), always re-enabled by cleanup
----------------------------------------------------------------------------
local controlsCache = nil
local function getControls()
	if controlsCache then return controlsCache end
	if not RunService:IsRunning() then return nil end -- (Studio edit-mode preview: no controls)
	local lp = Players.LocalPlayer
	local scripts = lp and lp:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, pm = pcall(require, module)
	if ok and type(pm) == "table" and pm.GetControls then
		local ok2, controls = pcall(function() return pm:GetControls() end)
		if ok2 then controlsCache = controls end
	end
	return controlsCache
end

-- Phones and tablets: the on-screen JUMP button would sit on top of the summon, so it hides
-- for the whole sequence. remember() puts Visible back in cleanup, and the watcher stops the
-- PlayerModule from showing it again mid-summon (cleanup disconnects it before restoring).
local function hideTouchJump(seq)
	if not UserInputService.TouchEnabled then return end
	local lp = Players.LocalPlayer
	local gui = lp and lp:FindFirstChildOfClass("PlayerGui")
	local touchGui = gui and gui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if not (jump and jump:IsA("GuiObject")) then return end
	remember(seq, jump, "Visible")
	jump.Visible = false
	table.insert(seq.conns, jump:GetPropertyChangedSignal("Visible"):Connect(function()
		if jump.Visible then jump.Visible = false end
	end))
end

----------------------------------------------------------------------------
-- finding the altar and laying out the stage
----------------------------------------------------------------------------
local function findShrines()
	local list = {}
	local root = workspace:FindFirstChild("Worlds") or workspace
	for _, d in root:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("OrbShrine") then table.insert(list, d) end
	end
	return list
end

local function nearestShrine(pos)
	local best, bestD = nil, math.huge
	for _, s in findShrines() do
		local d = (s:GetPivot().Position - pos).Magnitude
		if d < bestD then best, bestD = s, d end
	end
	return best
end

-- altar can be the shrine Model, its SummonAltar dressing, or anything inside the shrine
local function resolveAltar(altar)
	if typeof(altar) ~= "Instance" then return nil, nil end
	local shrine, dressing = altar, nil
	if altar:GetAttribute("SummonAltar") then
		dressing = altar
		shrine = altar.Parent
	else
		local child = altar:FindFirstChild("SummonAltar")
		local ref = altar:FindFirstChild("Altar")
		if child and child:GetAttribute("SummonAltar") then
			dressing = child
		elseif ref and ref:IsA("ObjectValue") and ref.Value then
			dressing = ref.Value
		end
	end
	-- climb to the shrine model (the one marked OrbShrine = true), if there is one
	local node = shrine
	while node and node ~= workspace and node ~= game do
		if node:GetAttribute("OrbShrine") then
			shrine = node
			break
		end
		node = node.Parent
	end
	if shrine and not dressing then
		local child = shrine:FindFirstChild("SummonAltar")
		if child and child:GetAttribute("SummonAltar") then dressing = child end
	end
	return shrine, dressing
end

-- raycast that ignores invisible blockers (trigger zones, invisible walls): they never block the view
local function castSolid(origin, vector, params)
	for _ = 1, 4 do
		local hit = workspace:Raycast(origin, vector, params)
		if not hit or hit.Instance.Transparency < 0.8 then return hit end
		local ok = pcall(function() params:AddToFilter(hit.Instance) end)
		if not ok then return hit end
	end
	return nil
end

local function computeStage(seq, altar)
	local lp = Players.LocalPlayer
	local cam = workspace.CurrentCamera
	local char = lp and lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local viewerPos = if hrp then hrp.Position else cam.CFrame.Position
	if altar == nil then altar = nearestShrine(viewerPos) end
	local shrine, dressing = resolveAltar(altar)
	local st = { shrine = shrine, dressing = dressing }

	-- raycasts (floor, camera) ignore effects, champions, characters and the altar dressing
	local ignore = { effectsRoot() }
	local champs = workspace:FindFirstChild("ClientChampions")
	if champs then table.insert(ignore, champs) end
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(ignore, p.Character) end
	end
	if dressing then table.insert(ignore, dressing) end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	st.params = params

	local center = dressing and dressing:GetAttribute("Center")
	local crystal = dressing and dressing:GetAttribute("CrystalPosition")
	local floorY = dressing and dressing:GetAttribute("FloorY")
	if typeof(center) ~= "Vector3" then
		if shrine and (shrine:IsA("Model") or shrine:IsA("BasePart")) then
			local cf, size
			if shrine:IsA("Model") then cf, size = shrine:GetBoundingBox() else cf, size = shrine.CFrame, shrine.Size end
			center = cf.Position - Vector3.new(0, size.Y / 2, 0)
			if typeof(crystal) ~= "Vector3" then crystal = cf.Position + Vector3.new(0, size.Y / 2 + 2, 0) end
		else
			-- no altar at all: put the stage in front of the player
			local look = flat(if hrp then hrp.CFrame.LookVector else cam.CFrame.LookVector)
			if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
			center = viewerPos + look.Unit * 14
			local hit = workspace:Raycast(center + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
			center = if hit then hit.Position else center - Vector3.new(0, 3, 0)
		end
	end
	if typeof(crystal) ~= "Vector3" then crystal = center + Vector3.new(0, 10, 0) end
	if type(floorY) ~= "number" then floorY = center.Y end
	st.center, st.crystal, st.floorY = center, crystal, floorY

	-- "in front of the altar" = toward the player
	local d = flat(viewerPos - center)
	if d.Magnitude < 0.5 then d = flat(-cam.CFrame.LookVector) end
	if d.Magnitude < 0.01 then d = Vector3.new(0, 0, 1) end
	st.dir = d.Unit

	-- how far the pedestal reaches toward a direction (so champions never stand inside it)
	local function reach(dirv)
		local best = 0
		if not shrine then return best end
		for _, p in shrine:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 0.95 and not (dressing and p:IsDescendantOf(dressing)) then
				local cf, s = p.CFrame, p.Size
				local tall = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
				if tall > 1.5 then -- flat floor plates don't count (people stand on those)
					local ext = (math.abs(cf.RightVector:Dot(dirv)) * s.X + math.abs(cf.UpVector:Dot(dirv)) * s.Y
						+ math.abs(cf.LookVector:Dot(dirv)) * s.Z) / 2
					best = math.max(best, (p.Position - center):Dot(dirv) + ext)
				end
			end
		end
		return best
	end
	local n = #seq.entries
	local gap = seq.gap
	local half = (n - 1) * gap / 2
	local baseR = tonumber(dressing and dressing:GetAttribute("BaseRadius")) or 0
	local function radiusFor(dirv)
		local r = math.max(reach(dirv), baseR * 0.85) + 3.4
		if n > 1 then
			local spread = half / math.max(r, 1)
			r = math.max(r, reach(rotY(dirv, spread)) + 3.4, reach(rotY(dirv, -spread)) + 3.4)
		end
		return math.clamp(r, 5, 26)
	end
	-- of the directions near the player's side, pick the one with the clearest view (rocks, trees...)
	local function clearance(dirv, r)
		local spot = center + dirv * r
		local origin = Vector3.new(spot.X, floorY + 3.5, spot.Z)
		local right = dirv:Cross(Vector3.yAxis)
		local score = 0
		for _, dist in { 9, 15, 21 } do
			for _, side in { -4, 0, 4 } do
				local target = origin + dirv * dist + right * side + Vector3.new(0, 2, 0)
				if not castSolid(origin, target - origin, params) then score += 1 end
			end
		end
		return score
	end
	local bestDir, bestR, bestScore = st.dir, radiusFor(st.dir), -1
	for _, deg in { 0, 25, -25, 50, -50, 75, -75 } do
		local dv = rotY(st.dir, math.rad(deg))
		local r = radiusFor(dv)
		local score = clearance(dv, r)
		if score > bestScore then bestDir, bestR, bestScore = dv, r, score end -- ties keep the smaller turn
		if score >= 9 then break end
	end
	st.dir = bestDir
	local R = bestR

	local function groundAt(pos)
		local hit = workspace:Raycast(Vector3.new(pos.X, floorY + 12, pos.Z), Vector3.new(0, -30, 0), params)
		if hit and math.abs(hit.Position.Y - floorY) < 4 then return hit.Position.Y end
		return floorY
	end
	-- the lineup is a shallow arc around the altar (one spot for a single summon)
	st.spots = {}
	local sum = Vector3.zero
	for k = 1, n do
		local offset = (k - (n + 1) / 2) * gap
		local p = center + rotY(st.dir, offset / R) * R
		p = Vector3.new(p.X, groundAt(p), p.Z)
		st.spots[k] = p
		sum += p
	end
	local S = sum / n
	st.S = S
	st.groundS = S.Y
	st.half = half
	st.Q = S + Vector3.new(0, if n > 1 then 5.6 else 4.6, 0) -- the energy sphere
	st.safe = S + Vector3.new(0, 3.5, 0) + st.dir * 0.5   -- camera rays start here (never inside the pedestal)
	st.clearRadius = half + 5
	st.sigilR = tonumber(dressing and dressing:GetAttribute("SigilRadius")) or 8
	-- the most central spots go to the best results
	local order = {}
	for k = 1, n do order[k] = k end
	table.sort(order, function(a, b) return math.abs(a - (n + 1) / 2) < math.abs(b - (n + 1) / 2) end)
	st.order = order
	return st
end

----------------------------------------------------------------------------
-- hiding whatever stands in the shot (your own character + champions, anyone in the way)
----------------------------------------------------------------------------
local function hideModel(seq, model)
	if seq.hidden[model] then return end
	seq.hidden[model] = true
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			remember(seq, d, "LocalTransparencyModifier")
			d.LocalTransparencyModifier = 1
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then
			remember(seq, d, "Enabled")
			d.Enabled = false
		end
	end
end

local function scanHide(seq)
	local lp = Players.LocalPlayer
	local st = seq.stage
	local cam = workspace.CurrentCamera
	local a = if cam then cam.CFrame.Position else st.S
	local b = st.S + Vector3.new(0, 3, 0)
	local ab = b - a
	local function inTheWay(pos)
		if flat(pos - st.S).Magnitude < st.clearRadius then return true end
		local k = clamp01((pos - a):Dot(ab) / math.max(ab:Dot(ab), 1e-3))
		return (a + ab * k - pos).Magnitude < 4
	end
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and (p == lp or inTheWay(root.Position)) then hideModel(seq, char) end
	end
	local champs = workspace:FindFirstChild("ClientChampions")
	if champs then
		for _, m in champs:GetChildren() do
			local pr = m:IsA("Model") and m.PrimaryPart
			if pr and ((lp and m:GetAttribute("OwnerId") == lp.UserId) or inTheWay(pr.Position)) then hideModel(seq, m) end
		end
	end
end

----------------------------------------------------------------------------
-- the result screen (HUD "Reveal"): the hold ends when it closes
----------------------------------------------------------------------------
local revealCache = nil
local revealSearchAt = 0
local function resultScreenOpen()
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	if not (revealCache and revealCache:IsDescendantOf(pg)) then
		if os.clock() < revealSearchAt then return false end
		revealSearchAt = os.clock() + 1
		revealCache = pg:FindFirstChild("Reveal", true)
	end
	local node = revealCache
	if not node then return false end
	while node and node ~= pg do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") and not node.Enabled then return false end
		node = node.Parent
	end
	return node == pg
end

----------------------------------------------------------------------------
-- camera: shots are { focus, yaw, pitch (degrees, relative to the stage direction), dist, fov }
----------------------------------------------------------------------------
local function makeShot(focus, yaw, pitch, dist, fov)
	return { focus = focus, yaw = yaw, pitch = pitch, dist = dist, fov = fov }
end

-- distance at which something `height` studs tall fills `fill` of the screen height
local function distFor(height, fov, fill)
	return (height / fill) / 2 / math.tan(math.rad(fov) / 2)
end

local function shotPos(seq, s)
	local h = rotY(seq.stage.dir, math.rad(s.yaw))
	local pitch = math.rad(s.pitch)
	return s.focus + h * (math.cos(pitch) * s.dist) + Vector3.new(0, math.sin(pitch) * s.dist, 0)
end

local function lerpShot(a, b, k)
	return {
		focus = a.focus:Lerp(b.focus, k), yaw = lerp(a.yaw, b.yaw, k), pitch = lerp(a.pitch, b.pitch, k),
		dist = lerp(a.dist, b.dist, k), fov = lerp(a.fov, b.fov, k),
	}
end

local function shotNow(seq)
	local c = seq.cam
	if not c then return nil end
	return lerpShot(c.from, c.to, c.ease(clamp01((seq.t - c.start) / c.dur)))
end

-- glide from wherever the camera is now to `target` (arcs around the focus, scales with speed)
local function camTo(seq, target, duration, easeName)
	local from = shotNow(seq) or target
	seq.cam = { from = from, to = target, start = seq.t, dur = math.max(duration or 0, 1e-3), ease = easeFn(easeName or "inout") }
end

local function updateCamera(seq, dt)
	local cam = workspace.CurrentCamera
	if not cam or not seq.cam then return end
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	local st = seq.stage
	local s = shotNow(seq)
	local pos = shotPos(seq, s)
	-- never inside a wall, and nothing big right beside the lens: rays from in front of the altar
	-- to the camera spot and to points around it; the camera moves in front of whatever they hit
	local ray = pos - st.safe
	local len = ray.Magnitude
	if len > 0.1 then
		local fwd = ray.Unit
		local right = fwd:Cross(Vector3.yAxis)
		right = if right.Magnitude > 0.1 then right.Unit else Vector3.xAxis
		local up = right:Cross(fwd)
		local allowed = len
		for _, off in { Vector2.new(0, 0), Vector2.new(3.5, 0), Vector2.new(-3.5, 0), Vector2.new(0, 2.2) } do
			local target = pos + right * off.X + up * off.Y
			local hit = castSolid(st.safe, target - st.safe, st.params)
			if hit then
				local frac = (hit.Position - st.safe).Magnitude / math.max((target - st.safe).Magnitude, 0.01)
				allowed = math.min(allowed, len * frac - 0.8)
			end
		end
		allowed = math.max(allowed, math.min(5, len))
		-- pull in at once, ease back out slowly (no popping)
		if allowed < seq.camClamp then seq.camClamp = allowed else seq.camClamp = math.min(allowed, seq.camClamp + dt * 10) end
		if seq.camClamp < len then pos = st.safe + fwd * seq.camClamp end
	end
	pos = Vector3.new(pos.X, math.max(pos.Y, st.floorY + 1.2), pos.Z)
	local cf = CFrame.lookAt(pos, s.focus)
	local fov = s.fov
	-- smooth hand-off from the player's own camera at the start
	local b = clamp01(seq.t / seq.blendTime)
	if b < 1 then
		local e = EASE.inout(b)
		cf = seq.camCFrame:Lerp(cf, e)
		fov = lerp(seq.camFov, fov, e)
	end
	-- gentle shake: smooth noise, capped (no random jumps)
	seq.kick *= math.exp(-dt * 7)
	local amount = math.min(seq.kick + seq.rumble, MAX_SHAKE)
	if amount > 0.003 then
		local n = os.clock() * 13
		cf = cf * CFrame.Angles(math.rad(math.noise(n, 0.3) * amount * 1.6), math.rad(math.noise(0.7, n) * amount * 1.6), 0)
			* CFrame.new(math.noise(n, 5.1) * amount * 0.3, math.noise(9.2, n) * amount * 0.3, 0)
	end
	cam.CFrame = cf
	cam.FieldOfView = math.clamp(fov, 20, 100)
end

local function restoreCamera(seq)
	if not seq.camSaved then return end
	seq.camSaved = false
	local cam = workspace.CurrentCamera
	if not cam then return end
	local lp = Players.LocalPlayer
	local live = RunService:IsRunning() -- (false in a Studio edit-mode preview)
	local subject = seq.camSubject
	if live and lp and (subject == nil or not subject:IsDescendantOf(workspace)) then
		local char = lp.Character
		subject = char and char:FindFirstChildOfClass("Humanoid")
	end
	-- in a live game always hand the camera back to the player (never leave it scripted)
	local camType = seq.camType
	if live and camType == Enum.CameraType.Scriptable then camType = Enum.CameraType.Custom end
	cam.CameraType = camType
	if subject then cam.CameraSubject = subject end
	cam.FieldOfView = seq.camFov
	cam.CFrame = seq.camCFrame
	if live and lp and not subject then
		-- just respawned: the new Humanoid may arrive a moment later (give up after 6 s)
		task.spawn(function()
			local giveUp = os.clock() + 6
			while os.clock() < giveUp do
				local char = lp.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum then
					if not current then cam.CameraSubject = hum end
					return
				end
				task.wait(0.1)
			end
		end)
	end
end

----------------------------------------------------------------------------
-- screen UI: letterbox bars, flash, caption (pill / name / power / line), banner
----------------------------------------------------------------------------
local function buildGui(seq)
	local lp = Players.LocalPlayer
	local parent = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not parent and RunService:IsEdit() then
		parent = game:GetService("CoreGui") -- Studio edit-mode preview only
	end
	if not parent then return nil end
	local gui = make("ScreenGui", { Name = "SummonCinematicUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local u = { gui = gui, groups = { pill = {}, name = {}, power = {}, sub = {} } }
	local function fade(group, inst, prop) table.insert(u.groups[group], { inst, prop }) end
	local FONT = Enum.Font.FredokaOne

	u.top = make("Frame", { Name = "TopBar", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = UDim2.fromScale(1, 0), ZIndex = 2 }, gui)
	u.bottom = make("Frame", { Name = "BottomBar", BackgroundColor3 = BLACK, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), ZIndex = 2 }, gui)
	u.flash = make("Frame", { Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = 10 }, gui)

	-- rarity pill (above the name). Sized from the screen HEIGHT so it looks the same on every device.
	u.pill = make("Frame", { Name = "RarityPill", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.715),
		Size = UDim2.fromScale(0.26, 0.046), SizeConstraint = Enum.SizeConstraint.RelativeYY, BackgroundColor3 = WHITE, Visible = false, ZIndex = 6 }, gui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, u.pill)
	u.pillStroke = make("UIStroke", { Thickness = 2, Color = BLACK }, u.pill)
	u.pillText = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.84, 0.76),
		BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = WHITE, Text = "", ZIndex = 7 }, u.pill)
	u.pillTextStroke = make("UIStroke", { Thickness = 1.5, Color = BLACK }, u.pillText)
	u.pillScale = make("UIScale", {}, u.pill)
	fade("pill", u.pill, "BackgroundTransparency"); fade("pill", u.pillStroke, "Transparency")
	fade("pill", u.pillText, "TextTransparency"); fade("pill", u.pillTextStroke, "Transparency")

	-- NEW! stamp (left of the pill) and "+1 copy" chip (right of the pill)
	local function chip(name, text, color, textColor, anchorX, posX, rotation)
		local f = make("Frame", { Name = name, AnchorPoint = Vector2.new(anchorX, 0.5), Position = UDim2.new(posX, if anchorX == 1 then -8 else 8, 0.5, 0),
			Size = UDim2.fromScale(0.62, 1.2), Rotation = rotation, BackgroundColor3 = color, Visible = false, ZIndex = 7 }, u.pill)
		make("UICorner", { CornerRadius = UDim.new(0.35, 0) }, f)
		local st = make("UIStroke", { Thickness = 2, Color = BLACK }, f)
		local l = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.78),
			BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = textColor, Text = text, ZIndex = 8 }, f)
		local sc = make("UIScale", {}, f)
		fade("pill", f, "BackgroundTransparency"); fade("pill", st, "Transparency"); fade("pill", l, "TextTransparency")
		return f, sc
	end
	u.newTag, u.newScale = chip("NewStamp", "NEW!", GOLD, Color3.fromRGB(70, 35, 0), 1, 0, -10)
	u.copyTag, u.copyScale = chip("CopyChip", "+1 copy", Color3.fromRGB(64, 74, 120), WHITE, 0, 1, 0)

	-- champion name (centre-low), power (below it), one line under that
	local function line(name, posY, height, width, color, strokeThickness, group)
		local l = make("TextLabel", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, posY), Size = UDim2.fromScale(width, height),
			BackgroundTransparency = 1, Font = FONT, TextScaled = true, TextColor3 = color, Text = "", Visible = false, ZIndex = 6 }, gui)
		local st = make("UIStroke", { Thickness = strokeThickness, Color = Color3.fromRGB(20, 18, 40) }, l)
		fade(group, l, "TextTransparency"); fade(group, st, "Transparency")
		return l, st
	end
	u.name, u.nameStroke = line("ChampionName", 0.79, 0.08, 0.9, WHITE, 3, "name")
	make("UITextSizeConstraint", { MaxTextSize = 80 }, u.name)
	u.nameScale = make("UIScale", {}, u.name)
	u.power = line("Power", 0.858, 0.042, 0.6, Color3.fromRGB(255, 214, 90), 2, "power")
	u.sub = line("Collection", 0.905, 0.03, 0.8, Color3.fromRGB(205, 215, 245), 1.5, "sub")

	gui.Parent = parent
	return u
end

local function captionPart(u, group, alpha)
	for _, f in u.groups[group] do (f[1] :: any)[f[2]] = alpha end
end
local function captionAlpha(u, alpha)
	for group in u.groups do captionPart(u, group, alpha) end
end

local function letterbox(seq, on, duration)
	local u = seq.ui
	if not u then return end
	local from
	tween(seq, duration, function(k)
		from = from or u.top.Size.Y.Scale
		local h = lerp(from, if on then seq.barHeight else 0, k)
		u.top.Size = UDim2.fromScale(1, h)
		u.bottom.Size = UDim2.fromScale(1, h)
	end, "inout")
end

-- a short, gentle screen flash (<= 0.35 opacity, ~0.15 s)
local function flash(seq, color, alpha)
	local u = seq.ui
	alpha = math.min(alpha or 0, MAX_FLASH)
	if not u or alpha <= 0 then return end
	u.flash.BackgroundColor3 = color
	u.flash.BackgroundTransparency = 1 - alpha
	tween(seq, 0.15, function(k) u.flash.BackgroundTransparency = lerp(1 - alpha, 1, k) end, "out")
end

local function showCaption(seq, e)
	local u = seq.ui
	if not u then return end
	local pal = e.tier.palette
	local bright = pal.main.R * 0.3 + pal.main.G * 0.59 + pal.main.B * 0.11 > 0.72 -- light pill -> dark text
	u.pill.BackgroundColor3 = pal.main
	u.pillStroke.Color = pal.dark
	u.pillText.Text = string.upper(e.rarity)
	u.pillText.TextColor3 = if bright then pal.dark:Lerp(BLACK, 0.55) else WHITE
	u.pillTextStroke.Color = if bright then pal.light else pal.dark
	u.name.Text = e.name
	u.nameStroke.Color = pal.dark:Lerp(BLACK, 0.4)
	u.power.Text = "POWER  " .. Format.Short(e.power)
	u.sub.Text = if e.dup then "Duplicate  -  added to your collection" else "Added to your collection"
	u.newTag.Visible = not e.dup
	u.copyTag.Visible = e.dup
	for _, g in { u.pill, u.name, u.power, u.sub } do g.Visible = true end
	captionAlpha(u, 1)
	-- pill (above) -> name (centre-low) -> power (below): the eye always knows where to look
	tween(seq, 0.2, function(k) u.pillScale.Scale = lerp(0.4, 1, k); captionPart(u, "pill", clamp01(1 - k)) end, "back", 0.06)
	if e.dup and not atLeast(e.rarity, "Epic") then
		-- duplicates of the lower tiers: no big name pop, the "+1 copy" chip pops instead
		u.nameScale.Scale = 0.8
		tween(seq, 0.18, function(k) captionPart(u, "name", 1 - k) end, "out", 0.12)
		tween(seq, 0.26, function(k) u.copyScale.Scale = lerp(2.2, 1, k) end, "back", 0.14)
	else
		tween(seq, 0.28, function(k) u.nameScale.Scale = lerp(1.7, 1, k); captionPart(u, "name", 1 - k) end, "out", 0.14)
	end
	tween(seq, 0.2, function(k) captionPart(u, "power", 1 - k) end, "out", 0.28)
	tween(seq, 0.2, function(k) captionPart(u, "sub", 1 - k) end, "out", 0.38)
	if not e.dup then
		tween(seq, 0.24, function(k) u.newScale.Scale = lerp(2.3, 1, k); u.newTag.Rotation = lerp(-26, -10, k) end, "back", 0.34)
	end
end

-- LEGENDARY / MYTHIC title: slams in at the top, styled by tier.bannerStyle
local function showBanner(seq, tier)
	local u = seq.ui
	if not u or not tier.banner then return end
	local style = tier.bannerStyle or {}
	local pal = tier.palette
	local font = style.font or Enum.Font.LuckiestGuy
	local frame = make("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.125),
		Size = UDim2.fromScale(1, 0.095), BackgroundTransparency = 1, ZIndex = 6 }, u.gui)
	local scale = make("UIScale", { Scale = 2.3 }, frame)
	local fades = {} -- { inst, prop, visibleValue }
	if style.band then
		local band = make("Frame", { Name = "Band", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.92), BackgroundColor3 = style.stroke or BLACK, BorderSizePixel = 0, ZIndex = 6 }, frame)
		make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.2),
			NumberSequenceKeypoint.new(0.82, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, band)
		table.insert(fades, { band, "BackgroundTransparency", 0 })
	end
	local function title(name, color, z)
		return make("TextLabel", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 1),
			BackgroundTransparency = 1, Font = font, Text = tier.banner, TextScaled = true, TextColor3 = color, ZIndex = z }, frame)
	end
	local ghosts = {}
	if style.glitch then
		-- two offset copies that wobble for a moment (movement only, no flashing)
		for i, c in { pal.main, pal.light } do
			local g = title("Ghost" .. i, c, 7)
			table.insert(fades, { g, "TextTransparency", 0.4 })
			ghosts[i] = g
		end
	end
	local text = title("Title", WHITE, 8)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(style.top or pal.light, style.bottom or pal.main) }, text)
	local stroke = make("UIStroke", { Thickness = 4, Color = style.stroke or BLACK, LineJoinMode = Enum.LineJoinMode.Round }, text)
	table.insert(fades, { text, "TextTransparency", 0 })
	table.insert(fades, { stroke, "Transparency", 0 })
	if style.shine then
		-- a white copy masked to a thin diagonal band that sweeps across the letters
		local glint = title("Shine", WHITE, 9)
		local grad = make("UIGradient", { Rotation = 20, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }) }, glint)
		table.insert(fades, { glint, "TextTransparency", 0 })
		tween(seq, 0.65, function(k) grad.Offset = Vector2.new(lerp(-1, 1, k), 0) end, "inout", 0.3)
	end
	local function alpha(a)
		for _, f in fades do (f[1] :: any)[f[2]] = lerp(f[3], 1, a) end
	end
	alpha(1)
	tween(seq, 0.26, function(k) scale.Scale = lerp(2.3, 1, k); alpha(1 - k) end, "out")
	if #ghosts > 0 then
		tween(seq, 0.45, function(k)
			local j = (1 - k) * 0.02
			for i, g in ghosts do
				local side = if i == 1 then 1 else -1
				g.Position = UDim2.fromScale(0.5 + math.noise(k * 6, i) * j * side + j * 0.4 * side, 0.5 + math.noise(i, k * 6) * j * 2)
			end
			if k >= 1 then for _, g in ghosts do g.Visible = false end end
		end, "linear", 0.08)
	end
	playHook(seq, tier, "banner")
	kick(seq, (tier.shake or 0) * 0.5)
	u.banner, u.bannerScale, u.bannerAlpha = frame, scale, alpha
end

-- small name tag over each champion in a multi-summon lineup
local function makeTag(seq, e)
	if e.tagged or not e.model then return end
	e.tagged = true
	local tier = e.tier
	local FONT = Enum.Font.FredokaOne
	local lowDup = e.dup and not atLeast(e.rarity, "Epic")
	-- the tag hangs on its own invisible part at the champion's spot: a BillboardGui only shows when it
	-- sits in a part (or in PlayerGui), and inside the model its pop-in ScaleTo would move the tag
	local k = e.scale / e.baseScale
	local anchor = newPart({ Name = "TagAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(e.spot) })
	local bb = make("BillboardGui", { Name = "SummonTag", Size = UDim2.fromScale(5.4, 1.6), -- (studs: narrower than the lineup gap)
		StudsOffsetWorldSpace = Vector3.new(0, (e.foot + e.topAbove) * k + 1.2, 0), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 160 })
	local holder = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, bb)
	local scale = make("UIScale", { Scale = 0 }, holder)
	local top = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.58), Font = FONT, TextScaled = true,
		Text = if lowDup then "+1 copy" else e.name, TextColor3 = WHITE }, holder)
	make("UIStroke", { Thickness = 2, Color = tier.palette.dark:Lerp(BLACK, 0.4) }, top)
	local bottom = make("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.4), Font = FONT,
		TextScaled = true, Text = if lowDup then e.name else string.upper(e.rarity), TextColor3 = tier.palette.main }, holder)
	make("UIStroke", { Thickness = 1.5, Color = BLACK }, bottom)
	if not e.dup then
		local tag = make("TextLabel", { BackgroundColor3 = GOLD, Position = UDim2.fromScale(0.02, -0.36), Size = UDim2.fromScale(0.26, 0.38), Rotation = -12,
			Font = FONT, TextScaled = true, Text = "NEW!", TextColor3 = Color3.fromRGB(70, 35, 0) }, holder)
		make("UICorner", { CornerRadius = UDim.new(0.3, 0) }, tag)
	end
	bb.Parent = anchor
	anchor.Parent = seq.folder
	tween(seq, 0.3, function(k) scale.Scale = k end, "back", 0.05)
end

----------------------------------------------------------------------------
-- champions: cloned + scaled up front (so the reveal frame never hitches), shown at the reveal
----------------------------------------------------------------------------
local function makeSilhouette(tier)
	-- used when a champion has no model: a glowing figure in the tier colour
	local m = Instance.new("Model")
	m.Name = "Silhouette"
	local function piece(name, size, y, x, shape)
		local p = newPart({ Name = name, Size = size, CFrame = CFrame.new(x or 0, y, 0), Color = tier.palette.glow,
			Material = Enum.Material.ForceField, Shape = shape or Enum.PartType.Block })
		p.Parent = m
		return p
	end
	local root = piece("HumanoidRootPart", Vector3.new(2, 2, 1), 3)
	root.Transparency = 1
	piece("Torso", Vector3.new(2, 2.1, 1), 3.35)
	piece("Head", Vector3.new(1.5, 1.5, 1.5), 5.2, 0, Enum.PartType.Ball)
	piece("LeftLeg", Vector3.new(0.85, 2.1, 0.9), 1.05, -0.5)
	piece("RightLeg", Vector3.new(0.85, 2.1, 0.9), 1.05, 0.5)
	piece("LeftArm", Vector3.new(0.75, 2, 0.8), 3.4, -1.45)
	piece("RightArm", Vector3.new(0.75, 2, 0.8), 3.4, 1.45)
	m.PrimaryPart = root
	return m
end

local function prepareChampion(seq, e)
	local models = ReplicatedStorage:FindFirstChild("ChampionModels")
	local template = models and models:FindFirstChild(e.result.id)
	local model = if template and template:IsA("Model") then template:Clone() else makeSilhouette(e.tier)
	model.Name = "Summoned_" .. tostring(e.result.id)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		elseif d:IsA("Humanoid") then
			d.EvaluateStateMachine = false -- (stops the Humanoid switching collisions back on)
			d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			d.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		model:Destroy()
		model = makeSilhouette(e.tier)
		root = model.PrimaryPart
	end
	root.Anchored = true -- the rest hangs on the Motor6D joints: the champion can never fall
	model.PrimaryPart = root
	-- measure how high the root sits above the feet, so the feet stand exactly on the floor
	local bbCF, bbSize = model:GetBoundingBox()
	local bottom = bbCF.Position.Y - bbSize.Y / 2
	local feet = math.huge
	for _, name in { "LeftFoot", "RightFoot", "LeftLeg", "RightLeg" } do
		local f = model:FindFirstChild(name, true)
		if f and f:IsA("BasePart") then feet = math.min(feet, f.Position.Y - f.Size.Y / 2) end
	end
	if feet < math.huge then bottom = feet end
	local base = model:GetScale()
	local s = if seq.multi then math.min(e.tier.championScale or 1.3, 1.25) else (e.tier.championScale or 1.3)
	e.model, e.root, e.baseScale = model, root, base
	e.foot = math.clamp(root.Position.Y - bottom, 0.3, 10)
	e.topAbove = math.max(bbCF.Position.Y + bbSize.Y / 2 - root.Position.Y, 1)
	e.height = bbSize.Y
	e.heightFinal = bbSize.Y * s
	e.scale = base * s
	e.rig = Anim.Rig(model)
	e.pose = P[e.tier.pose or ""] or P.handsOnHips
	e.buf = {}
	pcall(function() model:ScaleTo(e.scale * 0.7) end)
	e.curScale = e.scale * 0.7
end

-- put the champion on its spot, feet on the floor, facing the camera
local function placeChampion(e, absScale)
	if math.abs((e.curScale or 0) - absScale) > 1e-3 then
		pcall(function() e.model:ScaleTo(absScale) end)
		e.curScale = absScale
	end
	local k = absScale / e.baseScale
	local y = e.spot.Y + e.foot * k - 0.03
	local pos = Vector3.new(e.spot.X, y, e.spot.Z)
	local face = e.face or (e.spot + Vector3.new(0, 0, -1))
	local look = Vector3.new(face.X, y, face.Z)
	if (look - pos).Magnitude < 0.1 then look = pos + Vector3.new(0, 0, -1) end
	e.model:PivotTo(CFrame.lookAt(pos, look))
end

local function makeAura(seq, e)
	if not atLeast(e.rarity, "Rare") then return end
	local pal = e.tier.palette
	local holder = newPart({ Name = "Aura", Size = Vector3.new(3.2, 0.3, 3.2), Transparency = 1, CFrame = CFrame.new(e.spot + Vector3.new(0, 0.3, 0)) })
	local aura = clone("Emitters/Aura", function() return Instance.new("ParticleEmitter") end)
	aura.Color = ColorSequence.new(pal.glow, pal.main)
	aura.Rate = if atLeast(e.rarity, "Legendary") then 16 else 9
	aura.Enabled = true
	aura.Parent = holder
	if atLeast(e.rarity, "Epic") then
		local embers = clone("Emitters/Embers", function() return Instance.new("ParticleEmitter") end)
		embers.Color = ColorSequence.new(pal.light, pal.main)
		embers.Rate = 10
		embers.Enabled = true
		embers.Parent = holder
	end
	holder.Parent = seq.folder
end

local function revealChampion(seq, e, big)
	local pal = e.tier.palette
	placeChampion(e, e.scale * 0.7)
	e.model.Parent = seq.folder
	e.riseStart = seq.t
	e.shown = true
	-- pops from 70 % to full size with a little overshoot; feet stay planted the whole time
	tween(seq, 0.3, function(k) placeChampion(e, e.scale * lerp(0.7, 1, k)) end, "back")
	-- glows white-hot, then the real colours come through (a rim of the tier colour stays)
	local hl = make("Highlight", { FillColor = pal.light, OutlineColor = pal.main, FillTransparency = 0, OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded, Adornee = e.model })
	hl.Parent = e.model
	tween(seq, 0.55, function(k)
		hl.FillTransparency = k
		hl.OutlineTransparency = lerp(0, if big then 0.55 else 0.75, k)
	end, "out", 0.06)
	-- key light from the camera side, so the champion reads even in the darkened scene
	local toward = flat((e.face or e.spot) - e.spot)
	toward = if toward.Magnitude > 0.1 then toward.Unit else seq.stage.dir
	local holder = newPart({ Name = "KeyLight", Size = Vector3.one * 0.2, Transparency = 1,
		CFrame = CFrame.new(e.spot + toward * 3.2 + Vector3.new(0, e.heightFinal * 0.7, 0)) })
	local light = make("PointLight", { Color = pal.light, Range = if big then 14 else 10, Brightness = 0, Shadows = false }, holder)
	holder.Parent = seq.folder
	tween(seq, 0.45, function(k) light.Brightness = lerp(if big then 6 else 4, if big then 1.8 else 1.3, k) end, "out")
	makeAura(seq, e)
end

----------------------------------------------------------------------------
-- effects (all built from ReplicatedStorage.SummonFx templates)
----------------------------------------------------------------------------
local function makeShockPool(seq, n)
	for i = 1, n do
		local anchor = newPart({ Name = "ShockAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(seq.stage.S) })
		local ring = clone("ShockRing", function()
			return make("CylinderHandleAdornment", { Radius = 1, InnerRadius = 0.86, Height = 0.12 })
		end)
		ring.Adornee = anchor
		ring.CFrame = CFrame.Angles(math.rad(90), 0, 0) -- lie flat
		ring.Transparency = 1
		ring.Parent = anchor
		anchor.Parent = seq.folder
		seq.shockSlots[i] = { anchor = anchor, ring = ring, token = 0 }
	end
end

-- a flat ring that expands and fades (ground shockwaves, sphere pulses)
local function shock(seq, pos, color, radius, duration, thickness)
	if #seq.shockSlots == 0 then return end
	seq.shockIndex = seq.shockIndex % #seq.shockSlots + 1
	local slot = seq.shockSlots[seq.shockIndex]
	slot.token += 1
	local token = slot.token
	slot.anchor.CFrame = CFrame.new(pos)
	local ring = slot.ring
	ring.Color3 = color
	ring.Transparency = 1
	tween(seq, duration, function(k)
		if slot.token ~= token then return end -- this slot was reused by a newer ring
		local r = lerp(0.6, radius, k)
		ring.Radius = r
		ring.InnerRadius = math.max(r - thickness * (1 - 0.6 * k), 0)
		ring.Height = 0.14
		ring.Transparency = lerp(0.05, 1, k * k)
	end, "out")
end

local function makeBurst(seq)
	local holder = newPart({ Name = "BurstHolder", Shape = Enum.PartType.Ball, Size = Vector3.one, Transparency = 1, CFrame = CFrame.new(seq.stage.Q) })
	local pe = clone("Emitters/Burst", function()
		return make("ParticleEmitter", { Rate = 0, Speed = NumberRange.new(14, 28), Lifetime = NumberRange.new(0.5, 0.9), Drag = 5, LightEmission = 1 })
	end)
	pe.Enabled = false
	pe.Parent = holder
	holder.Parent = seq.folder
	seq.burstHolder, seq.burstPE = holder, pe
end

local function burstAt(seq, pos, tier, count)
	if not seq.burstPE then return end
	seq.burstHolder.CFrame = CFrame.new(pos)
	seq.burstPE.Color = ColorSequence.new(tier.palette.light, tier.palette.main)
	seq.burstPE:Emit(math.clamp(math.floor(count), 1, 90))
end

-- particles drifting INTO a point (the crystal while charging, the sphere while building)
local function makeConverge(seq, pos, radius, rate)
	local holder = newPart({ Name = "Converge", Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 2, Transparency = 1, CFrame = CFrame.new(pos) })
	local pe = clone("Emitters/Converge", function() return Instance.new("ParticleEmitter") end)
	pe.Shape = Enum.ParticleEmitterShape.Sphere
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	pe.Lifetime = NumberRange.new(0.55, 0.6)
	pe.Speed = NumberRange.new(radius / 0.6 * 0.95)
	pe.Rate = rate
	pe.Enabled = true
	pe.Parent = holder
	paint(seq, pe, "glow", "seq2")
	holder.Parent = seq.folder
	return pe
end

-- the summon circle on the floor where the champion(s) will stand
local function makeCircle(seq)
	local st = seq.stage
	local circle = clone("SummonCircle", function()
		local m = Instance.new("Model")
		for i = 1, 24 do
			local a = i / 24 * math.pi * 2
			newPart({ Name = "OuterRing", Size = Vector3.new(0.16, 0.06, 0.9), CFrame = CFrame.Angles(0, a, 0) * CFrame.new(3.2, 0, 0) }).Parent = m
		end
		return m
	end)
	local origSize = {}
	for _, p in circle:GetDescendants() do
		if p:IsA("BasePart") then origSize[p] = p.Size end
	end
	local s = seq.circleR / 3.3
	pcall(function() circle:ScaleTo(s) end)
	-- ScaleTo makes the lines fatter too (chunky in a big lineup circle): every line keeps its new
	-- length, but its thickness grows at most 25 % (square glyphs grow at most 25 % too)
	local thick = math.min(s, 1.25)
	for p, o in origSize do
		local sorted = { o.X, o.Y, o.Z }
		table.sort(sorted)
		local long = if sorted[3] > sorted[2] * 1.8 then sorted[3] else math.huge -- (no clear long side = a glyph)
		local function axis(v) return if v == long then v * s else v * thick end
		p.Size = Vector3.new(axis(o.X), axis(o.Y), axis(o.Z))
	end
	local center = Vector3.new(st.S.X, st.groundS + 0.26, st.S.Z) -- above the altar sigil and the dark pool (no z-fighting)
	circle:PivotTo(CFrame.new(center))
	local origin = CFrame.new(center)
	local outer, inner = {}, {}
	for _, p in circle:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = 1
			table.insert(if p.Name == "OuterRing" then outer else inner, { part = p, offset = origin:ToObjectSpace(p.CFrame) })
			paint(seq, p, if p.Name == "OuterRing" then "main" elseif p.Name == "Glyph" then "light" else "glow")
		end
	end
	circle.Parent = seq.folder
	local angle = 0
	tween(seq, 0.35, function(k)
		local tr = lerp(1, 0.1, k)
		for _, e in outer do e.part.Transparency = tr end
		for _, e in inner do e.part.Transparency = tr end
	end, "out")
	-- the outer ring and the inner pattern turn in opposite directions
	seq.actors.circle = function(sdt)
		angle += sdt * (0.45 + seq.spin * 0.6)
		local a = origin * CFrame.Angles(0, angle, 0)
		local b = origin * CFrame.Angles(0, -angle * 1.35, 0)
		for _, e in outer do move(seq, e.part, a * e.offset) end
		for _, e in inner do move(seq, e.part, b * e.offset) end
	end
end

local function makeSphere(seq, b)
	local st = seq.stage
	local model = clone("Sphere", function()
		local m = Instance.new("Model")
		local core = newPart({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.one })
		make("PointLight", { Name = "Light" }, core)
		core.Parent = m
		newPart({ Name = "Shell", Shape = Enum.PartType.Ball, Size = Vector3.one, Material = Enum.Material.ForceField }).Parent = m
		newPart({ Name = "Halo", Shape = Enum.PartType.Ball, Size = Vector3.one, Transparency = 0.82 }).Parent = m
		return m
	end)
	model:PivotTo(CFrame.new(st.Q))
	local core, shell, halo = model:FindFirstChild("Core"), model:FindFirstChild("Shell"), model:FindFirstChild("Halo")
	local light = core and core:FindFirstChildOfClass("PointLight")
	for _, p in { core, shell, halo } do p.Size = Vector3.one * 0.05 end
	model.Parent = seq.folder
	paint(seq, core, "glow")    -- hot, bright centre
	paint(seq, shell, "light")  -- shimmering skin
	paint(seq, halo, "main")    -- tier-coloured aura around it
	if light then
		paint(seq, light, "glow")
		light.Brightness = 0
		light.Range = 10 + seq.sphereW * 2
		light.Shadows = false
	end
	local sp = { model = model, k = 0.05, pulse = 0, pop = 1, fade = 0, glow = 0, flare = 0 }
	seq.sphere = sp
	tween(seq, b * 0.7, function(k) sp.k = lerp(0.05, 1, k); sp.glow = k end, "out")
	seq.actors.sphere = function(sdt, t)
		sp.pulse *= math.exp(-sdt * 6)
		local w = seq.sphereW * sp.k * sp.pop * (1 + 0.035 * math.sin(t * 9) + sp.pulse)
		core.Size = Vector3.one * math.max(w * 0.78, 0.05)
		shell.Size = Vector3.one * math.max(w, 0.05)
		halo.Size = Vector3.one * math.max(w * 1.55, 0.05)
		core.Transparency = sp.fade
		shell.Transparency = sp.fade
		halo.Transparency = lerp(0.62, 1, sp.fade) -- (the tier colour around the white-hot core)
		if light then light.Brightness = sp.glow * 3 + sp.pulse * 6 + sp.flare end
	end
end

-- the sphere throbs and pushes out a ring
local function pulse(seq)
	if seq.sphere then seq.sphere.pulse = 0.2 end
	shock(seq, seq.stage.Q, seq.theme.light, seq.sphereW * 2.4, 0.4, 0.45)
	kick(seq, (seq.tier.shake or 0) * 0.3)
end

local function popSphere(seq)
	local sp = seq.sphere
	if not sp then return end
	tween(seq, 0.09, function(k) sp.pop = lerp(1, 1.35, k) end, "out")
	tween(seq, 0.16, function(k) sp.pop = lerp(1.35, 0.05, k); sp.fade = k end, "in", 0.09)
	tween(seq, 0.55, function(k) sp.flare = lerp(8, 0, k); sp.glow = 1 - k end, "out")
	later(seq, 0.6, function() seq.actors.sphere = nil end)
end

-- energy pours from the altar crystal into the sphere (two curved beams)
local function makeFeed(seq, b)
	local st = seq.stage
	local anchor = newPart({ Name = "FeedAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(st.S) })
	local function attachment(pos, axis)
		local up = if math.abs(axis.Y) > 0.9 then st.dir else Vector3.yAxis
		local z = axis:Cross(up).Unit
		local y = z:Cross(axis).Unit
		local a = Instance.new("Attachment")
		a.CFrame = CFrame.fromMatrix(pos - st.S, axis, y, z) -- a beam curves along its attachments' X axis
		a.Parent = anchor
		return a
	end
	local a0 = attachment(st.crystal, (st.dir + Vector3.new(0, 0.35, 0)).Unit)
	local a1 = attachment(st.Q, Vector3.new(0, -1, 0))
	local size = math.max(seq.tier.sphereScale or 1, 0.8)
	local feed = {}
	for i, spec in { { w0 = 0.35, w1 = 1.1, role = "glow", c0 = 7, c1 = 5 }, { w0 = 0.12, w1 = 0.4, role = "light", c0 = 6.5, c1 = 4.5 } } do
		local beam = clone("Beams/EnergyBeam", function() return make("Beam", { LightEmission = 1, FaceCamera = true, Segments = 24 }) end)
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.CurveSize0 = spec.c0
		beam.CurveSize1 = spec.c1
		beam.Width0 = 0
		beam.Width1 = 0
		beam.Parent = anchor
		paint(seq, beam, spec.role, "seq")
		feed[i] = { beam = beam, w0 = spec.w0 * size, w1 = spec.w1 * size }
	end
	anchor.Parent = seq.folder
	seq.feed = feed
	tween(seq, math.max(b * 0.25, 0.12), function(k)
		for _, f in feed do f.beam.Width0 = f.w0 * k; f.beam.Width1 = f.w1 * k end
	end, "out")
end

local function makeRings(seq, tier, b)
	local count = math.clamp(math.floor(tier.rings or 0), 0, #RING_TILTS)
	if count == 0 then return end
	local st = seq.stage
	local N = 24
	local thick = if (tier.sphereScale or 1) >= 1.4 then 0.2 else 0.15
	local frame = CFrame.lookAt(st.Q, st.Q + st.dir)
	local rings = {}
	for i = 1, count do
		local r = seq.sphereW * 0.5 * (1.4 + 0.32 * (i - 1)) + 0.35
		local len = 2 * math.pi * r / N * 1.08
		local segs = {}
		for j = 1, N do
			local p = clone("RingSegment", function() return newPart({ Size = Vector3.new(0.16, 0.16, 1) }) end)
			p.Size = Vector3.new(thick, thick, len)
			p.Transparency = 1
			p.CFrame = CFrame.new(st.Q)
			p.Parent = seq.folder
			paint(seq, p, if i % 2 == 1 then "glow" else "main")
			segs[j] = p
		end
		local tilt = RING_TILTS[i]
		local sign = if tier.counterRotate and i % 2 == 0 then -1 else 1
		rings[i] = { segs = segs, r = r, angle = i * 1.3, grow = 0, expand = 1,
			frame = frame * CFrame.Angles(math.rad(tilt[1]), math.rad(tilt[2]), math.rad(tilt[3])),
			speed = (tier.ringSpeed or 2) * sign * (1 - 0.1 * (i - 1)) }
	end
	seq.rings = rings
	-- rings "draw on" segment by segment while they open up
	local shown = 0
	tween(seq, math.max(b * 0.35, 0.15), function(k)
		local want = math.floor(k * N + 0.5)
		for _, ring in rings do
			ring.grow = k
			for j = shown + 1, want do ring.segs[j].Transparency = 0.05 end
		end
		shown = math.max(shown, want)
	end, "out", b * 0.08)
	seq.actors.rings = function(sdt)
		local spin = 1 + seq.spin
		for _, ring in rings do
			ring.angle += sdt * ring.speed * spin
			local radius = ring.r * (0.35 + 0.65 * ring.grow) * ring.expand
			for j, seg in ring.segs do
				move(seq, seg, ring.frame * CFrame.Angles(0, ring.angle + j * (2 * math.pi / N), 0) * CFrame.new(radius, 0, 0))
			end
		end
	end
end

local function makeRunes(seq, tier, b)
	local count = math.clamp(math.floor(tier.runes or 0), 0, 12)
	if count == 0 then return end
	local st = seq.stage
	local list = {}
	for i = 1, count do
		local m = clone("Rune", function()
			local mm = Instance.new("Model")
			newPart({ Name = "Plate", Size = Vector3.new(1.1, 1.5, 0.08), Material = Enum.Material.Glass }).Parent = mm
			newPart({ Name = "Mark1", Size = Vector3.new(0.12, 1.05, 0.1) }).Parent = mm
			return mm
		end)
		local plate = m:FindFirstChild("Plate") or m:FindFirstChildWhichIsA("BasePart")
		local pivot = plate.CFrame
		local parts = {}
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				local baseT = if p == plate then 0.3 else 0
				table.insert(parts, { part = p, offset = pivot:ToObjectSpace(p.CFrame), base = baseT })
				paint(seq, p, if p == plate then "dark" else "main")
				p.Transparency = 1
				p.CFrame = CFrame.new(st.Q)
			end
		end
		m.Parent = seq.folder
		list[i] = { parts = parts, phase = (i - 1) / count * math.pi * 2, h = if i % 2 == 0 then 0.9 else -0.5 }
	end
	local data = { list = list, radius = 0, angle = 0 }
	seq.runes = data
	local visible = false
	tween(seq, math.max(b * 0.35, 0.2), function(k)
		if not visible then
			visible = true
			for _, r in list do for _, e in r.parts do e.part.Transparency = e.base end end
		end
		data.radius = (seq.sphereW * 0.5 + 2.4) * k
	end, "back", b * 0.15)
	seq.actors.runes = function(sdt, t)
		data.angle += sdt * 0.9 * (1 + seq.spin * 0.5)
		for _, r in data.list do
			local out = rotY(st.dir, data.angle + r.phase)
			local pos = st.Q + out * data.radius + Vector3.new(0, r.h + math.sin(t * 2.2 + r.phase) * 0.25, 0)
			local cf = CFrame.lookAt(pos, pos + out)
			for _, e in r.parts do move(seq, e.part, cf * e.offset) end
		end
	end
end

-- glowing wisps spiral up from the altar sigil into the sphere
local function makeWisps(seq, count)
	local st = seq.stage
	local list = {}
	for i = 1, count do
		local w = clone("Wisp", function() return newPart({ Name = "Wisp", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45 }) end)
		w.CFrame = CFrame.new(st.center)
		w.Parent = seq.folder
		paint(seq, w, "glow")
		local tr = w:FindFirstChildOfClass("Trail")
		if tr then paint(seq, tr, "main", "seq") end
		list[i] = { part = w, trail = tr, offset = (i - 1) / count, lastU = 1, loops = 0, angle = 0 }
	end
	seq.wisps = list
	local RATE = 0.85 -- trips per second
	local floorCenter = Vector3.new(st.center.X, st.floorY + 0.4, st.center.Z)
	local mid = st.center:Lerp(st.Q, 0.55) + Vector3.new(0, 6, 0)
	seq.actors.wisps = function(sdt, t)
		for i, w in list do
			local u = (t * RATE + w.offset) % 1
			if u < w.lastU then
				-- a new trip: new start point on the camera side of the sigil, and no streak across the screen
				w.loops += 1
				w.angle = math.rad(-75 + 150 * ((i * 0.37 + w.loops * 0.61) % 1))
				if w.trail then w.trail:Clear() end
			end
			w.lastU = u
			local start = floorCenter + rotY(st.dir, w.angle) * (st.sigilR * 0.85)
			local e = u ^ 1.4
			local p = start:Lerp(mid, e):Lerp(mid:Lerp(st.Q, e), e)
			local swirl = (1 - e) * 1.6
			local a = w.angle * 3 + e * 14
			move(seq, w.part, CFrame.new(p + Vector3.new(math.cos(a) * swirl, 0, math.sin(a) * swirl)))
		end
	end
end

local function strike(seq)
	local st = seq.stage
	seq.boltIndex = seq.boltIndex % #seq.bolts + 1
	local bolt = seq.bolts[seq.boltIndex]
	local radius = seq.sphereW * 0.5 * (if seq.sphere then seq.sphere.k else 1)
	local out = rng:NextUnitVector()
	local from = st.Q + out * radius
	local to
	if rng:NextNumber() < 0.35 then
		-- crackle down onto the summon circle
		to = Vector3.new(st.S.X, st.groundS + 0.3, st.S.Z) + rotY(st.dir, rng:NextNumber(0, math.pi * 2)) * (seq.circleR * 0.9)
	else
		to = st.Q + (out + rng:NextUnitVector() * 0.45).Unit * (radius + rng:NextNumber(2.5, 5.5))
	end
	local segs = #bolt.segs
	local d = to - from
	local prev = from
	for i = 1, segs do
		local nxt = if i == segs then to else from + d * (i / segs) + rng:NextUnitVector() * d.Magnitude * 0.09
		local seg = bolt.segs[i]
		local w = 0.2 - i * 0.012
		seg.Size = Vector3.new(w, w, math.max((nxt - prev).Magnitude, 0.05))
		seg.CFrame = CFrame.lookAt((prev + nxt) / 2, nxt)
		seg.Transparency = 0
		prev = nxt
	end
	bolt.hideAt = seq.t + 0.09
	bolt.visible = true
	if not seq.lightningSound then seq.lightningSound = playHook(seq, seq.tier, "lightning") end
end

local function makeLightning(seq, tier, delay)
	local bolts = {}
	for bi = 1, 3 do
		local segs = {}
		for i = 1, 7 do
			local p = clone("Bolt", function() return newPart({ Size = Vector3.new(0.18, 0.18, 1) }) end)
			p.Transparency = 1
			p.CFrame = CFrame.new(seq.stage.Q)
			p.Parent = seq.folder
			paint(seq, p, "light")
			segs[i] = p
		end
		bolts[bi] = { segs = segs, hideAt = 0, visible = false }
	end
	seq.bolts, seq.boltIndex, seq.boltAcc = bolts, 0, 0
	later(seq, delay, function()
		seq.actors.lightning = function(sdt, t)
			seq.boltAcc += sdt * (tier.lightning or 0) * 7 * seq.boltBoost
			while seq.boltAcc >= 1 do
				seq.boltAcc -= 1
				strike(seq)
			end
			for _, bolt in bolts do
				if bolt.visible and t >= bolt.hideAt then
					bolt.visible = false
					for _, s in bolt.segs do s.Transparency = 1 end
				end
			end
		end
	end)
end

-- light shafts rising from the edge of the summon circle
local function makeFloorBeams(seq, tier, b)
	local n = math.clamp(math.floor(tier.floorBeams or 0), 0, 12)
	if n == 0 then return end
	local st = seq.stage
	local base = CFrame.new(st.S.X, st.groundS, st.S.Z)
	local anchor = newPart({ Name = "ShaftAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = base })
	local beams = {}
	for i = 1, n do
		local off = rotY(st.dir, i / n * math.pi * 2 + 0.3) * seq.circleR
		local a0 = make("Attachment", { Position = off + Vector3.new(0, 0.15, 0) }, anchor)
		local a1 = make("Attachment", { Position = off + Vector3.new(0, 16, 0) }, anchor)
		local beam = clone("Beams/LightShaft", function() return make("Beam", { LightEmission = 1, FaceCamera = true }) end)
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = 0, 0
		beam.Parent = anchor
		paint(seq, beam, "glow", "seq")
		beams[i] = beam
	end
	anchor.Parent = seq.folder
	local data = { beams = beams, w = 0 }
	seq.shafts = data
	tween(seq, math.max(b * 0.3, 0.15), function(k)
		data.w = k
		for _, beam in beams do beam.Width0 = 1.3 * k; beam.Width1 = 0.35 * k end
	end, "out", b * 0.2)
	local angle = 0
	seq.actors.shafts = function(sdt)
		angle += sdt * 0.5
		move(seq, anchor, base * CFrame.Angles(0, angle, 0))
	end
end

-- giant light pillars around the summon spot (Legendary)
local function makePillars(seq, tier, delay, duration)
	local n = math.clamp(math.floor(tier.pillars or 0), 0, 8)
	if n == 0 then return end
	local st = seq.stage
	-- the pillars rise around the ALTAR (beside and behind the sphere), never between camera and champion
	local radius = st.sigilR + 1.5
	local angles = { 55, -55, 125, -125, 90, -90, 160, -160 }
	local list = {}
	for i = 1, n do
		local pos = Vector3.new(st.center.X, st.floorY, st.center.Z) + rotY(st.dir, math.rad(angles[i])) * radius
		local p = clone("Pillar", function() return newPart({ Shape = Enum.PartType.Cylinder, Transparency = 0.25 }) end)
		p.Size = Vector3.new(0.1, 2.2, 2.2)
		p.Transparency = 0.4
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = seq.folder
		paint(seq, p, "glow")
		list[i] = { part = p, pos = pos, h = 0.1, w = 2.2 }
	end
	seq.pillars = list
	tween(seq, duration, function(k)
		for _, pl in list do
			pl.h = lerp(0.1, 36, k)
			pl.part.Size = Vector3.new(pl.h, pl.w, pl.w)
			pl.part.CFrame = CFrame.new(pl.pos + Vector3.new(0, pl.h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end, "out", delay)
end

-- Mythic: dark energy spreads over the ground, then crimson erupts out of it
local function darkSpread(seq, b)
	local tier, st = seq.tier, seq.stage
	local pal = tier.palette
	setTheme(seq, tier.darkPalette or { main = pal.dark:Lerp(pal.main, 0.25), light = pal.dark, dark = BLACK, glow = pal.dark:Lerp(pal.main, 0.45) }, b * 0.25)
	local pool = clone("DarkPool", function()
		return newPart({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(10, 0, 6) })
	end)
	pool.CFrame = CFrame.new(st.S.X, st.groundS + 0.16, st.S.Z) * CFrame.Angles(0, 0, math.rad(90))
	pool.Size = Vector3.new(0.05, 0.2, 0.2)
	pool.Transparency = 0.28
	pool.Parent = seq.folder
	tween(seq, b * 0.5, function(k) local d = lerp(0.2, 34, k); pool.Size = Vector3.new(0.05, d, d) end, "out")
	local mistHolder = newPart({ Name = "Mist", Size = Vector3.new(22, 0.2, 22), Transparency = 1, CFrame = CFrame.new(st.S.X, st.groundS + 0.4, st.S.Z) })
	local mist = clone("Emitters/DarkMist", function() return Instance.new("ParticleEmitter") end)
	mist.Enabled = true
	mist.Parent = mistHolder
	mistHolder.Parent = seq.folder
	seq.darkPool, seq.darkMist = pool, mist
	darkenTo(seq, math.min((tier.darken or 0) + 0.08, 0.5), b * 0.4, "inout")
	later(seq, b * 0.5, function()
		-- the "upgrade" moment
		setTheme(seq, pal, b * 0.12)
		pool.Color = Color3.fromRGB(46, 0, 12)
		flash(seq, pal.main, 0.12)
		kick(seq, (tier.shake or 0) * 0.6)
		shock(seq, Vector3.new(st.S.X, st.groundS + 0.35, st.S.Z), pal.main, 14, 0.5, 1)
		seq.boltBoost = 1.8
		if seq.sphere then seq.sphere.pulse = 0.3 end
	end)
end

-- everything from the build-up winds down at the reveal
local function endBuildEffects(seq)
	for _, pe in { seq.crystalConverge, seq.sphereConverge } do pe.Enabled = false end
	if seq.feed then
		local feed = seq.feed
		tween(seq, 0.15, function(k)
			for _, f in feed do f.beam.Width0 = f.w0 * (1 - k); f.beam.Width1 = f.w1 * (1 - k) end
		end, "in")
	end
	for _, beam in seq.altarBeams do beam.Enabled = false end
	local d = seq.dressing
	if d then
		local from
		tween(seq, 0.35, function(k)
			from = from or (tonumber(d:GetAttribute("Boost")) or 1)
			d:SetAttribute("Boost", lerp(from, 0.3, k))
		end, "out")
	end
	if seq.rings then
		local rings = seq.rings
		tween(seq, 0.35, function(k)
			for _, ring in rings do
				ring.expand = lerp(1, 2.4, k)
				for _, s in ring.segs do s.Transparency = lerp(0.05, 1, k) end
			end
			if k >= 1 then seq.actors.rings = nil end
		end, "out")
	end
	if seq.runes then
		local data = seq.runes
		local r0
		tween(seq, 0.4, function(k)
			r0 = r0 or data.radius
			data.radius = r0 * lerp(1, 2.2, k)
			for _, r in data.list do
				for _, e in r.parts do e.part.Transparency = lerp(e.base, 1, k) end
			end
			if k >= 1 then seq.actors.runes = nil end
		end, "out")
	end
	if seq.wisps then
		seq.actors.wisps = nil
		for _, w in seq.wisps do
			w.part.Transparency = 1
			if w.trail then w.trail.Enabled = false end
		end
	end
	if seq.bolts then
		seq.actors.lightning = nil
		for _, bolt in seq.bolts do
			for _, s in bolt.segs do s.Transparency = 1 end
		end
	end
	if seq.lightningSound then fadeSound(seq, seq.lightningSound, 0, 0.3) end
	if seq.chargeSound then fadeSound(seq, seq.chargeSound, 0, 0.35) end
	if seq.riser then fadeSound(seq, seq.riser, 0, 0.2) end
	if seq.shafts then
		local data = seq.shafts
		tween(seq, 0.45, function(k)
			for _, beam in data.beams do beam.Width0 = 1.3 * data.w * (1 - k); beam.Width1 = 0.35 * data.w * (1 - k) end
		end, "out")
	end
	if seq.pillars then
		local list = seq.pillars
		tween(seq, 0.6, function(k)
			for _, pl in list do
				local w = pl.w * lerp(1, 2, k)
				pl.part.Size = Vector3.new(pl.h, w, w)
				pl.part.Transparency = lerp(0.4, 1, k)
			end
		end, "out")
	end
	if seq.darkPool then
		local pool = seq.darkPool
		seq.darkMist.Enabled = false
		tween(seq, 0.6, function(k) pool.Transparency = lerp(0.28, 1, k) end, "out")
	end
	seq.rumble = 0
	local spin0
	tween(seq, 0.5, function(k) spin0 = spin0 or seq.spin; seq.spin = lerp(spin0, 0.2, k) end, "out")
end

-- light rays fanning out behind the champion at the big reveal (tier.rays; Rare and up).
-- One anchor part carries every ray (Beams between attachments), so spinning it is one CFrame.
local function makeRays(seq, e)
	local tier = e.tier
	local n = math.clamp(math.floor(tier.rays or 0), 0, 24)
	if n == 0 then return end
	local pal = tier.palette
	local toward = flat((e.face or e.spot) - e.spot)
	toward = if toward.Magnitude > 0.1 then toward.Unit else seq.stage.dir
	-- the fan stands behind the champion (further back in a lineup, behind the side champions too),
	-- centred on the chest and facing the camera
	local center = e.spot + Vector3.new(0, e.heightFinal * 0.55, 0) - toward * (if seq.multi then 4 else 2)
	local base = CFrame.lookAt(center, center + toward)
	local anchor = newPart({ Name = "RayFan", Size = Vector3.one * 0.2, Transparency = 1, CFrame = base })
	local hub = make("Attachment", { Name = "Hub" }, anchor)
	local length = e.heightFinal * 1.35 + 3
	local rays = {}
	for i = 1, n do
		local a = (i - 0.5) / n * math.pi * 2
		local tip = make("Attachment", { Name = "Tip" }, anchor)
		local beam = clone("Beams/Ray", function()
			return make("Beam", { FaceCamera = true, LightEmission = 0.35, LightInfluence = 0, Segments = 10, Width0 = 0.15, Width1 = 1.6,
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.08, 0.3),
					NumberSequenceKeypoint.new(0.5, 0.62), NumberSequenceKeypoint.new(1, 1) }) })
		end)
		beam.Attachment0, beam.Attachment1 = hub, tip
		beam.Color = ColorSequence.new(pal.light, pal.main)
		local long = i % 2 == 0 -- long wide rays and short thin ones take turns
		if tier.rayDark and not long then
			-- (Mythic) the short rays are dark streaks between the glowing ones: a crimson + black fan
			beam.Color = ColorSequence.new(pal.dark, pal.main:Lerp(pal.dark, 0.5))
			beam.LightEmission = 0
		end
		rays[i] = { beam = beam, tip = tip, dir = Vector3.new(math.cos(a), math.sin(a), 0),
			len = length * (if long then 1 else 0.72), w0 = beam.Width0, w1 = beam.Width1 * (if long then 1.2 else 0.75) }
		beam.Width0, beam.Width1 = 0, 0
		beam.Parent = anchor
	end
	anchor.Parent = seq.folder
	local data = { grow = 0, dim = 1 }
	seq.rayFan = data
	tween(seq, 0.4, function(k) data.grow = k end, "back", 0.04)
	local angle, lastGrow, lastDim = 0, -1, -1
	local spin = tier.raySpeed or 0.25
	seq.actors.rays = function(sdt)
		angle += sdt * spin
		move(seq, anchor, base * CFrame.Angles(0, 0, angle))
		if data.grow ~= lastGrow or data.dim ~= lastDim then -- (only touch the rays while they change)
			lastGrow, lastDim = data.grow, data.dim
			for _, r in rays do
				r.tip.Position = r.dir * (r.len * (0.15 + 0.85 * data.grow))
				r.beam.Width0 = r.w0 * data.grow * data.dim
				r.beam.Width1 = r.w1 * data.grow * data.dim
			end
		end
	end
end

----------------------------------------------------------------------------
-- the big reveal treatment (single summon, or the best result of a multi-summon)
----------------------------------------------------------------------------
local function bigReveal(seq, e)
	local tier = e.tier
	local pal = tier.palette
	local chest = e.spot + Vector3.new(0, e.heightFinal * 0.45, 0)
	local ground = e.spot + Vector3.new(0, 0.3, 0)
	flash(seq, pal.light, tier.flash or 0)
	kick(seq, tier.shake or 0)
	-- multi-pulse burst: rings rolling out from the champion
	for i = 1, math.clamp(math.floor(tier.pulses or 0), 0, 3) do
		later(seq, (i - 1) * 0.11, function()
			shock(seq, chest, pal.light, seq.sphereW * (1.2 + i * 0.5), 0.35, 0.4)
		end)
	end
	if (tier.shockwave or 0) >= 14 then
		shock(seq, ground + Vector3.new(0, 0.1, 0), WHITE, tier.shockwave * 0.7, 0.45, 0.6) -- second, inner wave
	end
	playHook(seq, tier, "impact")
	makeRays(seq, e)
	if tier.banner then later(seq, 0.12, function() showBanner(seq, tier) end) end
	showCaption(seq, e)
	-- the scene lifts a little so the champion reads (tiers can keep it darker with revealDarken)
	darkenTo(seq, tonumber(tier.revealDarken) or (tier.darken or 0) * 0.55, 0.45, "out")
end

local function bloom(seq, e, final)
	local tier = e.tier
	if e.seed then
		e.seedState = "done"
		e.seed.Transparency = 1
		local tr = e.seed:FindFirstChildOfClass("Trail")
		if tr then tr.Enabled = false end
	end
	local chest = e.spot + Vector3.new(0, e.heightFinal * 0.45, 0)
	burstAt(seq, chest, tier, if final then (tier.burst or 30) else math.max(8, (tier.burst or 30) * 0.35))
	shock(seq, e.spot + Vector3.new(0, 0.3, 0), tier.palette.main, if final then (tier.shockwave or 6) else 3.5,
		if final then 0.6 else 0.35, if final then 1.4 else 0.6)
	revealChampion(seq, e, final)
	if seq.multi and not final then makeTag(seq, e) end
	playHook(seq, tier, "reveal", if final then 1 else 0.6)
	if final then bigReveal(seq, e) end
end

-- one small crystal shard per result flies out of the sphere to its lineup spot
local function launchSeed(seq, e)
	local seed = clone("Wisp", function() return newPart({ Name = "Seed" }) end)
	seed.Name = "Seed"
	seed.Shape = Enum.PartType.Block
	seed.Size = Vector3.new(0.7, 1.5, 0.7)
	seed.Color = e.tier.palette.main
	seed.Transparency = 0
	seed.CFrame = CFrame.new(seq.stage.Q)
	local tr = seed:FindFirstChildOfClass("Trail")
	if tr then
		tr.Color = ColorSequence.new(e.tier.palette.glow)
		tr.Enabled = true
	end
	make("PointLight", { Color = e.tier.palette.main, Range = if atLeast(e.rarity, "Epic") then 7 else 4.5,
		Brightness = if atLeast(e.rarity, "Epic") then 1.8 else 1, Shadows = false }, seed)
	seed.Parent = seq.folder
	e.seed = seed
	e.seedState = "fly"
	e.seedStart = seq.t
	e.seedFrom = seq.stage.Q
	e.seedTo = e.spot + Vector3.new(0, 1.3, 0)
	e.seedSize = 1
end

local function bloomGap(e)
	if atLeast(e.rarity, "Epic") then return BLOOM_GAP * 2 end
	if e.dup then return BLOOM_GAP * 0.5 end -- duplicates of the lower tiers bloom in half the time
	return BLOOM_GAP
end

----------------------------------------------------------------------------
-- camera plans
----------------------------------------------------------------------------
local function shotEstablish(seq)
	local st = seq.stage
	local fov = 68
	local top = math.max(st.crystal.Y + 3, st.Q.Y + 4)
	local bottom = st.groundS - 0.5
	local y = (top + bottom) / 2
	local focus = Vector3.new(st.S.X, y - 1, st.S.Z):Lerp(Vector3.new(st.center.X, y - 1, st.center.Z), 0.3)
	return makeShot(focus, -14, 7, distFor(top - bottom, fov, 0.8), fov)
end

local function shotMedium(seq)
	return makeShot(seq.stage.Q + Vector3.new(0, 2.2, 0), -10, 9, 14 + seq.sphereW, 64)
end

local function shotReveal(seq, e)
	local fov = 58
	local yaw = if seq.camStyle == "orbit" then 16 else -8
	local banner = seq.tier.banner ~= nil
	local pitch = if banner then -3 else 5 -- the top tiers get a heroic low angle
	-- the champion fills ~44 % of the screen height above the caption (bottom); with a banner at the
	-- top it is a bit smaller and lower (~25 %..65 % of the screen), so the title never covers the head
	local fill = if banner then 0.4 else 0.44
	local focusY = if banner then 0.38 else 0.3
	return makeShot(e.spot + Vector3.new(0, e.heightFinal * focusY, 0), yaw, pitch, distFor(e.heightFinal, fov, fill), fov)
end

local function shotLineup(seq)
	local st = seq.stage
	local h, mid = 0, Vector3.zero
	for _, e in seq.entries do
		h = math.max(h, e.heightFinal)
		mid += e.spot
	end
	mid /= #seq.entries
	local fov = 60
	local cam = workspace.CurrentCamera
	local aspect = math.max(cam.ViewportSize.X / math.max(cam.ViewportSize.Y, 1), 1)
	local tanH = math.tan(math.rad(fov / 2)) * aspect
	-- everyone in view with room above the heads for their name tags (caption stays below the feet)
	local dist = math.max(distFor(h, fov, 0.36), (st.half + 3.5) / tanH)
	return makeShot(mid + Vector3.new(0, h * 0.42, 0), -6, 8, dist, fov)
end

local function cameraStart(seq)
	if seq.camStyle == "hold" then
		camTo(seq, shotMedium(seq), 0)
	else
		camTo(seq, shotEstablish(seq), 0)
	end
end

local function cameraBuild(seq, b)
	local q, w = seq.stage.Q, seq.sphereW
	local style = seq.camStyle
	if style == "push" then
		camTo(seq, makeShot(q + Vector3.new(0, 1, 0), -14, 6, 14 + w, 62), b * 0.45, "inout")
		later(seq, b * 0.45, function() camTo(seq, makeShot(q + Vector3.new(0, 0.8, 0), -8, 4, 10.5 + w, 60), b * 0.55, "in") end)
	elseif style == "orbit" then
		camTo(seq, makeShot(q + Vector3.new(0, 1.2, 0), -40, 3, 13 + w, 62), b * 0.3, "inout")
		later(seq, b * 0.3, function() camTo(seq, makeShot(q + Vector3.new(0, 0.9, 0), 30, -3, 12 + w, 60), b * 0.7, "inout") end)
	elseif style == "zoom" then
		camTo(seq, makeShot(q + Vector3.new(0, 1, 0), -6, 5, 14 + w, 66), b * 0.35, "inout")
		later(seq, b * 0.35, function() camTo(seq, makeShot(q + Vector3.new(0, 0.8, 0), 0, 2, 12 + w, 50), b * 0.65, "in") end)
	else -- "hold": stay on the medium shot with a slow drift
		camTo(seq, makeShot(q + Vector3.new(0, 2, 0), -6, 8, 13 + w, 63), b + 0.2, "inout")
	end
end

local function cameraReveal(seq, shot)
	if seq.camStyle == "zoom" then
		-- a quick zoom punch, then settle
		local punch = table.clone(shot)
		punch.fov = shot.fov - 8
		punch.dist = shot.dist * 0.92
		camTo(seq, punch, 0.2, "out")
		later(seq, 0.2, function() camTo(seq, shot, 0.8, "inout") end)
	else
		camTo(seq, shot, if seq.camStyle == "hold" then 0.35 else 0.45, "out")
	end
end

----------------------------------------------------------------------------
-- the frame loop (one RenderStep binding per sequence, right after the default camera)
----------------------------------------------------------------------------
local function watch(seq)
	scanHide(seq)
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and flat(root.Position - seq.stage.S).Magnitude > 120 then
		task.defer(finish, seq, "aborted") -- teleported away mid-summon
		return
	end
	if seq.holding then
		local held = os.clock() - seq.holdStart
		-- the HUD sets the LocalPlayer attribute SummonResultsOpen true/false; without it we look
		-- for its result screen ("Reveal") ourselves
		local flag = lp and lp:GetAttribute("SummonResultsOpen")
		local open = if flag ~= nil then flag == true else resultScreenOpen()
		if open then
			seq.sawScreen = true
		elseif seq.sawScreen or held > HOLD_NO_SCREEN then
			task.defer(finish, seq, "released")
			return
		end
		if held > (if flag == true then HOLD_SCREEN_MAX else HOLD_MAX) then task.defer(finish, seq, "released") end
	end
end

local function step(seq, dt)
	dt = math.min(dt, 0.1)
	local sdt = dt * (if seq.holding then 1 else speed)
	seq.t += sdt
	if not seq.canSkip and not seq.holding and seq.t >= CAN_SKIP_AFTER then seq.canSkip = true end

	-- 1) tweens, in the order they were made (newer ones win)
	seq.iterating = true
	local list = seq.anims
	local n, w = #list, 0
	for i = 1, n do
		local a = list[i]
		local keep = true
		if seq.t >= a.start then
			local k = clamp01((seq.t - a.start) / a.dur)
			a.fn(a.ease(k))
			keep = k < 1
		end
		if keep then
			w += 1
			list[w] = a
		end
	end
	for i = n, w + 1, -1 do list[i] = nil end
	seq.iterating = false
	for _, a in seq.pending do table.insert(list, a) end
	table.clear(seq.pending)

	-- 2) moving pieces: one BulkMoveTo for everything
	table.clear(seq.moveParts)
	table.clear(seq.moveCFrames)
	for _, fn in seq.actors do fn(sdt, seq.t) end
	if #seq.moveParts > 0 then
		workspace:BulkMoveTo(seq.moveParts, seq.moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- 3) colours and camera
	updateTheme(seq)
	updateCamera(seq, dt)

	-- 4) keep our own character hidden (the default camera scripts may reset it)
	for _, p in seq.charParts do p.LocalTransparencyModifier = 1 end

	-- 5) safety checks a few times per second
	seq.watchClock += dt
	if seq.watchClock >= 0.2 then
		seq.watchClock = 0
		watch(seq)
	end
end

----------------------------------------------------------------------------
-- setup / cleanup
----------------------------------------------------------------------------
local function makeEntries(results)
	local list = {}
	if type(results) ~= "table" then return list end
	for i, r in ipairs(results) do
		if #list >= MAX_RESULTS then break end
		if type(r) == "table" and type(r.id) == "string" then
			local def = Config.ChampionById[r.id]
			local rarity = if type(r.rarity) == "string" and r.rarity ~= "" then r.rarity else (def and def.rarity or "Common")
			table.insert(list, {
				result = r, index = i, def = def, rarity = rarity, tier = SummonTiers.get(rarity),
				dup = r.new == false,
				power = tonumber(r.power) or (def and def.power) or 0,
				name = if def then def.name else r.id,
				phase = rng:NextNumber(0, math.pi * 2),
			})
		end
	end
	-- bloom order: lowest rarity first, the best one last
	table.sort(list, function(a, b)
		local ra, rb = SummonTiers.rank(a.rarity), SummonTiers.rank(b.rarity)
		if ra ~= rb then return ra < rb end
		return a.index < b.index
	end)
	return list
end

-- lineup spacing: at least LINEUP_GAP, wider when the champions are wide (they must never overlap)
local function lineupGap(entries)
	local models = ReplicatedStorage:FindFirstChild("ChampionModels")
	local widest = 0
	for _, e in entries do
		local t = models and models:FindFirstChild(e.result.id)
		local width = 4
		if t and t:IsA("Model") then
			local _, size = t:GetBoundingBox()
			width = math.min(size.X, 7)
		end
		widest = math.max(widest, width * math.min(e.tier.championScale or 1.3, 1.25))
	end
	return math.max(LINEUP_GAP, widest + 0.8)
end

local function newSeq(entries, opts)
	local best = entries[#entries]
	local tier = best.tier
	local multi = #entries > 1
	local gap = if multi then lineupGap(entries) else LINEUP_GAP
	local quick = opts.quick == true and not multi and not atLeast(best.rarity, "Rare")
	local times = if quick then QUICK_TIMES else tier.times
	local revealTime = times.reveal
	if not multi and best.dup and not atLeast(best.rarity, "Epic") then revealTime *= 0.5 end
	local sphereW = 3.4 * (tier.sphereScale or 1) * (if quick then 0.85 else 1)
	return {
		entries = entries, best = best, tier = tier, multi = multi, quick = quick, times = times, revealTime = revealTime,
		camStyle = if quick then "hold" else (tier.camera or "hold"),
		sphereW = sphereW,
		gap = gap,
		circleR = if multi then (#entries - 1) * gap / 2 + 2.8 else math.max(2.8, sphereW * 0.75 + 1.3),
		barHeight = if quick or not atLeast(best.rarity, "Rare") then 0.045 else 0.065,
		blendTime = if quick then 0.3 else 0.5,
		t = 0, stop = false, done = false, canSkip = false, holding = false, iterating = false,
		anims = {}, pending = {}, actors = {}, conns = {}, sounds = {}, saved = {}, hidden = {},
		charParts = {}, altarBeams = {}, paintables = {}, shockSlots = {}, shockIndex = 0,
		moveParts = {}, moveCFrames = {},
		theme = paletteCopy(NEUTRAL), lastTint = 0, dark = 0, kick = 0, rumble = 0, spin = 0, boltBoost = 1,
		watchClock = 0, renderName = "", camClamp = math.huge,
	}
end

local function cleanup(seq, reason)
	local soft = reason == "finished" or reason == "released"
	try("unbind", function() RunService:UnbindFromRenderStep(seq.renderName) end)
	for _, c in seq.conns do c:Disconnect() end
	table.clear(seq.conns)
	try("sounds", function()
		-- loops always stop; after a normal end the last chime may ring out
		for s in seq.sounds do
			if s.Looped or not soft then s:Stop() end
		end
	end)
	try("altar", function()
		local d = seq.dressing
		if d and d.Parent then
			d:SetAttribute("Boost", 0)
			d:SetAttribute("Tint", nil)
		end
	end)
	-- everything we borrowed from other objects goes back exactly
	for inst, props in seq.saved do
		for prop, value in props do
			pcall(function() (inst :: any)[prop] = value end)
		end
	end
	table.clear(seq.saved)
	table.clear(seq.charParts)
	try("effects", function() if seq.folder then seq.folder:Destroy() end end)
	try("gui", function() if seq.ui then seq.ui.gui:Destroy() end end)
	try("lighting", function()
		if seq.grade then seq.grade:Destroy() end
		if seq.savedExposure ~= nil then Lighting.ExposureCompensation = seq.savedExposure end
	end)
	try("camera", function() restoreCamera(seq) end)
	try("controls", function()
		if seq.controlsOff then
			seq.controlsOff = false
			local c = getControls()
			if c then c:Enable() end
		end
	end)
end

function finish(seq, reason)
	if seq.done then return end
	seq.done = true
	seq.stop = true
	seq.reason = reason
	if current == seq then current = nil end
	cleanup(seq, reason)
	phaseEvent:Fire("done", reason)
end

local function setup(seq, altar)
	local lp = Players.LocalPlayer
	local cam = workspace.CurrentCamera
	stopAllSounds()
	counter += 1
	seq.id = counter
	seq.renderName = "SummonCinematic_" .. counter
	local folder = Instance.new("Folder")
	folder.Name = "SummonSequence_" .. counter
	folder.Parent = effectsRoot()
	seq.folder = folder

	-- where everything happens
	seq.stage = computeStage(seq, altar)
	local st = seq.stage
	seq.dressing = st.dressing
	for i = #seq.entries, 1, -1 do
		seq.entries[i].spot = st.spots[st.order[#seq.entries - i + 1]]
	end

	-- camera (saved exactly, restored by cleanup)
	seq.camType, seq.camSubject, seq.camCFrame, seq.camFov = cam.CameraType, cam.CameraSubject, cam.CFrame, cam.FieldOfView
	seq.camSaved = true
	cam.CameraType = Enum.CameraType.Scriptable

	-- player controls off only during the sequence
	local controls = getControls()
	if controls then
		seq.controlsOff = true
		try("disable controls", function() controls:Disable() end)
	end
	try("touch jump", function() hideTouchJump(seq) end)

	-- lighting
	seq.savedExposure = Lighting.ExposureCompensation
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SummonGrade"
	grade.Parent = Lighting
	seq.grade = grade

	-- prompts and the shrine's name sign get out of the shot
	try("prompts", function()
		remember(seq, ProximityPromptService, "Enabled")
		ProximityPromptService.Enabled = false
	end)
	if st.shrine then
		for _, d in st.shrine:GetDescendants() do
			if d:IsA("BillboardGui") and not (st.dressing and d:IsDescendantOf(st.dressing)) then
				remember(seq, d, "Enabled")
				d.Enabled = false
			end
		end
	end
	if st.dressing then
		local beams = st.dressing:FindFirstChild("Beams")
		if beams then
			for _, b in beams:GetChildren() do
				if b:IsA("Beam") then
					remember(seq, b, "Enabled")
					remember(seq, b, "Color")
					table.insert(seq.altarBeams, b)
				end
			end
		end
	end

	-- your own character (and anyone standing in the shot) is hidden; death/respawn ends the show
	if lp then
		local char = lp.Character
		if char then
			for _, p in char:GetDescendants() do
				if p:IsA("BasePart") then table.insert(seq.charParts, p) end
			end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				table.insert(seq.conns, hum.Died:Connect(function() finish(seq, "aborted") end))
			end
		end
		table.insert(seq.conns, lp.CharacterAdded:Connect(function() finish(seq, "aborted") end))
	end
	scanHide(seq)

	seq.ui = buildGui(seq)
	makeShockPool(seq, 8)
	makeBurst(seq)
	for _, e in seq.entries do prepareChampion(seq, e) end

	-- champions keep breathing in their pose (also during the hold)
	seq.actors.champions = function(_, t)
		for _, e in seq.entries do
			if e.shown and e.rig then
				local k = clamp01((t - e.riseStart) / 0.35)
				local pose = if k < 1 then Anim.Mix(P.land, e.pose, EASE.out(k)) else e.pose
				local idle = Anim.Idle(t + e.phase)
				for _, j in JOINTS do e.buf[j] = (pose[j] or ID) * (idle[j] or ID) end
				Anim.Blend(e.rig, e.buf, 1)
			end
		end
	end
	-- seeds fly in an arc, then hover and spin until they bloom
	seq.actors.seeds = function(_, t)
		for _, e in seq.entries do
			local seed = e.seed
			if seed and e.seedState ~= "done" then
				local pos
				if e.seedState == "fly" then
					local u = clamp01((t - e.seedStart) / SEED_FLIGHT)
					local ue = EASE.inout(u)
					local mid = (e.seedFrom + e.seedTo) / 2 + Vector3.new(0, 3, 0)
					pos = e.seedFrom:Lerp(mid, ue):Lerp(mid:Lerp(e.seedTo, ue), ue)
					if u >= 1 then e.seedState = "hover" end
				else
					pos = e.seedTo + Vector3.new(0, math.sin(t * 3 + e.phase) * 0.15, 0)
				end
				move(seq, seed, CFrame.new(pos) * CFrame.Angles(0, t * 4 + e.phase, math.rad(10)))
			end
		end
	end

	RunService:BindToRenderStep(seq.renderName, Enum.RenderPriority.Camera.Value + 1, function(dt)
		if seq.done then return end
		local ok, err = pcall(step, seq, dt)
		if not ok then
			warn("[SummonCinematic] frame error: " .. tostring(err))
			seq.stop = true
			task.defer(finish, seq, "error")
		end
	end)
end

----------------------------------------------------------------------------
-- the beats
----------------------------------------------------------------------------
local function phaseCharge(seq)
	local tier, st = seq.tier, seq.stage
	local c = seq.times.charge
	setPhase(seq, "charge")
	letterbox(seq, true, math.min(0.35, c))
	-- darken: the same small amount for everyone first (no spoilers), then the tier's own amount
	local early = math.min(tier.darken or 0, 0.12)
	darkenTo(seq, early, c * 0.4, "inout")
	darkenTo(seq, tier.darken or 0, c * 0.6, "inout", c * 0.4)
	-- the altar wakes up (the SummonAltars script reads Boost/Tint): rings spin up, sigil lights
	local d = seq.dressing
	if d then
		tween(seq, c, function(k) d:SetAttribute("Boost", k) end, "inout")
		for _, beam in seq.altarBeams do
			beam.Color = ColorSequence.new(seq.theme.glow)
			beam.Enabled = true
		end
	end
	makeCircle(seq)
	seq.crystalConverge = makeConverge(seq, st.crystal, 5.5, (tier.converge or 10) * 0.8)
	local spin0
	tween(seq, c, function(k) spin0 = spin0 or seq.spin; seq.spin = lerp(spin0, 0.6, k) end, "in")
	-- the tier shows itself from 40 % of the charge (Mythic first pretends to be gold)
	local first = if tier.falseColor then paletteFrom(tier.falseColor) else tier.palette
	later(seq, c * 0.4, function() setTheme(seq, first, c * 0.5) end)
	seq.chargeSound = playHook(seq, tier, "charge")
	local amb, ambVolume = playHook(seq, tier, "ambience", 0.02)
	if amb then
		seq.ambience = amb
		fadeSound(seq, amb, ambVolume, c + seq.times.build * 0.5)
	end
	cameraStart(seq)
	waitFor(seq, c)
end

local function phaseBuild(seq)
	local tier, st = seq.tier, seq.stage
	local b = seq.times.build
	setPhase(seq, "build")
	seq.crystalConverge.Enabled = false
	makeSphere(seq, b)
	makeFeed(seq, b)
	seq.sphereConverge = makeConverge(seq, st.Q, 4 + seq.sphereW * 0.5, tier.converge or 10)
	makeRings(seq, tier, b)
	makeRunes(seq, tier, b)
	if tier.spiral then makeWisps(seq, 6) end
	makeFloorBeams(seq, tier, b)
	if (tier.lightning or 0) > 0 then makeLightning(seq, tier, b * 0.3) end
	makePillars(seq, tier, b * 0.45, b * 0.55)
	-- the sphere throbs a few times as it fills up
	local pulses = math.floor(tier.pulses or 0)
	for i = 1, pulses do
		later(seq, b * (0.3 + 0.6 * i / (pulses + 1)), function() pulse(seq) end)
	end
	-- energy rises: rings spin faster, a low rumble grows
	local spin0
	tween(seq, b, function(k)
		spin0 = spin0 or seq.spin
		seq.spin = lerp(spin0, 1.6, k)
		seq.rumble = (tier.shake or 0) * 0.4 * k
	end, "in")
	if tier.darkSpread then darkSpread(seq, b) end
	-- risers are started part-way in, so their climax lands on the reveal
	local riser = playHook(seq, tier, "build")
	if riser and riser.TimeLength > b / speed + 0.1 then riser.TimePosition = riser.TimeLength - b / speed - 0.05 end
	seq.riser = riser
	cameraBuild(seq, b)
	waitFor(seq, b)
end

local function phaseSingle(seq)
	local e = seq.entries[1]
	setPhase(seq, "reveal")
	local shot = shotReveal(seq, e)
	e.face = shotPos(seq, shot) -- the champion looks at the camera
	endBuildEffects(seq)
	popSphere(seq)
	bloom(seq, e, true)
	cameraReveal(seq, shot)
	waitFor(seq, seq.revealTime)
end

local function phaseLineup(seq)
	local tier, st = seq.tier, seq.stage
	setPhase(seq, "reveal")
	local shot = shotLineup(seq)
	local camPos = shotPos(seq, shot)
	for _, e in seq.entries do e.face = camPos end
	endBuildEffects(seq)
	popSphere(seq)
	kick(seq, (tier.shake or 0) * 0.4)
	burstAt(seq, st.Q, tier, (tier.burst or 30) * 0.5)
	shock(seq, st.Q, seq.theme.light, seq.sphereW * 1.6, 0.35, 0.5)
	for _, e in seq.entries do launchSeed(seq, e) end
	camTo(seq, shot, 0.6, "inout")
	waitFor(seq, SEED_FLIGHT)
	for i, e in seq.entries do
		local final = i == #seq.entries
		local gap = bloomGap(e)
		if atLeast(e.rarity, "Epic") and e.seed then
			-- anticipation: the seed swells and glows before an Epic+ bloom
			local seed = e.seed
			tween(seq, gap, function(k) seed.Size = Vector3.new(0.7, 1.5, 0.7) * lerp(1, 1.6, k) end, "in")
			shock(seq, e.spot + Vector3.new(0, 0.3, 0), e.tier.palette.main, 2.5, gap, 0.3)
		end
		if final and atLeast(e.rarity, "Epic") then
			camTo(seq, makeShot(e.spot + Vector3.new(0, e.heightFinal * 0.4, 0), shot.yaw, 4, distFor(e.heightFinal, 58, 0.44), 58), gap + 0.3, "inout")
		end
		waitFor(seq, gap)
		bloom(seq, e, final)
	end
	waitFor(seq, seq.revealTime)
end

local function phaseOutro(seq)
	local o = math.max(seq.times.outro or 0.2, 0.1)
	setPhase(seq, "outro")
	local u = seq.ui
	if u then
		tween(seq, o, function(k)
			captionAlpha(u, k)
			if u.bannerAlpha then
				u.bannerAlpha(k)
				u.bannerScale.Scale = lerp(1, 0.85, k)
			end
		end, "inout")
		letterbox(seq, false, o)
	end
	if seq.rayFan then
		local data = seq.rayFan
		tween(seq, o + 0.3, function(k) data.dim = lerp(1, 0.6, k) end, "inout") -- (they stay, softer, during the hold)
	end
	if seq.multi then
		makeTag(seq, seq.best) -- the best one gets its name tag once the caption goes
		camTo(seq, shotLineup(seq), o + 0.7, "inout") -- back out so the whole lineup (and its tags) is in view
	end
	darkenTo(seq, (seq.tier.darken or 0) * 0.35, o + 0.3, "inout")
	if seq.ambience then fadeSound(seq, seq.ambience, 0, o + 0.4) end
	waitFor(seq, o)
end

-- after Play returns the champions stay posed (slow camera drift) until the result screen closes
local function beginHold(seq)
	seq.holding = true
	seq.canSkip = false
	seq.holdStart = os.clock()
	seq.sawScreen = false
	setPhase(seq, "hold")
	-- a slow drift, starting once the current camera move (e.g. the lineup pull-back) has landed
	local function drift()
		local s = shotNow(seq)
		if not s then return end
		local target = table.clone(s)
		target.dist = s.dist * 0.95
		target.yaw = s.yaw + 4
		camTo(seq, target, 9, "linear")
	end
	local c = seq.cam
	local left = if c then c.start + c.dur - seq.t else 0
	if left > 0.05 then later(seq, left, drift) else drift() end
end

-- tier.silence (Mythic): a held breath between the build and the reveal. The riser and the
-- ambience cut out, the sphere hangs still, then the reveal hits out of the quiet.
local function phaseSilence(seq)
	local s = tonumber(seq.tier.silence) or 0
	if s <= 0 or seq.quick then return end
	for snd in seq.sounds do
		if snd.IsPlaying then fadeSound(seq, snd, 0, math.min(0.15, s * 0.5)) end
	end
	local spin0
	tween(seq, s, function(k) spin0 = spin0 or seq.spin; seq.spin = lerp(spin0, 0.15, k); seq.rumble = 0 end, "out")
	waitFor(seq, s)
end

local function runSequence(seq, altar)
	setup(seq, altar)
	phaseCharge(seq)
	phaseBuild(seq)
	phaseSilence(seq)
	if seq.multi then phaseLineup(seq) else phaseSingle(seq) end
	phaseOutro(seq)
end

----------------------------------------------------------------------------
-- public API
----------------------------------------------------------------------------
function SummonCinematic.Play(results, altar, opts)
	if not RunService:IsClient() then return "server" end
	opts = if type(opts) == "table" then opts else {}
	if current then finish(current, "aborted") end -- never two at once
	local entries = makeEntries(results)
	if #entries == 0 then return "empty" end
	local seq = newSeq(entries, opts)
	current = seq
	speed = 1
	local ok, err = pcall(runSequence, seq, altar)
	if not ok and err ~= STOP then
		warn("[SummonCinematic] " .. tostring(err))
		finish(seq, "error")
		return "error"
	end
	if seq.done then return seq.reason or "aborted" end
	if opts.hold == false then
		finish(seq, "finished")
	else
		beginHold(seq)
	end
	return "finished"
end

function SummonCinematic.Skip(): boolean
	local seq = current
	if not seq or seq.holding or not seq.canSkip then return false end
	finish(seq, "skipped")
	return true
end

function SummonCinematic.IsPlaying(): boolean
	return current ~= nil and not current.holding
end

function SummonCinematic.CanSkip(): boolean
	return current ~= nil and not current.holding and current.canSkip == true
end

function SummonCinematic.IsHolding(): boolean
	return current ~= nil and current.holding == true
end

-- Clear: ends the hold (the lineup / posed champion goes, camera + controls come back) and sweeps
-- away anything a crashed sequence could have left behind. A summon that is still PLAYING is left
-- alone (Skip() is for that). Safe to call at any time, as often as you like.
function SummonCinematic.Clear(): boolean
	local seq = current
	local ended = false
	if seq and seq.holding then
		finish(seq, "released")
		ended = true
	end
	local live = current -- (nil now, unless a summon is still playing)
	try("sweep", function()
		local root = workspace:FindFirstChild("ClientEffects")
		if root then
			for _, f in root:GetChildren() do
				if string.sub(f.Name, 1, 15) == "SummonSequence_" and not (live and live.folder == f) then f:Destroy() end
			end
		end
		if not live then
			local grade = Lighting:FindFirstChild("SummonGrade")
			if grade then grade:Destroy() end
			local lp = Players.LocalPlayer
			local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
			local gui = pg and pg:FindFirstChild("SummonCinematicUI")
			if gui then gui:Destroy() end
		end
	end)
	return ended
end
SummonCinematic.Release = SummonCinematic.Clear
SummonCinematic.ClearLineup = SummonCinematic.Clear

function SummonCinematic.SetSpeed(multiplier: number)
	speed = math.clamp(tonumber(multiplier) or 1, 0.25, 4)
end

function SummonCinematic.GetSpeed(): number
	return speed
end

-- Auto Hatch: a cheap 0.6 s flash of the altar in the tier colour (the SummonAltars script animates it)
function SummonCinematic.Pulse(altar, rarityId)
	local _, dressing = resolveAltar(altar)
	if not dressing then return end
	if current and current.dressing == dressing and not current.holding then return end
	local tier = SummonTiers.get(rarityId)
	dressing:SetAttribute("PulseColor", tier.palette.main)
	dressing:SetAttribute("PulseTime", os.clock())
end

function SummonCinematic.PlayUiSound(name)
	local id = SummonTiers.ui and SummonTiers.ui[name or "click"]
	if type(id) ~= "string" then return end
	local s = soundFor(id)
	s.Looped = false
	s.Volume = 0.4
	s.PlaybackSpeed = 1
	s.TimePosition = 0
	s:Play()
end

-- Studio only: play a tier with fake results, e.g. DebugPreview("Mythic") or
-- DebugPreview({ "Common", "Rare", "Legendary" }) or DebugPreview("Rare", nil, { duplicate = true })
function SummonCinematic.DebugPreview(rarity, altar, opts)
	if not RunService:IsStudio() then
		warn("[SummonCinematic] DebugPreview only works in Studio")
		return "not-studio"
	end
	opts = if type(opts) == "table" then opts else {}
	local ids = if type(rarity) == "table" then rarity else { rarity or "Legendary" }
	local models = ReplicatedStorage:FindFirstChild("ChampionModels")
	local results = {}
	for i, rid in ids do
		rid = tostring(rid)
		local pick, n = nil, 0
		for _, c in Config.Champions do
			if c.rarity == rid and (not models or models:FindFirstChild(c.id)) then
				n += 1
				pick = pick or c
				if n == i then pick = c break end -- a bit of variety in a lineup
			end
		end
		table.insert(results, { uid = "preview-" .. i, id = if pick then pick.id else "Unknown", new = not opts.duplicate,
			rarity = rid, power = if pick then pick.power else 0 })
	end
	if not altar then
		local lp = Players.LocalPlayer
		local char = lp and lp.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		altar = nearestShrine(if root then root.Position else workspace.CurrentCamera.CFrame.Position)
	end
	return SummonCinematic.Play(results, altar, opts)
end

-- warm up the summon sounds so the first summon isn't silent
if RunService:IsClient() and RunService:IsRunning() then
	task.spawn(function()
		local f = SoundService:WaitForChild("SummonSounds", 10)
		if not f then return end
		local list = {}
		for _, s in f:GetChildren() do
			if s:IsA("Sound") then table.insert(list, s) end
		end
		pcall(function() ContentProvider:PreloadAsync(list) end)
	end)
end

return SummonCinematic
