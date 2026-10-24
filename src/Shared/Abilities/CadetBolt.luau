-- Cadet Bolt :: Rookie Thunder Rush (impact 0.60s, total 1.25s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(1, 1, 1)
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side = f:Cross(UP).Unit
	local IMP, head, torso, rh, lh = 0.6, ctx.part("Head"), ctx.part("UpperTorso"), ctx.part("RightHand"), ctx.part("LeftHand")
	local tp0 = ctx.targetPos()
	local dashEnd = start + f * math.max(0, (Vector3.new(tp0.X, start.Y, tp0.Z) - start).Magnitude - 2.3)
	-- yellow glow: highlight + pulsing torso light + an electric ball that wraps the right fist
	local hl = Instance.new("Highlight"); hl.FillColor = C1; hl.FillTransparency = 0.75; hl.OutlineColor = C1; hl.OutlineTransparency = 0.35
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = ctx.model; hl.Parent = ctx.model
	local glow = Instance.new("PointLight"); glow.Color = C1; glow.Range = 12; glow.Brightness = 1; glow.Parent = torso or ctx.root
	local fist = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Color = C1, Transparency = 1, CFrame = CFrame.new(start) })
	task.delay(1.6, function() hl:Destroy(); glow:Destroy(); for _, p in made do p:Destroy() end end)
	ctx.callout()

	task.spawn(function()
		local fx, cr = 0, 0
		while el() < 1.25 do
			local t = el()
			local hp = head and head.Position or ctx.myPos() + UP * 1.5
			glow.Brightness = t < 0.75 and 2 + math.sin(t * 40) or 3 * math.max(0, 1 - (t - 0.75) / 0.4)
			if t > 0.45 and t < 0.8 then fist.CFrame = rh and rh.CFrame or CFrame.new(ctx.myPos() + f); fist.Transparency = 0.15 else fist.Transparency = 1 end
			-- sparks crackling out of the spiky hair (fewer, floating sparks after the hit)
			if t - fx > 0.04 then fx = t
				if t < 0.75 or (t < 1.15 and math.random() < 0.3) then
					Fx.Particles(hp + UP * 0.5, { color = C1, count = t < 0.75 and 2 or 1, speed = 6, size = 0.3, lifetime = t < 0.75 and 0.2 or 0.5, spread = 70, gravity = t < 0.75 and 0 or -4, light = 1 })
				end
				if t > 0.5 and t < 0.75 then Fx.Particles(fist.Position, { color = C2, count = 2, speed = 5, size = 0.2, lifetime = 0.15, light = 1 }) end
			end
			if t - cr > 0.09 and t < 0.75 then cr = t
				local a = math.random() * math.pi * 2
				local d = Vector3.new(math.cos(a), 0, math.sin(a))
				Fx.Lightning(hp + d * 0.4 + UP * 0.4, hp + d * 1.2 + UP * (1.1 + math.random() * 0.4), math.random() < 0.5 and C1 or C2, 3, 0.08, 0.07)
			end
			ctx.wait(0)
		end
	end)
	task.delay(0.75, function() Fx.Tween(hl, 0.4, { FillTransparency = 1, OutlineTransparency = 1 }) end)

	-- 0.30 lightning streak: zig-zag bolts along the dash + three white speed lines stretching behind him
	task.delay(0.3, function()
		local a, b = start + UP * 0.3, dashEnd + UP * 0.3
		Fx.Burst(a, C1, 3, 0.2, { startSize = 0.6 }); Fx.Burst(a, C3, 2, 0.25, { transparency = 0.4 })
		Fx.Lightning(a, b, C1, 6, 0.22, 0.3); Fx.Lightning(a + UP * 0.7, b + UP * 0.7, C2, 5, 0.18, 0.15)
		for i = -1, 1 do
			local o = a:Lerp(b, 0.4 + 0.15 * i) + side * i * 0.9 + UP * (0.5 + math.abs(i) * 0.6)
			local s = mk({ Size = Vector3.new(0.1, 0.1, 4), Color = C4, CFrame = CFrame.lookAt(o, o + f) })
			fade(s, 0.2, { Size = Vector3.new(0.05, 0.05, 8), CFrame = CFrame.lookAt(o + f * 2, o + f * 3) })
		end
	end)

	-- 0.60 IMPACT: cartoon zig-zag bolt through the target, crackling rings, cyan sparks
	task.delay(math.max(0, IMP - 0.02 - el()), function()
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		local pts = { tp + UP * 4.6 + side * 0.7, tp + UP * 2 - side * 0.8, tp - UP * 0.5 + side * 0.6, tg - side * 0.4 }
		for i = 1, 3 do
			local a, b = pts[i], pts[i + 1]
			local cf, len = CFrame.lookAt((a + b) / 2, b), (b - a).Magnitude + 0.35
			local bolt = mk({ Size = Vector3.new(0.4, 0.4, len), Color = C1, CFrame = cf })
			local core = mk({ Size = Vector3.new(0.16, 0.16, len), Color = C4, CFrame = cf })
			task.delay(0.12, function() fade(bolt, 0.06); fade(core, 0.05) end)
		end
		Fx.Lightning(tp + UP * 6, tp, C2, 5, 0.2, 0.15)
		Fx.Ring(CFrame.new(tp), C4, 1, 6, 0.3, 0.2); Fx.Ring(CFrame.new(tg + UP * 0.15), C2, 2, 9, 0.4, 0.15)
		Fx.Burst(tp, C1, 4.5, 0.22, { startSize = 0.6 })
		Fx.Particles(tp, { color = C2, count = 30, speed = 22, size = 0.35, lifetime = 0.45, light = 1 })
		Fx.Particles(tp + UP, { color = C1, count = 12, speed = 14, size = 0.25, lifetime = 0.35, light = 1 })
		Fx.Light(tp, C1, 18, 5, 0.35); Fx.HitFlash(ctx.target, C1, 0.25)
		ctx.flash(C1, 0.2, 0.15); ctx.shake(0.2, 0.25)
	end)

	-- 0.00 eager crouch charge with a jittery little shiver
	Fx.Ring(CFrame.new(ctx.ground() + UP * 0.1), C1, 1, 4, 0.3, 0.12)
	local crouch = { Root = T(0, -0.9, 0), Waist = R(-20), Neck = R(18), RightShoulder = R(-40, 0, 12), RightElbow = R(90), LeftShoulder = R(80, 0, -20), LeftElbow = R(130),
		RightHip = R(50), LeftHip = R(50), RightKnee = R(-75), LeftKnee = R(-75), RightAnkle = R(25), LeftAnkle = R(25) }
	ctx.pose(crouch, to(0.1), "out")
	for i = 1, 4 do
		local j = i % 2 == 0 and 3 or -3
		crouch.RightShoulder, crouch.LeftShoulder, crouch.Waist = R(-40, 0, 12 + j), R(80, 0, -20 + j), R(-20, j, 0)
		ctx.pose(crouch, to(0.1 + i * 0.05), "linear")
	end
	-- 0.30 lightning dash, leaning in, fist cocked, legs trailing
	Fx.Trail(ctx.part("LowerTorso"), C1, 0.3, 1.2); Fx.Trail(torso, C2, 0.3, 0.8)
	task.spawn(ctx.moveTo, dashEnd, 0.15)
	ctx.pose({ Root = T(0, -0.35, -0.2, -15), Waist = R(-25), Neck = R(25), RightShoulder = R(-40, 0, 12), RightElbow = R(95), LeftShoulder = R(60, 0, -25), LeftElbow = R(100),
		LeftHip = R(-30), RightHip = R(20), LeftKnee = R(-50), RightKnee = R(-30) }, to(0.38), "snap")
	-- 0.38 skids in low and coils
	ctx.pose({ Root = T(0, -0.8, 0), Waist = R(-15, 25, 0), Neck = R(15), RightShoulder = R(-45, 0, 15), RightElbow = R(100), LeftShoulder = R(70, 0, -20), LeftElbow = R(120),
		RightHip = R(30), LeftHip = R(60), RightKnee = R(-70), LeftKnee = R(-60), LeftAnkle = R(15) }, to(0.5), "out")
	-- 0.50 rising uppercut, hopping 2.5 studs
	task.spawn(ctx.moveTo, dashEnd + UP * 2.5 + f * 0.4, 0.22)
	Fx.Trail(fist, C1, 0.3, 0.4)
	ctx.pose({ Root = T(0, 0, -0.2), Waist = R(5, -15, 0), RightShoulder = R(95, 0, 8), RightElbow = R(70), LeftShoulder = R(-20, 0, -30), LeftElbow = R(40), Neck = R(15),
		RightHip = R(-10), LeftHip = R(40), LeftKnee = R(-70) }, to(0.55), "linear")
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.targetPos()) * CFrame.new(0.6, 0.5, 0), C1, 2.4, 150, 0.2, 0.55, 90)
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.targetPos()) * CFrame.new(0.6, 0.5, -0.1), C4, 2.6, 150, 0.18, 0.2, 90)
	ctx.pose({ Root = T(0, 0.2, 0), Waist = R(8, -30, 0), RightShoulder = R(170, 0, 10), RightElbow = R(20), LeftShoulder = R(-50, 0, -35), LeftElbow = R(30), Neck = R(25),
		RightHip = R(-15), RightKnee = R(-10), LeftHip = R(55), LeftKnee = R(-85), LeftAnkle = R(-20), RightAnkle = R(-30) }, to(0.64), "snap")
	at(0.75)
	-- 0.75 tucks and flips back home
	task.spawn(ctx.moveTo, start, 0.2, 2)
	ctx.pose({ Root = T(0, 0.3, 0, 25), RightHip = R(70), LeftHip = R(70), RightKnee = R(-95), LeftKnee = R(-95), RightShoulder = R(40, 0, 40), LeftShoulder = R(40, 0, -40),
		RightElbow = R(60), LeftElbow = R(60), Neck = R(10) }, to(0.95), "out")
	-- 0.95 lands knees bent 30
	Fx.Ring(CFrame.new(ctx.ground() + UP * 0.1), C2, 1, 4.5, 0.25, 0.12)
	Fx.Particles(ctx.ground() + UP * 0.3, { color = C1, count = 8, speed = 7, size = 0.25, lifetime = 0.3, spread = 80, light = 1 })
	ctx.pose({ Root = T(0, -0.45, 0, -8), RightHip = R(30), LeftHip = R(30), RightKnee = R(-45), LeftKnee = R(-45), RightAnkle = R(15), LeftAnkle = R(15),
		RightShoulder = R(10, 0, 35), LeftShoulder = R(10, 0, -35) }, to(1.02), "out")
	-- 1.02 proud fist pump, grinning up
	ctx.pose({ LeftShoulder = R(160, 0, -10), LeftElbow = R(60), RightShoulder = R(0, 0, 20), RightElbow = R(100), Neck = R(10), Waist = R(5, -10, 0), Root = T(0, 0.05, 0),
		LeftHip = R(-5), RightHip = R(5), RightKnee = R(-10) }, to(1.13), "back")
	local fp = lh and lh.Position or ctx.myPos() + UP * 3
	Fx.Ring(CFrame.new(fp), C4, 0.5, 2.5, 0.2, 0.1); Fx.Burst(fp, C1, 1.2, 0.15)
	Fx.Particles(fp, { color = C1, count = 8, speed = 6, size = 0.25, lifetime = 0.3, light = 1 })
	at(1.17)
	ctx.pose(P.guard, 0.2)
end
