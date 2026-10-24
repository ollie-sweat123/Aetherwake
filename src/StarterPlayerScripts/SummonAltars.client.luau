-- SummonAltars (client): the idle animation of every summon altar's dressing
-- (the SummonAltar model inside each shrine): spinning energy rings, bobbing
-- runes, a breathing crystal light. It is purely cosmetic and local.
--
-- Cheap on purpose:
--   * only altars within ACTIVE_RANGE studs of the camera are animated
--   * ONE RenderStepped connection and ONE workspace:BulkMoveTo call per frame
--   * colours are only rewritten while they are actually changing
--
-- The summon cinematic talks to this script through attributes on the altar:
--   Boost (0..1)              -> rings/runes spin faster, crystal glows brighter
--   Tint (Color3)             -> colour the altar shifts to while Boost > 0
--   PulseTime + PulseColor    -> a short 0.6 s flash (SummonCinematic.Pulse / Auto Hatch)
--
-- The themed orb in the pedestal (an "OrbDesign" model inside the SummonAltar, one look per world:
-- Starter / Rift / Tide / Forge) idles here too, in the same loop:
--   Core (Neon ball + PointLight)  -> the glow breathes (light brightness)
--   Shell (Glass ball)             -> its transparency breathes with the glow
--   Orbiters/ (motes, shards, drops) -> circle the orb slowly and bob (attributes Speed, Phase, Bob, Twirl)
--   Spinners/ (water ring, cog ring)  -> turn on their own tilted axis with a slow wobble (Speed, Wobble)
-- Everything spins faster while the altar is awake (Boost / Pulse), like the rings above it.

local RunService = game:GetService("RunService")

local ACTIVE_RANGE = 120
local PULSE_TIME = 0.6

type Mover = { parts: { BasePart }, offsets: { CFrame } } -- parts that keep a fixed offset from a moving pivot
type Ring = Mover & { base: CFrame, speed: number, angle: number }
type Rune = Mover & { base: CFrame, phase: number }
type Orbiter = Mover & { base: CFrame, speed: number, phase: number, bob: number, twirl: number }
type Spinner = Mover & { base: CFrame, speed: number, angle: number, wobble: number }
type Orb = {
	center: Vector3,
	shell: BasePart?,
	shellBase: number,
	light: PointLight?,
	lightBase: number,
	orbiters: { Orbiter },
	spinners: { Spinner },
	angle: number,
}
type Altar = {
	model: Model,
	center: Vector3,
	crystalPos: Vector3,
	crystal: Mover?,
	light: PointLight?,
	lightBase: number,
	rings: { Ring },
	runes: { Rune },
	runeAngle: number,
	colorParts: { BasePart },
	baseColors: { Color3 },
	lastMix: number,
	lastTint: Color3?,
	orb: Orb?,
	orbRetryAt: number,
}

local altars: { [Model]: Altar } = {}

-- remember where every part of a group sits relative to a pivot
local function mover(pivot: CFrame, parts: { BasePart }): Mover
	local offsets = {}
	for i, p in parts do offsets[i] = pivot:ToObjectSpace(p.CFrame) end
	return { parts = parts, offsets = offsets }
end

local function partsOf(inst: Instance): { BasePart }
	local list = {}
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then table.insert(list, d) end
	end
	return list
end

-- read an altar's themed orb (OrbDesign). Returns nil if there is none, or while its parts
-- are still streaming in (we only start moving it once every part has arrived).
local function readOrb(model: Model): Orb?
	local design = model:FindFirstChild("OrbDesign")
	if not design then return nil end
	local center = design:GetAttribute("Center")
	if typeof(center) ~= "Vector3" then return nil end
	if #partsOf(design) < (tonumber(design:GetAttribute("PartCount")) or 0) then return nil end
	local o: Orb = {
		center = center, shell = nil, shellBase = 0.5, light = nil, lightBase = 1,
		orbiters = {}, spinners = {}, angle = 0,
	}
	local shell = design:FindFirstChild("Shell")
	if shell and shell:IsA("BasePart") then
		o.shell = shell
		o.shellBase = shell.Transparency
	end
	local core = design:FindFirstChild("Core")
	o.light = core and core:FindFirstChildOfClass("PointLight")
	if o.light then o.lightBase = o.light.Brightness end
	local orbiters = design:FindFirstChild("Orbiters")
	if orbiters then
		for _, p in orbiters:GetChildren() do
			if p:IsA("BasePart") then
				local r = mover(p.CFrame, { p }) :: Orbiter
				r.base = p.CFrame
				r.speed = tonumber(p:GetAttribute("Speed")) or 1
				r.phase = tonumber(p:GetAttribute("Phase")) or 0
				r.bob = tonumber(p:GetAttribute("Bob")) or 0.3
				r.twirl = tonumber(p:GetAttribute("Twirl")) or 0
				table.insert(o.orbiters, r)
			end
		end
	end
	local spinners = design:FindFirstChild("Spinners")
	if spinners then
		for _, m in spinners:GetChildren() do
			if m:IsA("Model") then
				local base = m.WorldPivot
				local s = mover(base, partsOf(m)) :: Spinner
				s.base = base
				s.speed = tonumber(m:GetAttribute("Speed")) or 0.4
				s.wobble = tonumber(m:GetAttribute("Wobble")) or 0
				s.angle = 0
				table.insert(o.spinners, s)
			end
		end
	end
	return o
end

local function register(model: Model)
	if altars[model] or not model:GetAttribute("SummonAltar") then return end
	local center = model:GetAttribute("Center")
	local crystalPos = model:GetAttribute("CrystalPosition")
	if typeof(center) ~= "Vector3" or typeof(crystalPos) ~= "Vector3" then return end
	local a: Altar = {
		model = model, center = center, crystalPos = crystalPos, crystal = nil, light = nil, lightBase = 1.2,
		rings = {}, runes = {}, runeAngle = 0, colorParts = {}, baseColors = {}, lastMix = 0, lastTint = nil,
		orb = nil, orbRetryAt = 0,
	}
	local crystal = model:FindFirstChild("Crystal")
	if crystal then
		a.crystal = mover(CFrame.new(crystalPos), partsOf(crystal))
		local core = crystal:FindFirstChild("Core")
		a.light = core and core:FindFirstChildOfClass("PointLight")
		if a.light then a.lightBase = a.light.Brightness end
	end
	local ringFolder = model:FindFirstChild("EnergyRings")
	if ringFolder then
		for _, m in ringFolder:GetChildren() do
			if m:IsA("Model") then
				local base = m.WorldPivot
				local r = mover(base, partsOf(m)) :: Ring
				r.base = base
				r.speed = tonumber(m:GetAttribute("Speed")) or 0.8
				r.angle = 0
				table.insert(a.rings, r)
			end
		end
	end
	local runeFolder = model:FindFirstChild("Runes")
	if runeFolder then
		for _, m in runeFolder:GetChildren() do
			if m:IsA("Model") then
				local base = m:GetPivot()
				local r = mover(base, partsOf(m)) :: Rune
				r.base = base
				r.phase = tonumber(m:GetAttribute("Phase")) or 0
				table.insert(a.runes, r)
			end
		end
	end
	-- the glowing pieces that change colour on Boost / Pulse
	for _, folderName in { "Sigil", "EnergyRings" } do
		local f = model:FindFirstChild(folderName)
		if f then
			for _, p in partsOf(f) do
				table.insert(a.colorParts, p)
				table.insert(a.baseColors, p.Color)
			end
		end
	end
	altars[model] = a
end

local function unregister(model: Model)
	local a = altars[model]
	if not a then return end
	altars[model] = nil
	-- put colours back in case the model streams back in later
	for i, p in a.colorParts do
		if p.Parent then p.Color = a.baseColors[i] end
	end
end

-- find altars now and whenever one streams in; drop them when they stream out
local function consider(inst: Instance)
	if inst:IsA("Model") and inst.Name == "SummonAltar" then
		-- wait a moment so all of its parts have arrived
		task.defer(function()
			if inst:IsDescendantOf(workspace) then register(inst) end
		end)
	end
end
for _, d in workspace:GetDescendants() do consider(d) end
workspace.DescendantAdded:Connect(consider)
workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("Model") and altars[inst] then unregister(inst) end
end)

-- reused every frame (no new tables per frame)
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function push(m: Mover, pivot: CFrame)
	for i, p in m.parts do
		local n = #moveParts + 1
		moveParts[n] = p
		moveCFrames[n] = pivot * m.offsets[i]
	end
end

RunService.RenderStepped:Connect(function(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local camPos = cam.CFrame.Position
	local now = os.clock()
	table.clear(moveParts)
	table.clear(moveCFrames)
	for model, a in altars do
		if not model.Parent then
			unregister(model)
		elseif (a.center - camPos).Magnitude < ACTIVE_RANGE then
			local boost = math.clamp(tonumber(model:GetAttribute("Boost")) or 0, 0, 1)
			local pulseAt = tonumber(model:GetAttribute("PulseTime")) or 0
			local pulse = math.clamp(1 - (now - pulseAt) / PULSE_TIME, 0, 1)
			local energy = math.max(boost, pulse) -- how "awake" the altar is right now
			local spinMul = 1 + energy * 5
			-- crystal: bob + slow spin
			if a.crystal then
				local bob = math.sin(now * 1.4) * 0.35
				push(a.crystal, CFrame.new(a.crystalPos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, now * 0.6 * (1 + energy * 3), 0))
			end
			if a.light then
				a.light.Brightness = a.lightBase + math.sin(now * 2) * 0.25 + boost * 2.5 + pulse * 3
			end
			-- energy rings spin around their own tilted axis
			for _, r in a.rings do
				r.angle += dt * r.speed * spinMul
				push(r, r.base * CFrame.Angles(0, r.angle, 0))
			end
			-- runes orbit the crystal slowly and bob up and down
			a.runeAngle += dt * 0.12 * spinMul
			local orbit = CFrame.new(a.crystalPos) * CFrame.Angles(0, a.runeAngle, 0) * CFrame.new(-a.crystalPos)
			for _, r in a.runes do
				local bob = Vector3.new(0, math.sin(now * 1.3 + r.phase) * 0.3, 0)
				push(r, (orbit * r.base) + bob)
			end
			-- colour: shift toward the summon tint (Boost) or the pulse colour (Pulse)
			local tint = model:GetAttribute("Tint")
			local pulseColor = model:GetAttribute("PulseColor")
			local target: Color3? = nil
			local mix = 0
			if pulse > boost and typeof(pulseColor) == "Color3" then
				target, mix = pulseColor, pulse
			elseif boost > 0 and typeof(tint) == "Color3" then
				target, mix = tint, boost
			end
			if math.abs(mix - a.lastMix) > 0.02 or (mix > 0 and target ~= a.lastTint) or (mix == 0 and a.lastMix ~= 0) then
				for i, p in a.colorParts do
					p.Color = if target then a.baseColors[i]:Lerp(target, mix * 0.85) else a.baseColors[i]
				end
				a.lastMix = mix
				a.lastTint = target
			end
			-- the themed orb: accents circle and bob, rings turn, the glow breathes
			if not a.orb and now >= a.orbRetryAt then
				a.orbRetryAt = now + 1 -- (try again in a second: still streaming in, or no OrbDesign)
				a.orb = readOrb(model)
			end
			local o = a.orb
			if o then
				o.angle += dt * 0.35 * spinMul
				local breath = math.sin(now * 1.7)
				if o.light then o.light.Brightness = o.lightBase + breath * 0.3 + energy * 2 end
				if o.shell then o.shell.Transparency = o.shellBase + breath * 0.05 end
				local c = o.center
				for _, r in o.orbiters do
					-- circle around the orb's vertical axis, twirl on the spot, bob up and down
					local around = CFrame.new(c) * CFrame.Angles(0, o.angle * r.speed, 0) * CFrame.new(-c)
					local lift = Vector3.new(0, math.sin(now * 1.2 + r.phase) * r.bob, 0)
					push(r, (around * r.base * CFrame.Angles(0, now * r.twirl, 0)) + lift)
				end
				for _, s in o.spinners do
					-- turn around the ring's own (tilted) axis; the tilt itself wobbles a little
					s.angle += dt * s.speed * spinMul
					local tilt = CFrame.Angles(math.sin(now * 0.5) * s.wobble, 0, math.cos(now * 0.4) * s.wobble)
					push(s, CFrame.new(c) * tilt * (CFrame.new(-c) * s.base) * CFrame.Angles(0, s.angle, 0))
				end
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
