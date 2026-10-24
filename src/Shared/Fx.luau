-- Fx: client-side visual effects toolkit (no textures/assets needed).
-- Every effect cleans itself up. All functions are safe to call many times.
-- Colours can be Color3 or "#rrggbb" strings.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local Fx = {}

local folder = workspace:FindFirstChild("ClientEffects")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = workspace
end

local function col(c)
	if typeof(c) == "Color3" then return c end
	if type(c) == "string" then return Color3.fromHex(c) end
	return Color3.new(1, 1, 1)
end
Fx.col = col

function Fx.Tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- basic effect part (anchored, no collisions, neon by default)
function Fx.Part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k == "Color" then p.Color = col(v) else (p :: any)[k] = v end
	end
	p.Parent = folder
	return p
end

-- expanding, fading ball
function Fx.Burst(pos, color, size, duration, opts)
	opts = opts or {}
	duration = duration or 0.35
	local p = Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (opts.startSize or size * 0.2), Color = color,
		Transparency = opts.transparency or 0.1, CFrame = CFrame.new(pos), Material = opts.material or Enum.Material.Neon })
	Fx.Tween(p, duration, { Size = Vector3.one * size, Transparency = 1 })
	Debris:AddItem(p, duration + 0.05)
	return p
end

-- flat expanding ring lying on a plane (cf's UpVector = ring normal)
function Fx.Ring(cf, color, startSize, endSize, duration, thickness)
	duration = duration or 0.4
	local p = Fx.Part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(thickness or 0.2, startSize, startSize), Color = color,
		Transparency = 0.15, CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) })
	Fx.Tween(p, duration, { Size = Vector3.new(thickness or 0.2, endSize, endSize), Transparency = 1 })
	Debris:AddItem(p, duration + 0.05)
	return p
end

-- ground shockwave: ring + dust puff
function Fx.Shockwave(pos, color, radius, duration)
	Fx.Ring(CFrame.new(pos + Vector3.new(0, 0.15, 0)), color, 1, radius * 2, duration or 0.45, 0.25)
	Fx.Ring(CFrame.new(pos + Vector3.new(0, 0.3, 0)), "#ffffff", 0.5, radius * 1.4, (duration or 0.45) * 0.7, 0.12)
	Fx.Particles(pos + Vector3.new(0, 0.5, 0), { color = "#d8cbb0", count = 14, speed = 10, size = 0.8, lifetime = 0.5, spread = 180 })
end

-- crescent slash arc: a sweep of thin neon wedges around cf (LookVector = slash forward, UpVector = arc axis)
function Fx.Slash(cf, color, radius, arcDeg, duration, width, tilt)
	duration = duration or 0.25
	local segs = 10
	arcDeg = arcDeg or 140
	local base = cf * CFrame.Angles(0, 0, math.rad(tilt or 0))
	for i = 0, segs do
		local a = math.rad(-arcDeg / 2 + arcDeg * i / segs)
		local w = (width or 0.5) * math.sin(math.pi * i / segs) + 0.05
		local segCF = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius)
		local p = Fx.Part({ Size = Vector3.new(radius * math.rad(arcDeg) / segs * 1.15, w, 0.08), Color = color, Transparency = 1, CFrame = segCF })
		task.delay(duration * i / segs * 0.6, function()
			p.Transparency = 0.05
			Fx.Tween(p, duration * 0.8, { Transparency = 1, Size = p.Size * Vector3.new(1, 0.2, 1) })
		end)
		Debris:AddItem(p, duration * 1.6)
	end
end

-- straight beam between two points (neon cylinder that thins out)
function Fx.Beam(from, to, color, width, duration)
	duration = duration or 0.25
	local d = (to - from)
	local p = Fx.Part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(d.Magnitude, width or 0.4, width or 0.4), Color = color,
		Transparency = 0.05, CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0) })
	Fx.Tween(p, duration, { Size = Vector3.new(d.Magnitude, 0.02, 0.02), Transparency = 1 })
	Debris:AddItem(p, duration + 0.05)
	return p
end

-- jagged lightning bolt
function Fx.Lightning(from, to, color, segments, duration, width)
	segments = segments or 8
	local prev = from
	local dir = to - from
	for i = 1, segments do
		local t = i / segments
		local nxt = from + dir * t
		if i < segments then
			nxt += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * dir.Magnitude * 0.12
		end
		Fx.Beam(prev, nxt, color, width or 0.25, duration or 0.2)
		prev = nxt
	end
end

-- moving projectile with a trail; calls onHit when it arrives. Returns the part.
function Fx.Projectile(from, to, speed, color, size, onHit, opts)
	opts = opts or {}
	local p = Fx.Part({ Shape = opts.shape or Enum.PartType.Ball, Size = Vector3.one * (size or 0.8), Color = color, CFrame = CFrame.lookAt(from, to) })
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, (size or 0.8) * 0.4, 0); a0.Parent = p
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -(size or 0.8) * 0.4, 0); a1.Parent = p
	local tr = Instance.new("Trail"); tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = opts.trailLife or 0.25
	tr.Color = ColorSequence.new(col(opts.trailColor or color)); tr.LightEmission = 1
	tr.Transparency = NumberSequence.new(0.1, 1); tr.FaceCamera = true; tr.Parent = p
	local dist = (to - from).Magnitude
	local t = dist / (speed or 60)
	local arc = opts.arc or 0
	task.spawn(function()
		local start = os.clock()
		while true do
			local k = math.min((os.clock() - start) / t, 1)
			local pos = from:Lerp(to, k) + Vector3.new(0, math.sin(math.pi * k) * arc, 0)
			p.CFrame = CFrame.lookAt(pos, to)
			if k >= 1 then break end
			task.wait()
		end
		if onHit then onHit(to) end
		p.Transparency = 1
		Debris:AddItem(p, 0.3)
	end)
	return p, t
end

-- quick particle puff (no textures: square sparks)
function Fx.Particles(pos, opts)
	opts = opts or {}
	local a = Fx.Part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local att = Instance.new("Attachment"); att.Parent = a
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(col(opts.color or "#ffffff"))
	-- light: a number 0..1, or true/false for glowing / not glowing
	pe.LightEmission = if type(opts.light) == "number" then opts.light elseif opts.light == true then 1 elseif opts.light == false then 0 else 0.6
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.size or 0.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(0.1, 1)
	pe.Lifetime = NumberRange.new((opts.lifetime or 0.5) * 0.6, opts.lifetime or 0.5)
	pe.Speed = NumberRange.new((opts.speed or 8) * 0.5, opts.speed or 8)
	pe.SpreadAngle = Vector2.new(opts.spread or 180, opts.spread or 180)
	pe.Acceleration = opts.gravity and Vector3.new(0, -opts.gravity, 0) or Vector3.zero
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-180, 180)
	pe.Enabled = false
	pe.Parent = att
	pe:Emit(opts.count or 12)
	Debris:AddItem(a, (opts.lifetime or 0.5) + 0.2)
	return pe
end

-- point light flash
function Fx.Light(pos, color, range, brightness, duration)
	local a = Fx.Part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight"); l.Color = col(color); l.Range = range or 14; l.Brightness = brightness or 3; l.Parent = a
	Fx.Tween(l, duration or 0.4, { Brightness = 0 })
	Debris:AddItem(a, (duration or 0.4) + 0.05)
end

-- spikes erupting from the ground in a ring or line
function Fx.Spikes(pos, color, count, height, duration, radius)
	for i = 1, count or 6 do
		local a = (i / (count or 6)) * math.pi * 2
		local r = (radius or 2) * (0.6 + math.random() * 0.4)
		local base = pos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local h = (height or 3) * (0.7 + math.random() * 0.5)
		local p = Fx.Part({ Size = Vector3.new(0.6, 0.1, 0.6), Color = color, Material = Enum.Material.Neon,
			CFrame = CFrame.new(base) * CFrame.Angles(math.rad(math.random(-25, 25)), a, math.rad(math.random(-25, 25))) })
		Fx.Tween(p, 0.15, { Size = Vector3.new(0.6, h, 0.6), CFrame = p.CFrame * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
		task.delay((duration or 0.6) * 0.6, function() Fx.Tween(p, (duration or 0.6) * 0.4, { Transparency = 1, Size = Vector3.new(0.1, h, 0.1) }) end)
		Debris:AddItem(p, (duration or 0.6) + 0.1)
	end
end

-- vertical light pillar
function Fx.Pillar(pos, color, height, radius, duration)
	local p = Fx.Part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height or 20, (radius or 2) * 2, (radius or 2) * 2), Color = color, Transparency = 0.2,
		CFrame = CFrame.new(pos + Vector3.new(0, (height or 20) / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	Fx.Tween(p, duration or 0.5, { Size = Vector3.new(height or 20, 0.1, 0.1), Transparency = 1 })
	Debris:AddItem(p, (duration or 0.5) + 0.05)
end

-- balls orbiting a moving centre (centreFn returns a Vector3) for `duration` seconds
function Fx.Orbit(centreFn, color, count, radius, duration, size, speed)
	local parts = {}
	for i = 1, count or 3 do
		parts[i] = Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (size or 0.6), Color = color })
	end
	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < (duration or 1) do
			local t = os.clock() - start
			local c = centreFn()
			for i, p in parts do
				local a = t * (speed or 6) + i / #parts * math.pi * 2
				p.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * (radius or 2), math.sin(t * 3 + i) * 0.4, math.sin(a) * (radius or 2)))
			end
			task.wait()
		end
		for _, p in parts do Fx.Tween(p, 0.15, { Size = Vector3.zero, Transparency = 1 }); Debris:AddItem(p, 0.2) end
	end)
	return parts
end

-- floating callout text (e.g. the ability name)
function Fx.Callout(pos, text, color, size, duration)
	local a = Fx.Part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromScale((size or 1) * 8, (size or 1) * 1.6); bb.LightInfluence = 0; bb.AlwaysOnTop = false; bb.Parent = a
	local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1, 1); l.BackgroundTransparency = 1; l.Font = Enum.Font.FredokaOne
	l.TextScaled = true; l.Text = text; l.TextColor3 = col(color); l.Parent = bb
	local s = Instance.new("UIStroke"); s.Thickness = 3; s.Color = Color3.new(0, 0, 0); s.Parent = l
	local sc = Instance.new("UIScale"); sc.Scale = 0.3; sc.Parent = l
	Fx.Tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	Fx.Tween(a, duration or 1, { CFrame = a.CFrame + Vector3.new(0, 2, 0) })
	task.delay((duration or 1) * 0.6, function() Fx.Tween(l, (duration or 1) * 0.4, { TextTransparency = 1 }); Fx.Tween(s, (duration or 1) * 0.4, { Transparency = 1 }) end)
	Debris:AddItem(a, (duration or 1) + 0.05)
end

-- attach a trail to a body part / weapon for `duration` seconds
function Fx.Trail(part, color, duration, width)
	if not part then return end
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, (width or 0.6), 0); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -(width or 0.6), 0); a1.Parent = part
	local tr = Instance.new("Trail"); tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = 0.18; tr.LightEmission = 1
	tr.Color = ColorSequence.new(col(color)); tr.Transparency = NumberSequence.new(0.15, 1); tr.Parent = part
	task.delay(duration or 0.4, function() tr.Enabled = false; Debris:AddItem(tr, 0.3); Debris:AddItem(a0, 0.3); Debris:AddItem(a1, 0.3) end)
end

-- camera shake + screen flash (only for the local player's own champions)
local shakeUntil, shakeAmount = 0, 0
function Fx.Shake(amount, duration)
	shakeAmount = math.max(shakeAmount, amount or 0.3)
	shakeUntil = math.max(shakeUntil, os.clock() + (duration or 0.25))
end
game:GetService("RunService"):BindToRenderStep("FxShake", Enum.RenderPriority.Camera.Value + 1, function()
	if os.clock() < shakeUntil then
		local cam = workspace.CurrentCamera
		local a = shakeAmount
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * 2 * a), math.rad((math.random() - 0.5) * 2 * a), 0)
			* CFrame.new((math.random() - 0.5) * a * 0.4, (math.random() - 0.5) * a * 0.4, 0)
	else
		shakeAmount = 0
	end
end)

local flashGui
function Fx.Flash(color, alpha, duration)
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return end
	if not flashGui or not flashGui.Parent then
		flashGui = Instance.new("ScreenGui"); flashGui.Name = "FxFlash"; flashGui.IgnoreGuiInset = true; flashGui.DisplayOrder = 50; flashGui.ResetOnSpawn = false; flashGui.Parent = pg
	end
	local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BorderSizePixel = 0; f.BackgroundColor3 = col(color); f.BackgroundTransparency = 1 - (alpha or 0.4); f.Parent = flashGui
	Fx.Tween(f, duration or 0.25, { BackgroundTransparency = 1 })
	Debris:AddItem(f, (duration or 0.25) + 0.05)
end

-- briefly tint a model with a Highlight (e.g. the enemy flashing white when hit)
function Fx.HitFlash(model, color, duration)
	if not model or not model.Parent then return end
	local h = Instance.new("Highlight")
	h.FillColor = col(color or "#ffffff"); h.FillTransparency = 0.3; h.OutlineTransparency = 1; h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model; h.Parent = folder
	Fx.Tween(h, duration or 0.15, { FillTransparency = 1 })
	Debris:AddItem(h, (duration or 0.15) + 0.05)
end

----------------------------------------------------------------------------
-- Ability animation language: Telegraph, Glint, ImpactStar
-- (added for the ability brief; every function above is unchanged)
----------------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local TELEGRAPH_LIFT = 0.05 -- studs above the ground point, so the marker never z-fights the floor
local DAMAGE_TINT = Color3.fromRGB(255, 90, 60) -- red/orange on the ground = "damage lands here"

-- Ground telegraph: shows WHERE and WHEN an ability's hit lands.
--   Fx.Telegraph(groundPos, radius, color, leadTime, style, opts?)
--   * groundPos = the point on the ground under the target (lifted 0.05 studs here)
--   * an outer ring (thin, ability colour) appears at once
--   * an inner disc fills from the centre to the ring over exactly `leadTime` seconds,
--     so the hit lands the moment it is full
--   * style "ultimate" adds a second, slower ring and 4 chevrons sliding inward
--   * opts.dim = true: ~35 % opacity and no chevrons (other players' champions)
--   * at the impact it flashes white for 0.08 s, fades out in 0.2 s and removes itself
-- It is ONE invisible anchor part; the rings, disc and chevrons are handle adornments
-- drawn on it (a part can't be ring-shaped, a CylinderHandleAdornment with InnerRadius can).
-- Returns a handle: handle.Impact() flashes it now (call it when the hit really lands),
-- handle.Destroy() removes it at once. Both are safe to call more than once.
function Fx.Telegraph(groundPos, radius, color, leadTime, style, opts)
	opts = opts or {}
	radius = math.max(tonumber(radius) or 5, 1)
	leadTime = math.max(tonumber(leadTime) or 1, 0.05)
	local ultimate = style == "ultimate"
	local accent = col(color)
	local opacity = if opts.dim then 0.35 else 1
	-- turns a normal transparency into this telegraph's one (dimmed for other players)
	local function see(transparency) return 1 - (1 - transparency) * opacity end

	local anchor = Fx.Part({ Name = "Telegraph", Size = Vector3.one * 0.2, Transparency = 1,
		CFrame = CFrame.new(groundPos + Vector3.new(0, TELEGRAPH_LIFT, 0)) })
	-- safety net FIRST: whatever happens next (even an error below, or an ability module
	-- that crashes), the marker is always removed
	Debris:AddItem(anchor, leadTime + 1.5)
	local shapes, tweens = {}, {}
	local function add(className, props)
		local a = Instance.new(className)
		for k, v in props do (a :: any)[k] = v end
		a.Adornee = anchor
		a.AlwaysOnTop = false
		a.Parent = anchor
		table.insert(shapes, a)
		return a
	end
	local function tween(inst, t, goal)
		local tw = TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Linear), goal)
		tw:Play()
		table.insert(tweens, tw)
	end
	-- cylinder adornments are drawn along their Z axis: tip them over so they lie flat.
	-- Each shape gets its own small height `y`, so overlapping shapes never flicker.
	local function flat(y) return CFrame.new(0, y, 0) * CFrame.Angles(math.rad(90), 0, 0) end

	local ringWidth = math.clamp(radius * 0.05, 0.15, 0.35)
	local fillMax = radius - ringWidth -- the disc grows until it touches the ring
	-- 1) outer ring: appears at once (WHERE)
	add("CylinderHandleAdornment", { Name = "Ring", CFrame = flat(0.01), Height = 0.04, Radius = radius, InnerRadius = fillMax,
		Color3 = accent, Transparency = see(0.05) })
	-- 2) inner disc: fills over exactly leadTime (WHEN)
	local fill = add("CylinderHandleAdornment", { Name = "Fill", CFrame = flat(0), Height = 0.02, Radius = 0.05, InnerRadius = 0,
		Color3 = accent:Lerp(DAMAGE_TINT, 0.35), Transparency = see(0.75) })
	tween(fill, leadTime, { Radius = fillMax, Transparency = see(0.4) })

	if ultimate then
		-- 3) a second, slower ring: a broken arc that starts wider, closes in and turns as it goes
		local slow = add("CylinderHandleAdornment", { Name = "SlowRing", CFrame = flat(0.03), Height = 0.04, Angle = 300,
			Radius = radius * 1.45, InnerRadius = radius * 1.45 - ringWidth * 0.7, Color3 = accent:Lerp(WHITE, 0.35), Transparency = see(0.25) })
		tween(slow, leadTime, { Radius = radius + ringWidth * 1.6, InnerRadius = radius + ringWidth * 0.9,
			CFrame = flat(0.03) * CFrame.Angles(0, 0, math.rad(150)) })
		-- 4) four chevrons (a "V" of two thin bars each), tips pointing at the centre, sliding inward
		if not opts.dim then
			local arm = math.clamp(radius * 0.2, 0.9, 1.8)
			local spread = math.rad(38)
			local function armCFrame(dir, dist, side) -- dir = flat unit vector from the centre outward
				local tip = dir * dist + Vector3.new(0, 0.06, 0)
				local armDir = CFrame.Angles(0, side * spread, 0):VectorToWorldSpace(dir)
				local mid = tip + armDir * arm / 2
				return CFrame.lookAt(mid, mid + armDir)
			end
			for i = 0, 3 do
				local a = i * math.pi / 2 + math.pi / 4
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				for _, side in { -1, 1 } do
					local bar = add("BoxHandleAdornment", { Name = "Chevron", Size = Vector3.new(0.3, 0.04, arm),
						CFrame = armCFrame(dir, radius + 0.4, side), Color3 = accent:Lerp(WHITE, 0.5), Transparency = see(0.1) })
					tween(bar, leadTime, { CFrame = armCFrame(dir, radius * 0.4, side) })
				end
			end
		end
	end

	local finished = false
	local handle = { part = anchor }
	function handle.Impact()
		if finished then return end
		finished = true
		for _, tw in tweens do tw:Cancel() end
		fill.Radius = fillMax -- full: the hit lands the moment it is full
		for _, s in shapes do s.Color3 = WHITE; s.Transparency = see(0.05) end
		task.delay(0.08, function()
			for _, s in shapes do
				if s.Parent then Fx.Tween(s, 0.2, { Transparency = 1 }) end
			end
		end)
		Debris:AddItem(anchor, 0.35)
	end
	function handle.Destroy()
		finished = true
		for _, tw in tweens do tw:Cancel() end
		anchor:Destroy()
	end
	task.delay(leadTime, handle.Impact) -- flashes on time even if nobody calls Impact()
	return handle
end

-- A star made of thin glowing bars (no textures). Each bar crosses the middle, so it
-- makes 2 opposite points; `lengths` = one length (0..1) per bar. `at` is a Vector3,
-- or a BasePart to stick to (the star then follows it, e.g. a swinging weapon).
-- Returns the turning frame, its UIScale and the bars, for the caller to animate.
local function makeStar(at, color, size, lengths, thickness, lifetime)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Star"
	bb.Size = UDim2.fromScale(size, size) -- on a BillboardGui, scale = studs: it reads like a real object
	bb.LightInfluence = 0
	bb.Brightness = 2 -- above 1 = it glows
	bb.AlwaysOnTop = false
	local holder: Instance
	if typeof(at) == "Instance" and at:IsA("BasePart") then
		bb.Adornee = at
		bb.Parent = folder
		holder = bb
	else
		holder = Fx.Part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(at) })
		bb.Adornee = holder :: BasePart
		bb.Parent = holder
	end
	Debris:AddItem(holder, lifetime + 0.1)
	local spin = Instance.new("Frame")
	spin.BackgroundTransparency = 1
	spin.AnchorPoint = Vector2.new(0.5, 0.5)
	spin.Position = UDim2.fromScale(0.5, 0.5)
	spin.Size = UDim2.fromScale(1, 1)
	spin.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = spin
	local bars = {}
	for i, length in lengths do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(length, thickness)
		bar.Rotation = (i - 1) * 180 / #lengths
		bar.BackgroundColor3 = color
		bar.BorderSizePixel = 0
		-- white-hot in the middle, fading to nothing at the tips = a pointy ray
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.5, WHITE), ColorSequenceKeypoint.new(1, color) })
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = bar
		bar.Parent = spin
		table.insert(bars, bar)
	end
	return spin, scale, bars
end

-- Anticipation glint: a small 4-point star sparkle ("something's coming").
-- `at` = a BasePart (it follows it, e.g. the weapon or hand) or a Vector3.
function Fx.Glint(at, color, size, duration)
	if not (typeof(at) == "Vector3" or (typeof(at) == "Instance" and at:IsA("BasePart"))) then return end
	duration = duration or 0.35
	local spin, scale = makeStar(at, col(color or WHITE), size or 2.4, { 0.75, 1 }, 0.08, duration)
	-- pop in, turn a little, shrink away
	Fx.Tween(scale, duration * 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	Fx.Tween(spin, duration, { Rotation = 45 }, Enum.EasingStyle.Sine)
	task.delay(duration * 0.3, function()
		Fx.Tween(scale, duration * 0.7, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
end

-- Impact star: an 8-point white "pow" at the hit point that pops and fades fast.
function Fx.ImpactStar(pos, color, size, duration)
	if typeof(pos) ~= "Vector3" then return end
	duration = math.max(duration or 0.2, 0.08)
	local spin, scale, bars = makeStar(pos, col(color or WHITE), size or 4.5, { 1, 0.55, 1, 0.55 }, 0.1, duration)
	spin.Rotation = math.random(0, 44) -- a different angle every hit
	scale.Scale = 0.35
	Fx.Tween(scale, 0.05, { Scale = 1 })
	task.delay(0.05, function() Fx.Tween(scale, duration - 0.05, { Scale = 1.2 }) end)
	for _, bar in bars do
		Fx.Tween(bar, duration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
end

return Fx
