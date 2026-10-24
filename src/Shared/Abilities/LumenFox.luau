-- Lumen Fox :: Foxfire Lantern Pounce (impact 1.05s, total 1.70s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(1, 1, 1)
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP = 1.05
	local torso, lt = ctx.part("UpperTorso"), ctx.part("LowerTorso")
	local hands = { ctx.part("RightHand"), ctx.part("LeftHand"), ctx.part("RightHand") }
	ctx.callout()
	Fx.HitFlash(ctx.model, C1, 0.5)

	-- 3 foxfire wisps: flung from the fingertips, drift round the enemy, become glass lanterns, then spiral into the strike
	local wisps = {}
	for i = 1, 3 do
		wisps[i] = { launch = 0.06 + i * 0.07,
			ball = Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, Color = C1, Transparency = 1 }),
			shell = Fx.Part({ Size = Vector3.new(1.2, 1.6, 1.2), Color = C2, Material = Enum.Material.Glass, Transparency = 1 }),
			top = Fx.Part({ Size = Vector3.new(1.35, 0.15, 1.35), Color = C1, Transparency = 1 }),
			bot = Fx.Part({ Size = Vector3.new(1.35, 0.15, 1.35), Color = C1, Transparency = 1 }) }
	end
	task.spawn(function()
		local spin, last, spark, cracked = 0, 0, 0, false
		while el() < 1.3 do
			local t = el(); spin += (t - last) * (t < 0.7 and 0.8 or 3.5); last = t
			local tp = ctx.targetPos()
			for i, w in wisps do
				if t >= w.launch then
					if not w.from then
						local h = hands[i]; w.from = h and h.Position or ctx.myPos()
						w.ball.Transparency = 0; Fx.Trail(w.ball, C1, 0.6, 0.25)
						w.out = start + (CFrame.Angles(0, i * 2.09 + 1, 0) * f) * 2.6 + UP * 1.2
					end
					local a = i * 2.09 + spin
					local station = tp + Vector3.new(math.cos(a) * 4, 0.8 + math.sin(t * 4 + i) * 0.3, math.sin(a) * 4)
					local pos, lit
					if t < 0.3 then pos, lit = w.from:Lerp(w.out, math.clamp((t - w.launch) / (0.3 - w.launch), 0, 1)), 0
					elseif t < IMP then local k = math.clamp((t - 0.3) / 0.35, 0, 1); k = 1 - (1 - k) ^ 2; pos, lit = w.out:Lerp(station, k), k
					else local k = math.clamp((t - IMP) / 0.15, 0, 1); local r = 4 * (1 - k)
						pos, lit = tp + Vector3.new(math.cos(a + k * 6) * r, 0.8 * (1 - k), math.sin(a + k * 6) * r), 0 end
					local pulse = t > 0.7 and t < IMP and 0.25 * math.sin(t * 30 + i) or 0
					w.ball.CFrame = CFrame.new(pos); w.ball.Size = Vector3.one * (0.7 + pulse + (t > 0.7 and 0.2 or 0))
					if t < IMP then
						local cf = CFrame.new(pos) * CFrame.Angles(0, a * 2, 0)
						w.shell.CFrame, w.top.CFrame, w.bot.CFrame = cf, cf * CFrame.new(0, 0.85, 0), cf * CFrame.new(0, -0.85, 0)
						w.shell.Transparency = 1 - lit * (t > 0.7 and 0.8 or 0.6); w.top.Transparency = 1 - lit; w.bot.Transparency = 1 - lit
					end
				end
			end
			if t >= IMP and not cracked then -- lanterns crack open, foxfire spirals in leaving pink trails
				cracked = true
				for _, w in wisps do
					fade(w.shell, 0.18, { Size = Vector3.new(2, 2.4, 2) }); fade(w.top, 0.2, { CFrame = w.top.CFrame + UP * 1.5 }); fade(w.bot, 0.2, { CFrame = w.bot.CFrame - UP * 1.2 })
					Fx.Trail(w.ball, C4, 0.3, 0.35)
				end
			end
			if t - spark > 0.1 then spark = t
				for _, w in wisps do if w.from then Fx.Particles(w.ball.Position, { color = C4, count = 2, speed = 2, size = 0.25, lifetime = 0.4, light = 1 }) end end
				if t > 0.7 and t < 1.0 and lt then Fx.Particles(lt.Position - f * 0.7, { color = C1, count = 4, speed = 4, size = 0.35, lifetime = 0.4, gravity = 4, light = 1 }) end
			end
			ctx.wait(0)
		end
		for _, w in wisps do fade(w.ball, 0.15, { Size = Vector3.one * 0.1 }) end
	end)

	-- the hit: 3 golden claw rakes, lanterns burst in, orange-white flash and sparkles
	task.delay(IMP - 0.02, function()
		local tp = ctx.targetPos()
		local face = CFrame.lookAt(tp - f * 1.2, tp - f * 2.2)
		ctx.impact()
		local marks = {}
		for i = -1, 1 do
			local cf = face * CFrame.new(i * 0.8, 0, 0) * CFrame.Angles(0, 0, math.rad(25))
			local glow = Fx.Part({ Size = Vector3.new(0.5, 0.1, 0.1), Color = C4, Transparency = 0.5, CFrame = cf * CFrame.new(0, 0, 0.05) })
			local m = Fx.Part({ Size = Vector3.new(0.18, 0.1, 0.12), Color = C2, CFrame = cf })
			Fx.Tween(m, 0.08, { Size = Vector3.new(0.18, 5.5, 0.12) }); Fx.Tween(glow, 0.1, { Size = Vector3.new(0.55, 6, 0.1) })
			table.insert(marks, m); table.insert(marks, glow)
		end
		task.delay(0.25, function() for _, m in marks do
			Fx.Particles(m.Position, { color = C1, count = 8, speed = 5, size = 0.3, lifetime = 0.5, gravity = 8, light = 1 }); fade(m, 0.2, { Size = m.Size * Vector3.new(0.2, 1, 1) })
		end end)
		Fx.Burst(tp - f, C3, 3, 0.3, { startSize = 0.1 }); Fx.Burst(tp, C1, 5, 0.4, { transparency = 0.45 })
		Fx.Particles(tp, { color = C1, count = 20, speed = 20, size = 0.4, lifetime = 0.5, light = 1 })
		Fx.Particles(tp, { color = C4, count = 14, speed = 16, size = 0.35, lifetime = 0.5, light = 1 })
		Fx.Light(tp, C2, 18, 4, 0.5); if ctx.target then Fx.HitFlash(ctx.target, C3, 0.3) end
		ctx.flash(C2, 0.25, 0.2); ctx.shake(0.4, 0.3)
	end)

	-- 0.00 pirouette on one toe, arms out, wisps fling off the fingertips
	task.spawn(ctx.pose, { Root = T(0, 0.3, 0), Neck = R(10), RightShoulder = R(0, 0, 85), LeftShoulder = R(0, 0, -85), RightElbow = R(10), LeftElbow = R(10),
		LeftHip = R(15), LeftKnee = R(-70), RightAnkle = R(-35) }, 0.1)
	ctx.spin(360, 0.27)
	ctx.face(ctx.targetPos())
	-- 0.30 stalk low, hands under the chin, wiggle the hips twice
	local stalk = { Root = T(0, -1.0, 0.3, -20), Waist = R(-15), Neck = R(30), RightShoulder = R(95, 0, -25), RightElbow = R(130), LeftShoulder = R(95, 0, 25), LeftElbow = R(130),
		RightHip = R(80), LeftHip = R(80), RightKnee = R(-120), LeftKnee = R(-120), RightAnkle = R(30), LeftAnkle = R(30) }
	ctx.pose(stalk, to(0.4), "out")
	Fx.Light(ctx.targetPos(), C1, 16, 2, 0.9)
	for i = 1, 3 do
		stalk.Waist = R(-15, i % 2 == 1 and 15 or -15, 0); stalk.Root = T(i % 2 == 1 and 0.25 or -0.25, -1.0, 0.3, -20)
		ctx.pose(stalk, to(0.4 + i * 0.1), "inout")
	end
	-- 0.70 pounce: tight arc, curled with hands above the head, then tip over head-first
	local land = ctx.targetPos() - f * 2.2
	Fx.Trail(torso, C1, 0.4, 1.1); Fx.Trail(torso, C2, 0.4, 0.5)
	task.spawn(ctx.moveTo, Vector3.new(land.X, start.Y, land.Z), 0.33, 4)
	ctx.pose({ Root = T(0, 0.3, 0, 15), Waist = R(10), Neck = R(15), RightShoulder = R(175, 0, -10), LeftShoulder = R(175, 0, 10), RightElbow = R(15), LeftElbow = R(15),
		RightHip = R(70), LeftHip = R(70), RightKnee = R(-110), LeftKnee = R(-110) }, to(0.84), "out")
	ctx.pose({ Root = T(0, 0, -0.5, -75), Waist = R(-15), Neck = R(25), RightShoulder = R(175, 0, -15), LeftShoulder = R(175, 0, 15), RightElbow = R(0), LeftElbow = R(0),
		RightHip = R(20), LeftHip = R(20), RightKnee = R(-40), LeftKnee = R(-40) }, to(1.0), "in")
	-- 1.00 rake: both arms whip down, claws spread
	ctx.pose({ Root = T(0, -0.6, -0.5, -20), Waist = R(-25), Neck = R(10), RightShoulder = R(-30, 0, 30), LeftShoulder = R(-30, 0, -30), RightElbow = R(10), LeftElbow = R(10),
		RightHip = R(50), LeftHip = R(50), RightKnee = R(-80), LeftKnee = R(-80) }, to(1.06), "snap")
	at(1.2)
	-- 1.20 hop back on all fours, sit neatly, cute head tilt
	task.spawn(ctx.moveTo, start, 0.22, 1.3)
	ctx.pose({ Root = T(0, -0.9, 0, -55), Waist = R(-10), Neck = R(40), RightShoulder = R(60, 0, 5), LeftShoulder = R(60, 0, -5), RightElbow = R(10), LeftElbow = R(10),
		RightHip = R(75), LeftHip = R(75), RightKnee = R(-100), LeftKnee = R(-100) }, to(1.42), "out")
	local sit = { Root = T(0, -1.4, 0.2), RightHip = R(85, 0, 5), LeftHip = R(85, 0, -5), RightKnee = R(-150), LeftKnee = R(-150), RightAnkle = R(40), LeftAnkle = R(40),
		RightShoulder = R(20, 0, -5), LeftShoulder = R(20, 0, 5), RightElbow = R(50), LeftElbow = R(50), Neck = R(5) }
	ctx.pose(sit, to(1.52), "back")
	sit.Neck = R(5, 0, 18); ctx.pose(sit, to(1.62), "back")
	ctx.pose(P.guard, 0.2)
end