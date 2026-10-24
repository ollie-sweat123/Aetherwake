-- Harpoon Rook :: Undertow Reel (impact 1.45s, total 2.10s)
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
	task.delay(2.7, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP, g0, side = 1.45, ctx.ground(), f:Cross(UP).Unit
	local rh, lh = ctx.part("RightHand"), ctx.part("LeftHand")
	local function hp(p) return p and p.Position or ctx.myPos() + f end
	local w = ctx.weapon(); if w then w.LocalTransparencyModifier = 1; task.delay(2.25, function() w.LocalTransparencyModifier = 0 end) end
	ctx.callout()

	-- conjured harpoon: shaft + steel point + growing teal glass barb with a gold neon edge (wedge pairs, top and bottom)
	local shaft = mk({ Shape = Enum.PartType.Cylinder, Color = C1, Material = Enum.Material.Metal })
	local hd = {}
	for _, fl in { 1, -1 } do
		table.insert(hd, { mk({ Shape = Enum.PartType.Wedge, Color = C3, Material = Enum.Material.Metal }), 0.5, fl, false })
		table.insert(hd, { mk({ Shape = Enum.PartType.Wedge, Color = C2 }), 1.15, fl, true })
		table.insert(hd, { mk({ Shape = Enum.PartType.Wedge, Color = C1, Material = Enum.Material.Glass, Transparency = 0.25 }), 1, fl, true })
	end
	local lamp = mk({ Size = Vector3.one * 0.2, Transparency = 1 })
	local glow = Instance.new("PointLight"); glow.Color = C2; glow.Range = 12; glow.Brightness = 0; glow.Parent = lamp
	local function harpoon(butt, d, g)
		local top = butt + d * 5
		line(shaft, butt, top, 0.22)
		local H = CFrame.lookAt(top, top + d, math.abs(d.Y) > 0.95 and f or UP)
		for _, e in hd do
			local s = e[4] and (0.05 + 1.45 * g) * e[2] or e[2]
			e[1].Size = Vector3.new(e[4] and 0.3 * e[2] or 0.25, math.max(s * 0.32, 0.05), s)
			e[1].CFrame = H * CFrame.new(0, e[3] * s * 0.16, -s / 2) * CFrame.Angles(0, 0, e[3] < 0 and math.pi or 0)
		end
		lamp.CFrame = H
		return top + d * 1.5
	end
	-- golden rope coil (3 stacked rings of segments), the rope itself, and the curling wave (6 aqua glass wedges + white foam lips)
	local coil = {}
	for k = 1, 3 do for i = 1, 10 do
		local a, r = i * math.pi / 5, 1.7 - k * 0.15
		local p = g0 + Vector3.new(math.cos(a) * r, 0.1 + k * 0.16, math.sin(a) * r)
		table.insert(coil, mk({ Size = Vector3.new(0.14, 0.14, r * 0.68), Color = C2, Transparency = 1, CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))) }))
	end end
	local rope = mk({ Shape = Enum.PartType.Cylinder, Color = C2, Transparency = 1 })
	local wav, lip = {}, {}
	for j = 1, 6 do
		wav[j] = mk({ Shape = Enum.PartType.Wedge, Color = C1, Material = Enum.Material.Glass, Transparency = 1 })
		lip[j] = mk({ Color = C3, Transparency = 1 })
	end
	local copy = {}
	task.spawn(function()
		local fx, coilA = 0, 0
		while el() < 2.1 do
			local t, tp, tg = el(), ctx.targetPos(), ctx.targetGround()
			local Rp = hp(rh)
			local mid = (Rp + hp(lh)) / 2
			local aim = ((tp + UP * 2) - Rp).Unit
			local g = math.clamp((t - 0.3) / 0.5, 0, 1)
			local tip
			if t >= 0.86 and not copy.from then copy.from, copy.d = Rp - aim * 2, aim; copy.hit = tp - aim * 5.3 end
			if t < 0.2 then local rad = (Rp - ctx.myPos()) * Vector3.new(1, 0, 1); rad = rad.Magnitude > 0.2 and rad.Unit or side; tip = harpoon(Rp - rad * 1.5, rad, 0)
			elseif t < 0.3 then tip = harpoon(Vector3.new(Rp.X, g0.Y, Rp.Z), UP, 0)
			elseif t < 0.86 then tip = harpoon(Rp - aim * 2, aim, g)
			elseif t < 1.65 then
				local k = math.clamp((t - 0.86) / 0.14, 0, 1)
				local shake = (t > 1.35 and t < 1.5) and side * math.sin(t * 90) * 0.12 or Vector3.zero
				tip = harpoon(copy.from:Lerp(copy.hit, k) + shake, copy.d, 1)
			elseif t < 1.78 then local k = (t - 1.65) / 0.13; tip = harpoon(copy.hit:Lerp(Rp - UP * 2.4, k), copy.d:Lerp(UP, k).Unit, 1 - k)
			elseif t < 1.95 then tip = harpoon(Rp - UP * 2.4, UP, 0)
			else tip = harpoon(Vector3.new(Rp.X, g0.Y, Rp.Z), UP, 0) end
			glow.Brightness = (t > 0.3 and t < 1.65) and 1 + 4 * g or 0
			-- droplets stream in and condense on the head while he cocks the throw
			if t > 0.33 and t < 0.8 and t - fx > 0.03 then fx = t
				local d = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				local drop = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, Color = C1, Material = Enum.Material.Glass, CFrame = CFrame.new(tip + (d.Magnitude > 0.01 and d.Unit or UP) * 3) })
				Fx.Tween(drop, 0.14, { CFrame = CFrame.new(tip - aim * 0.7), Size = Vector3.one * 0.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				task.delay(0.15, function() drop:Destroy() end)
			end
			-- coil glows brighter as he cocks, the rope pays out, goes taut and pulses, then reels back in
			coilA = t < 0.25 and 0 or (t < 0.3 and 0.6 or (t < 1.65 and 0.6 + 0.4 * g or math.max(0, 1 - (t - 1.65) / 0.25)))
			for _, c in coil do c.Transparency = 1 - coilA end
			if copy.from and t < 1.78 then
				line(rope, t < 1.0 and g0 + UP * 0.6 or mid, shaft.Position - shaft.CFrame.RightVector * shaft.Size.X / 2, t < 1.0 and 0.12 or 0.14 + 0.06 * math.sin(t * 40))
				rope.Transparency = t < 1.0 and 0.1 or 0.15 * (1 + math.sin(t * 40))
			else rope.Transparency = 1 end
			-- the wave: rises behind the target, curls over it, crashes, drains away
			local h = t > IMP and math.max(0.3, 8 * (1 - (t - IMP) / 0.2)) or math.max(0.3, 8 * (1 - (1 - math.clamp((t - 1.0) / 0.3, 0, 1)) ^ 3))
			local curl = -1.25 * math.clamp((t - 1.35) / 0.1, 0, 1) ^ 2
			local wa = t < 1.0 and 0 or (t < IMP and 1 or math.max(0, 1 - (t - IMP) / 0.2))
			for j = 1, 6 do
				local dj = CFrame.Angles(0, math.rad(-50 + (j - 1) * 20), 0) * f
				local b = tg + dj * 3.8
				local cf = CFrame.lookAt(b, b - dj) * CFrame.Angles(curl + math.sin(t * 8 + j) * 0.04, 0, 0) * CFrame.new(0, h / 2, 0)
				wav[j].Size, wav[j].CFrame, wav[j].Transparency = Vector3.new(2.5, h, 2.8), cf, 1 - wa * 0.75
				lip[j].Size, lip[j].CFrame, lip[j].Transparency = Vector3.new(2.6, 0.4, 0.7), cf * CFrame.new(0, h / 2, 1.2), 1 - wa
			end
			ctx.wait(0)
		end
		for _, p in { shaft, rope, table.unpack(coil) } do fade(p, 0.12) end
		for _, e in hd do fade(e[1], 0.12) end
	end)
	task.delay(1.35, function() Fx.Trail(lip[2], C3, 0.35, 0.3); Fx.Trail(lip[5], C3, 0.35, 0.3) end)
	task.delay(1.0, function() local tp = ctx.targetPos()
		Fx.Particles(tp, { color = C1, count = 12, speed = 10, size = 0.35, lifetime = 0.4, gravity = 30, light = 0.6 }); Fx.HitFlash(ctx.model, C4, 0.6)
		Fx.Particles(tp, { color = C3, count = 6, speed = 6, size = 0.3, lifetime = 0.4, light = 0.6 })
	end)

	-- the crash: splash ball, 40 droplets, foam ring, gold ForceField shockwave
	task.delay(IMP - 0.02, function()
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		Fx.Burst(tp, C3, 9, 0.5, { startSize = 2, transparency = 0.25, material = Enum.Material.Glass }); Fx.Burst(tp, C1, 6, 0.35, { startSize = 2 })
		Fx.Particles(tp, { color = C1, count = 24, speed = 26, size = 0.5, lifetime = 0.7, gravity = 40, spread = 70, light = 0.5 })
		Fx.Particles(tp, { color = C3, count = 16, speed = 22, size = 0.4, lifetime = 0.6, gravity = 40, light = 0.5 })
		Fx.Ring(CFrame.new(tg + UP * 0.15), C3, 2, 12, 0.5, 0.3)
		Fx.Burst(tp, C2, 8, 0.4, { startSize = 2, transparency = 0, material = Enum.Material.ForceField })
		Fx.Light(tp, C2, 20, 4, 0.5); Fx.HitFlash(ctx.target, C3, 0.3); Fx.HitFlash(ctx.model, C4, 0.4)
		ctx.flash(C3, 0.35, 0.2); ctx.shake(0.5, 0.35)
		task.delay(0.25, function() Fx.Particles(tg + UP, { color = C3, count = 14, speed = 5, size = 0.5, lifetime = 0.5, gravity = 10, spread = 80, light = 0.4 }) end)
		task.delay(0.3, function() Fx.Particles(tp, { color = C2, count = 12, speed = 3, size = 0.3, lifetime = 0.8, light = 1 }) end)
	end)

	-- 0.00 sweeps the harpoon once around his body (white trail on the point)
	Fx.Trail(hd[1][1], C3, 0.25, 0.35)
	task.spawn(ctx.pose, { RightShoulder = R(10, 0, 88), RightElbow = R(5), LeftShoulder = R(10, 0, -60), LeftElbow = R(30), Root = T(0, -0.2, 0), RightKnee = R(-15), LeftKnee = R(-15) }, 0.06)
	ctx.spin(360, to(0.2))
	ctx.face(ctx.targetPos())
	-- 0.20 slams the butt down and widens into a low stance: the rope coil appears in a puff of sand and foam
	ctx.pose({ Root = T(0, -0.65, 0), RightHip = R(35, 0, 18), LeftHip = R(35, 0, -18), RightKnee = R(-60), LeftKnee = R(-60), RightAnkle = R(20), LeftAnkle = R(20),
		RightShoulder = R(40, 0, 25), RightElbow = R(50), LeftShoulder = R(30, 0, -30), LeftElbow = R(60), Waist = R(-10), Neck = R(-5) }, to(0.27), "snap")
	Fx.Particles(g0 + UP * 0.4, { color = C2, count = 12, speed = 8, size = 0.5, lifetime = 0.45, spread = 70, gravity = 15, light = 0.3 })
	Fx.Particles(g0 + UP * 0.4, { color = C3, count = 8, speed = 6, size = 0.4, lifetime = 0.4, spread = 80, light = 0.3 }); ctx.shake(0.1, 0.1)
	-- 0.30 crow-hop 2 studs back and cock the javelin over his shoulder, left arm pointing at the target
	task.spawn(ctx.moveTo, start - f * 2, 0.22, 1.1)
	ctx.pose({ RightHip = R(30), RightKnee = R(-70), LeftHip = R(10), LeftKnee = R(-20), RightShoulder = R(150, 0, 30), RightElbow = R(70), LeftShoulder = R(90, 0, -20),
		Waist = R(5, -45, 0), Root = T(0, 0.1, 0) }, to(0.42), "out")
	ctx.pose({ Root = T(0, -0.25, 0.2, 10), Waist = R(5, -50, 0), RightShoulder = R(150, 0, 35), RightElbow = R(75), LeftShoulder = R(90, 0, -25), LeftElbow = R(5),
		Neck = R(0, 35, 0), RightHip = R(-10), RightKnee = R(-45), LeftHip = R(30), LeftKnee = R(-5) }, to(0.55), "out")
	at(0.78)
	-- 0.80 explosive throw: step in, right arm whips through, back leg kicks up
	task.spawn(ctx.moveTo, start - f * 0.3, 0.12)
	ctx.pose({ Root = T(0, -0.3, -0.7, -18), Waist = R(-15, 45, 0), RightShoulder = R(105, 0, 5), RightElbow = R(0), LeftShoulder = R(10, 0, -40), LeftElbow = R(50),
		Neck = R(5), LeftHip = R(50), LeftKnee = R(-30), RightHip = R(-55), RightKnee = R(-60) }, to(0.9), "snap")
	at(1.0)
	-- 1.00 plants both feet and grabs the rope, leaning back to brace
	ctx.pose({ Root = T(0, -0.5, 0.4, 20), Waist = R(5), RightShoulder = R(75, 0, -12), LeftShoulder = R(75, 0, 12), RightElbow = R(35), LeftElbow = R(35),
		RightHip = R(55), LeftHip = R(20), RightKnee = R(-55), LeftKnee = R(-25), RightAnkle = R(20), LeftAnkle = R(25) }, to(1.12), "out")
	at(1.35)
	-- 1.35 the huge two-handed yank: almost horizontal, heels dug in, roaring
	ctx.pose({ Root = T(0, -1.0, 1.1, 55), Waist = R(10), Neck = R(-30), RightShoulder = R(35, 0, 15), LeftShoulder = R(35, 0, -15), RightElbow = R(125), LeftElbow = R(125),
		RightHip = R(75), LeftHip = R(70), RightKnee = R(-35), LeftKnee = R(-30), RightAnkle = R(35), LeftAnkle = R(35) }, to(1.43), "snap")
	at(1.65)
	-- 1.65 the harpoon flies back into his hand
	task.spawn(ctx.moveTo, start, 0.12)
	ctx.pose({ RightShoulder = R(150, 0, 20), RightElbow = R(20), LeftShoulder = R(20, 0, -25), LeftElbow = R(30), Root = T(0, -0.1, 0), Neck = R(10) }, to(1.78), "out")
	-- 1.78 spins it round behind his back...
	task.spawn(ctx.pose, { RightShoulder = R(-40, 0, 20), RightElbow = R(30), LeftShoulder = R(-40, 0, -20), LeftElbow = R(30), Root = T(0, -0.1, 0) }, 0.06)
	ctx.spin(360, to(1.94))
	ctx.face(ctx.targetPos())
	-- 1.95 ...and slams the butt into the ground with a smirk
	ctx.pose({ Root = T(0, -0.15, 0), RightShoulder = R(40, 0, 20), RightElbow = R(40), LeftShoulder = R(0, 0, -35), LeftElbow = R(110), Neck = R(5, -15, 8),
		Waist = R(0, 10, 0), RightHip = R(0, 0, 10), LeftHip = R(0, 0, -10) }, to(2.0), "snap")
	Fx.Ring(CFrame.new(ctx.ground() + UP * 0.15), C3, 1, 6, 0.4, 0.2)
	Fx.Particles(ctx.ground() + UP * 0.3, { color = C3, count = 8, speed = 6, size = 0.4, lifetime = 0.35, spread = 70, light = 0.3 })
	at(2.03)
	ctx.pose(P.guard, 0.2)
end
