-- Bramble Kid :: Thornroot Bonk (impact 1.00s, total 1.60s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(1, 1, 1)
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local function line(p, a, b, w) local d = b - a; if d.Magnitude < 0.02 then b = a + UP * 0.02; d = b - a end
		p.Size = Vector3.new(d.Magnitude, w, w); p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP = 1.0
	local hand, lt = ctx.part("RightHand"), ctx.part("LowerTorso")
	local w = ctx.weapon(); if w then w.LocalTransparencyModifier = 1; task.delay(1.75, function() w.LocalTransparencyModifier = 0 end) end
	ctx.callout()

	-- conjured stick -> thorn club: shaft, knob, 6 thorn spikes and 4 spiral vines, driven every frame
	local shaft = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = C1, Material = Enum.Material.Wood })
	local knob = Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = C1, Material = Enum.Material.Wood })
	local spikes, vines = {}, {}
	for i = 1, 6 do spikes[i] = Fx.Part({ Shape = Enum.PartType.Wedge, Color = i % 2 == 0 and C2 or C3, Transparency = 1 }) end
	for i = 1, 12 do vines[i] = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = i % 3 == 0 and C3 or C2 }) end
	local planted = true
	local function vpt(sf, j, n, len, r) local a = j * math.pi / 2 + n * 1.8; return (sf * CFrame.new(math.cos(a) * r, math.sin(a) * r, -len * n / 3)).Position end
	task.spawn(function()
		while el() < 1.6 do
			local t = el()
			local grow = math.clamp(t / 0.35, 0, 1)
			local s = t < 1.1 and 1 + math.clamp((t - 0.35) / 0.3, 0, 1) or 2 - math.clamp((t - 1.1) / 0.3, 0, 1)
			local sk = t < 1.1 and math.clamp((t - 0.35) / 0.25, 0, 1) or 1 - math.clamp((t - 1.1) / 0.25, 0, 1)
			local vt = math.clamp((t - 1.1) / 0.35, 0, 1)
			if hand and hand.Parent then
				local hp, a, b = hand.Position, nil, nil
				if planted then
					a, b = Vector3.new(hp.X, ctx.ground().Y, hp.Z) + f * 0.4, hp + UP * 0.35
				else
					local d = (hand.CFrame * CFrame.Angles(math.rad(-70), 0, 0)).LookVector
					a, b = hp - d * 0.5, hp + d * 2.6 * s
				end
				line(shaft, a, b, 0.28 * s)
				local sf, len = CFrame.lookAt(a, b), (b - a).Magnitude
				knob.Size = Vector3.one * 0.55 * s; knob.CFrame = CFrame.new(b)
				for i, p in spikes do
					p.Size = Vector3.new(0.15, 0.1 + 0.7 * sk * s, 0.45); p.Transparency = sk > 0 and 0 or 1
					p.CFrame = sf * CFrame.new(0, 0, -len + (i % 2) * 0.35) * CFrame.Angles(0, 0, math.rad(i * 60)) * CFrame.new(0, 0.3 * s + p.Size.Y / 2, 0)
				end
				for j = 0, 3 do for k = 1, 3 do
					local v = vines[j * 3 + k]
					line(v, vpt(sf, j, k - 1, len * grow, 0.2 * s), vpt(sf, j, k, len * grow, 0.2 * s), 0.09 * s); v.Transparency = vt
				end end
			end
			ctx.wait(0)
		end
		for _, p in { shaft, knob, table.unpack(spikes) } do fade(p, 0.1) end
		for _, p in vines do fade(p, 0.1) end
	end)

	-- the hit: THWACK on the head, wood chips, vine snares curling up round the enemy's feet
	task.delay(IMP - 0.02, function()
		local top, g = ctx.targetTop(), ctx.targetGround()
		ctx.impact()
		Fx.Burst(top, C4, 3, 0.25, { startSize = 0.1 }); Fx.Burst(top, C3, 4.5, 0.35, { transparency = 0.5 })
		Fx.Callout(top + UP * 1.5, "THWACK!", C4, 1, 0.8)
		Fx.Light(top, C4, 14, 4, 0.35)
		for _ = 1, 8 do
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
			local chip = Fx.Part({ Size = Vector3.new(0.35, 0.25, 0.6), Color = C1, Material = Enum.Material.Wood, CFrame = CFrame.new(top) })
			fade(chip, 0.5, { CFrame = CFrame.new(top + dir * 4.5 - UP * 1.5) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		end
		Fx.Particles(top, { color = C2, count = 12, speed = 16, size = 0.45, lifetime = 0.6, gravity = 12 })
		Fx.Ring(CFrame.new(g + UP * 0.15), C4, 1, 10, 0.35, 0.3); Fx.Shockwave(g, C2, 4, 0.45)
		local snares = {}
		for v = 1, 3 do for k = 1, 4 do
			local a0, a1 = v * 2.09 + (k - 1) * 0.9, v * 2.09 + k * 0.9
			local p0 = g + Vector3.new(math.cos(a0) * (2.4 - k * 0.2), (k - 1) * 0.6 + 0.1, math.sin(a0) * (2.4 - k * 0.2))
			local p1 = g + Vector3.new(math.cos(a1) * (2.2 - k * 0.2), k * 0.6 + 0.1, math.sin(a1) * (2.2 - k * 0.2))
			local sn = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = k % 2 == 0 and C2 or C3, Transparency = 1 })
			line(sn, p0, p1, 0.18); table.insert(snares, sn)
			task.delay(k * 0.04, function() sn.Transparency = 0 end)
		end end
		task.delay(0.16, function() for _, sn in snares do fade(sn, 0.4, { CFrame = sn.CFrame - UP * 1.2 }) end end)
		ctx.shake(0.25, 0.3)
	end)

	-- 0.00 plant the stick, lean on it with a cocky grin while vines spiral up it
	Fx.Particles(ctx.ground() + f * 1.5 + UP * 0.3, { color = "#c9b48f", count = 10, speed = 5, size = 0.5, lifetime = 0.45, spread = 70 })
	ctx.pose({ Root = T(0, -0.35, 0), Waist = R(-10, 15, 0), Neck = R(-5, 0, 10), RightShoulder = R(60, 0, 8), RightElbow = R(20), LeftShoulder = R(10, 0, -25), LeftElbow = R(40),
		RightHip = R(25), LeftHip = R(10), RightKnee = R(-35), LeftKnee = R(-30) }, to(0.3))
	at(0.35)
	-- 0.35 yank it overhead into a deep crouch: the stick swells into a thorn club
	planted = false
	Fx.Light(ctx.myPos(), C2, 14, 2.5, 1.25)
	ctx.pose({ Root = T(0, -1.0, 0.2), Waist = R(12), Neck = R(10), RightShoulder = R(170, 0, 10), RightElbow = R(40), LeftShoulder = R(170, 0, -10), LeftElbow = R(40),
		RightHip = R(75), LeftHip = R(75), RightKnee = R(-120), LeftKnee = R(-120), RightAnkle = R(35), LeftAnkle = R(35) }, to(0.6), "back")
	Fx.Particles(knob.Position, { color = C2, count = 10, speed = 3, size = 0.45, lifetime = 0.8, gravity = 5, light = 0.3 })
	at(0.65)
	-- 0.65 leap up and forward with a full front flip, club stretched out
	local land = ctx.targetPos() - f * 2.4
	Fx.Trail(knob, C1, 0.45, 0.6); Fx.Trail(knob, C2, 0.45, 0.3)
	task.spawn(ctx.moveTo, Vector3.new(land.X, start.Y, land.Z), 0.3, 4)
	for i = 1, 4 do
		ctx.pose({ Root = T(0, 0.4, 0, -90 * i), Waist = R(-20), RightShoulder = R(100, 0, 8), RightElbow = R(10), LeftShoulder = R(100, 0, -8), LeftElbow = R(10),
			RightHip = R(80), LeftHip = R(80), RightKnee = R(-110), LeftKnee = R(-110) }, to(0.65 + 0.07 * i), "linear")
		if lt then Fx.Particles(lt.Position, { color = C2, count = 4, speed = 3, size = 0.4, lifetime = 0.5, gravity = 3 }) end
	end
	-- 0.93 whip the club from overhead down onto the enemy's head, knees buckle
	ctx.pose({ Root = T(0, 0.2, 0), Waist = R(15), RightShoulder = R(170, 0, 8), RightElbow = R(30), LeftShoulder = R(170, 0, -8), LeftElbow = R(30),
		RightHip = R(30), LeftHip = R(30), RightKnee = R(-50), LeftKnee = R(-50) }, to(0.95), "out")
	ctx.pose({ Root = T(0, -0.7, -0.4, -10), Waist = R(-25), Neck = R(10), RightShoulder = R(55, 0, -5), RightElbow = R(5), LeftShoulder = R(55, 0, 5), LeftElbow = R(5),
		RightHip = R(50), LeftHip = R(50), RightKnee = R(-75), LeftKnee = R(-75) }, to(1.0), "in")
	at(1.1)
	-- 1.10 hop home, club shrinks back to a twig on his shoulder, rub the nose
	task.spawn(ctx.moveTo, start, 0.25, 1)
	local rest = { Root = T(0, 0, 0), Waist = R(0, 10, 0), Neck = R(5), RightShoulder = R(20, 0, 25), RightElbow = R(125), LeftShoulder = R(0, 0, -10), LeftElbow = R(10), RightKnee = R(-5), LeftKnee = R(-5) }
	ctx.pose(rest, to(1.3), "out")
	rest.LeftShoulder, rest.LeftElbow, rest.Neck = R(85, 0, 35), R(115), R(10, -10, 0)
	ctx.pose(rest, to(1.4), "out")
	for i = 1, 2 do rest.LeftShoulder = R(85, 0, i % 2 == 1 and 22 or 38); ctx.pose(rest, to(1.4 + 0.06 * i), "inout") end
	ctx.pose(P.guard, 0.2)
end