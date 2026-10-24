-- Gearling :: Overclock Whirl (impact 0.80s, total 1.40s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or Color3.new(0.6, 0.7, 0.8), C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	task.delay(1.8, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side = f:Cross(UP).Unit
	local IMP, head, torso, rh, w = 0.8, ctx.part("Head"), ctx.part("UpperTorso"), ctx.part("RightHand"), ctx.weapon()
	local WHITE, STEAM = Color3.new(1, 1, 1), Color3.new(0.92, 0.94, 0.97)
	local tp0 = ctx.targetPos()
	local dashEnd = start + f * math.max(0, (Vector3.new(tp0.X, start.Y, tp0.Z) - start).Magnitude - 2.6)
	local function wtip()
		local h = rh and rh.Position or ctx.myPos() + f
		if not w then return h end
		local s = w.Size
		local ax = (s.X >= s.Y and s.X >= s.Z) and Vector3.new(s.X / 2, 0, 0) or (s.Y >= s.Z and Vector3.new(0, s.Y / 2, 0) or Vector3.new(0, 0, s.Z / 2))
		local a, b = w.CFrame * ax, w.CFrame * -ax
		return (a - h).Magnitude > (b - h).Magnitude and a or b
	end
	-- clockwork gear = flat neon cylinder (axle on its X axis) + block teeth around the rim
	local function gear(r, th, n, ts, col, tcol, mat)
		local g = { r = r, th = th, n = n, ts = ts, disc = mk({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(th, r * 2, r * 2), Color = col, Transparency = 1 }), teeth = {} }
		for i = 1, n do g.teeth[i] = mk({ Size = Vector3.new(th, ts, ts), Color = tcol, Material = mat or Enum.Material.Neon, Transparency = 1 }) end
		return g
	end
	local function place(g, cf, ang, s, tr)
		s = math.max(s, 0.01)
		g.disc.Size = Vector3.new(g.th, g.r * 2 * s, g.r * 2 * s); g.disc.CFrame = cf * CFrame.Angles(ang, 0, 0); g.disc.Transparency = tr
		for i, p in g.teeth do
			p.Size = Vector3.new(g.th, g.ts * s, g.ts * s); p.Transparency = tr
			p.CFrame = cf * CFrame.Angles(ang + i * 2 * math.pi / g.n, 0, 0) * CFrame.new(0, g.r * s, 0)
		end
	end
	local g1, g2 = gear(1, 0.22, 8, 0.38, C1, C1), gear(0.7, 0.22, 8, 0.3, C2, C2)
	local big = gear(2.5, 0.4, 10, 0.7, C2, C3, Enum.Material.Metal)
	local dz = { gear(0.22, 0.08, 4, 0.14, C2, C2), gear(0.22, 0.08, 4, 0.14, C2, C2), gear(0.22, 0.08, 4, 0.14, C2, C2) }
	local ant = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, Color = C4, CFrame = CFrame.new(start) })
	local al = Instance.new("PointLight"); al.Color = C4; al.Range = 10; al.Brightness = 3; al.Parent = ant
	ctx.callout()

	task.spawn(function()
		local last, ang, bang, fx, from = 0, 0, 0, 0, nil
		while el() < 1.42 do
			local t = el(); local dt = t - last; last = t
			local tc = torso and torso.CFrame or ctx.root.CFrame
			-- back gears: wind faster with every crank, double speed in the spin, wind down and shrink away
			local spd = t < 0.35 and 6 + math.min(3, math.floor(t / 0.115) + 1) * 8 or (t < 0.9 and 55 or 55 * math.max(0, 1 - (t - 0.9) / 0.4))
			ang += spd * dt
			local s = math.min(1, t / 0.1) * math.clamp(1 - (t - 0.9) / 0.4, 0, 1)
			place(g1, tc * CFrame.new(-0.4, 0.25, 0.62) * CFrame.Angles(0, math.pi / 2, 0), ang, s, s < 0.03 and 1 or 0)
			place(g2, tc * CFrame.new(0.6, -0.4, 0.7) * CFrame.Angles(0, math.pi / 2, 0), -ang * 1.43 + 0.3, s, s < 0.03 and 1 or 0)
			local tip = ((head and head.CFrame or tc * CFrame.new(0, 1.5, 0)) * CFrame.new(0, 1.3, 0)).Position
			ant.CFrame = CFrame.new(tip); ant.Transparency = t < 1.3 and 0 or 1; al.Brightness = t < 1.3 and 2 + math.random() * 3 or 0
			-- the big brass gear wheel: whirs out of the wrench, grinds the target, pops off and rolls away
			if t >= IMP then
				from = from or wtip()
				local tp = ctx.targetPos()
				local contact = tp - f * 1.1
				local k, pos, sc = math.min(1, (t - IMP) / 0.06), contact, 1
				if t < IMP + 0.06 then pos, sc = from:Lerp(contact, k), 0.15 + 0.85 * k
				elseif t > 1.05 then local r = t - 1.05; local k2 = math.min(1, r / 0.3)
					pos = contact + side * 9 * r + UP * (math.sin(k2 * math.pi) * 1.5 - (contact.Y - ctx.targetGround().Y - 2.5) * k2)
				end
				bang += (t < 1.05 and 40 or -9 / 2.5) * dt
				place(big, CFrame.fromMatrix(pos, f, UP), bang, sc, math.clamp((t - 1.1) / 0.3, 0, 1))
			end
			-- three tiny dizzy gears circling the head
			for i, g in dz do
				local a = t * 7 + i * 2.09
				local c = tip - UP * 0.4 + Vector3.new(math.cos(a), math.sin(t * 6 + i) * 0.15, math.sin(a)) * 1.1
				local ds = t < 0.9 and 0 or math.min(1, (t - 0.9) / 0.08) * math.clamp((1.4 - t) / 0.08, 0, 1)
				place(g, CFrame.new(c) * CFrame.Angles(0, a, 0), t * 12, ds, ds < 0.03 and 1 or 0)
			end
			if t - fx > 0.04 then fx = t
				local back = (tc * CFrame.new(0, 0.2, 1)).Position
				if t < 0.75 then Fx.Particles(back, { color = STEAM, count = t < 0.35 and 1 or 2, speed = 3, size = 1.2, lifetime = 0.6, gravity = -4, spread = 35, light = 0 }) end
				if t > 0.35 and t < 0.75 then Fx.Particles(ctx.ground() + UP * 0.2, { color = C1, count = 3, speed = 10, size = 0.25, lifetime = 0.3, gravity = 40, spread = 70, light = 1 }) end
				if t > IMP and t < 1.05 then Fx.Particles(ctx.targetPos() - f * 1.2, { color = C1, count = 4, speed = 18, size = 0.22, lifetime = 0.35, gravity = 35, spread = 45, light = 1 }) end
			end
			ctx.wait(0)
		end
	end)

	-- 0.80 IMPACT: big clang
	task.delay(math.max(0, IMP - 0.02 - el()), function()
		local tp = ctx.targetPos()
		ctx.impact()
		Fx.Ring(CFrame.lookAt(tp - f * 0.8, tp - f * 1.8) * CFrame.Angles(-math.pi / 2, 0, 0), WHITE, 2, 6, 0.25, 0.25)
		Fx.Particles(tp - f, { color = C1, count = 30, speed = 24, size = 0.3, lifetime = 0.5, gravity = 35, spread = 50, light = 1 })
		Fx.Particles(tp, { color = C4, count = 10, speed = 14, size = 0.35, lifetime = 0.7, gravity = 45, light = 0.5 })
		Fx.Burst(tp - f * 0.5, C2, 4, 0.2, { startSize = 0.6 }); Fx.Light(tp, C1, 16, 5, 0.35)
		Fx.HitFlash(ctx.target, C2, 0.25); ctx.flash(C2, 0.25, 0.15); ctx.shake(0.25, 0.3)
	end)
	task.delay(1.0, function() Fx.Particles(ant.Position, { color = STEAM, count = 6, speed = 3, size = 0.8, lifetime = 0.6, gravity = -3, spread = 30, light = 0 }) end)

	-- 0.00 wind-up: reaches behind its back and cranks the wrench 3 times, knees bobbing
	for i = 1, 3 do
		local crank = { RightShoulder = R(-75, 0, 30), RightElbow = R(110), RightWrist = R(0, i % 2 == 1 and 60 or -60, 0), LeftShoulder = R(0, 0, -35), LeftElbow = R(110),
			Waist = R(5, 15, 0), Neck = R(-5, -20, 0), Root = T(0, -0.25, 0), RightKnee = R(-30), LeftKnee = R(-30), RightHip = R(20), LeftHip = R(20) }
		ctx.pose(crank, to(i * 0.115 - 0.055), "out")
		crank.RightWrist, crank.Root, crank.RightKnee, crank.LeftKnee, crank.RightHip, crank.LeftHip = R(0, i % 2 == 1 and -60 or 60, 0), T(0, 0, 0), R(-5), R(-5), R(5), R(5)
		ctx.pose(crank, to(i * 0.115), "back")
		local tc = torso and torso.CFrame or ctx.root.CFrame
		local bp = (tc * CFrame.new(0, 0, 0.8)).Position
		Fx.Ring(CFrame.lookAt(bp, bp + tc.LookVector) * CFrame.Angles(-math.pi / 2, 0, 0), WHITE, 0.4, 1.8, 0.12, 0.08)
		Fx.Particles(bp, { color = STEAM, count = 4, speed = 4, size = 0.9, lifetime = 0.5, gravity = -4, spread = 40, light = 0 })
	end
	-- 0.35 spins like a top (3 full turns) while skittering at the enemy, wrench held straight out
	task.spawn(ctx.moveTo, dashEnd, 0.4)
	Fx.Trail(w or rh, C1, 0.45, 0.5)
	for i = 1, 9 do
		local wob = i % 2 == 0 and 10 or -10
		ctx.pose({ Root = T(0, -0.15 + (i % 2) * 0.1, 0, 0, -120 * i, 0), RightShoulder = R(0, 0, 90), RightElbow = R(0), LeftShoulder = R(0, 0, -80), LeftElbow = R(10),
			Neck = R(0, 0, wob), Waist = R(0, 0, -wob * 0.4), RightKnee = R(-20), LeftKnee = R(-20), RightHip = R(10), LeftHip = R(10) }, to(0.35 + i * 0.042), "linear")
	end
	-- 0.73 final clang: winds the waist and whips a sideways wrench smash, skidding to a stop
	ctx.pose({ Root = T(0, -0.35, 0.15), Waist = R(-5, 45, 0), RightShoulder = R(40, 0, 100), RightElbow = R(10), LeftShoulder = R(20, 0, -50), LeftElbow = R(40), Neck = R(0, -20, 0),
		LeftHip = R(35), LeftKnee = R(-40), RightHip = R(-25), RightKnee = R(-20) }, to(0.77), "out")
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.targetPos()) * CFrame.new(0, 0.6, -0.5), C1, 3, 120, 0.2, 0.5, -8)
	ctx.pose({ Root = T(0, -0.4, -0.2), Waist = R(-10, -60, 0), RightShoulder = R(85, -20, 30), RightElbow = R(0), LeftShoulder = R(-10, 0, -60), LeftElbow = R(30), Neck = R(0, 25, 0),
		LeftHip = R(40), LeftKnee = R(-45), RightHip = R(-30), RightKnee = R(-25), RightAnkle = R(20) }, to(0.84), "snap")
	Fx.Particles(ctx.ground() + UP * 0.3, { color = C3, count = 10, speed = 8, size = 0.5, lifetime = 0.4, spread = 80, light = 0.2 })
	-- 0.90 dizzy daze: staggers half a stud, head rolling in a circle twice, wrench drooping
	task.spawn(ctx.moveTo, ctx.myPos() - f * 0.5, 0.25)
	for i = 1, 8 do
		local a = i * math.pi / 2
		ctx.pose({ Neck = R(15 * math.cos(a), 0, 15 * math.sin(a)), Waist = R(0, 0, -6 * math.sin(a)), Root = T(0, -0.1, 0, 0, 0, 4 * math.sin(a)),
			RightShoulder = R(-10, 0, 8), RightElbow = R(10), LeftShoulder = R(10, 0, -25), LeftElbow = R(20), RightKnee = R(-15), LeftKnee = R(-10), LeftHip = R(8) }, to(0.9 + i * 0.0525), "inout")
	end
	ctx.pose(P.guard, 0.2)
end
