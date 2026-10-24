-- Instructor Ren :: Seven Quiet Lines (impact 1.42s, total 2.00s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or Color3.new(1, 1, 1), C[2] or ctx.accent, C[3] or Color3.new(0.15, 0.15, 0.4), C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP, torso, head, w, WHITE = 1.42, ctx.part("UpperTorso"), ctx.part("Head"), ctx.weapon(), Color3.new(1, 1, 1)
	-- vanish / reappear helper (body parts, accessories and face decals) + white outline
	local body = {}
	for _, d in ctx.model:GetDescendants() do if (d:IsA("BasePart") and d ~= ctx.root) or d:IsA("Decal") then table.insert(body, d) end end
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = C1; hl.OutlineTransparency = 0; hl.Adornee = ctx.model; hl.Parent = ctx.model
	local function vis(on) for _, p in body do p.LocalTransparencyModifier = on and 0 or 1 end; hl.Enabled = on end
	task.delay(2.05, function() vis(true); hl:Destroy() end)
	task.delay(2.4, function() for _, p in made do p:Destroy() end end)
	local ring, lines, g0 = {}, {}, ctx.ground()
	for i = 1, 24 do ring[i] = mk({ Size = Vector3.new(0.5, 0.12, 0.25), Color = C4, Transparency = 1 }) end
	ctx.callout()

	task.spawn(function()
		local fx = 0
		while el() < 2.0 do
			local t = el()
			-- lilac ground ring slowly widening 2 -> 6 studs, fading out after 1.6
			local rad, tr = 1 + 2 * math.clamp(t / 1.0, 0, 1), t < 1.6 and 0.6 or 0.6 + 0.4 * math.min(1, (t - 1.6) / 0.35)
			for i, p in ring do
				p.Size = Vector3.new(2 * math.pi * rad / 24 * 1.1, 0.12, 0.25); p.Transparency = tr
				p.CFrame = CFrame.new(g0 + UP * 0.1) * CFrame.Angles(0, i * math.pi / 12 + t * 0.4, 0) * CFrame.new(0, 0, -rad)
			end
			-- thin pale-blue wind streaks spiralling up around him (dead stillness from 1.0)
			if t - fx > 0.045 and t < 1.0 then fx = t
				local a, h, r, c = math.random() * math.pi * 2, math.random() * 2.5, 2 + math.random() * 0.6, ctx.myPos() - UP * 2.5
				local function sp(aa, hh) return CFrame.lookAt(c + Vector3.new(math.cos(aa) * r, hh, math.sin(aa) * r), c + Vector3.new(math.cos(aa + 0.3) * r, hh + 0.2, math.sin(aa + 0.3) * r)) end
				local s = mk({ Size = Vector3.new(0.08, 0.08, 1.4), Color = math.random() < 0.7 and C2 or C1, Transparency = 0.2, CFrame = sp(a, h) })
				fade(s, 0.6, { CFrame = sp(a + 1.1, h + 1.6), Size = Vector3.new(0.03, 0.03, 0.8) })
			end
			ctx.wait(0)
		end
	end)

	-- 1.42 IMPACT: the sheath clicks and every hanging line snaps shut into one brilliant starburst cut
	task.delay(math.max(0, IMP - 0.02 - el()), function()
		local c = ctx.targetPos()
		ctx.impact()
		if w then w.LocalTransparencyModifier = 1 end
		for _, ln in lines do fade(ln, 0.1, { Size = Vector3.new(0.3, 0.3, 0.05), CFrame = CFrame.lookAt(c, c + ln.CFrame.LookVector) }) end
		local fv = (ctx.myPos() - c) * Vector3.new(1, 0, 1); fv = fv.Magnitude > 0.1 and fv.Unit or f
		for k = 1, 8 do
			local d, len = CFrame.fromAxisAngle(fv, k * math.pi / 4) * UP, k % 2 == 0 and 3.5 or 6
			local sp = mk({ Size = Vector3.new(0.14, 0.14, 0.5), Color = WHITE, CFrame = CFrame.lookAt(c + d * 0.25, c + d) })
			Fx.Tween(sp, 0.08, { Size = Vector3.new(0.14, 0.14, len), CFrame = CFrame.lookAt(c + d * len / 2, c + d * len) })
			task.delay(0.1, function() fade(sp, 0.2, { Size = Vector3.new(0.02, 0.02, len) }) end)
		end
		Fx.Burst(c, WHITE, 4, 0.2, { startSize = 0.5 }); Fx.Ring(CFrame.new(c), C2, 1, 10, 0.4, 0.2)
		Fx.Ring(CFrame.new(ctx.targetGround() + UP * 0.15), C1, 2, 12, 0.5, 0.15)
		Fx.Particles(c, { color = C2, count = 20, speed = 18, size = 0.25, lifetime = 0.4, light = 1 })
		Fx.Light(c, C2, 20, 5, 0.4); Fx.HitFlash(ctx.target, WHITE, 0.3)
		ctx.flash(WHITE, 0.4, 0.2); ctx.shake(0.5, 0.35)
	end)

	-- 0.00 draw stance: sinks low, eyes closed, sword drawn back to the left hip
	ctx.pose({ Root = T(0, -0.8, 0), LeftHip = R(30), LeftKnee = R(-35), RightHip = R(-20), RightKnee = R(-25), LeftAnkle = R(10), Waist = R(-5, 25, 0), Neck = R(-10, -15, 0),
		RightShoulder = R(10, 0, -55), RightElbow = R(70), LeftShoulder = R(20, 0, 20), LeftElbow = R(80) }, to(0.3), "inout")
	at(0.4)
	-- 0.40 vanishes and flickers through seven cuts on a 5-stud circle (heptagram order)
	local base, elev = math.atan2(-f.Z, -f.X), { -35, 20, -10, 45, -50, 10, 30 }
	vis(false)
	Fx.Burst(ctx.myPos(), C1, 3, 0.2, { startSize = 1 }); Fx.Particles(ctx.myPos(), { color = C2, count = 12, speed = 10, size = 0.25, lifetime = 0.3, light = 1 })
	local cut = { Root = T(0, -0.4, -0.5), RightShoulder = R(100, 0, 0), RightElbow = R(0), Waist = R(-10, -40, 0), LeftShoulder = R(-20, 0, -30), LeftElbow = R(20),
		LeftHip = R(40), LeftKnee = R(-40), RightHip = R(-30), RightKnee = R(-15), Neck = R(0, 20, 0) }
	for i = 1, 7 do
		local ti, a, tp = 0.4 + (i - 1) * 0.085, base + (i - 1) * 3 * 2 * math.pi / 7, ctx.targetPos()
		local p = Vector3.new(tp.X + math.cos(a) * 5, start.Y, tp.Z + math.sin(a) * 5)
		ctx.moveTo(p, 0.01)
		task.spawn(ctx.pose, cut, 0.02, "snap")
		vis(true)
		local hd = (tp - p) * Vector3.new(1, 0, 1); hd = hd.Magnitude > 0.1 and hd.Unit or f
		local e = math.rad(elev[i])
		local ln = mk({ Size = Vector3.new(0.15, 0.15, 1), Color = C1, Transparency = 0.3, CFrame = CFrame.lookAt(tp, tp + hd * math.cos(e) + UP * math.sin(e)) })
		Fx.Tween(ln, 0.05, { Size = Vector3.new(0.15, 0.15, 9) })
		local pl = Instance.new("PointLight"); pl.Color = C2; pl.Range = 6; pl.Brightness = 1.5; pl.Parent = ln
		lines[i] = ln
		Fx.Particles(tp + hd * (math.random() - 0.5) * 2, { color = WHITE, count = 6, speed = 8, size = 0.2, lifetime = 0.25, light = 1 })
		if torso then fade(mk({ Size = torso.Size, Color = C2, Material = Enum.Material.ForceField, CFrame = torso.CFrame * CFrame.new(0, 0, -0.5) }), 0.3) end
		if head then fade(mk({ Shape = Enum.PartType.Ball, Size = head.Size, Color = C2, Material = Enum.Material.ForceField, CFrame = head.CFrame * CFrame.new(0, 0, -0.5) }), 0.3) end
		at(ti + 0.05)
		vis(false)
		at(ti + 0.085)
	end
	-- 1.00 reappears behind the target, back turned, perfectly still, sliding the blade home
	local tp = ctx.targetPos()
	local behind = Vector3.new(tp.X, start.Y, tp.Z) + f * 4.5
	ctx.moveTo(behind, 0.01); ctx.face(behind + f * 10); vis(true)
	ctx.flash(C3, 0.15, 0.6)
	for _, ln in lines do Fx.Tween(ln, 0.4, { Transparency = 0, Size = Vector3.new(0.25, 0.25, 9) }) end
	local sheathe = { Root = T(0, -0.1, 0), RightShoulder = R(90, 0, -20), RightElbow = R(10), LeftShoulder = R(15, 0, 15), LeftElbow = R(75), Neck = R(-5), Waist = R(0, 10, 0) }
	ctx.pose(sheathe, 0.05, "out")
	sheathe.RightShoulder, sheathe.RightElbow = R(10, 0, -45), R(70)
	ctx.pose(sheathe, to(1.4), "inout")
	-- 1.42 the click: a tiny waist settle
	sheathe.Waist = R(-3, 10, 0)
	ctx.pose(sheathe, to(1.55), "snap")
	-- 1.60 opens his eyes, shoulders relax, one calm step away; silver petals drift down
	for i = 1, 10 do
		local pp = ctx.targetPos() + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 8 + UP * (2 + math.random() * 2)
		local pt = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.05, 0.25, 0.4), Color = i % 3 == 0 and C4 or C1, Material = Enum.Material.Glass, Transparency = 0.2,
			CFrame = CFrame.new(pp) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		fade(pt, 0.75, { CFrame = CFrame.new(pp - UP * 1.6) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6) })
	end
	Fx.Tween(hl, 0.4, { OutlineTransparency = 1 })
	ctx.pose({ Root = T(0, -0.05, -0.7), Neck = R(10), RightShoulder = R(5, 0, 8), RightElbow = R(15), LeftShoulder = R(10, 0, -5), LeftElbow = R(40),
		RightHip = R(-15), LeftHip = R(20), LeftKnee = R(-15) }, to(1.8), "inout")
	if w then w.LocalTransparencyModifier = 0 end
	-- 1.80 turns calmly back toward the enemy as he settles into guard
	task.spawn(ctx.spin, 180, 0.2)
	ctx.pose(P.guard, 0.2)
end
