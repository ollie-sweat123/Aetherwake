-- Paragon Astra :: Zenith Comet Lance (impact 1.60s, total 2.50s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or Color3.new(1, 1, 1), C[3] or ctx.accent, C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	task.delay(2.9, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side = f:Cross(UP).Unit
	local IMP, head, torso, lt, rh, w = 1.6, ctx.part("Head"), ctx.part("UpperTorso"), ctx.part("LowerTorso"), ctx.part("RightHand"), ctx.weapon()
	local function wtip()
		local h = rh and rh.Position or ctx.myPos() + f
		if not w then return h + f * 1.5 end
		local s = w.Size
		local ax = (s.X >= s.Y and s.X >= s.Z) and Vector3.new(s.X / 2, 0, 0) or (s.Y >= s.Z and Vector3.new(0, s.Y / 2, 0) or Vector3.new(0, 0, s.Z / 2))
		local a, b = w.CFrame * ax, w.CFrame * -ax
		return (a - h).Magnitude > (b - h).Magnitude and a or b
	end
	-- wedge pointing outward along local +Y of cf (Size = thickness, width, length)
	local OUT = CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
	local tp0, g0 = ctx.targetPos(), ctx.ground()
	local flatT = Vector3.new(tp0.X, start.Y, tp0.Z)
	local apex, diveEnd = start + UP * 18, flatT - f * 2
	local land = diveEnd - f * 5
	local diveDeg = math.min(72, math.deg(math.atan2(18, math.max(1, (diveEnd - start).Magnitude))))
	local hl = Instance.new("Highlight"); hl.FillColor = C1; hl.FillTransparency = 0.75; hl.OutlineColor = C1; hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.Occluded; hl.Adornee = ctx.model; hl.Parent = ctx.model
	task.delay(2.6, function() hl:Destroy() end)
	-- star crest, light column, constellation, spear-tip star (ball, 3 spinning rings, 8 spikes, orange light), comet sheath
	local crest, core = {}, mk({ Shape = Enum.PartType.Ball, Size = Vector3.one, Color = C1, Transparency = 1 })
	for k = 1, 5 do crest[k] = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.1, 0.7, 1.5), Color = C1, Transparency = 1 }) end
	local column = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 1.2, 1.2), Color = C2, Transparency = 1 })
	local stars, links, cp = {}, {}, { { -4, 0, -1 }, { -2.5, 1, 0.5 }, { -1, 0.5, -0.5 }, { 0.5, 1.4, 0.3 }, { 2, 0.8, -0.6 }, { 3.3, 1.8, 0.4 }, { 4.2, 0.4, -0.2 } }
	for i, o in cp do
		stars[i] = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Color = C2, Transparency = 1, CFrame = CFrame.new(tp0 + UP * 9 + side * o[1] + UP * o[2] + f * o[3]) })
		if i > 1 then local a, b = stars[i - 1].Position, stars[i].Position
			links[i] = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new((b - a).Magnitude, 0.1, 0.1), Color = C3, Transparency = 1, CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0) }) end
	end
	local tipBall = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = C1, Transparency = 1 })
	local tl = Instance.new("PointLight"); tl.Color = C4; tl.Range = 24; tl.Brightness = 0; tl.Parent = tipBall
	local rings, spikes = {}, {}
	for r = 1, 3 do rings[r] = {}; for i = 1, 12 do rings[r][i] = mk({ Size = Vector3.new(0.9, 0.1, 0.1), Color = C2, Transparency = 1 }) end end
	for k = 1, 8 do spikes[k] = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.12, 0.5, 2.2), Color = C1, Transparency = 1 }) end
	local sheath = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 5, Color = C1, Material = Enum.Material.ForceField, Transparency = 1 })
	ctx.callout()
	Fx.Trail(w, C1, 0.4, 0.4)

	task.spawn(function()
		local fx, beamed = 0, false
		while el() < 2.5 do
			local t, me = el(), ctx.myPos()
			local hc = head and head.CFrame or CFrame.new(me + UP * 1.5)
			-- golden star crest behind the head
			local s = math.clamp(t / 0.4, 0, 1) * (1 - math.clamp((t - 1.9) / 0.5, 0, 1))
			local cc = hc * CFrame.new(0, 0.3, 0.75) * CFrame.Angles(0, 0, t * 1.5)
			for k, p in crest do p.Size = Vector3.new(0.1, 0.7 * math.max(s, 0.05), 1.5 * math.max(s, 0.05)); p.Transparency = s < 0.03 and 1 or 0
				p.CFrame = cc * CFrame.Angles(0, 0, k * 2 * math.pi / 5) * CFrame.new(0, 1.25 * s, 0) * OUT end
			core.CFrame, core.Size, core.Transparency = cc, Vector3.one * math.max(s, 0.05), s < 0.03 and 1 or 0
			-- light column from the ground to her during the ascent
			if t > 0.4 and t < 1.0 then local k = (t - 0.4) / 0.6; local top = me - UP * 1.5
				column.Size = Vector3.new(math.max(0.1, top.Y - g0.Y), 1.4 * (1 - 0.7 * k), 1.4 * (1 - 0.7 * k)); column.CFrame = CFrame.new((g0 + top) / 2) * CFrame.Angles(0, 0, math.pi / 2); column.Transparency = 0.25 + 0.75 * k
			else column.Transparency = 1 end
			-- constellation draws itself one star at a time; links snap to the target as she dives; stars fade one by one
			for i, st in stars do
				local on = t > 0.45 + i * 0.06 and t < 1.95 + i * 0.06
				st.Transparency = on and 0 or 1
				if links[i] then links[i].Transparency = (on and t < 1.27) and 0.2 or 1 end
			end
			if t >= 1.27 and not beamed then beamed = true; for _, st in stars do Fx.Beam(st.Position, ctx.targetPos(), C3, 0.25, 0.35) end end
			-- spear tip charges into a blazing star at the apex, and leads the dive
			local tip = wtip()
			if t > 0.9 and t < 1.6 then local k = math.min(1, (t - 0.9) / 0.35)
				tipBall.CFrame, tipBall.Size, tipBall.Transparency = CFrame.new(tip), Vector3.one * (0.5 + 2.5 * k), 0; tl.Brightness = 8
			else tipBall.Transparency = 1; tl.Brightness = 0 end
			local charging = t > 0.9 and t < 1.27
			for r, ring in rings do
				local rcf = CFrame.new(tip) * CFrame.Angles(t * 4 * r, t * 3 + r * 2.1, r * 1.05)
				for i, p in ring do p.CFrame = rcf * CFrame.Angles(0, i * math.pi / 6, 0) * CFrame.new(0, 0, -1.7); p.Transparency = charging and 0 or 1 end
			end
			for k, p in spikes do
				p.CFrame = CFrame.lookAt(tip, tip + f) * CFrame.Angles(0, 0, k * math.pi / 4 + t * 2) * CFrame.new(0, 1.6 + 0.3 * math.sin(t * 30 + k), 0) * OUT
				p.Transparency = charging and 0 or 1
			end
			-- comet sheath around her body during the dive
			if t > 1.27 and t < 1.6 then sheath.CFrame = torso and torso.CFrame or CFrame.new(me); sheath.Transparency = 0.2 else sheath.Transparency = 1 end
			if t - fx > (t < 1.9 and 0.03 or 0.05) then fx = t
				local hp = (hc * CFrame.new(0, 0.6, 0.1)).Position
				Fx.Particles(hp, { color = math.random() < 0.6 and C2 or C1, count = t < 1.9 and 3 or 1, speed = 4, size = 1.2, lifetime = 0.5, gravity = -8, spread = 25, light = 1 })
				if t > 0.4 and t < 0.9 then Fx.Particles(me + Vector3.new(math.random() - 0.5, -1, math.random() - 0.5) * 3, { color = C3, count = 2, speed = 3, size = 0.3, lifetime = 0.6, gravity = -6, light = 1 }) end
				if t > 1.27 and t < 1.6 then Fx.Particles(me, { color = math.random() < 0.5 and C2 or C4, count = 4, speed = 4, size = 0.5, lifetime = 0.4, light = 1 }) end
			end
			ctx.wait(0)
		end
	end)

	-- 1.60 IMPACT: giant five-pointed star bursts from the target, white nova, triple rings, 80 embers
	task.delay(math.max(0, IMP - 0.02 - el()), function()
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		local fv = (start - tp) * Vector3.new(1, 0, 1); fv = fv.Magnitude > 0.1 and fv.Unit or -f
		local scf, big = CFrame.lookAt(tp, tp + fv), {}
		for k = 1, 5 do big[k] = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.3, 0.3, 0.3), Color = C1 }) end
		task.spawn(function()
			local s0 = os.clock()
			while os.clock() - s0 < 0.45 do
				local k = os.clock() - s0
				local L = 5 * math.min(1, k / 0.1)
				for i, p in big do
					p.Size = Vector3.new(0.3, math.max(0.3, 2.2 * L / 5), math.max(0.3, L)); p.Transparency = math.clamp((k - 0.2) / 0.25, 0, 1)
					p.CFrame = scf * CFrame.Angles(0, 0, math.rad(i * 72 + 36 * k / 0.45)) * CFrame.new(0, 0.6 + L / 2, 0) * OUT
				end
				ctx.wait(0)
			end
			for _, p in big do p:Destroy() end
		end)
		Fx.Burst(tp, C2, 12, 0.45, { startSize = 2 })
		for i, c in { C2, C1, C3 } do task.delay((i - 1) * 0.06, function() Fx.Ring(CFrame.new(tg + UP * (0.15 + 0.1 * i)), c, 2, 20, 0.55, 0.3) end) end
		Fx.Particles(tp, { color = C4, count = 80, speed = 30, size = 0.45, lifetime = 0.7, gravity = 10, light = 1 })
		Fx.Particles(tp, { color = C2, count = 20, speed = 20, size = 0.35, lifetime = 0.5, light = 1 })
		Fx.Light(tp, C4, 28, 8, 0.6); Fx.HitFlash(ctx.target, C2, 0.4)
		ctx.flash(C2, 0.6, 0.15); task.delay(0.08, function() ctx.flash(C1, 0.4, 0.35) end)
		ctx.shake(0.9, 0.45)
	end)

	-- 0.00 ignition: spins the spear twice around her body, waist twisting
	for i = 1, 6 do
		local tw = i <= 3 and 40 or -40
		ctx.pose({ RightShoulder = R(70, 0, 45), RightElbow = R(20), RightWrist = R(0, (i * 120) % 360, 0), LeftShoulder = R(30, 0, -40), LeftElbow = R(40),
			Waist = R(0, tw, 0), Neck = R(0, -tw * 0.3, 0), Root = T(0, -0.1, 0), RightKnee = R(-15), LeftKnee = R(-10) }, to(i * 0.05), "linear")
	end
	-- 0.30 plants her feet and draws herself up tall
	ctx.pose({ Root = T(0, 0.15, 0), Neck = R(10), RightShoulder = R(10, 0, 20), RightElbow = R(30), LeftShoulder = R(5, 0, -15), LeftElbow = R(10), Waist = R(5) }, to(0.4), "out")
	-- 0.40 ascension: rises 18 studs, arched, arms spread; the sky darkens violet
	local dusk = C3:Lerp(Color3.new(0, 0, 0), 0.6)
	ctx.flash(dusk, 0.15, 1.3)
	task.spawn(ctx.moveTo, apex, 0.5)
	ctx.pose({ Root = T(0, 0, 0, 8), Waist = R(10), Neck = R(15), RightShoulder = R(0, 0, 90), LeftShoulder = R(0, 0, -90), RightElbow = R(5), LeftElbow = R(5),
		RightAnkle = R(-35), LeftAnkle = R(-35), LeftKnee = R(-10) }, to(0.75), "out")
	at(0.9)
	-- 0.90 apex: spear cocked back like a javelin, left arm aimed at the enemy, legs split
	ctx.flash(dusk, 0.1, 0.9)
	ctx.pose({ RightShoulder = R(-150, 0, 10), RightElbow = R(90), Waist = R(0, 50, 0), LeftShoulder = R(90, 0, 0), LeftElbow = R(0), LeftHip = R(30), RightHip = R(-40),
		LeftKnee = R(-20), RightKnee = R(-30), Neck = R(-10, -20, 0), Root = T(0, 0, 0, 5) }, to(1.1), "back")
	at(1.25)
	-- 1.25 comet dive: straight as an arrow, spear thrust ahead, gold and violet starfire trailing
	Fx.Trail(torso, C1, 0.4, 1.5); Fx.Trail(lt, C3, 0.4, 2.5); Fx.Trail(w, C2, 0.4, 0.6)
	task.spawn(ctx.moveTo, diveEnd, 0.32)
	ctx.pose({ Root = T(0, 0, 0, -diveDeg - 90), RightShoulder = R(175, 0, 0), LeftShoulder = R(175, 0, 0), RightElbow = R(0), LeftElbow = R(0), Neck = R(30),
		RightHip = R(-5), LeftHip = R(-5), RightAnkle = R(-40), LeftAnkle = R(-40) }, to(1.36), "out")
	at(1.56)
	-- 1.56 the spear plunges in, body coiled low
	ctx.pose({ Root = T(0, -0.8, -0.3, -5), RightKnee = R(-70), LeftKnee = R(-70), RightHip = R(50), LeftHip = R(60), Waist = R(-30), RightShoulder = R(80, 0, 0), RightElbow = R(0),
		LeftShoulder = R(75, 0, 10), LeftElbow = R(20), Neck = R(20), RightAnkle = R(20), LeftAnkle = R(15) }, to(1.64), "snap")
	at(1.9)
	-- 1.90 springs off in a high backward arc, spinning once with the spear held out
	task.spawn(ctx.moveTo, land, 0.35, 5)
	for i = 1, 3 do
		ctx.pose({ Root = T(0, 0.2, 0, 10, -120 * i, 0), RightShoulder = R(0, 0, 90), RightElbow = R(0), LeftShoulder = R(0, 0, -80), RightHip = R(30), RightKnee = R(-60),
			LeftHip = R(20), LeftKnee = R(-40), Neck = R(10) }, to(1.9 + i * 0.1), "linear")
	end
	-- 2.20 soft landing amid drifting gold sparkles, a spear twirl, then planted upright, chin raised
	Fx.Ring(CFrame.new(ctx.ground() + UP * 0.1), C1, 1, 6, 0.35, 0.12)
	Fx.Particles(ctx.myPos() + UP * 3, { color = C1, count = 14, speed = 2, size = 0.3, lifetime = 0.9, gravity = 2, spread = 180, light = 1 })
	ctx.pose({ Root = T(0, -0.4, 0, -6), RightHip = R(30), LeftHip = R(30), RightKnee = R(-45), LeftKnee = R(-45), RightShoulder = R(10, 0, 45), LeftShoulder = R(10, 0, -35) }, to(2.27), "out")
	for i = 1, 3 do ctx.pose({ RightShoulder = R(40, 0, 30), RightElbow = R(40), RightWrist = R(0, (i * 120) % 360, 0), LeftShoulder = R(5, 0, -15), Neck = R(8) }, to(2.27 + i * 0.03), "linear") end
	ctx.pose({ RightShoulder = R(15, 0, 20), RightElbow = R(70), LeftShoulder = R(0, 0, -15), LeftElbow = R(10), Neck = R(12), Waist = R(4), Root = T(0, 0.05, 0) }, to(2.43), "back")
	ctx.pose(P.guard, 0.2)
end
