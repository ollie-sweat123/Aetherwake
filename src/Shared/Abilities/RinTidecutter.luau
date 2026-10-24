-- Rin Tidecutter: Ebbline Mirror Dance (impact 1.05s, total 1.75s)
return function(ctx)
	local Fx, P, R, T = ctx.Fx, ctx.P, ctx.R, ctx.T
	local NAVY, SKY, AQUA, FOAM = ctx.palette[1] or ctx.accent, ctx.palette[2] or ctx.accent, ctx.palette[3] or ctx.accent, ctx.palette[4] or Color3.new(1, 1, 1)
	local IMPACT, GLASS, UP, LIMB, BALL = 1.05, Enum.Material.Glass, Vector3.yAxis, Vector3.new(1, 2, 1), Enum.PartType.Ball
	local t0, start = os.clock(), ctx.myPos()
	local function at(t) local d = t - (os.clock() - t0); if d > 0 then ctx.wait(d) end end
	local function flat(v) return Vector3.new(v.X, 0, v.Z) end
	local function dir() local d = flat(ctx.targetPos() - ctx.myPos()); return d.Magnitude > 0.05 and d.Unit or flat(ctx.root.CFrame.LookVector).Unit end
	local function mk(props, life) local p = Fx.Part(props); task.delay(life, function() p:Destroy() end); return p end
	-- time-bounded background per-frame updater (fn returns true to stop early)
	local function run(dur, fn) task.spawn(function() local s = os.clock(); while os.clock() - s < dur and not fn((os.clock() - s) / dur) do ctx.wait(0) end end) end
	local d0 = dir(); local right = d0:Cross(UP)
	-- 0.00 blade flick + two heel taps; puddles open at her sides and sky-blue glass water-mirrors of Rin rise out of them
	ctx.callout()
	Fx.Trail(ctx.weapon(), AQUA, 1.6, 0.4); Fx.HitFlash(ctx.model, AQUA, 0.4)
	local mirrors, puddles, alive, lastDrop = {}, {}, true, 0
	for _, side in { -1, 1 } do
		local g = ctx.ground() + right * side * 3.2
		Fx.Ring(CFrame.new(g + UP * 0.1), AQUA, 0.5, 4.5, 0.45, 0.12)
		local pd = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.1, 0.1), Color = AQUA, Transparency = 0.45, CFrame = CFrame.new(g + UP * 0.05) * CFrame.Angles(0, 0, math.pi / 2) }, 1.8)
		Fx.Tween(pd, 0.3, { Size = Vector3.new(0.06, 4, 4) }); table.insert(puddles, pd)
		-- parts: 1 torso, 2 head, 3-4 legs, 5 free arm, 6 sword arm, 7 neon blade; the two mirrors use opposite hands for perfect symmetry
		local m = { side = side, hand = -side, base = g + UP * 3, cut = side < 0 and 0.7 or 0.8, list = {} }
		for i, sz in { Vector3.new(2, 2, 1), Vector3.one * 1.2, LIMB, LIMB, LIMB, LIMB, Vector3.new(0.2, 3.4, 0.45) } do
			local blade = i == 7
			m.list[i] = mk({ Size = sz, Shape = i == 2 and BALL or Enum.PartType.Block, Color = blade and FOAM or SKY, Material = blade and Enum.Material.Neon or GLASS, Transparency = blade and 0.1 or 0.35 }, 1.5)
		end
		Fx.Trail(m.list[3], FOAM, 0.9, 0.3); table.insert(mirrors, m)
	end
	local function armAngle(now, cut) -- hang low -> draw back -> raise -> down-cut at `cut`
		if now < 0.35 then return 15 elseif now < 0.5 then return 15 - 60 * (now - 0.35) / 0.15 end
		if now < cut - 0.04 then return -45 + 210 * (now - 0.5) / (cut - 0.54) end
		return 165 - 155 * math.min(1, (now - cut + 0.04) / 0.08)
	end
	run(1.2, function()
		local now, tp = os.clock() - t0, ctx.targetPos()
		if not alive then return true end
		for _, m in mirrors do
			local flank = Vector3.new(tp.X, m.base.Y, tp.Z) + right * m.side * 3.6
			local pos = flank
			if now < 0.35 then pos = m.base - UP * 4.5 * (1 - now / 0.35) ^ 2 -- rise out of the puddle
			elseif now < 0.65 then local k = (now - 0.35) / 0.3; pos = m.base:Lerp(flank, 1 - (1 - k) ^ 2) + right * m.side * math.sin(math.pi * k) * 2.5 end -- curve out to the flank
			local L, cf, h = m.list, CFrame.lookAt(pos, Vector3.new(tp.X, pos.Y, tp.Z)), m.hand
			local sh = cf * CFrame.new(1.5 * h, 0.9, 0) * CFrame.Angles(0, 0, h * 0.35) * CFrame.Angles(math.rad(armAngle(now, m.cut)), 0, 0)
			L[1].CFrame, L[2].CFrame, L[3].CFrame, L[4].CFrame = cf, cf * CFrame.new(0, 1.6, 0), cf * CFrame.new(-0.5, -2, 0) * CFrame.Angles(0.3, 0, 0), cf * CFrame.new(0.5, -2, 0) * CFrame.Angles(-0.3, 0, 0)
			L[5].CFrame, L[6].CFrame, L[7].CFrame = cf * CFrame.new(-1.5 * h, 0, 0) * CFrame.Angles(0.4, 0, 0), sh * CFrame.new(0, -0.9, 0), sh * CFrame.new(0, -3.6, 0)
			if now - lastDrop > 0.1 then Fx.Particles(pos, { color = AQUA, count = 4, speed = 4, size = 0.25, lifetime = 0.4, spread = 90, gravity = 20, light = 0.5 }) end
		end
		if now - lastDrop > 0.1 then lastDrop = now end; return false
	end)
	local flick = { RightShoulder = R(-15, 0, 40), RightElbow = R(10), RightWrist = R(0, 0, -30), LeftShoulder = R(10, 0, -15), LeftElbow = R(30), Neck = R(0, 0, 12), Waist = R(0, 10, 0), Root = T(0, -0.1, 0) }
	local tap = table.clone(flick); tap.RightHip, tap.RightKnee, tap.Root = R(-15), R(-30), T(0, -0.2, 0)
	ctx.pose(flick, 0.08, "snap")
	for _ = 1, 2 do ctx.pose(tap, 0.045); ctx.pose(flick, 0.045) end
	-- 0.35 fan dash: Rin glides in to ~3 studs in front of the enemy as the mirrors curve out to its flanks
	at(0.35)
	local tp = ctx.targetPos()
	local spot = Vector3.new(tp.X, start.Y, tp.Z) - d0 * math.max(3, flat(tp - start).Magnitude - 2.2)
	Fx.Trail(ctx.part("RightFoot"), FOAM, 0.35, 0.3)
	ctx.pose({ Root = T(0, -0.6, 0, -8), Waist = R(-10, 25, 0), Neck = R(0, -20, 0), RightShoulder = R(-40, 0, 25), RightElbow = R(20), LeftShoulder = R(40, 0, -20), LeftElbow = R(60),
		RightHip = R(50), LeftHip = R(20), RightKnee = R(-70), LeftKnee = R(-50) }, 0.07, "snap")
	ctx.moveTo(spot, 0.2)
	at(0.64)
	for _, g in { ctx.ground(), mirrors[1].list[1].Position - UP * 3, mirrors[2].list[1].Position - UP * 3 } do -- mist puff + droplet splash where each lands
		Fx.Particles(g + UP * 0.3, { color = FOAM, count = 10, speed = 4, size = 1, lifetime = 0.5, spread = 85, light = 0.2 }); Fx.Ring(CFrame.new(g + UP * 0.1), AQUA, 1, 4, 0.3, 0.1)
	end
	-- 0.65 mirror cuts in perfect symmetry (left at 0.70, right at 0.80) as Rin sinks and draws her blade to her left hip
	task.spawn(function()
		for _, m in mirrors do
			at(m.cut)
			local p, mp = ctx.targetPos(), m.list[1].Position
			Fx.Slash(CFrame.lookAt(mp, p) * CFrame.new(0, 0.3, 0), AQUA, 3.2, 150, 0.3, 0.6, m.side * 40)
			Fx.Particles(p, { color = FOAM, count = 18, speed = 16, size = 0.3, lifetime = 0.4, spread = 70, gravity = 25, light = 0.5 })
			for _ = 1, 3 do -- glass splash wedges peel off
				local w = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(0.3, 0.8, 0.6), Color = SKY, Material = GLASS, Transparency = 0.3, CFrame = CFrame.new(p) }, 0.5)
				local off = flat(p - mp).Unit * 2 + Vector3.new(math.random() - 0.5, 1 + math.random(), math.random() - 0.5) * 2
				Fx.Tween(w, 0.4, { CFrame = CFrame.new(p + off) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1 })
			end
			Fx.Light(p, SKY, 12, 2.5, 0.35); Fx.HitFlash(ctx.target, AQUA, 0.12)
		end
	end)
	ctx.pose({ Root = T(0, -0.8, 0, -5), Waist = R(-10, -40, 0), Neck = R(0, 35, 0), RightShoulder = R(30, 0, -35), RightElbow = R(70), RightWrist = R(0, 0, 20), LeftShoulder = R(20, 0, -20), LeftElbow = R(60),
		RightHip = R(55), LeftHip = R(55), RightKnee = R(-80), LeftKnee = R(-80), RightAnkle = R(25), LeftAnkle = R(25) }, 0.3, "inout")
	-- 1.00 rising twirl cut: spring 2.5 studs up with a 360 spin as the blade sweeps from low to overhead
	at(1.0)
	task.spawn(ctx.moveTo, ctx.myPos() + UP * 2.5 + dir() * 0.5, 0.22)
	Fx.Trail(ctx.part("RightHand"), FOAM, 0.35, 0.4); Fx.Trail(ctx.part("LeftFoot"), SKY, 0.35, 0.3)
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.targetPos()), FOAM, 3.4, 170, 0.28, 0.7, 75)
	local tw = { RightElbow = R(10), LeftShoulder = R(20, 0, -70), LeftElbow = R(20), RightHip = R(20), RightKnee = R(-40), LeftHip = R(-10), LeftKnee = R(-10), RightAnkle = R(-30), LeftAnkle = R(-30) }
	run(0.27, function(k) -- the blade sweep finishes in the first half of the spin
		local sw = 1 - (1 - math.min(1, k * 2.2)) ^ 2
		tw.Root, tw.Waist, tw.RightShoulder = T(0, 0.2, 0, -10 * (1 - k), 360 * k, 0), R(5, -20 + 40 * sw, 0), R(-30 + 200 * sw, 0, 20); ctx.pose(tw, 0); return false
	end)
	at(IMPACT - 0.02)
	ctx.impact()
	alive = false
	tp = ctx.targetPos()
	for _, m in mirrors do -- each mirror collapses into a glass ball that pops into 40 droplets
		local c = m.list[1].Position
		for _, p in m.list do Fx.Tween(p, 0.12, { CFrame = CFrame.new(c), Size = Vector3.one * 0.3, Transparency = 1 }) end
		local ball = mk({ Shape = BALL, Size = Vector3.one, Color = SKY, Material = GLASS, Transparency = 0.25, CFrame = CFrame.new(c) }, 0.5); Fx.Tween(ball, 0.12, { Size = Vector3.one * 3.5 })
		task.delay(0.12, function()
			Fx.Tween(ball, 0.12, { Size = Vector3.one * 5.5, Transparency = 1 }); Fx.Ring(CFrame.new(c - UP * 2.8), FOAM, 1, 6, 0.4, 0.12)
			Fx.Particles(c, { color = AQUA, count = 40, speed = 22, size = 0.4, lifetime = 0.55, spread = 180, gravity = 35, light = 0.6 })
		end)
	end
	for i = 0, 1 do -- white + sky-blue water ribbons coil up around the target
		local b = mk({ Shape = BALL, Size = Vector3.one * 0.5, Color = i == 0 and FOAM or SKY, CFrame = CFrame.new(tp) }, 0.7)
		Fx.Trail(b, i == 0 and FOAM or SKY, 0.55, 0.35)
		run(0.5, function(k) local a = k * math.pi * 5 + i * math.pi; b.CFrame = CFrame.new(ctx.targetGround() + Vector3.new(math.cos(a) * (2.6 - k), 0.5 + k * 6, math.sin(a) * (2.6 - k))); return false end)
	end
	Fx.Ring(CFrame.new(ctx.targetGround() + UP * 0.12), AQUA, 2, 14, 0.6, 0.2); Fx.Burst(tp, FOAM, 5, 0.3)
	ctx.flash(NAVY, 0.4, 0.06); task.delay(0.06, function() ctx.flash(Color3.new(1, 1, 1), 0.3, 0.08) end)
	ctx.shake(0.5, 0.35)
	-- 1.30 soft one-foot landing, crisp horizontal flick of water off the blade, mist + fading puddles, back to mid guard
	at(1.3)
	local cur = ctx.myPos()
	task.spawn(ctx.moveTo, Vector3.new(cur.X, start.Y, cur.Z) - dir() * 1.2, 0.2)
	ctx.pose({ Root = T(0, -0.3, 0), Neck = R(-5), RightShoulder = R(40, 0, 50), RightElbow = R(20), LeftShoulder = R(20, 0, -50), LeftElbow = R(20),
		RightHip = R(30), RightKnee = R(-40), LeftHip = R(40), LeftKnee = R(-90) }, 0.15, "out")
	at(1.46)
	ctx.pose({ Root = T(0, -0.15, 0), Waist = R(0, -15, 0), RightShoulder = R(80, 0, 75), RightElbow = R(0), LeftShoulder = R(20, 0, -20), LeftElbow = R(40), RightHip = R(10), LeftHip = R(-5) }, 0.06, "snap")
	local w = ctx.weapon()
	Fx.Particles(w and w.Position or ctx.myPos() + right * 2, { color = AQUA, count = 14, speed = 14, size = 0.25, lifetime = 0.45, spread = 50, gravity = 30, light = 0.5 })
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.myPos() + right), FOAM, 2, 70, 0.18, 0.25, 0)
	Fx.Particles(ctx.ground() + UP * 0.4, { color = SKY, count = 10, speed = 3, size = 1.2, lifetime = 0.6, spread = 90, gravity = -1, light = 0.2 })
	for _, pd in puddles do Fx.Tween(pd, 0.3, { Transparency = 1 }) end; Fx.Light(ctx.targetPos(), SKY, 12, 3, 0.45)
	at(1.54)
	ctx.pose(P.guard, 0.2)
end
