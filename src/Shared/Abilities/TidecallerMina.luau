-- Tidecaller Mina :: Moonwell Crescent Tide (impact 1.30s, total 1.80s)
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
	task.delay(2.4, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP, rh, gc = 1.3, ctx.part("RightHand"), ctx.ground() + UP * 0.12
	local w = ctx.weapon(); if w then w.LocalTransparencyModifier = 1; task.delay(1.95, function() w.LocalTransparencyModifier = 0 end) end
	ctx.callout()

	-- conjured moon staff, rotating rune ring (14 arcs + 6 violet runes), 3 seawater ribbons (aqua/white/violet), orb, 8-piece crescent + violet ForceField glow
	local staff = mk({ Shape = Enum.PartType.Cylinder, Color = C3, Material = Enum.Material.Glass, Transparency = 0.15 })
	local gem = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Color = C2 })
	local ring, runes, rib, heads, RC = {}, {}, {}, {}, { C2, C3, C4 }
	for i = 1, 14 do ring[i] = mk({ Size = Vector3.new(1.4, 0.1, 0.18), Color = C2, Transparency = 1 }) end
	for i = 1, 6 do runes[i] = mk({ Size = Vector3.new(0.4, 0.1, 0.6), Color = C4, Transparency = 1 }) end
	for r = 1, 3 do rib[r] = {}; for j = 1, 7 do rib[r][j] = mk({ Shape = Enum.PartType.Cylinder, Color = RC[r], Transparency = 1 }) end
		heads[r] = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = RC[r], Transparency = 1 }) end
	local orbG = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one, Color = C2, Material = Enum.Material.Glass, Transparency = 1 })
	local orbN = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = C2, Transparency = 1 })
	local disc = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 5.3, 5.3), Color = C3, Material = Enum.Material.Glass, Transparency = 1 })
	local cres, glo = {}, {}
	for j = 1, 8 do cres[j] = mk({ Color = C2, Transparency = 1 }); glo[j] = mk({ Color = C4, Material = Enum.Material.ForceField, Transparency = 1 }) end
	local function crescent(cf, r, span, close, vis)
		for j = 1, 8 do
			local u = (j - 0.5) / 8
			local seg = cf * CFrame.Angles(0, 0, math.rad(135) + span * (u - 0.5)) * CFrame.new(r, 0, 0)
			local th, len = 0.55 * ((0.25 + 0.75 * math.sin(math.pi * u)) * (1 - close) + close), r * span / 8 * 1.12
			cres[j].Size, cres[j].CFrame, cres[j].Transparency = Vector3.new(th, len, 0.3), seg, 1 - vis
			glo[j].Size, glo[j].CFrame, glo[j].Transparency = Vector3.new(th + 0.35, len * 1.05, 0.5), seg, vis > 0.05 and 0 or 1
		end
	end
	local holder = mk({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(start) })
	local light = Instance.new("PointLight"); light.Color = C4; light.Range = 16; light.Brightness = 1.5; light.Parent = holder
	task.spawn(function()
		local fx, launch, mcf = 0, nil, nil
		while el() < 1.8 do
			local t, tp = el(), ctx.targetPos()
			-- staff: upright, twirled flat overhead (2 turns), upright overhead, whipping with the arm, twirled, upright
			local grip = rh and rh.Position or ctx.myPos() + f
			local dir = UP
			if t >= 0.35 and t < 0.8 then dir = CFrame.fromAxisAngle(UP, (t - 0.35) / 0.45 * 4 * math.pi) * f
			elseif t >= 1.05 and t < 1.5 then dir = rh and -rh.CFrame.UpVector or f
			elseif t >= 1.5 and t < 1.63 then dir = CFrame.fromAxisAngle(f, (t - 1.5) / 0.13 * 2 * math.pi) * UP end
			local tip = grip + dir * 2.8
			line(staff, grip - dir * ((t >= 0.35 and t < 0.8) and 2.2 or 1.2), tip, 0.22); gem.CFrame = CFrame.new(tip)
			-- rune ring turns under her, then shrinks away
			local rs = math.max(0.05, t < 1.5 and 1 or 1 - (t - 1.5) / 0.3)
			local ra = math.clamp(t / 0.2, 0, 1) * (t < 1.5 and 1 or rs)
			for i, p in ring do p.Size = Vector3.new(1.4 * rs, 0.1, 0.18); p.Transparency = 1 - ra * 0.85
				p.CFrame = CFrame.new(gc) * CFrame.Angles(0, t * 0.9 + i * 0.4488, 0) * CFrame.new(0, 0, -3 * rs) end
			for i, p in runes do p.CFrame = CFrame.new(gc) * CFrame.Angles(0, -t * 1.4 + i * 1.047, 0) * CFrame.new(0, 0.02, -2.3 * rs); p.Transparency = 1 - ra end
			light.Brightness = t < 0.35 and 1.5 or (t < 0.8 and 2 + 4 * (t - 0.35) / 0.45 or math.max(0, 6 - math.max(0, t - IMP) * 12))
			-- three ribbons spiral up from the ring into the staff tip
			local grow, rv = math.clamp((t - 0.35) / 0.25, 0, 1), (t > 0.35 and t < 0.95) and 1 - math.clamp((t - 0.85) / 0.1, 0, 1) or 0
			for r = 1, 3 do
				local prev
				for j = 0, 7 do
					local s = grow * j / 7
					local a, rad = r * 2.094 + t * 6 + s * 7.85, 3 * (1 - s) + 0.2 * s
					local pt = gc:Lerp(tip, s) + Vector3.new(math.cos(a) * rad, 0, math.sin(a) * rad)
					if prev then line(rib[r][j], prev, pt, 0.16 + 0.08 * (1 - s)); rib[r][j].Transparency = 1 - rv * 0.85 end
					prev = pt
				end
				heads[r].CFrame = CFrame.new(prev); heads[r].Transparency = 1 - rv
			end
			-- water orb 1 -> 3 studs, then the crescent forms, flies, closes into a full moon and bursts
			local ok = math.clamp((t - 0.8) / 0.15, 0, 1)
			if t >= 0.8 and t < 1.0 then local sz = 1 + 2 * ok * (1 - math.clamp((t - 0.95) / 0.05, 0, 1))
				orbG.Size, orbN.Size = Vector3.one * sz, Vector3.one * sz * 0.55
				orbG.CFrame = CFrame.new(tip + UP * sz * 0.4); orbN.CFrame = orbG.CFrame; orbG.Transparency, orbN.Transparency = 0.35, 0
			else orbG.Transparency, orbN.Transparency = 1, 1 end
			if t >= 0.95 and t < 1.12 then
				crescent(CFrame.lookAt(tip + UP * 0.6, tip + UP * 0.6 + f), 0.6 + math.clamp((t - 0.95) / 0.1, 0, 1), 3.5, 0, math.clamp((t - 0.95) / 0.06, 0, 1))
			elseif t >= 1.12 and t < IMP then
				if not launch then launch = tip + UP * 0.6; Fx.Trail(cres[4], C3, 0.25, 1); Fx.Trail(cres[5], C2, 0.25, 0.7) end
				local k = (t - 1.12) / (IMP - 1.12)
				local pos = launch:Lerp(tp, k)
				crescent(CFrame.lookAt(pos, pos + f) * CFrame.Angles(0, 0, k * 1.2), 1.6 + 1.4 * k, 3.5, 0, 1)
				if t - fx > 0.03 then fx = t; Fx.Particles(pos, { color = C3, count = 3, speed = 3, size = 0.35, lifetime = 0.35, gravity = 15, light = 0.6 }) end
			elseif t >= IMP and t < 1.44 then
				mcf = mcf or CFrame.lookAt(tp, tp + f) * CFrame.Angles(0, 0, 1.2)
				local k = math.clamp((t - IMP) / 0.06, 0, 1)
				crescent(mcf, 3 + 0.3 * math.clamp((t - 1.36) / 0.08, 0, 1), 3.5 + 2.9 * k, k, 1)
				disc.CFrame = mcf * CFrame.Angles(0, math.pi / 2, 0); disc.Transparency = 1 - k * 0.55
			elseif t >= 1.44 and mcf then
				for j = 1, 8 do fade(cres[j], 0.2, { CFrame = cres[j].CFrame * CFrame.new(2.5, 0, 0) }); fade(glo[j], 0.2) end
				fade(disc, 0.15, { Size = Vector3.new(0.15, 8, 8) }); mcf = nil
			end
			if t < 0.35 and t - fx > 0.05 then fx = t
				local a = math.random() * 6.28
				Fx.Particles(gc + Vector3.new(math.cos(a) * 3, 0.2, math.sin(a) * 3), { color = C2, count = 2, speed = 2, size = 0.3, lifetime = 0.6, gravity = -6, spread = 20, light = 0.6 })
			end
			holder.CFrame = CFrame.new(ctx.myPos())
			ctx.wait(0)
		end
		for _, p in { staff, gem, table.unpack(ring) } do fade(p, 0.12) end
		for _, p in runes do fade(p, 0.12) end
	end)
	for r = 1, 3 do task.delay(0.35, function() Fx.Trail(heads[r], RC[r], 0.6, 0.25) end) end

	-- full moon: aqua highlight, foam ring at the feet; at 1.44 the moon bursts into spray and violet sparkles, then drizzles
	task.delay(IMP - 0.02, function()
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		Fx.HitFlash(ctx.target, C2, 0.5); Fx.Ring(CFrame.new(tg + UP * 0.15), C3, 2, 9, 0.5, 0.2)
		Fx.Light(tp, C2, 18, 4, 0.5); ctx.shake(0.35, 0.3)
		task.delay(0.14, function()
			Fx.Burst(tp, C3, 7, 0.3, { startSize = 5, transparency = 0.3 })
			Fx.Particles(tp, { color = C2, count = 30, speed = 22, size = 0.45, lifetime = 0.6, gravity = 25, light = 0.6 })
			Fx.Particles(tp, { color = C4, count = 14, speed = 14, size = 0.3, lifetime = 0.6, light = 1 }); ctx.flash(C3, 0.3, 0.2)
		end)
		task.delay(0.25, function() Fx.Particles(tp + UP * 4, { color = C3, count = 16, speed = 2, size = 0.3, lifetime = 0.8, gravity = 30, spread = 60, light = 0.4 }) end)
		task.delay(0.35, function() Fx.Particles(tp, { color = C4, count = 8, speed = 3, size = 0.25, lifetime = 0.5, light = 1 }) end)
	end)

	-- 0.00 plants the staff, eyes closed, and rises 1.5 studs with toes pointed
	task.spawn(ctx.moveTo, start + UP * 1.5, 0.35)
	ctx.pose({ RightShoulder = R(55, 0, -12), RightElbow = R(65), LeftShoulder = R(55, 0, 12), LeftElbow = R(75), Neck = R(-22), Waist = R(5),
		RightKnee = R(-12), LeftKnee = R(-25), RightAnkle = R(-45), LeftAnkle = R(-45) }, to(0.35), "inout")
	-- 0.35 twirls the staff overhead, left arm stretched out, waist turning with it
	local spinP = { RightShoulder = R(172, 0, 8), RightElbow = R(12), LeftShoulder = R(5, 0, -92), LeftElbow = R(5), Neck = R(10), RightAnkle = R(-45), LeftAnkle = R(-45), LeftKnee = R(-25) }
	for i = 1, 3 do spinP.Waist = R(0, i % 2 == 1 and 22 or -22, 0); ctx.pose(spinP, to(0.35 + i * 0.15), "inout") end
	-- 0.80 staff straight overhead in both hands, chin up: the ribbons meet in a water orb
	ctx.pose({ RightShoulder = R(176, 0, -4), LeftShoulder = R(176, 0, 4), RightElbow = R(8), LeftElbow = R(8), Neck = R(28), Waist = R(10),
		RightAnkle = R(-45), LeftAnkle = R(-45), LeftKnee = R(-20) }, to(1.0), "out")
	at(1.05)
	-- 1.05 wind to the upper right, then the sweeping diagonal slash, left hip forward
	ctx.pose({ RightShoulder = R(165, 0, 40), RightElbow = R(10), LeftShoulder = R(120, 0, -10), LeftElbow = R(30), Waist = R(8, -35, 0), Neck = R(15),
		RightAnkle = R(-40), LeftAnkle = R(-40) }, to(1.11), "out")
	ctx.pose({ RightShoulder = R(40, -20, -45), RightElbow = R(5), LeftShoulder = R(90, 0, -5), LeftElbow = R(0), Waist = R(-15, 50, 0), Neck = R(-5),
		LeftHip = R(40), LeftKnee = R(-25), RightHip = R(-15), RightAnkle = R(-30), Root = T(0, -0.1, -0.5, -10) }, to(1.22), "snap")
	at(1.5)
	-- 1.50 floats back down, twirls the staff once, small elegant bow
	task.spawn(ctx.moveTo, start, 0.25)
	ctx.pose({ RightShoulder = R(70, 0, 10), RightElbow = R(30), LeftShoulder = R(20, 0, -20), LeftElbow = R(20), Waist = R(0, 15, 0) }, to(1.63), "inout")
	ctx.pose({ Waist = R(-22), Neck = R(-18), RightShoulder = R(20, 0, 15), RightElbow = R(20), LeftShoulder = R(35, 0, -5), LeftElbow = R(80),
		RightHip = R(10), LeftHip = R(-15), LeftKnee = R(-25), Root = T(0, -0.15, 0.1) }, to(1.75), "back")
	ctx.pose(P.guard, 0.2)
end
