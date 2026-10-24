-- Sage Willow :: Ancient Grove Verdict (impact 1.25s, total 1.95s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(1, 1, 1)
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local function seg(a, b, w) local d = b - a; if d.Magnitude < 0.02 then b = a + UP * 0.02; d = b - a end
		return { Size = Vector3.new(d.Magnitude, w, w), CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0) } end
	local function line(p, a, b, w) local s = seg(a, b, w); p.Size, p.CFrame = s.Size, s.CFrame end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP, hand = 1.25, ctx.part("RightHand")
	local w = ctx.weapon(); if w then w.LocalTransparencyModifier = 1; task.delay(2.1, function() w.LocalTransparencyModifier = 0 end) end
	ctx.callout()

	-- conjured spirit staff, willow branches (3 segments + leaf tip each), glyph circle of 2 dashed rings + 6 runes
	local staff = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = C4, Material = Enum.Material.Wood })
	local orb = Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Color = C1 })
	local gc = ctx.targetGround() + UP * 0.15
	local base = ctx.ground() - f * 2.8
	local top = base + UP * 10
	local branches, tips, rings, runes = {}, {}, {}, {}
	for i = 1, 6 do
		branches[i] = { Fx.Part({ Color = C1, Transparency = 1 }), Fx.Part({ Color = C1, Transparency = 1 }), Fx.Part({ Color = C2, Transparency = 1 }) }
		tips[i] = Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, Color = C2, Transparency = 1 })
	end
	for i = 1, 28 do rings[i] = Fx.Part({ Color = i <= 14 and C1 or C4, Transparency = 1 }) end
	for i = 1, 6 do runes[i] = Fx.Part({ Size = Vector3.new(0.35, 0.6, 0.1), Color = C4, Transparency = 1 }) end
	task.spawn(function()
		local spin, last, leafT = 0, 0, 0
		while el() < 1.9 do
			local t = el(); spin += (t - last) * (t < 0.8 and 1.2 or (t < 1.35 and 4.5 or 2)); last = t
			local tp = ctx.targetPos()
			if hand and hand.Parent then
				local hp, u = hand.Position, hand.CFrame.UpVector
				line(staff, hp + u * 1.2, hp - u * 4, 0.3); orb.CFrame = CFrame.new(hp - u * 4.25)
			end
			local gA = math.clamp((t - 0.35) / 0.3, 0, 1)
			local sc = (t < 0.8 and 1 or math.max(0.6, 1 - (t - 0.8) * 1.1)) * (t < 1.35 and 1 or math.max(0, 1 - (t - 1.35) / 0.4))
			for i, p in rings do
				local outer = i <= 14
				local r = (outer and 3.4 or 2.4) * sc
				p.Size = Vector3.new(math.max(r * 0.32, 0.05), 0.12, 0.2)
				p.CFrame = CFrame.new(gc) * CFrame.Angles(0, (outer and spin or -spin) + (i % 14) * math.pi / 7, 0) * CFrame.new(0, 0, -r)
				p.Transparency = 1 - gA * 0.9
			end
			for i, p in runes do
				local a = spin * 1.6 + i * 1.047
				local pos = gc + Vector3.new(math.cos(a) * 2.9 * sc, 0.6 + math.sin(t * 5 + i) * 0.2, math.sin(a) * 2.9 * sc)
				if t > IMP then pos = pos:Lerp(tp, math.clamp((t - IMP) / 0.12, 0, 1)) end
				p.CFrame = CFrame.lookAt(pos, gc + UP * 0.6 + f * 0.01); p.Transparency = t > IMP + 0.12 and 1 or 1 - gA
			end
			local g = math.clamp((t - 0.45) / 0.3, 0, 1)
			local wk = 1 - (1 - math.clamp((t - 0.8) / 0.22, 0, 1)) ^ 3
			local bf = 1 - math.clamp((t - 1.35) / 0.35, 0, 1)
			for i, sgs in branches do
				local d = CFrame.Angles(0, i * 1.047, 0) * f
				local wa = i * 1.047 + t * 3
				local wrapEnd = tp + Vector3.new(math.cos(wa) * 1.7, (i - 3.5) * 0.45, math.sin(wa) * 1.7)
				local p1 = (top + d * 2 * g + UP * 0.6 * g):Lerp(top:Lerp(tp, 0.3) + UP * 1.5, wk)
				local p2 = (top + d * 3.5 * g - UP * 0.6 * g):Lerp(top:Lerp(tp, 0.65) + UP * 1 + d, wk)
				local p3 = (top + d * 4.2 * g - UP * 2.6 * g):Lerp(wrapEnd, wk)
				line(sgs[1], top, p1, 0.22); line(sgs[2], p1, p2, 0.16); line(sgs[3], p2, p3, 0.1)
				for _, s in sgs do s.Transparency = 1 - g * bf * 0.95 end
				tips[i].CFrame = CFrame.new(p3); tips[i].Transparency = 1 - g * bf
			end
			if t - leafT > 0.08 and g > 0 and bf > 0 then leafT = t
				Fx.Particles(tips[math.random(1, 6)].Position, { color = math.random() < 0.5 and C2 or C1, count = 2, speed = 1.5, size = 0.35, lifetime = 0.8, gravity = 4, light = 1 })
			end
			ctx.wait(0)
		end
		for _, p in { staff, orb, table.unpack(rings) } do fade(p, 0.12) end
		for i = 1, 6 do fade(tips[i], 0.12); fade(runes[i], 0.12); for _, s in branches[i] do fade(s, 0.12) end end
	end)

	-- the verdict: a teal pillar erupts through the glyph onto the single foe
	task.delay(IMP - 0.02, function()
		local tp = ctx.targetPos()
		ctx.impact()
		local up90 = CFrame.Angles(0, 0, math.pi / 2)
		local pil = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = C1, Size = Vector3.new(0.2, 2.5, 2.5), CFrame = CFrame.new(gc) * up90 })
		Fx.Tween(pil, 0.12, { Size = Vector3.new(14, 2.5, 2.5), CFrame = CFrame.new(gc + UP * 7) * up90 })
		task.delay(0.14, function() fade(pil, 0.45, { Size = Vector3.new(14, 0.1, 0.1) }) end)
		Fx.Pillar(gc, C3, 16, 0.6, 0.5); Fx.Burst(tp, C2, 6, 0.35); Fx.Shockwave(gc, C1, 5, 0.5)
		Fx.Particles(tp, { color = C4, count = 30, speed = 26, size = 0.45, lifetime = 0.6, gravity = 10, light = 1 })
		Fx.Light(tp, C1, 20, 5, 0.5)
		ctx.flash(C3, 0.7, 0.3); ctx.shake(0.55, 0.4)
	end)

	-- 0.00 sweep the staff up into a rooted stance: glowing roots spread, leaves swirl
	Fx.Light(ctx.myPos(), C1, 18, 3, 1.95)
	local roots = {}
	for i = 1, 4 do
		local d, g0 = CFrame.Angles(0, math.rad(45 + i * 90), 0) * f, ctx.ground() + UP * 0.1
		for k = 1, 2 do
			local a, b = g0 + d * (k - 1) * 2, g0 + (CFrame.Angles(0, (k - 1.5) * 0.5, 0) * d) * k * 2
			local r = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = k == 1 and C1 or C2 })
			line(r, a, a + (b - a) * 0.05, 0.25 - k * 0.07); task.delay((k - 1) * 0.12, function() Fx.Tween(r, 0.15, seg(a, b, 0.25 - k * 0.07)) end)
			table.insert(roots, r)
		end
	end
	for k = 0, 2 do task.delay(k * 0.12, function() local c = ctx.myPos()
		for j = 1, 4 do local a = j * 1.57 + k
			Fx.Particles(c + Vector3.new(math.cos(a) * 1.6, -2, math.sin(a) * 1.6), { color = j % 2 == 0 and C1 or C2, count = 3, speed = 6, size = 0.35, lifetime = 0.6, spread = 20, gravity = -4, light = 1 })
		end end) end
	ctx.pose({ RightShoulder = R(90, 0, 45), RightElbow = R(20), LeftShoulder = R(60, 0, -30), LeftElbow = R(30), Waist = R(0, 15, 0), Root = T(0, -0.2, 0) }, to(0.17), "inout")
	local raise = { RightShoulder = R(170, 0, 8), RightElbow = R(10), LeftShoulder = R(165, 0, -8), LeftElbow = R(25), Neck = R(20), Waist = R(8), Root = T(0, -0.35, 0),
		RightHip = R(0, 0, 12), LeftHip = R(0, 0, -12), RightKnee = R(-20), LeftKnee = R(-20) }
	ctx.pose(raise, to(0.35), "out")
	-- 0.35 hold high: a willow of light grows behind, the glyph opens under the enemy
	local up90 = CFrame.Angles(0, 0, math.pi / 2)
	local trunk = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = C2, Material = Enum.Material.Glass, Transparency = 0.35, Size = Vector3.new(0.1, 1.6, 1.6), CFrame = CFrame.new(base) * up90 })
	local core = Fx.Part({ Shape = Enum.PartType.Cylinder, Color = C1, Size = Vector3.new(0.1, 0.6, 0.6), CFrame = CFrame.new(base) * up90 })
	for _, p in { trunk, core } do Fx.Tween(p, 0.3, { Size = Vector3.new(10, p.Size.Y, p.Size.Z), CFrame = CFrame.new(base + UP * 5) * up90 }, Enum.EasingStyle.Back) end
	raise.Neck = R(5); ctx.pose(raise, to(0.8), "inout")
	-- 0.80 point the staff: branches lash forward and bind the target
	if ctx.target then Fx.HitFlash(ctx.target, C1, 0.5) end
	for _, tip in tips do Fx.Trail(tip, C2, 0.45, 0.2) end
	ctx.pose({ RightShoulder = R(95, 0, 0), RightElbow = R(0), LeftShoulder = R(-35, 0, -45), LeftElbow = R(15), LeftWrist = R(-40), Waist = R(-8, 15, 0), Root = T(0, -0.3, -0.2),
		RightHip = R(-10, 0, 10), LeftHip = R(15, 0, -10), RightKnee = R(-15), LeftKnee = R(-25) }, to(0.95), "back")
	at(1.15)
	-- 1.15 slam the staff butt down with both hands, crouching low
	ctx.pose({ RightShoulder = R(45, 0, -20), RightElbow = R(15), LeftShoulder = R(50, 0, 20), LeftElbow = R(15), Waist = R(-20), Neck = R(-5), Root = T(0, -0.9, 0, -8),
		RightHip = R(60, 0, 8), LeftHip = R(60, 0, -8), RightKnee = R(-85), LeftKnee = R(-85), RightAnkle = R(25), LeftAnkle = R(25) }, to(1.24), "snap")
	at(1.35)
	-- 1.35 the tree dissolves into falling leaves, roots sink; straighten and smooth a sleeve
	for k = 0, 4 do Fx.Particles(base + UP * (2 + k * 2), { color = k % 2 == 0 and C2 or C1, count = 10, speed = 4, size = 0.4, lifetime = 0.9, gravity = 6, light = 1 }) end
	for _, tip in tips do Fx.Particles(tip.Position, { color = C2, count = 4, speed = 2, size = 0.35, lifetime = 0.8, gravity = 6, light = 1 }) end
	fade(trunk, 0.5, { Size = Vector3.new(10, 0.2, 0.2) }); fade(core, 0.4)
	for _, r in roots do fade(r, 0.45, { CFrame = r.CFrame - UP * 0.5 }) end
	local stand = { RightShoulder = R(25, 0, 10), RightElbow = R(125), LeftShoulder = R(55, 0, 30), LeftElbow = R(105), Neck = R(-5), Waist = R(0, 5, 0), Root = T(0, -0.1, 0) }
	ctx.pose(stand, to(1.6), "inout")
	stand.LeftShoulder, stand.LeftElbow = R(45, 0, 25), R(75); ctx.pose(stand, to(1.86), "inout")
	ctx.pose(P.guard, 0.2)
end