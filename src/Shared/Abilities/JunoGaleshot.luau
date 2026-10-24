-- Juno Galeshot: Skylark Cyclone Arrow (impact 1.35s, total 2.20s). Her bow is in the LEFT hand, so the right hand draws.
return function(ctx)
	local Fx, P, R, T = ctx.Fx, ctx.P, ctx.R, ctx.T
	local GREEN, MINT, WHITE, TEAL = ctx.palette[1] or ctx.accent, ctx.palette[2] or ctx.accent, ctx.palette[3] or Color3.new(1, 1, 1), ctx.palette[4] or ctx.accent
	local IMPACT, UP, CYL, BALL, WEDGE = 1.35, Vector3.yAxis, Enum.PartType.Cylinder, Enum.PartType.Ball, Enum.PartType.Wedge
	local t0, start = os.clock(), ctx.myPos()
	local function at(t) local d = t - (os.clock() - t0); if d > 0 then ctx.wait(d) end end
	local function flat(v) return Vector3.new(v.X, 0, v.Z) end
	local function dir() local d = flat(ctx.targetPos() - ctx.myPos()); return d.Magnitude > 0.05 and d.Unit or flat(ctx.root.CFrame.LookVector).Unit end
	local function mk(props, life) local p = Fx.Part(props); task.delay(life, function() p:Destroy() end); return p end
	local function faceCF(pos, d) return CFrame.lookAt(pos, pos + d) * CFrame.Angles(-math.pi / 2, 0, 0) end -- UpVector = d
	local function bow() local h = ctx.part("LeftHand"); return h and h.Position or ctx.myPos() + dir() * 1.5 end
	-- time-bounded per-frame helpers: run = background updater (fn returns true to stop), drive = procedural pose (yields)
	local function run(dur, fn) task.spawn(function() local s = os.clock(); while os.clock() - s < dur and not fn((os.clock() - s) / dur, os.clock() - s) do ctx.wait(0) end end) end
	local function drive(dur, fn) local s = os.clock(); while os.clock() - s < dur do ctx.pose(fn((os.clock() - s) / dur), 0); ctx.wait(0) end end
	-- 0.00 goggle snap: lens flash, two mint rings circle up her legs, leaves kick up, bouncy crouch
	ctx.callout()
	ctx.pose({ Root = T(0, -0.35, 0), Neck = R(12), RightShoulder = R(150, 0, 10), RightElbow = R(120), LeftShoulder = R(30, 0, -15), LeftElbow = R(40),
		RightHip = R(25), LeftHip = R(25), RightKnee = R(-35), LeftKnee = R(-35) }, 0.12, "snap")
	local head = ctx.part("Head")
	Fx.Burst(head and head.Position + head.CFrame.LookVector * 0.6 or ctx.myPos() + UP * 1.6, GREEN, 1.4, 0.2); Fx.HitFlash(ctx.model, GREEN, 0.2)
	Fx.Particles(ctx.ground() + UP * 0.3, { color = GREEN, count = 12, speed = 6, size = 0.35, lifetime = 0.5, spread = 60, gravity = 6, light = 0.3 })
	for i = 0, 1 do
		local r = mk({ Shape = CYL, Size = Vector3.new(0.08, 3, 3), Color = i == 0 and MINT or WHITE }, 0.45)
		run(0.32, function(k) r.CFrame = CFrame.new(ctx.ground() + UP * (0.2 + k * 3 + i * 0.6)) * CFrame.Angles(0, k * 12 + i * math.pi, 0.3) * CFrame.Angles(0, 0, math.pi / 2); r.Transparency = 0.3 + 0.7 * k end)
	end
	at(0.18)
	ctx.pose({ Root = T(0, -0.55, 0, -6), Neck = R(10), RightShoulder = R(40, 0, 20), RightElbow = R(60), LeftShoulder = R(30, 0, -15), LeftElbow = R(50),
		RightHip = R(45), LeftHip = R(45), RightKnee = R(-70), LeftKnee = R(-70), RightAnkle = R(20), LeftAnkle = R(20) }, 0.1, "out")
	-- 0.30 updraft leap 7 studs up and back with a full backflip (Root pitch 360) over a spiral of four rising rings
	at(0.3)
	local d, g0 = dir(), ctx.ground()
	local apex = start + UP * 7 - d * 1.5
	Fx.Particles(g0 + UP * 0.4, { color = Color3.fromRGB(200, 190, 160), count = 16, speed = 12, size = 0.8, lifetime = 0.45, spread = 85, light = 0 }); Fx.Shockwave(g0, MINT, 3, 0.4)
	Fx.Trail(ctx.part("LeftFoot"), WHITE, 0.45, 0.3); Fx.Trail(ctx.part("RightFoot"), MINT, 0.45, 0.3)
	for i = 1, 4 do
		local r, sp = mk({ Shape = CYL, Size = Vector3.new(0.1, 4.5 - i * 0.6, 4.5 - i * 0.6), Color = i % 2 == 0 and WHITE or MINT }, 0.6), i % 2 == 0 and 20 or -20
		run(0.5, function(k) r.CFrame = CFrame.new(g0 + UP * (i * 1.2 + k * 4.5) - d * 1.5 * k) * CFrame.Angles(0, k * sp, 0.2) * CFrame.Angles(0, 0, math.pi / 2); r.Transparency = 0.25 + 0.75 * k end)
	end
	task.spawn(ctx.moveTo, apex, 0.33)
	local tuck = { RightHip = R(80), LeftHip = R(80), RightKnee = R(-110), LeftKnee = R(-110), Waist = R(-15), Neck = R(-10), RightShoulder = R(40, 0, 10), RightElbow = R(90), LeftShoulder = R(40, 0, -10), LeftElbow = R(90) }
	drive(0.33, function(k) tuck.Root = T(0, 0, 0, 360 * k * k * (3 - 2 * k), 0, 0); return tuck end)
	-- 0.65 mid-air hang: arrow forms, three spinning wind lenses line up on the aim, feathers orbit, two spirals converge, light pulses faster
	at(0.65)
	task.spawn(ctx.moveTo, apex - d * 0.4 + UP * 0.4, 0.48)
	local draw, release = table.clone(P.bowDraw), table.clone(P.bowRelease)
	for j, v in { RightHip = R(25), RightKnee = R(-60), LeftHip = R(-5), LeftKnee = R(-25), Root = T(0, -0.1, 0, -25) } do draw[j], release[j] = v, v end -- dangling legs, leaning down to aim
	local nock = table.clone(draw); nock.RightShoulder, nock.RightElbow = R(90, 0, 10), R(30)
	local arrow, tip = mk({ Shape = WEDGE, Size = Vector3.new(0.35, 0.35, 0.2), Color = GREEN }, 0.9), mk({ Shape = BALL, Size = Vector3.one * 0.6, Color = MINT, Material = Enum.Material.ForceField }, 0.6)
	local lenses, motes = {}, { mk({ Shape = BALL, Size = Vector3.one * 0.4, Color = GREEN }, 0.75), mk({ Shape = BALL, Size = Vector3.one * 0.4, Color = WHITE }, 0.75) }
	for i = 1, 3 do
		lenses[i] = { f = i / 4, spin = i % 2 == 0 and -8 or 8, vanes = {}, disc = mk({ Shape = CYL, Size = Vector3.new(0.15, 0.1, 0.1), Color = TEAL, Material = Enum.Material.Glass, Transparency = 0.45 }, 0.9) }
		for j = 1, 3 do lenses[i].vanes[j] = mk({ Size = Vector3.new(0.2, 0.2, 1.2), Color = j == 1 and WHITE or MINT }, 0.9) end
	end
	Fx.Trail(motes[1], GREEN, 0.55, 0.2); Fx.Trail(motes[2], WHITE, 0.55, 0.2)
	Fx.Orbit(function() return ctx.myPos() end, WHITE, 5, 2.4, 0.6, 0.3, 7)
	local aim, charging, nextPulse, gap = d, true, 0, 0.16
	run(0.6, function(_, tt)
		if not charging then return true end
		local b, tgt = bow(), ctx.targetPos()
		aim = (tgt - b).Magnitude > 0.1 and (tgt - b).Unit or d
		local g, acf = math.min(1, tt / 0.35), CFrame.lookAt(b, b + aim)
		arrow.CFrame, arrow.Size, tip.CFrame = acf * CFrame.new(0, 0, -0.6 - 1.2 * g), Vector3.new(0.35, 0.35, 0.2 + 2.4 * g), acf * CFrame.new(0, 0, -0.8 - 2.4 * g)
		for _, L in lenses do
			local pcf, D = faceCF(b:Lerp(tgt, L.f), aim) * CFrame.Angles(0, tt * L.spin, 0), 3.6 * g
			L.disc.CFrame, L.disc.Size = pcf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.15, D + 0.1, D + 0.1)
			for j, v in L.vanes do v.CFrame = pcf * CFrame.Angles(0, j * 2 * math.pi / 3, 0) * CFrame.new(D / 2, 0, 0) end
		end
		local c = 1 - math.min(1, tt / 0.5)
		for j, m in motes do m.CFrame = faceCF(tip.Position, aim) * CFrame.Angles(0, tt * 14 + j * math.pi, 0) * CFrame.new(3 * c, -2 * c, 0) end
		if tt >= nextPulse then Fx.Light(b, GREEN, 12, 3, gap); nextPulse, gap = tt + gap, math.max(0.04, gap * 0.75) end
		return false
	end)
	ctx.pose(nock, 0.1, "out")
	ctx.pose(draw, 0.4, "inout")
	-- 1.20 release: the arrow drills through every lens inside a twisting helix (0.12s flight); recoil pushes her back 1 stud
	at(1.2)
	charging = false
	local b, tgt, FLY = bow(), ctx.targetPos(), 0.12
	aim = (tgt - b).Magnitude > 0.1 and (tgt - b).Unit or aim
	Fx.Ring(faceCF(b, aim), WHITE, 1, 5, 0.25, 0.1); Fx.Particles(b, { color = MINT, count = 10, speed = 12, size = 0.3, lifetime = 0.25, spread = 180, light = 1 })
	task.spawn(ctx.moveTo, ctx.myPos() - d, 0.12)
	tip.Transparency = 1; Fx.Trail(arrow, WHITE, 0.4, 0.45)
	Fx.Tween(arrow, FLY, { CFrame = CFrame.lookAt(tgt, tgt + aim), Size = Vector3.new(0.3, 0.3, 3.4) }, Enum.EasingStyle.Linear)
	for j, m in motes do
		Fx.Trail(m, j == 1 and GREEN or TEAL, 0.3, 0.2)
		run(FLY, function(k) m.CFrame = faceCF(b:Lerp(tgt, k), aim) * CFrame.Angles(0, k * 14 + j * math.pi, 0) * CFrame.new(0.7, 0, 0); return false end)
		task.delay(FLY, function() m.Transparency = 1 end)
	end
	for _, L in lenses do
		task.delay(FLY * L.f, function() -- each lens doubles in size and fades as the arrow passes
			Fx.Tween(L.disc, 0.2, { Size = L.disc.Size * Vector3.new(1, 2, 2), Transparency = 1 }); Fx.Burst(L.disc.Position, MINT, 2, 0.15)
			for _, v in L.vanes do Fx.Tween(v, 0.2, { Size = Vector3.new(0.05, 0.05, 2), Transparency = 1 }) end
		end)
	end
	ctx.pose(release, 0.05, "snap")
	-- 1.35 impact: a roaring mini-cyclone (five spinning rings with swirling streaks), leaves and feathers swept up, wind blades
	at(IMPACT - 0.02)
	ctx.impact()
	arrow.Transparency = 1
	local tp, rings = ctx.targetPos(), {}
	for j = 1, 5 do
		local D, glass = 2.5 + (j - 1) * 1.6, j % 2 == 0
		rings[j] = { D = D, h = 0.4 + (j - 1) * 2.2, streaks = {}, disc = mk({ Shape = CYL, Size = Vector3.new(0.12, D, D), Color = glass and TEAL or MINT, Material = glass and Enum.Material.Glass or Enum.Material.Neon, Transparency = 0.55 }, 0.75) }
		for q = 1, 3 do rings[j].streaks[q] = mk({ Size = Vector3.new(0.25, 0.25, D * 0.7), Color = q == 1 and WHITE or GREEN }, 0.75) end
	end
	run(0.65, function(_, tt)
		local grow, fade, c = math.min(1, tt / 0.15), math.clamp((tt - 0.4) / 0.25, 0, 1), ctx.targetGround()
		for j, r in rings do
			local sc = (0.3 + 0.7 * grow) * (1 - 0.7 * fade)
			local cf = CFrame.new(c + UP * r.h * (0.5 + 0.5 * grow)) * CFrame.Angles(0, tt * (18 + j * 3), 0) * CFrame.Angles(0.12, 0, 0)
			r.disc.CFrame, r.disc.Size, r.disc.Transparency = cf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.12, r.D * sc, r.D * sc), 0.55 + 0.45 * fade
			for q, sk in r.streaks do sk.CFrame, sk.Transparency = cf * CFrame.Angles(0, q * 2 * math.pi / 3, 0) * CFrame.new(r.D * sc / 2, 0, 0), fade end
		end
		return false
	end)
	for q = 0, 2 do
		task.delay(q * 0.12, function() Fx.Particles(ctx.targetGround() + UP * 0.5, { color = q == 1 and WHITE or GREEN, count = 14, speed = 14, size = 0.4, lifetime = 0.7, spread = 30, gravity = -8, light = 0.3 }) end)
	end
	for q = 1, 8 do
		local out = Vector3.new(math.cos(q * math.pi / 4), 0, math.sin(q * math.pi / 4))
		local w = mk({ Shape = WEDGE, Size = Vector3.new(0.12, 0.5, 2.4), Color = q % 2 == 0 and WHITE or MINT, CFrame = CFrame.lookAt(tp + out * 1.5, tp + out * 3) }, 0.4)
		Fx.Tween(w, 0.3, { CFrame = CFrame.lookAt(tp + out * 8, tp + out * 9), Size = Vector3.new(0.05, 0.2, 1), Transparency = 1 })
	end
	Fx.Burst(tp, WHITE, 5, 0.3); Fx.HitFlash(ctx.target, MINT, 0.3); ctx.shake(0.55, 0.4)
	ctx.flash(GREEN, 0.35, 0.07); task.delay(0.07, function() ctx.flash(WHITE, 0.3, 0.08) end)
	-- 1.75 float down with a twirl, flipping the bow in her hand; gust ring on landing, victory arm, back to guard
	at(1.75)
	task.spawn(ctx.moveTo, start, 0.25)
	local twirl = { RightHip = R(20), RightKnee = R(-50), LeftHip = R(10), LeftKnee = R(-10), LeftShoulder = R(30, 0, -40) }
	drive(0.25, function(k) twirl.Root, twirl.LeftWrist, twirl.RightShoulder = T(0, 0, 0, 0, 360 * k, 0), R(-720 * k, 0, 0), R(170 * k, 0, 20); return twirl end)
	Fx.Ring(CFrame.new(ctx.ground() + UP * 0.1), WHITE, 1, 8, 0.4, 0.1) -- soft gust ring on landing, leftover leaves drift down
	Fx.Particles(ctx.myPos() + UP * 4, { color = GREEN, count = 10, speed = 3, size = 0.35, lifetime = 0.8, spread = 180, gravity = 4, light = 0.2 })
	ctx.pose(P.victory, 0.08, "out")
	ctx.pose(P.guard, 0.2)
end
