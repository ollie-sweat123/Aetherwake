-- Leviathan Nerissa :: Coronation of the Abyss (impact 2.00s, total 2.60s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local function line(p, a, b, w) local d = b - a; if d.Magnitude < 0.02 then d = UP * 0.02 end
		p.Size = Vector3.new(d.Magnitude, w, w); p.CFrame = CFrame.lookAt(a + d / 2, a + d, math.abs(d.Unit.Y) > 0.98 and Vector3.xAxis or UP) * CFrame.Angles(0, math.pi / 2, 0) end
	task.delay(3.2, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP, g0, side, WHITE = 2.0, ctx.ground(), f:Cross(UP).Unit, Color3.new(1, 1, 1)
	local high = start + UP * 6
	local rh, lh, head = ctx.part("RightHand"), ctx.part("LeftHand"), ctx.part("Head")
	local function hp(p) return p and p.Position or ctx.myPos() + f end
	local w = ctx.weapon(); if w then w.LocalTransparencyModifier = 1; task.delay(2.75, function() w.LocalTransparencyModifier = 0 end) end
	ctx.callout()

	-- conjured trident (navy shaft, gold crossbar + 3 prongs, 3 gold spikes), crown light, water pillar, coral-gold halo
	local shaft = mk({ Shape = Enum.PartType.Cylinder, Color = C2, Material = Enum.Material.Metal })
	local bar = mk({ Shape = Enum.PartType.Cylinder, Color = C3 })
	local prong, spike = {}, {}
	for i = 1, 3 do prong[i] = mk({ Shape = Enum.PartType.Cylinder, Color = C3 }); spike[i] = mk({ Shape = Enum.PartType.Cylinder, Color = C3, Transparency = 1 }) end
	local crown = mk({ Size = Vector3.one * 0.2, Transparency = 1 })
	local cl = Instance.new("PointLight"); cl.Color = C3; cl.Range = 12; cl.Brightness = 3; cl.Parent = crown
	local shell = mk({ Shape = Enum.PartType.Cylinder, Color = C1, Material = Enum.Material.Glass, Transparency = 1 })
	local core = mk({ Shape = Enum.PartType.Cylinder, Color = C1, Transparency = 1 })
	local halo, spk = {}, {}
	for i = 1, 16 do halo[i] = mk({ Color = C3, Transparency = 1 }) end
	for i = 1, 12 do spk[i] = mk({ Shape = Enum.PartType.Wedge, Color = i % 2 == 0 and C3:Lerp(C4, 0.5) or C1:Lerp(C3, 0.5), Transparency = 1 }) end
	-- spectral sea serpent: 14 glowing balls (smaller to the tail), beam links, back fins, wedge head with gold horns and white eyes
	local body, link, fin = {}, {}, {}
	for i = 1, 14 do body[i] = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * (1.55 - i * 0.075), Color = C1, Transparency = 1 }) end
	for i = 1, 13 do link[i] = mk({ Shape = Enum.PartType.Cylinder, Color = C1, Transparency = 1 }) end
	for i = 1, 6 do fin[i] = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.12, 0.7, 0.9), Color = C4, Transparency = 1 }) end
	local jawU = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(1.1, 0.5, 1.6), Color = C1, Transparency = 1 })
	local jawL = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.9, 0.35, 1.3), Color = C1, Transparency = 1 })
	local horn = { mk({ Size = Vector3.new(0.14, 0.14, 1.2), Color = C3, Transparency = 1 }), mk({ Size = Vector3.new(0.14, 0.14, 1.2), Color = C3, Transparency = 1 }) }
	local eye = { mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.28, Color = WHITE, Transparency = 1 }), mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.28, Color = WHITE, Transparency = 1 }) }
	for _, i in { 1, 6, 11 } do local l = Instance.new("PointLight"); l.Color = C1; l.Range = 8; l.Brightness = 2; l.Parent = body[i] end
	local a0 = math.atan2(-f.Z, -f.X)
	local function H(t, tp) -- the serpent head's path: helix up round her, dive arc, 3 tightening loops round the target
		if t < 1.3 then local k = math.clamp((t - 0.8) / 0.5, 0, 1); local a = k * 4 * math.pi
			return Vector3.new(high.X + math.cos(a) * 2.6, g0.Y + 0.5 + k * (high.Y + 2 - g0.Y - 0.5), high.Z + math.sin(a) * 2.6) end
		local wrap = function(k) local a = a0 + k * 6 * math.pi; local r = 4 - 2.5 * k
			return Vector3.new(tp.X + math.cos(a) * r, tp.Y - 2 + 4 * k, tp.Z + math.sin(a) * r) end
		if t < 1.6 then local k = (t - 1.3) / 0.3; return H(1.29, tp):Lerp(wrap(0), k) + UP * math.sin(k * math.pi) * 4 end
		return wrap(math.clamp((t - 1.6) / 0.35, 0, 1))
	end
	task.spawn(function()
		local fx, trails = 0, false
		while el() < 2.6 do
			local t, tp = el(), ctx.targetPos()
			local me, Rp, Lp = ctx.myPos(), hp(rh), hp(lh)
			-- trident pose by phase: at the chest, level overhead, upright, levelled at the foe, plunged down, twirled, planted
			local d, grip = UP, Rp
			if t < 0.4 then grip = (Rp + Lp) / 2 elseif t < 0.8 then d, grip = side, (Rp + Lp) / 2
			elseif t >= 1.3 and t < 1.95 then d = (tp - Rp).Unit elseif t >= 1.95 and t < 2.2 then d, grip = (-UP * 0.85 + f * 0.5).Unit, (Rp + Lp) / 2
			elseif t >= 2.2 and t < 2.4 then d = CFrame.fromAxisAngle(f, (t - 2.2) / 0.2 * 2 * math.pi) * UP end
			local butt = t >= 2.4 and Vector3.new(Rp.X, me.Y - 2.95, Rp.Z) or grip - d * (t >= 0.4 and t < 0.8 and 2.2 or 1.6)
			local top = butt + d * 4.6
			local pv = d:Cross(math.abs(d.Y) > 0.9 and f or UP).Unit
			line(shaft, butt, top, 0.2); line(bar, top - pv * 0.45, top + pv * 0.45, 0.14)
			local sp = math.clamp((t - 1.3) / 0.1, 0, 1) * ((t < 1.95) and 1 or 0)
			for i = 1, 3 do local base = top + pv * (i - 2) * 0.42
				line(prong[i], base, base + d * (i == 2 and 1.2 or 0.9), 0.12)
				local pt = base + d * (i == 2 and 1.2 or 0.9)
				line(spike[i], pt, pt + d * (0.05 + 1.3 * sp), 0.07); spike[i].Transparency = sp > 0 and 0 or 1
			end
			-- crown light, water pillar under her feet, gown pouring like a waterfall
			if head then crown.CFrame = CFrame.new(head.Position + UP * 0.8) end
			local ph = math.max(0, me.Y - start.Y)
			for _, e in { { shell, 4.4, 0.35 }, { core, 1.8, 0 } } do
				e[1].Size = Vector3.new(math.max(ph, 0.05), e[2], e[2]); e[1].CFrame = CFrame.new(g0 + UP * ph / 2) * CFrame.Angles(0, 0, math.pi / 2)
				e[1].Transparency = ph > 0.1 and e[3] or 1
			end
			-- halo unfolds behind her, rotating slowly, then shrinks away
			local hs = math.clamp((t - 0.4) / 0.25, 0, 1) * (1 - math.clamp((t - 2.2) / 0.3, 0, 1))
			local Hc = CFrame.lookAt(me - f * 1.6 + UP, me - f * 1.6 + UP + f)
			for i, p in halo do p.Size = Vector3.new(0.35, 2.4 * math.max(hs, 0.05), 0.3); p.Transparency = hs > 0.02 and 0 or 1
				p.CFrame = Hc * CFrame.Angles(0, 0, t * 0.5 + i * math.pi / 8) * CFrame.new(6 * math.max(hs, 0.05), 0, 0) end
			for i, p in spk do p.Size = Vector3.new(0.25, 0.9 * math.max(hs, 0.05), 1.6 * math.max(hs, 0.05)); p.Transparency = hs > 0.02 and 0 or 1
				p.CFrame = Hc * CFrame.Angles(0, 0, -t * 0.25 + i * math.pi / 6) * CFrame.new(6.9 * math.max(hs, 0.05), 0, 0) * CFrame.Angles(0, -math.pi / 2, 0) end
			-- the serpent (each segment trails the head along its path), squeezes to a point at 1.95, bursts at 2.0
			local sq, glowK = math.clamp((t - 1.95) / 0.05, 0, 1), math.clamp((t - 1.6) / 0.35, 0, 1)
			if t >= 0.8 and t < IMP then
				if not trails then trails = true; for i, b in body do Fx.Trail(b, C1, 1.2, b.Size.X * 0.3) end end
				for i, b in body do
					local ti = t - (i - 1) * 0.03
					b.CFrame = CFrame.new(H(math.max(ti, 0.8), tp):Lerp(tp, sq)); b.Transparency = ti > 0.8 and 0 or 1
					b.Color = C1:Lerp(WHITE, glowK * 0.6 + sq * 0.4); b.Size = Vector3.one * (1.55 - i * 0.075) * (1 - 0.85 * sq)
				end
				for i, l in link do line(l, body[i].Position, body[i + 1].Position, 0.35 * (1 - 0.85 * sq)); l.Transparency = body[i + 1].Transparency * 0.5 + 0.5 * (body[i + 1].Transparency) + 0.1 end
				for j, fp in fin do local b, nb = body[j * 2 + 1], body[j * 2]
					fp.CFrame = CFrame.lookAt(b.Position, b.Position + (nb.Position - b.Position + f * 0.01)) * CFrame.new(0, b.Size.X / 2 + 0.25, 0); fp.Transparency = b.Transparency end
				local hpos = body[1].Position
				local dir = (H(t, tp) - H(t - 0.03, tp)); dir = dir.Magnitude > 0.01 and dir.Unit or f
				local hc = CFrame.lookAt(hpos, hpos + dir) * CFrame.new(0, 0, -0.4)
				local jaw = (t > 1.3 and t < 1.45) and 0.6 or 0.1
				jawU.CFrame = hc * CFrame.new(0, 0.25, -0.5); jawL.CFrame = hc * CFrame.new(0, -0.1, -0.2) * CFrame.Angles(jaw, 0, 0) * CFrame.new(0, -0.15, -0.4) * CFrame.Angles(0, 0, math.pi)
				for s = 1, 2 do local x = s == 1 and 0.35 or -0.35
					horn[s].CFrame = hc * CFrame.new(x, 0.55, 0.45) * CFrame.Angles(math.rad(35), 0, 0); eye[s].CFrame = hc * CFrame.new(x, 0.35, -0.3) end
				local hv = body[1].Transparency
				for _, p in { jawU, jawL, horn[1], horn[2], eye[1], eye[2] } do p.Transparency = hv end
			elseif t >= IMP and body[1].Parent then
				for _, p in { jawU, jawL, horn[1], horn[2], eye[1], eye[2], table.unpack(body) } do p:Destroy() end
				for _, p in link do p:Destroy() end; for _, p in fin do p:Destroy() end
			end
			if t - fx > 0.05 then fx = t
				if t < 2.2 then Fx.Particles(me - UP * 2.4, { color = C1, count = 3, speed = 4, size = 0.35, lifetime = 0.5, gravity = 35, light = 0.6 }) end
				if t > 0.4 and t < 1.3 then local r = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5) * 10
					Fx.Particles(me + r, { color = C4, count = 2, speed = 1, size = 0.3, lifetime = 0.8, light = 1 }) end
				if t > 1.6 and t < 1.95 then local d2 = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					local m = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, Color = C4, CFrame = CFrame.new(tp + (d2.Magnitude > 0.01 and d2.Unit or UP) * 5) })
					Fx.Tween(m, 0.2, { CFrame = CFrame.new(tp), Size = Vector3.one * 0.1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In); task.delay(0.21, function() m:Destroy() end)
				end
			end
			ctx.wait(0)
		end
		for _, p in { shaft, bar, shell, core, table.unpack(prong) } do fade(p, 0.12) end
		for i = 1, 3 do fade(spike[i], 0.1) end
		for _, p in halo do fade(p, 0.1) end; for _, p in spk do fade(p, 0.1) end
	end)
	task.delay(1.3, function()
		local hc = CFrame.lookAt(body[1].Position, ctx.targetPos())
		Fx.Ring(hc * CFrame.Angles(math.rad(-90), 0, 0), C1, 1, 7, 0.35, 0.3); Fx.Ring(hc * CFrame.Angles(math.rad(-90), 0, 0), WHITE, 0.5, 5, 0.25, 0.12)
		Fx.Trail(body[1], C1:Lerp(WHITE, 0.6), 0.5, 0.9)
	end)
	task.delay(1.6, function() Fx.HitFlash(ctx.target, C1, 0.4) end)
	for n = 0, 2 do task.delay(1.62 + n * 0.1, function()
		local rg = Fx.Ring(CFrame.new(ctx.targetGround() + UP * (0.5 + n * 1.5)), C1, 5 - n, 2, 0.3, 0.25); Fx.Tween(rg, 0.3, { CFrame = rg.CFrame + UP * 3 })
	end) end

	-- the coronation: aqua + gold ForceField blast to 16, 12 glowing pearls burst up and rain down, 8 beams skyward
	task.delay(IMP - 0.02, function()
		local tp, tg = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		Fx.Burst(tp, C1, 16, 0.55, { startSize = 0.2, transparency = 0, material = Enum.Material.ForceField })
		Fx.Burst(tp, C3, 11, 0.45, { startSize = 0.2, transparency = 0.1, material = Enum.Material.ForceField }); Fx.Burst(tp, WHITE, 5, 0.25, { startSize = 0.2 })
		for i = 1, 8 do local o = (CFrame.Angles(0, i * math.pi / 4, 0) * f) * 2.5; Fx.Beam(tg + o, tg + o + UP * 22, i % 2 == 0 and C4 or C1, 0.6, 0.5) end
		Fx.Particles(tp, { color = C1, count = 30, speed = 30, size = 0.5, lifetime = 0.6, light = 1 })
		Fx.Light(tp, C1, 26, 6, 0.6); Fx.HitFlash(ctx.target, WHITE, 0.3)
		ctx.flash(C1:Lerp(WHITE, 0.5), 0.7, 0.3); ctx.shake(0.9, 0.5)
		local ps = {}
		for i = 1, 12 do local a, s = i * math.pi / 6, 4 + (i % 3) * 2
			local p = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = WHITE, CFrame = CFrame.new(tp) }); Fx.Trail(p, C3, 0.6, 0.18)
			ps[i] = { p, Vector3.new(math.cos(a) * s, 14 + (i % 4) * 3, math.sin(a) * s), false }
		end
		local s0 = el()
		while el() < 2.6 do
			local k = el() - s0
			for _, q in ps do
				local pos = tp + q[2] * k - UP * 50 * k * k
				if pos.Y < tg.Y + 0.3 then pos = Vector3.new(pos.X, tg.Y + 0.3, pos.Z); if not q[3] then q[3] = true; fade(q[1], 0.25, { Size = Vector3.one * 0.9 }) end end
				q[1].CFrame = CFrame.new(pos)
			end
			ctx.wait(0)
		end
		for _, q in ps do if not q[3] then fade(q[1], 0.2) end end
		Fx.Particles(tp, { color = C3, count = 12, speed = 3, size = 0.3, lifetime = 0.7, light = 1 })
	end)

	-- 0.00 eyes closed, trident folded to her chest, spiralling up 6 studs on the rising pillar; crown blazes, the sea darkens
	ctx.flash(C2, 0.35, 2.5); Fx.HitFlash(head, C3, 1)
	task.spawn(ctx.moveTo, high, 0.4)
	local fold = { RightShoulder = R(40, 0, -28), RightElbow = R(115), LeftShoulder = R(40, 0, 28), LeftElbow = R(115), Neck = R(14), RightAnkle = R(-35), LeftAnkle = R(-35) }
	for i = 1, 4 do fold.Root = T(0, 0, 0, 0, i * 90, 0); ctx.pose(fold, to(i * 0.1), "linear") end
	-- 0.40 arms spread wide, trident level overhead, back arched: the halo unfolds
	Fx.HitFlash(ctx.model, C1, 0.8)
	ctx.pose({ RightShoulder = R(160, 0, 38), LeftShoulder = R(160, 0, -38), RightElbow = R(25), LeftElbow = R(25), Waist = R(14), Neck = R(22), RightAnkle = R(-35), LeftAnkle = R(-35) }, to(0.62), "out")
	at(0.8)
	-- 0.80 conducting: left hand lowers to the pillar and lifts slowly as the serpent rises
	local cond = { RightShoulder = R(30, 0, 12), RightElbow = R(85), LeftShoulder = R(25, 0, -35), LeftElbow = R(15), LeftWrist = R(-35), Neck = R(-10), Waist = R(0, 10, 0), RightAnkle = R(-35), LeftAnkle = R(-35) }
	ctx.pose(cond, to(0.95), "inout")
	cond.LeftShoulder, cond.LeftWrist, cond.Neck = R(115, 0, -25), R(25), R(12); ctx.pose(cond, to(1.3), "inout")
	-- 1.30 trident levelled at the foe, left hand on her crown
	ctx.pose({ RightShoulder = R(95, 0, 0), RightElbow = R(0), LeftShoulder = R(165, 0, -35), LeftElbow = R(125), Waist = R(-5, -15, 0), Neck = R(-6), RightAnkle = R(-35), LeftAnkle = R(-35) }, to(1.4), "snap")
	at(1.6)
	-- 1.60 slowly closes her raised left hand
	ctx.pose({ RightShoulder = R(95, 0, 0), RightElbow = R(0), LeftShoulder = R(130, 0, -30), LeftElbow = R(35), LeftWrist = R(30), Waist = R(-5, -15, 0), Neck = R(4), RightAnkle = R(-35), LeftAnkle = R(-35) }, to(1.93), "inout")
	-- 1.95 fist clenched: a two-handed plunge of the trident
	ctx.pose({ RightShoulder = R(55, 0, -18), LeftShoulder = R(55, 0, 18), RightElbow = R(10), LeftElbow = R(10), Waist = R(-25), Neck = R(-12), Root = T(0, -0.3, 0, -10),
		RightKnee = R(-20), LeftKnee = R(-20), RightAnkle = R(-35), LeftAnkle = R(-35) }, to(2.03), "snap")
	at(2.2)
	-- 2.20 glides down as the pillar falls, twirls the trident, lands in a calm queenly pose
	task.spawn(ctx.moveTo, start, 0.3)
	ctx.pose({ RightShoulder = R(60, 0, 20), RightElbow = R(40), LeftShoulder = R(20, 0, -20), LeftElbow = R(30), Neck = R(5), RightAnkle = R(-20), LeftAnkle = R(-20) }, to(2.4), "inout")
	Fx.Ring(CFrame.new(g0 + UP * 0.15), C1, 2, 9, 0.45, 0.25); Fx.Particles(g0 + UP * 0.5, { color = C1, count = 16, speed = 10, size = 0.4, lifetime = 0.45, spread = 60, gravity = 30, light = 0.6 })
	ctx.pose({ RightShoulder = R(15, 0, 18), RightElbow = R(35), LeftShoulder = R(10, 0, -12), LeftElbow = R(50), Neck = R(12), Waist = R(0, -8, 0), RightHip = R(0, 0, 4), LeftHip = R(8), LeftKnee = R(-12) }, to(2.55), "back")
	ctx.pose(P.guard, 0.2)
end
