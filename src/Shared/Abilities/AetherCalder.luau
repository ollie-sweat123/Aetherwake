-- Aether Calder :: Skybreaker Oath (impact 1.30s, total 2.10s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or Color3.new(1, 1, 1), C[2] or ctx.accent, C[3] or ctx.accent, C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side = f:Cross(UP).Unit
	local IMP, torso, rh, w, WHITE = 1.3, ctx.part("UpperTorso"), ctx.part("RightHand"), ctx.weapon(), Color3.new(1, 1, 1)
	local tp0 = ctx.targetPos()
	local flatT = Vector3.new(tp0.X, start.Y, tp0.Z)
	local front, past, g0 = flatT - f * 1.8, flatT + f * 2.4 + side * 1.6, ctx.ground()
	-- holy glow: white highlight + gold light on the blade
	local hl = Instance.new("Highlight"); hl.FillColor = C1; hl.FillTransparency = 0.8; hl.OutlineColor = C1; hl.OutlineTransparency = 0.3
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = ctx.model; hl.Parent = ctx.model
	local gl = Instance.new("PointLight"); gl.Color = C3; gl.Range = 16; gl.Brightness = 5; gl.Parent = w or rh or ctx.root
	task.delay(2.25, function() hl:Destroy(); gl:Destroy() end)
	task.delay(2.6, function() for _, p in made do p:Destroy() end end)
	-- oath sigil (gold segment ring + 4 spokes), 6 wing feathers, 8 spectral swords
	local sig, spokes, wings, swords = {}, {}, {}, {}
	for i = 1, 28 do sig[i] = mk({ Size = Vector3.new(0.7, 0.1, 0.2), Color = C3, Transparency = 1 }) end
	for i = 1, 2 do spokes[i] = mk({ Size = Vector3.new(6, 0.1, 0.15), Color = C3, Transparency = 1 }) end
	for s = -1, 1, 2 do for j = 1, 3 do table.insert(wings, { p = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.15, 0.8, 3), Color = j == 2 and C3 or C1, Transparency = 1 }), s = s, j = j, L = 3.4 - j * 0.5 }) end end
	for i = 1, 8 do swords[i] = { mk({ Size = Vector3.new(0.6, 0.2, 4), Color = C2, Material = Enum.Material.ForceField, Transparency = 1 }), mk({ Size = Vector3.new(0.15, 0.1, 3.6), Color = WHITE, Transparency = 1 }),
		mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(1.4, 0.3, 0.35), Color = C3, Transparency = 1 }), mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 0.08, 0.08), Color = C3, Transparency = 1 }) } end
	ctx.callout()

	task.spawn(function()
		local last, ang, fx, trails = 0, 0, 0, false
		while el() < 2.1 do
			local t = el(); local dt = t - last; last = t
			-- sigil spreads under him, rotates slowly, fades after 1.4
			local s1, str = math.clamp(t / 0.3, 0.02, 1), t < 1.4 and 0.1 or 0.1 + 0.9 * math.min(1, (t - 1.4) / 0.4)
			local sc = CFrame.new(g0 + UP * 0.08) * CFrame.Angles(0, t * 0.5, 0)
			for i, p in sig do p.CFrame = sc * CFrame.Angles(0, i * 2 * math.pi / 28, 0) * CFrame.new(0, 0, -3 * s1); p.Size = Vector3.new(0.75 * s1, 0.1, 0.2); p.Transparency = str end
			for i, p in spokes do p.CFrame = sc * CFrame.Angles(0, i * math.pi / 2, 0); p.Size = Vector3.new(6 * s1, 0.1, 0.15); p.Transparency = str end
			-- wings unfold 0.4-0.7, flap once at 0.9-1.15, fold and fade after 1.4
			local open = math.clamp((t - 0.4) / 0.3, 0, 1) * (1 - math.clamp((t - 1.4) / 0.4, 0, 1))
			local flap = (t > 0.9 and t < 1.15) and math.sin(math.pi * (t - 0.9) / 0.25) or 0
			local tc = torso and torso.CFrame or ctx.root.CFrame
			for _, wg in wings do
				local th = wg.s * (8 + (15 + 22 * (wg.j - 1)) * open - 20 * flap * open)
				local Lc = wg.L * math.max(open, 0.05)
				wg.p.Size = Vector3.new(0.15, 0.8, Lc); wg.p.Transparency = open < 0.03 and 1 or 0.3 + 0.7 * math.clamp((t - 1.5) / 0.3, 0, 1)
				wg.p.CFrame = tc * CFrame.new(wg.s * 0.3, 0.35, 0.55) * CFrame.Angles(0, 0, -math.rad(th)) * CFrame.Angles(math.rad(15 + 30 * flap), 0, 0)
					* CFrame.new(0, Lc / 2, 0) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
			end
			-- the sword ring: fades in one by one, orbits, tightens 6 -> 4, then drives inward at 1.2-1.3
			local c = ctx.targetPos()
			local r = t < 0.8 and 6 or (t < 1.2 and 6 - 2 * (t - 0.8) / 0.4 or 4 - 1.9 * math.min(1, (t - 1.2) / 0.1))
			ang += (t < 0.8 and 0.6 or 0.6 + 3.4 * math.min(1, (t - 0.8) / 0.4)) * dt
			for i, sw in swords do
				local si = t < IMP and math.clamp((t - 0.4 - i * 0.045) / 0.08, 0, 1) or 0
				local a = ang + i * math.pi / 4
				local cf = CFrame.lookAt(c + Vector3.new(math.cos(a), 0, math.sin(a)) * r, c)
				sw[1].CFrame, sw[2].CFrame, sw[3].CFrame = cf, cf, cf * CFrame.new(0, 0, 2.05)
				sw[1].Transparency, sw[2].Transparency, sw[3].Transparency = 1 - 0.85 * si, 1 - si, 1 - si
				local tip = cf * Vector3.new(0, 0, -2)
				if t > 0.8 and t < 1.2 and (tip - c).Magnitude > 0.3 then
					sw[4].Size, sw[4].CFrame, sw[4].Transparency = Vector3.new((tip - c).Magnitude, 0.08, 0.08), CFrame.lookAt((tip + c) / 2, c) * CFrame.Angles(0, math.pi / 2, 0), 0.3
				else sw[4].Transparency = 1 end
			end
			if t > 0.8 and not trails then trails = true; for _, sw in swords do Fx.Trail(sw[1], C2, 0.5, 0.3) end end
			if t - fx > 0.05 then fx = t
				local a = math.random() * math.pi * 2
				if t < 1.2 then Fx.Particles(g0 + Vector3.new(math.cos(a), 0.2, math.sin(a)) * (1.5 + math.random() * 1.5), { color = C3, count = 2, speed = 2, size = 0.25, lifetime = 0.8, gravity = -6, spread = 20, light = 1 })
				elseif t < 1.45 then Fx.Particles(ctx.myPos() + UP, { color = C3, count = 3, speed = 3, size = 0.3, lifetime = 0.5, gravity = 15, light = 1 }) end
			end
			ctx.wait(0)
		end
	end)

	-- 1.30 IMPACT: all eight blades drive in -> blazing gold cross, white nova, twin shockwave rings
	task.delay(math.max(0, IMP - 0.02 - el()), function()
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		local cf = CFrame.lookAt(tp, tp + f)
		for k = 0, 1 do
			local b = mk({ Size = Vector3.new(0.1, 1, 1), Color = C3, CFrame = cf * CFrame.Angles(0, 0, k * math.pi / 2) })
			Fx.Tween(b, 0.12, { Size = Vector3.new(12, 1, 1) })
			task.delay(0.14, function() fade(b, 0.25, { Size = Vector3.new(14, 0.1, 0.1) }) end)
		end
		Fx.Burst(tp, C1, 8, 0.35, { startSize = 1 })
		Fx.Ring(CFrame.new(tg + UP * 0.2), C2, 2, 14, 0.45, 0.3)
		task.delay(0.08, function() Fx.Ring(CFrame.new(tg + UP * 0.3), C3, 2, 14, 0.45, 0.25) end)
		-- the blades scatter into feathers of light
		for i = 1, 14 do
			local a = i * math.pi / 7
			local d = Vector3.new(math.cos(a), 0.3 + math.random() * 0.6, math.sin(a))
			local fe = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.08, 0.35, 0.9), Color = i % 3 == 0 and C3 or C1, Transparency = 0.1, CFrame = CFrame.lookAt(tp + d * 2, tp + d * 3) })
			fade(fe, 0.7, { CFrame = CFrame.lookAt(tp + d * 7 - UP * 1.5, tp + d * 8) * CFrame.Angles(0, 0, math.random() * 6) })
		end
		Fx.Particles(tp, { color = C3, count = 22, speed = 16, size = 0.35, lifetime = 0.6, gravity = 6, light = 1 })
		Fx.Particles(tp, { color = C1, count = 14, speed = 22, size = 0.3, lifetime = 0.4, light = 1 })
		Fx.Light(tp, C3, 24, 6, 0.5); Fx.HitFlash(ctx.target, C1, 0.35)
		ctx.flash(C1, 0.5, 0.25); ctx.shake(0.7, 0.4)
		Fx.Tween(gl, 0.7, { Brightness = 0 }); Fx.Tween(hl, 0.7, { FillTransparency = 1, OutlineTransparency = 1 })
	end)

	-- 0.00 kneels on one knee, sword planted, head bowed
	ctx.pose({ Root = T(0, -1.0, 0), RightHip = R(-5), RightKnee = R(-90), RightAnkle = R(30), LeftHip = R(90), LeftKnee = R(-90), RightShoulder = R(45, 0, -15), RightElbow = R(20),
		LeftShoulder = R(45, 0, 15), LeftElbow = R(20), Neck = R(-15), Waist = R(-5) }, to(0.3), "out")
	Fx.Burst(g0 + UP * 0.3, C3, 3, 0.3, { startSize = 0.5 })
	at(0.4)
	-- 0.40 rises into an upright salute, heroic arch, wings unfolding
	ctx.pose({ RightShoulder = R(120, 0, 0), RightElbow = R(60), LeftShoulder = R(10, 0, -15), LeftElbow = R(15), Waist = R(8), Neck = R(5), Root = T(0, 0.05, 0) }, to(0.7), "out")
	at(0.8)
	-- 0.80 levels the sword at the enemy, left hand braced, knees bent, rising 0.5
	task.spawn(ctx.moveTo, start + UP * 0.5, 0.4)
	ctx.pose({ RightShoulder = R(90, 0, 0), RightElbow = R(0), LeftShoulder = R(80, 0, 25), LeftElbow = R(40), Waist = R(-10, -10, 0), Neck = R(5), Root = T(0, -0.35, 0.2),
		RightHip = R(-15), LeftHip = R(35), LeftKnee = R(-45), RightKnee = R(-35) }, to(1.0), "inout")
	at(1.2)
	-- 1.20 wing thrust: rockets in with a locked-arm thrust, legs trailing
	Fx.Trail(wings[3].p, C1, 0.3, 1); Fx.Trail(wings[6].p, C1, 0.3, 1); Fx.Trail(w or rh, C2, 0.3, 1)
	task.spawn(ctx.moveTo, front, 0.1)
	ctx.pose({ Root = T(0, 0, -0.3, -30), RightShoulder = R(90, 0, 0), RightElbow = R(0), LeftShoulder = R(-40, 0, -30), LeftElbow = R(10), Waist = R(-10, -15, 0), Neck = R(25),
		RightHip = R(-35), LeftHip = R(-15), RightKnee = R(-30), LeftKnee = R(-20), RightAnkle = R(-30), LeftAnkle = R(-30) }, to(1.28), "snap")
	at(1.32)
	-- 1.32 bursts through and stops just past the enemy, sweeping the sword down and out
	task.spawn(ctx.moveTo, past, 0.15)
	ctx.pose({ RightShoulder = R(30, 0, 75), RightElbow = R(5), LeftShoulder = R(10, 0, -30), Waist = R(0, -25, 0), Neck = R(0, 15, 0), Root = T(0, -0.3, 0),
		RightHip = R(15), LeftHip = R(-10), RightKnee = R(-30), LeftKnee = R(-20) }, to(1.6), "out")
	-- 1.60 brings it back up into a solemn salute, chin raised
	ctx.pose({ RightShoulder = R(120, 0, 0), RightElbow = R(60), LeftShoulder = R(0, 0, -10), LeftElbow = R(10), Waist = R(8), Neck = R(15), Root = T(0, 0.05, 0) }, to(1.85), "back")
	at(2.0)
	ctx.pose(P.guard, 0.2)
end
