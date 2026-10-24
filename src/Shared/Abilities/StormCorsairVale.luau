-- Storm Corsair Vale :: Thunderhead Broadside (impact 1.45s, total 2.15s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or Color3.new(0.2, 0.2, 0.25), C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP, g0, side, rh = 1.45, ctx.ground(), f:Cross(UP).Unit, ctx.part("RightHand")
	local WHITE, GREY = Color3.new(1, 1, 1), C3:Lerp(Color3.new(1, 1, 1), 0.3)
	local w = ctx.weapon(); if w then w.LocalTransparencyModifier = 1; task.delay(2.3, function() w.LocalTransparencyModifier = 0 end) end
	local cm = Instance.new("Model"); cm.Name = "StormCannons"; cm.Parent = workspace
	task.delay(2.8, function() for _, p in made do p:Destroy() end; cm:Destroy() end)
	ctx.callout()

	-- conjured cutlass (curved two-piece blade, gold guard, gold edge that lights up when the bolt hits)
	local b1 = mk({ Size = Vector3.new(0.1, 0.42, 2.2), Color = GREY:Lerp(WHITE, 0.6), Material = Enum.Material.Metal })
	local b2 = mk({ Size = Vector3.new(0.1, 0.36, 1.3), Color = GREY:Lerp(WHITE, 0.6), Material = Enum.Material.Metal })
	local guard = mk({ Size = Vector3.new(0.25, 0.9, 0.18), Color = C2 })
	local edge = mk({ Size = Vector3.new(0.12, 0.06, 2.2), Color = C2, Transparency = 1 })
	local function bladeTip() return (b2.CFrame * CFrame.new(0, 0, -0.65)).Position end
	-- storm cloud of 6 dark balls
	local cloud, csz = {}, { 5, 4, 6, 3.5, 4.5, 3 }
	for i = 1, 6 do cloud[i] = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = C3:Lerp(GREY, 0.4), Material = Enum.Material.SmoothPlastic, Transparency = 1 }) end
	local c0 = start + UP * 11
	local function cloudAt(t) local tp = ctx.targetPos(); local k = math.clamp((t - 0.7) / 0.5, 0, 1); return c0:Lerp(tp + UP * 9, k * k * (3 - 2 * k)) end
	-- three spectral storm cannons: glass barrel, gold muzzle + breech rings, block-and-wedge carriage, cylinder wheels
	local guns = {}
	local tg0 = ctx.targetGround()
	for i, off in { side * 3, -side * 3, -f * 3 + side * 0.6 } do
		local pos = g0 + off
		local g = { K = CFrame.lookAt(pos, Vector3.new(tg0.X, pos.Y, tg0.Z)), parts = {}, fire = 1.2 + (i - 1) * 0.08 }
		local bar = CFrame.new(0, 1.45, 0) * CFrame.Angles(math.rad(12), 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		g.bar = bar
		for _, d in {
			{ Vector3.new(3, 1.1, 1.1), bar, GREY, Enum.Material.Glass, Enum.PartType.Cylinder, 0.35 },
			{ Vector3.new(0.25, 1.4, 1.4), bar * CFrame.new(1.45, 0, 0), C2, Enum.Material.Neon, Enum.PartType.Cylinder, 0 },
			{ Vector3.new(0.3, 1.3, 1.3), bar * CFrame.new(-1.3, 0, 0), C2, Enum.Material.Neon, Enum.PartType.Cylinder, 0 },
			{ Vector3.one * 0.7, bar * CFrame.new(-1.65, 0, 0), GREY, Enum.Material.Glass, Enum.PartType.Ball, 0.35 },
			{ Vector3.new(1.3, 0.6, 2.2), CFrame.new(0, 0.6, 0.3), C3, Enum.Material.Glass, Enum.PartType.Block, 0.3 },
			{ Vector3.new(0.9, 0.4, 0.9), CFrame.new(0, 1.05, 1.0), C3, Enum.Material.Glass, Enum.PartType.Wedge, 0.3 },
			{ Vector3.new(0.25, 1, 1), CFrame.new(0.78, 0.5, -0.2), C3, Enum.Material.Glass, Enum.PartType.Cylinder, 0.3 },
			{ Vector3.new(0.25, 1, 1), CFrame.new(-0.78, 0.5, -0.2), C3, Enum.Material.Glass, Enum.PartType.Cylinder, 0.3 },
		} do
			local p = mk({ Size = d[1], Color = d[3], Material = d[4], Shape = d[5], Transparency = 1 }); p.Parent = cm
			table.insert(g.parts, { p, d[2], d[6] })
		end
		guns[i] = g
	end
	local function gunCF(g, t)
		local k = t - g.fire
		local rec = k < 0 and 0 or (k < 0.05 and 1.5 * k / 0.05 or 1.5 * math.max(0, 1 - (k - 0.05) / 0.25))
		local sink = 1.5 * (1 - math.clamp((t - 0.7) / 0.25, 0, 1)) + 1.5 * math.clamp((t - 1.65) / 0.4, 0, 1)
		return g.K * CFrame.new(0, -sink, rec)
	end
	local function ip(i) return ctx.targetPos() + (i == 1 and side * 1.3 or (i == 2 and -side * 1.3 or UP * 1.1)) end
	task.spawn(function()
		local fx, charged = 0, false
		while el() < 2.15 do
			local t = el()
			-- blade follows the sword hand, mostly extending the arm
			local hc = rh and rh.CFrame or ctx.root.CFrame
			local d = (-hc.UpVector * 0.87 + hc.LookVector * 0.5).Unit
			local B = CFrame.lookAt(hc.Position - hc.UpVector * 0.3, hc.Position - hc.UpVector * 0.3 + d, hc.RightVector)
			b1.CFrame = B * CFrame.new(0, 0, -1.2); b2.CFrame = B * CFrame.new(0, 0, -2.3) * CFrame.Angles(math.rad(14), 0, 0) * CFrame.new(0, 0, -0.65)
			guard.CFrame = B * CFrame.new(0, 0, 0.05); edge.CFrame = B * CFrame.new(0, 0.22, -1.2)
			if t >= 0.42 and not charged then charged = true
				for _, p in { b1, b2 } do p.Color, p.Material = C1, Enum.Material.Neon end; edge.Transparency = 0
			end
			-- cloud tweens in, rotates slowly, drifts over the enemy, then breaks up
			local cc, grow, brk = cloudAt(t), math.clamp(t / 0.3, 0, 1), math.clamp((t - 1.6) / 0.5, 0, 1)
			for i, p in cloud do
				local a, r = i * 1.047 + t * 0.6, (2.2 + (i % 3) * 0.6) * (1 + brk * 1.5)
				p.Size = Vector3.one * math.max(0.5, csz[i] * grow); p.Transparency = 1 - (0.7 * grow) * (1 - brk)
				p.CFrame = CFrame.new(cc + Vector3.new(math.cos(a) * r, (i % 2) * 0.6, math.sin(a) * r))
			end
			-- cannons fade in with a crimson glow, recoil when they fire, sink into smoke at the end
			local va = math.clamp((t - 0.7) / 0.3, 0, 1) * (1 - math.clamp((t - 1.65) / 0.4, 0, 1))
			for _, g in guns do
				local K = gunCF(g, t)
				for _, e in g.parts do e[1].CFrame = K * e[2]; e[1].Transparency = 1 - (1 - e[3]) * va end
				g.muzzle, g.breech = (K * g.bar * CFrame.new(1.7, 0, 0)).Position, (K * g.bar * CFrame.new(-1.4, 0, 0)).Position
			end
			if t - fx > 0.05 then fx = t
				if t < 0.4 then local a = t * 12
					Fx.Particles(ctx.myPos() + Vector3.new(math.cos(a) * 2, -1.5 + t * 5, math.sin(a) * 2), { color = GREY:Lerp(WHITE, 0.5), count = 2, speed = 3, size = 0.4, lifetime = 0.35, spread = 60, light = 0.2 })
				end
				if charged and t < 1.6 then Fx.Particles(bladeTip(), { color = C2, count = 2, speed = 6, size = 0.2, lifetime = 0.25, light = 1 }) end
				if t > 0.42 and t < 0.7 then Fx.Light(bladeTip(), math.random() < 0.5 and C2 or C4, 14, 2 + math.random() * 4, 0.05) end
				if va > 0.5 and t < 1.6 then
					for _, g in guns do
						Fx.Particles(g.breech:Lerp(g.muzzle, math.random()), { color = C4, count = 2, speed = 6, size = 0.18, lifetime = 0.15, light = 1 })
						Fx.Particles(g.breech + UP * 0.4, { color = C2, count = 2, speed = 5, size = 0.18, lifetime = 0.2, spread = 30, light = 1 })
					end
				end
			end
			ctx.wait(0)
		end
		for _, p in { b1, b2, guard, edge } do fade(p, 0.12) end
	end)

	-- the bolt: zigzag gold lightning + a cyan beam from the cloud into the raised blade
	task.delay(0.42, function()
		local tip, cc = bladeTip(), cloudAt(0.42)
		Fx.Lightning(cc, tip, C2, 5, 0.3, 0.35); Fx.Beam(cc, tip, C4, 0.6, 0.25)
		Fx.Burst(tip, WHITE, 3, 0.2, { startSize = 0.3 }); Fx.Burst(cc, C4, 7, 0.25, { transparency = 0.5 })
		Fx.HitFlash(b1, C1, 1.2); Fx.HitFlash(b2, C1, 1.2)
		ctx.flash(WHITE, 0.6, 0.15); ctx.shake(0.25, 0.2)
	end)
	task.delay(0.55, function() Fx.Lightning(cloudAt(0.55), bladeTip(), C4, 5, 0.15, 0.18) end)
	task.delay(0.75, function() Fx.HitFlash(cm, C1, 0.9) end)
	-- broadside: each cannon recoils, flashes and fires a lightning-wrapped gold cannonball (last lands at 1.45)
	for i, g in guns do
		task.delay(g.fire, function()
			local m, to_ = g.muzzle or g0, ip(i)
			Fx.Burst(m, C2:Lerp(WHITE, 0.5), 2, 0.15, { startSize = 0.1 })
			Fx.Particles(m, { color = GREY, count = 6, speed = 5, size = 0.8, lifetime = 0.5, spread = 40, light = 0.1 })
			Fx.Lightning(m, to_, C4, 5, 0.14, 0.12)
			Fx.Projectile(m, to_, (to_ - m).Magnitude / 0.09, C2, 1.2, function(pos)
				Fx.Burst(pos, C2, 2.5, 0.2); Fx.Particles(pos, { color = C4, count = 6, speed = 12, size = 0.25, lifetime = 0.25, light = 1 })
			end, { trailColor = GREY, trailLife = 0.35, arc = i == 3 and 1.5 or 0.5 })
		end)
	end
	task.delay(1.2, function() Fx.HitFlash(cm, C1, 0.5) end)
	task.delay(IMP - 0.02, function()
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		Fx.Burst(tp, C2, 7, 0.4, { startSize = 0.1 }); Fx.Burst(tp, WHITE, 4, 0.25, { startSize = 0.1 })
		for i = 1, 3 do Fx.Lightning(ip(i), ip(i % 3 + 1), C4, 5, 0.3, 0.15) end
		Fx.Ring(CFrame.new(tg + UP * 0.2), C1, 2, 14, 0.5, 0.3)
		Fx.Particles(tp, { color = C2, count = 26, speed = 24, size = 0.4, lifetime = 0.5, light = 1 })
		Fx.Light(tp, C2, 22, 5, 0.5); Fx.HitFlash(ctx.target, C2, 0.3)
		ctx.flash(C2:Lerp(WHITE, 0.5), 0.55, 0.25); ctx.shake(0.7, 0.4)
	end)
	-- aftermath: cannons sink in smoke puffs, gold sparks drizzle, cyan crackles skitter on the ground
	task.delay(1.65, function()
		for _, g in guns do Fx.Particles(g.K.Position + UP, { color = GREY, count = 10, speed = 3, size = 1.2, lifetime = 0.6, spread = 80, light = 0.1 }) end
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		Fx.Particles(tp + UP * 3, { color = C2, count = 14, speed = 3, size = 0.3, lifetime = 0.8, gravity = 12, spread = 80, light = 1 })
		for i = 1, 3 do local a = i * 2.1; Fx.Lightning(tg + Vector3.new(math.cos(a), 0.2, math.sin(a)) * 1.5, tg + Vector3.new(math.cos(a), 0.1, math.sin(a)) * 3.5, C4, 3, 0.3, 0.08) end
	end)

	-- 0.00 tips his tricorn, screen dims to a storm blue
	ctx.flash(C3, 0.3, 1.4)
	ctx.pose({ LeftShoulder = R(155, 0, -15), LeftElbow = R(125), Neck = R(-12), RightShoulder = R(15, 0, 12), RightElbow = R(20), Waist = R(0, 10, 0) }, to(0.14), "out")
	-- 0.14 thrusts the cutlass straight up, stretched tall, left hip cocked
	local sky = { RightShoulder = R(178, 0, 4), RightElbow = R(0), LeftShoulder = R(15, 0, -30), LeftElbow = R(30), Root = T(0, 0.25, 0), Neck = R(20), Waist = R(6),
		LeftHip = R(20, 0, -5), LeftKnee = R(-35), RightAnkle = R(-15) }
	ctx.pose(sky, to(0.36), "back")
	-- 0.40 braced as the lightning hits, teeth-gritting tremble
	sky.Root, sky.Neck, sky.RightKnee, sky.LeftKnee = T(0, -0.25, 0), R(32), R(-30), R(-35)
	for i = 1, 4 do sky.Waist = R(6, 0, i % 2 == 0 and 3 or -3); ctx.pose(sky, to(0.42 + i * 0.07), "linear") end
	-- 0.70 swings the cutlass down to point at the enemy, left boot forward, free hand on hip
	ctx.pose({ RightShoulder = R(92, 0, 0), RightElbow = R(0), LeftShoulder = R(0, 0, -38), LeftElbow = R(112), Neck = R(14), Waist = R(4, -10, 0), Root = T(0, -0.15, -0.3),
		LeftHip = R(38), LeftKnee = R(-22), RightHip = R(-12), RightKnee = R(-8) }, to(0.92), "back")
	at(1.18)
	-- 1.20 FIRE: a sharp horizontal slash signal, waist twisting 50
	ctx.pose({ RightShoulder = R(25, 0, 95), RightElbow = R(5), LeftShoulder = R(0, 0, -38), LeftElbow = R(112), Waist = R(0, -50, 0), Neck = R(10, 30, 0), Root = T(0, -0.25, -0.2),
		LeftHip = R(38), LeftKnee = R(-22) }, to(1.28), "snap")
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.targetPos()) * CFrame.new(0, 0.6, -1), C1, 3, 150, 0.25, 0.5, 0)
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.targetPos()) * CFrame.new(0, 0.6, -1.1), C2, 3.2, 150, 0.22, 0.2, 0)
	at(1.6)
	-- 1.60 cutlass resting on the shoulder, two fingers to the hat brim, crooked grin over the shoulder
	local rest = { RightShoulder = R(70, 0, 25), RightElbow = R(145), LeftShoulder = R(150, 0, -20), LeftElbow = R(130), Neck = R(5, -30, 12), Waist = R(0, 20, 0),
		Root = T(0, -0.1, 0), RightHip = R(0, 0, 6), LeftHip = R(10, 0, -6), LeftKnee = R(-15) }
	ctx.pose(rest, to(1.82), "inout")
	rest.LeftShoulder, rest.LeftElbow, rest.Neck = R(160, 0, -10), R(140), R(-6, -30, 12)
	ctx.pose(rest, to(1.98), "back")
	at(2.07)
	ctx.pose(P.guard, 0.2)
end
