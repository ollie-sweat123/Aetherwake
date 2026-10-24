-- Kaito Emberfist: Cinderheart Breaker (impact 1.50s, total 2.20s)
return function(ctx)
	local Fx, P, R, T = ctx.Fx, ctx.P, ctx.R, ctx.T
	local RED, AMBER, PALE, CRIMSON = ctx.palette[1] or ctx.accent, ctx.palette[2] or ctx.accent, ctx.palette[3] or Color3.new(1, 1, 1), ctx.palette[4] or ctx.accent
	local WHITE, SMOKE, IMPACT, UP, BALL, WEDGE = Color3.new(1, 1, 1), Color3.fromRGB(120, 115, 110), 1.5, Vector3.yAxis, Enum.PartType.Ball, Enum.PartType.Wedge
	local t0, start = os.clock(), ctx.myPos()
	local function at(t) local d = t - (os.clock() - t0); if d > 0 then ctx.wait(d) end end
	local function flat(v) return Vector3.new(v.X, 0, v.Z) end
	local function dir() local d = flat(ctx.targetPos() - ctx.myPos()); return d.Magnitude > 0.05 and d.Unit or flat(ctx.root.CFrame.LookVector).Unit end
	local function mk(props, life) local p = Fx.Part(props); task.delay(life, function() p:Destroy() end); return p end
	local function faceCF(pos, d) return CFrame.lookAt(pos, pos + d) * CFrame.Angles(-math.pi / 2, 0, 0) end -- ring facing along d
	local function hand(n) local h = ctx.part(n); return h and h.Position or ctx.myPos() + dir() * 1.5 end
	-- time-bounded background per-frame updater (fn returns true to stop early)
	local function run(dur, fn) task.spawn(function() local s = os.clock(); while os.clock() - s < dur and not fn(os.clock() - s) do ctx.wait(0) end end) end
	-- 0.00 coiled crouch: gauntlets flicker orange, embers rise off both fists, ground ring, light flares
	ctx.callout()
	Fx.HitFlash(ctx.model, RED, 0.15); task.delay(0.15, function() Fx.HitFlash(ctx.model, AMBER, 0.15) end)
	Fx.Ring(CFrame.new(ctx.ground() + UP * 0.1), RED, 2, 8, 0.45, 0.15); Fx.Light(ctx.myPos(), RED, 10, 4, 0.6)
	task.spawn(function()
		for i = 1, 5 do
			for _, n in { "LeftHand", "RightHand" } do Fx.Particles(hand(n), { color = i % 2 == 0 and AMBER or RED, count = 6, speed = 5, size = 0.3, lifetime = 0.4, spread = 25, gravity = -12, light = 1 }) end
			ctx.wait(0.06)
		end
	end)
	task.spawn(ctx.moveTo, start - dir() * 1.5, 0.25)
	ctx.pose({ Root = T(0, -0.8, 0, -8), Waist = R(-5, 40, 0), Neck = R(0, -30, 0), RightShoulder = R(-40, 0, 20), RightElbow = R(110), LeftShoulder = R(75, 0, -10), LeftElbow = R(115),
		RightHip = R(50), LeftHip = R(50), RightKnee = R(-80), LeftKnee = R(-80), RightAnkle = R(25), LeftAnkle = R(25) }, 0.22, "out")
	-- 0.30 explosive dash on a wake of flame footprints, dust burst at launch, trails on both forearms
	at(0.3)
	local d, tp = dir(), ctx.targetPos()
	local spot = Vector3.new(tp.X, start.Y, tp.Z) - d * math.max(2.5, flat(tp - start).Magnitude - 2.4)
	Fx.Particles(ctx.ground() + UP * 0.4, { color = SMOKE, count = 14, speed = 10, size = 0.8, lifetime = 0.4, spread = 80, light = 0 })
	Fx.Trail(ctx.part("RightLowerArm"), RED, 0.9, 0.35); Fx.Trail(ctx.part("LeftLowerArm"), AMBER, 0.9, 0.35)
	task.spawn(function()
		for _ = 1, 5 do
			local g = ctx.ground() + UP * 0.5
			local f = mk({ Shape = WEDGE, Size = Vector3.new(0.5, 1, 0.8), Color = math.random() < 0.5 and RED or AMBER, CFrame = CFrame.lookAt(g, g - d) }, 0.5)
			Fx.Tween(f, 0.4, { Size = Vector3.new(0.1, 1.8, 0.2), Transparency = 1, CFrame = f.CFrame * CFrame.Angles(math.rad(-25), 0, 0) + UP })
			ctx.wait(0.05)
		end
	end)
	ctx.pose({ Root = T(0, -0.3, 0, -25), Waist = R(-5), RightShoulder = R(-55, 0, 15), RightElbow = R(20), LeftShoulder = R(-55, 0, -15), LeftElbow = R(20),
		RightHip = R(40), RightKnee = R(-60), LeftHip = R(-30), LeftKnee = R(-20) }, 0.05, "snap")
	ctx.moveTo(spot, 0.18)
	-- 0.55 six-punch flurry (every 0.09s): burning fist afterimages, sparks, light pulses, micro shakes
	local base = { Root = T(0, -0.35, -0.5), RightHip = R(25), LeftHip = R(25), RightKnee = R(-40), LeftKnee = R(-40) }
	local pR = table.clone(base); pR.Waist, pR.Neck, pR.RightShoulder, pR.RightElbow, pR.LeftShoulder, pR.LeftElbow = R(-5, -30, 0), R(0, 25, 0), R(92, -8, 5), R(0), R(30, 0, -15), R(105)
	local pL = table.clone(base); pL.Waist, pL.Neck, pL.LeftShoulder, pL.LeftElbow, pL.RightShoulder, pL.RightElbow = R(-5, 30, 0), R(0, -25, 0), R(92, 8, -5), R(0), R(30, 0, 15), R(105)
	for i = 1, 6 do
		at(0.55 + (i - 1) * 0.09)
		local right = i % 2 == 0
		ctx.pose(right and pR or pL, 0.05, "snap")
		local dd, hp = dir(), hand(right and "RightHand" or "LeftHand")
		local ghost = mk({ Shape = BALL, Size = Vector3.one * 1.5, Color = right and RED or AMBER, Transparency = 0.3, CFrame = CFrame.new(hp) }, 0.25)
		Fx.Tween(ghost, 0.15, { CFrame = CFrame.new(hp + dd * 3 + UP * (math.random() - 0.5) * 0.8), Transparency = 1, Size = Vector3.one * 1.1 })
		local hit = ctx.targetPos() - dd * 0.9 + UP * (math.random() - 0.5) * 1.2
		Fx.Burst(hit, right and AMBER or RED, 1.8, 0.12); Fx.Light(hit, right and CRIMSON or RED, 10, 3, 0.1)
		Fx.Particles(hit, { color = PALE, count = 12, speed = 18, size = 0.3, lifetime = 0.3, spread = 120, light = 1 })
		Fx.Ring(faceCF(hit, dd), WHITE, 0.5, 2.5, 0.12, 0.08); ctx.shake(0.15, 0.08)
	end
	-- 1.10 hop back and forge the giant flame fist: core ball, six spinning spikes, pulsing red ForceField shell, embers pulled in
	at(1.1)
	d = dir()
	task.spawn(ctx.moveTo, ctx.myPos() - d * 1.2, 0.15, 0.5)
	ctx.flash(AMBER, 0.1, 0.3)
	local core = mk({ Shape = BALL, Size = Vector3.one * 0.5, Color = RED, Transparency = 0.05 }, 0.8)
	local shell = mk({ Shape = BALL, Size = Vector3.one * 0.5, Color = CRIMSON, Material = Enum.Material.ForceField }, 0.8)
	local spikes, charging, last = {}, true, 0
	for k = 1, 6 do spikes[k] = mk({ Shape = WEDGE, Size = Vector3.new(0.3, 1.6, 0.7), Color = AMBER }, 0.8) end
	run(0.5, function(tt)
		if not charging then return true end
		local g, hp = math.min(1, tt / 0.25), hand("RightHand")
		local cf = CFrame.lookAt(hp, hp + dir())
		core.CFrame, core.Size, shell.CFrame, shell.Size = cf, Vector3.one * (0.5 + 3 * g), cf, Vector3.one * (0.6 + 4 * g + math.sin(tt * 40) * 0.35)
		for k, sp in spikes do sp.CFrame = cf * CFrame.Angles(0, 0, tt * 9 + k * math.pi / 3) * CFrame.new(0, 2.5 * g + 0.2, 0) end
		if tt - last > 0.035 then
			last = tt
			local a = math.random() * math.pi * 2
			local e = mk({ Size = Vector3.one * 0.3, Color = math.random() < 0.5 and AMBER or PALE, CFrame = CFrame.new(hp + Vector3.new(math.cos(a), math.random() - 0.5, math.sin(a)) * 4) }, 0.25)
			Fx.Tween(e, 0.18, { CFrame = CFrame.new(hp), Size = Vector3.one * 0.05 })
		end
		return false
	end)
	ctx.pose({ Root = T(0, -0.45, 0.3), Waist = R(-5, 55, 0), Neck = R(-12, -35, 0), RightShoulder = R(-70, 0, 35), RightElbow = R(95), LeftShoulder = R(80, 0, -10), LeftElbow = R(60),
		LeftHip = R(30), LeftKnee = R(-30), RightHip = R(-10), RightKnee = R(-25) }, 0.2, "out")
	-- 1.42 straight cross with the root sliding in; the big hit lands at 1.50 and bursts out behind the enemy in rings of fire
	at(1.42)
	d = dir()
	task.spawn(ctx.moveTo, ctx.myPos() + d, 0.07)
	ctx.pose({ Root = T(0, -0.3, -1.1), Waist = R(-8, -45, 0), Neck = R(0, 35, 0), RightShoulder = R(92, -5, 0), RightElbow = R(0), LeftShoulder = R(20, 0, -25), LeftElbow = R(100),
		RightHip = R(-15), LeftHip = R(40), LeftKnee = R(-45), RightKnee = R(-10) }, 0.05, "snap")
	at(IMPACT - 0.02)
	charging = false
	ctx.impact()
	tp = ctx.targetPos()
	local fp, side = hand("RightHand"), d:Cross(UP)
	Fx.Tween(core, 0.25, { Size = Vector3.one * 7, Transparency = 1 }); Fx.Tween(shell, 0.25, { Size = Vector3.one * 8.5, Transparency = 1 })
	for _, sp in spikes do Fx.Tween(sp, 0.25, { CFrame = sp.CFrame * CFrame.new(0, 3, 0), Transparency = 1 }) end
	for k, col in { RED, AMBER, WHITE } do task.delay((k - 1) * 0.05, function() Fx.Ring(faceCF(tp + d * (k - 1) * 1.5, d), col, 2, 10 + k * 2, 0.35, 0.3) end) end
	for k = 1, 10 do -- cone of flame shards bursting out behind the enemy
		local out = d * 6 + side * math.cos(k * math.pi / 5) * 2.5 + UP * math.sin(k * math.pi / 5) * 2.5
		local sh = mk({ Shape = WEDGE, Size = Vector3.new(0.35, 0.9, 1.8), Color = k % 2 == 0 and RED or AMBER, CFrame = CFrame.lookAt(tp, tp + out) }, 0.45)
		Fx.Tween(sh, 0.35, { CFrame = CFrame.lookAt(tp + out, tp + out * 2), Size = Vector3.new(0.05, 0.2, 0.6), Transparency = 1 })
	end
	Fx.Beam(fp, tp + d * 7, PALE, 2, 0.3); Fx.Burst(tp, AMBER, 6, 0.35); Fx.Shockwave(ctx.targetGround(), RED, 5, 0.5)
	Fx.Particles(tp, { color = AMBER, count = 30, speed = 30, size = 0.45, lifetime = 0.45, spread = 180, light = 1 })
	Fx.HitFlash(ctx.target, CRIMSON, 0.35); ctx.flash(WHITE, 0.55, 0.1); ctx.shake(0.7, 0.4)
	task.delay(0.2, function() Fx.Ring(CFrame.new(ctx.targetGround() + UP * 0.12), RED, 5, 7.5, 0.7, 0.2) end) -- lingering ember ring
	-- 1.80 after holding the follow-through: pull back, crack knuckles over smoking gauntlets, bounce into stance
	at(1.8)
	Fx.Light(ctx.myPos(), RED, 12, 4, 0.45)
	task.spawn(ctx.moveTo, start, 0.32)
	ctx.pose({ Root = T(0, -0.1, 0), Neck = R(-10), RightShoulder = R(70, 0, -25), RightElbow = R(95), LeftShoulder = R(70, 0, 25), LeftElbow = R(95), RightHip = R(10), LeftHip = R(-5) }, 0.14, "out")
	for _, n in { "LeftHand", "RightHand" } do
		Fx.Particles(hand(n), { color = SMOKE, count = 8, speed = 3, size = 0.9, lifetime = 0.6, spread = 30, gravity = -6, light = 0 }); Fx.Burst(hand(n), AMBER, 0.9, 0.12)
	end
	at(1.98)
	ctx.pose({ Root = T(0, 0.35, 0), RightShoulder = R(35, 0, 10), RightElbow = R(70), LeftShoulder = R(35, 0, -10), LeftElbow = R(70) }, 0.06, "out")
	ctx.pose(P.guard, 0.2)
end
