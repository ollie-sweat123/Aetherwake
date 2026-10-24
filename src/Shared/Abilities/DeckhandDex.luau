-- Deckhand Dex :: Bilge-Buster Dinghy (impact 0.65s, total 1.30s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or Color3.new(1, 1, 1), C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local function line(p, a, b, w) local d = b - a; if d.Magnitude < 0.02 then d = UP * 0.02 end
		p.Size = Vector3.new(d.Magnitude, w, w); p.CFrame = CFrame.lookAt(a + d / 2, a + d, math.abs(d.Unit.Y) > 0.98 and Vector3.xAxis or UP) * CFrame.Angles(0, math.pi / 2, 0) end
	task.delay(1.9, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side, g0, IMP = f:Cross(UP).Unit, ctx.ground(), 0.65
	local tp0 = ctx.targetPos()
	local er = math.clamp(((tp0 - start) * Vector3.new(1, 0, 1)).Magnitude - 3.2, 1, 5)
	local s0, ram = start - f * 3.2, Vector3.new(tp0.X, start.Y, tp0.Z) - f * (er + 2.8)
	local s0g = Vector3.new(s0.X, g0.Y, s0.Z)
	local w = ctx.weapon(); if w then w.LocalTransparencyModifier = 1; task.delay(1.45, function() w.LocalTransparencyModifier = 0 end) end
	local rh, lh, head = ctx.part("RightHand"), ctx.part("LeftHand"), ctx.part("Head")
	local function hp(p) return p and p.Position or ctx.myPos() end
	ctx.callout()

	-- the dinghy: wood hull walls, wedge bow halves, two plank seats, red neon stripes; plus foam wave, wake and a conjured oar
	local boat, DARK = {}, C4:Lerp(Color3.new(0, 0, 0), 0.35)
	local function bp(size, off, col, mat, shape)
		table.insert(boat, { mk({ Size = size, Color = col, Material = mat or Enum.Material.Wood, Shape = shape or Enum.PartType.Block, Transparency = 1 }), off })
	end
	bp(Vector3.new(2.4, 0.25, 4), CFrame.new(0, 0.12, 0.2), DARK)
	for _, x in { -1.2, 1.2 } do
		bp(Vector3.new(0.2, 0.9, 4), CFrame.new(x, 0.45, 0.2), C4)
		bp(Vector3.new(0.06, 0.2, 4), CFrame.new(x * 1.1, 0.62, 0.2), C1, Enum.Material.Neon)
		bp(Vector3.new(0.9, 1.3, 1.6), CFrame.new(x * 0.54, 0.45, -2.6) * CFrame.Angles(0, 0, math.rad(x > 0 and -90 or 90)), C4, nil, Enum.PartType.Wedge)
	end
	bp(Vector3.new(2.6, 0.9, 0.2), CFrame.new(0, 0.45, 2.2), C4)
	bp(Vector3.new(2.3, 0.15, 0.5), CFrame.new(0, 0.75, 0.45), DARK)
	bp(Vector3.new(2.3, 0.15, 0.5), CFrame.new(0, 0.75, -1.5), DARK)
	local wave = mk({ Size = Vector3.new(2.8, 0.2, 1.8), Color = C3, Material = Enum.Material.Glass, Shape = Enum.PartType.Wedge, Transparency = 1 })
	local wake = mk({ Size = Vector3.one * 0.2, Transparency = 1 })
	local oar = mk({ Shape = Enum.PartType.Cylinder, Color = C4, Material = Enum.Material.Wood })
	local blade = mk({ Size = Vector3.new(0.12, 0.7, 1.1), Color = C1, Material = Enum.Material.SmoothPlastic })
	local bpos, bcf = s0g, CFrame.new(s0g)
	task.spawn(function()
		local popped, fx = false, 0
		while el() < 1.3 do
			local t = el()
			if t >= 0.25 and t < 0.75 then local m = ctx.myPos(); bpos = Vector3.new(m.X, g0.Y, m.Z) end
			local pop = math.clamp((t - 0.08) / 0.14, 0, 1)
			local rise = -1.2 * (1 - pop) ^ 2 + math.sin(pop * math.pi) * 0.35
			local stroke = (t > 0.25 and t < 0.6) and math.sin(((t - 0.25) % 0.175) / 0.175 * math.pi) or 0
			local sink = math.clamp((t - 0.8) / 0.5, 0, 1)
			bcf = CFrame.lookAt(bpos, bpos + f) * CFrame.new(0, rise - sink * 1.4 + stroke * 0.12, 0) * CFrame.Angles(stroke * 0.09 + sink * 0.35, 0, sink * 0.45)
			if pop > 0 and not popped then popped = true; for _, b in boat do b[1].Transparency = 0 end end
			for _, b in boat do b[1].CFrame = bcf * b[2] end
			local wh = 0.15 + stroke * 0.75
			wave.Size = Vector3.new(2.8, wh, 1.8); wave.CFrame = bcf * CFrame.new(0, wh / 2, -4.3); wave.Transparency = (t > 0.25 and t < 0.72) and 0.3 or 1
			wake.CFrame = bcf * CFrame.new(0, 0.15, 2.4) * CFrame.Angles(0, 0, math.pi / 2)
			if t - fx > 0.05 and t > 0.25 and t < 0.7 then fx = t
				Fx.Particles((bcf * CFrame.new(0, 0.2, 2.4)).Position, { color = C3, count = 3, speed = 4, size = 0.5, lifetime = 0.4, gravity = 10, light = 0.3 })
			end
			-- oar: upright in hand, across the lap, rowing in the "water" beside the hull, raised for the ram, then on the shoulder
			local Rp, Lp = hp(rh), hp(lh)
			local A, B
			if t < 0.17 then A, B = Rp - UP, Rp + UP * 3.2
			elseif t < 0.25 then A = (bcf * CFrame.new(-1.7, 1.3, -0.7)).Position; B = A + side * 3.8
			elseif t < 0.6 then
				local i, k = t < 0.425 and -1 or 1, ((t - 0.25) % 0.175) / 0.175
				B = k < 0.3 and (bcf * CFrame.new(i * 2.4, 1.1, -1.6 + k)).Position or (bcf * CFrame.new(i * 2.7, 0.05, -1.6 + (k - 0.3) / 0.7 * 3.4)).Position
				local H = (Rp + Lp) / 2; A = H + (H - B).Unit * 0.6
			elseif t < 0.75 then local d = Rp - Lp; d = d.Magnitude > 0.3 and d.Unit or side; A, B = Lp - d * 0.6, Rp + d * 2.6
			else A, B = Rp + f * 0.5, Rp - f * 2.4 + UP * 1.6 end
			line(oar, A, B, 0.18); blade.CFrame = CFrame.lookAt(B, B + (B - A))
			ctx.wait(0)
		end
		for _, b in boat do fade(b[1], 0.15) end
		fade(oar, 0.12); fade(blade, 0.12); fade(wave, 0.1)
	end)

	-- the bonk: blue glass splash fan off the bow, droplet geyser, ring at the enemy's feet, white pop
	task.delay(IMP - 0.02, function()
		local bow, tg = (bcf * CFrame.new(0, 0.6, -3.4)).Position, ctx.targetGround()
		ctx.impact()
		for i = 1, 6 do
			local d = ((CFrame.fromAxisAngle(f, math.rad(-75 + (i - 1) * 30)) * UP) + f * 0.25).Unit
			local p = mk({ Size = Vector3.new(0.4, 1.1, 2), Color = C2, Material = Enum.Material.Glass, Shape = Enum.PartType.Wedge, Transparency = 0.2, CFrame = CFrame.lookAt(bow + d, bow + d * 3) })
			Fx.Tween(p, 0.25, { Size = Vector3.new(0.3, 1.6, 4.5), CFrame = CFrame.lookAt(bow + d * 3, bow + d * 6) })
			task.delay(0.18, function() fade(p, 0.25) end)
		end
		Fx.Particles(bow, { color = C2, count = 25, speed = 28, size = 0.45, lifetime = 0.7, spread = 30, gravity = 55, light = 0.5 })
		Fx.Particles(bow, { color = C3, count = 14, speed = 20, size = 0.35, lifetime = 0.6, spread = 45, gravity = 50, light = 0.5 })
		Fx.Ring(CFrame.new(tg + UP * 0.15), C2, 1, 8, 0.45, 0.25)
		Fx.Burst(bow, C3, 2, 0.25, { startSize = 0.05 }); Fx.Light(bow, C2, 16, 3, 0.4)
		Fx.HitFlash(ctx.target, C3, 0.25); ctx.shake(0.2, 0.25)
	end)
	-- the boat sinks with a glug: foam ring, rising bubbles, drifting foam
	task.delay(0.8, function()
		local p = bpos
		Fx.Ring(CFrame.new(p + UP * 0.15), C3, 2, 5, 0.5, 0.15); Fx.Callout(p + UP * 2.5, "glug!", C2, 0.6, 0.6)
		Fx.Particles(p + UP * 3, { color = C3, count = 10, speed = 3, size = 0.4, lifetime = 0.7, gravity = 4, light = 0.3 })
		for k = 0, 4 do task.delay(k * 0.1, function()
			Fx.Particles(p + UP * 0.4, { color = k % 2 == 0 and C3 or C2, count = 5, speed = 2.5, size = 0.45, lifetime = 0.5, spread = 35, gravity = -6, light = 0.4 })
		end) end
	end)

	-- 0.00 two fingers to the lips: whistle
	ctx.pose({ LeftShoulder = R(120, 0, -25), LeftElbow = R(120), RightShoulder = R(20, 0, 15), RightElbow = R(30), Neck = R(12), Waist = R(5) }, to(0.08), "out")
	Fx.Particles(hp(head) + f * 0.8, { color = C3, count = 5, speed = 4, size = 0.25, lifetime = 0.3, spread = 25, light = 1 })
	-- 0.08 the dinghy pops up behind him and he plops down into it
	Fx.Ring(CFrame.new(s0g + UP * 0.2), C3, 1, 4, 0.35, 0.2)
	Fx.Particles(s0g + UP * 0.5, { color = C2, count = 10, speed = 12, size = 0.4, lifetime = 0.5, spread = 40, gravity = 40, light = 0.5 })
	task.spawn(ctx.moveTo, s0, 0.14, 1.2)
	ctx.pose({ Root = T(0, -1, 0), RightHip = R(90), LeftHip = R(90), RightKnee = R(-90), LeftKnee = R(-90),
		RightShoulder = R(40, 0, 10), LeftShoulder = R(40, 0, -10), RightElbow = R(50), LeftElbow = R(50) }, to(0.25), "back")
	Fx.Trail(wake, C3, 0.45, 1.2)
	-- 0.25 two big rowing strokes, left then right, leaning back hard on each pull
	local function row(sg, pull)
		return { Root = T(0, -1, 0, pull and 18 or -12), RightHip = R(90), LeftHip = R(90), RightKnee = R(-90), LeftKnee = R(-90),
			Waist = R(pull and 12 or -18, sg * (pull and 20 or -25), 0), Neck = R(pull and -12 or 15),
			RightShoulder = R(pull and 30 or 100, 0, pull and 15 or -10), LeftShoulder = R(pull and 30 or 100, 0, pull and -15 or 10),
			RightElbow = R(pull and 100 or 15), LeftElbow = R(pull and 100 or 15) }
	end
	for i = 1, 2 do
		local ts, sg = 0.25 + (i - 1) * 0.175, i == 1 and -1 or 1
		ctx.pose(row(sg, false), to(ts + 0.05), "out")
		task.spawn(ctx.moveTo, s0:Lerp(ram, i == 1 and 0.45 or 0.9), math.max(0.05, ts + 0.165 - el()))
		Fx.Particles(blade.Position, { color = C2, count = 8, speed = 9, size = 0.35, lifetime = 0.4, spread = 50, gravity = 30, light = 0.5 })
		ctx.pose(row(sg, true), to(ts + 0.175), "out")
		Fx.Particles(blade.Position, { color = C3, count = 8, speed = 12, size = 0.3, lifetime = 0.45, spread = 40, gravity = 35, light = 0.5 })
		Fx.Ring(CFrame.new(Vector3.new(blade.Position.X, g0.Y + 0.15, blade.Position.Z)), C3, 0.5, 2.5, 0.3, 0.12)
	end
	-- 0.60 RAM: lurch forward with the oar raised in both hands
	task.spawn(ctx.moveTo, ram, to(IMP))
	ctx.pose({ Root = T(0, -0.9, -0.3, -15), RightHip = R(90), LeftHip = R(90), RightKnee = R(-80), LeftKnee = R(-80), Waist = R(-20), Neck = R(10),
		RightShoulder = R(165, 0, 25), LeftShoulder = R(165, 0, -25), RightElbow = R(25), LeftElbow = R(25) }, to(0.7), "snap")
	at(0.75)
	-- 0.75 tossed 3 studs up out of the boat, arms flailing, lands on his feet
	task.spawn(ctx.moveTo, start, 0.38, 3)
	local function flail(a) return { Root = T(0, 0.2, 0, a * 10), RightShoulder = R(150 - a * 40, 0, 60), LeftShoulder = R(120 + a * 40, 0, -70), RightElbow = R(30), LeftElbow = R(60),
		RightHip = R(30 + a * 30), LeftHip = R(30 - a * 30), RightKnee = R(-60), LeftKnee = R(-40), Neck = R(15) } end
	ctx.pose(flail(1), to(0.84), "out"); ctx.pose(flail(-1), to(0.94), "inout"); ctx.pose(flail(1), to(1.03), "inout")
	ctx.pose(P.jump, to(1.12), "out")
	Fx.Particles(ctx.ground() + UP * 0.3, { color = C3, count = 8, speed = 6, size = 0.4, lifetime = 0.35, spread = 70, light = 0.3 })
	ctx.pose({ Root = T(0, -0.5, 0, -10), RightHip = R(40), LeftHip = R(40), RightKnee = R(-60), LeftKnee = R(-60), RightShoulder = R(110, 0, 30), RightElbow = R(120),
		LeftShoulder = R(10, 0, -30), LeftElbow = R(20) }, to(1.16), "snap")
	-- 1.16 oar on the right shoulder, cheeky left-hand thumbs-up and a cocky nod
	local thumbs = { Root = T(0, -0.1, 0), RightShoulder = R(110, 0, 30), RightElbow = R(120), LeftShoulder = R(70, 0, -25), LeftElbow = R(90), Waist = R(0, -15, 0),
		Neck = R(-10, 0, 8), RightHip = R(0, 0, 8), LeftHip = R(0, 0, -8) }
	ctx.pose(thumbs, to(1.21), "back")
	thumbs.Neck = R(12, 0, 8); ctx.pose(thumbs, to(1.25), "out")
	ctx.pose(P.guard, 0.2)
end
