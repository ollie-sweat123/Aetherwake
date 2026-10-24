-- Pip Sprout :: Sproutling Haymaker (impact 0.75s, total 1.40s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(1, 1, 1)
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP = 0.75
	local hand, head, lt = ctx.part("RightHand"), ctx.part("Head"), ctx.part("LowerTorso")
	ctx.callout()

	-- props: head-leaf propeller, 3 leaves orbiting the waist, a leafy ball wrapping the fist
	local function leaf(c, s, tr) return Fx.Part({ Shape = Enum.PartType.Wedge, Size = s or Vector3.new(0.12, 0.45, 0.9), Color = c, Transparency = tr or 0 }) end
	local prop = { leaf(C1, Vector3.new(0.1, 0.3, 1.3)), leaf(C2, Vector3.new(0.1, 0.3, 1.3)) }
	local orbit = { leaf(C1), leaf(C2), leaf(C1) }
	local wrap = { leaf(C1, nil, 1), leaf(C3, nil, 1), leaf(C2, nil, 1), leaf(C3, nil, 1) }
	local fist = Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, Color = C1, Transparency = 1 })
	task.spawn(function()
		local spin, orb, last = 0, 0, 0
		while el() < 1.36 do
			local t = el(); local dt = t - last; last = t
			spin += dt * (t < 0.65 and 2400 or 0) -- 720 deg in the first 0.3s, then keeps lifting
			orb += dt * (t < 0.3 and 4 or (t < 0.85 and 10 or 6))
			local wig = t >= 0.65 and math.sin(t * 28) * 35 or 0
			if head and head.Parent then
				local top = head.CFrame * CFrame.new(0, 1.05, 0)
				for i, p in prop do p.CFrame = top * CFrame.Angles(0, math.rad(spin + wig + i * 180), 0) * CFrame.new(0, 0, -0.6) * CFrame.Angles(math.rad(-12), 0, 0) end
			end
			local c = lt and lt.Position or ctx.myPos()
			for i, p in orbit do
				local a = orb + i * 2.09
				p.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 2, math.sin(t * 7 + i) * 0.35, math.sin(a) * 2)) * CFrame.Angles(0, -a, math.rad(25))
			end
			if hand and hand.Parent then
				local hp, k = hand.Position, math.clamp((t - 0.3) / 0.35, 0, 1)
				fist.CFrame = CFrame.new(hp)
				for i, p in wrap do
					local a, r = t * 12 + i * 1.57, 2.6 - 1.6 * k
					p.CFrame = CFrame.lookAt(hp + Vector3.new(math.cos(a) * r, math.sin(a * 0.8) * r * 0.5, math.sin(a) * r), hp)
				end
			end
			ctx.wait(0)
		end
		for _, p in { prop[1], prop[2], fist, orbit[1], orbit[2], orbit[3], wrap[1], wrap[2], wrap[3], wrap[4] } do fade(p, 0.15, { Size = Vector3.one * 0.05 }) end
	end)

	-- the hit: white cartoon star, leaf + petal burst, ring on the enemy's front face
	task.delay(IMP - 0.02, function()
		local tp = ctx.targetPos()
		local hit = tp - f * 1.3
		ctx.impact()
		local face = CFrame.lookAt(hit, hit + f)
		Fx.Burst(hit, C4, 4, 0.3, { startSize = 0.1 })
		Fx.Light(hit, C3, 14, 4, 0.35)
		for i = 0, 3 do
			local ray = Fx.Part({ Size = Vector3.new(0.3, 0.3, 0.2), Color = i % 2 == 0 and C4 or C3, CFrame = face * CFrame.Angles(0, 0, math.rad(i * 45)) })
			Fx.Tween(ray, 0.1, { Size = Vector3.new(5.5, 0.4, 0.2) }, Enum.EasingStyle.Back)
			task.delay(0.1, function() fade(ray, 0.2, { Size = Vector3.new(6.5, 0.05, 0.1) }) end)
		end
		Fx.Ring(face * CFrame.Angles(math.rad(90), 0, 0), C1, 1, 6, 0.35, 0.25)
		Fx.Particles(hit, { color = C1, count = 12, speed = 18, size = 0.5, lifetime = 0.6, gravity = 12 })
		Fx.Particles(hit, { color = C2, count = 6, speed = 14, size = 0.45, lifetime = 0.6, gravity = 12 })
		Fx.Particles(hit, { color = C3, count = 14, speed = 22, size = 0.35, lifetime = 0.5, gravity = 6, light = 1 })
		if ctx.target then Fx.HitFlash(ctx.target, C4, 0.1) end
		ctx.shake(0.2, 0.25)
	end)

	-- 0.00 crouch, fists to the hips, propeller leaf spins up, sparkles rise from the feet
	Fx.Light(ctx.myPos(), C1, 12, 2, 1.35)
	Fx.Particles(ctx.ground() + UP * 0.2, { color = C3, count = 12, speed = 5, size = 0.3, lifetime = 0.7, spread = 35, gravity = -6, light = 1 })
	ctx.pose({ Root = T(0, -0.7, 0, -8), Waist = R(-12), Neck = R(-20), RightHip = R(55), LeftHip = R(55), RightKnee = R(-85), LeftKnee = R(-85), RightAnkle = R(25), LeftAnkle = R(25),
		RightShoulder = R(-25, 0, 15), RightElbow = R(75), LeftShoulder = R(-25, 0, -15), LeftElbow = R(75) }, to(0.3))

	-- 0.30 propeller hop: right arm windmills twice while the leaf ball grows round the fist
	for _, p in wrap do p.Transparency = 0 end
	fist.Size, fist.Transparency = Vector3.one, 0.3
	Fx.Tween(fist, 0.35, { Size = Vector3.one * 2.2 }, Enum.EasingStyle.Back)
	Fx.Trail(hand, C1, 0.55, 0.5); Fx.Trail(hand, C3, 0.55, 0.22)
	task.spawn(ctx.moveTo, start + UP * 2.5, 0.33)
	for i = 1, 8 do
		local kick = i % 2 == 0
		ctx.pose({ Root = T(0, 0.2, 0), Neck = R(10), Waist = R(5, -10, 0), RightShoulder = R(90 * i + 20, 0, 15), RightElbow = R(10), LeftShoulder = R(10, 0, -85), LeftElbow = R(10),
			RightHip = R(kick and 45 or 10), RightKnee = R(-55), LeftHip = R(kick and 5 or 40), LeftKnee = R(-45) }, to(0.3 + 0.35 * i / 8), "linear")
	end

	-- 0.65 dive in with the haymaker
	local reach = math.clamp(((ctx.targetPos() - start) * Vector3.new(1, 0, 1)).Magnitude - 2.8, 1, 4)
	local from = hand and hand.Position or ctx.myPos()
	task.spawn(ctx.moveTo, start + f * reach, 0.1)
	ctx.pose({ Root = T(0, -0.2, -0.8, -15), Waist = R(-10, 35, 0), Neck = R(5), RightShoulder = R(95, 0, 5), RightElbow = R(0), LeftShoulder = R(-40, 0, -40), LeftElbow = R(20),
		RightHip = R(-30), RightKnee = R(-20), LeftHip = R(40), LeftKnee = R(-50) }, to(0.73), "snap")
	if hand then Fx.Beam(from, hand.Position, C1, 0.7, 0.18); Fx.Beam(from, hand.Position, C3, 0.3, 0.12) end

	-- 0.85 bounce back onto its bottom, spring up, proud hands-on-hips with a leaf wiggle
	at(0.85)
	Fx.Tween(fist, 0.2, { Size = Vector3.one * 0.1, Transparency = 1 })
	for _, p in wrap do Fx.Tween(p, 0.2, { Transparency = 1 }) end
	for _, p in orbit do Fx.Tween(p, 0.45, { Size = Vector3.one * 0.05 }) end
	task.spawn(ctx.moveTo, start, 0.15, 1.2)
	ctx.pose({ Root = T(0, -1.6, 0, 12), Waist = R(5), Neck = R(10, 0, 10), RightHip = R(85), LeftHip = R(85), RightKnee = R(-15), LeftKnee = R(-15),
		RightShoulder = R(-30, 0, 30), LeftShoulder = R(-30, 0, -30), RightElbow = R(10), LeftElbow = R(10) }, to(1.0), "out")
	Fx.Particles(ctx.ground() + UP * 0.3, { color = "#d8cbb0", count = 8, speed = 6, size = 0.5, lifetime = 0.4, spread = 70 })
	task.spawn(ctx.moveTo, start, 0.1, 0.8)
	ctx.pose(P.jump, to(1.1), "back")
	local proud = table.clone(P.handsOnHips); proud.Root = T(0, 0.05, 0)
	ctx.pose(proud, to(1.2), "back")
	Fx.Particles((head and head.Position or ctx.myPos()) + UP * 1.2, { color = C3, count = 14, speed = 4, size = 0.3, lifetime = 0.6, light = 1 })
	proud.Neck = R(12, 0, 12); ctx.pose(proud, to(1.26), "inout")
	proud.Neck = R(12, 0, -12); ctx.pose(proud, to(1.32), "inout")
	ctx.pose(P.guard, 0.2)
end