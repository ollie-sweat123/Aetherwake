-- Bubble Bo :: Pop-Pop Bubble Boop (impact 0.90s, total 1.40s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or Color3.new(1, 1, 1), C[3] or ctx.accent, C[4] or ctx.accent
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	task.delay(2, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local IMP, head = 0.9, ctx.part("Head")
	local tp0 = ctx.targetPos()
	local back, hop = start - f * 2.2, Vector3.new(tp0.X, start.Y, tp0.Z) - f * 5.1
	ctx.callout()

	-- the enemy bobs inside the bubble: only its height is touched, always measured from where it started, and it is
	-- held back on the ground until 1.3s so a knockback restore can never leave it floating
	local tgt = ctx.target
	local b0 = tgt and tgt.Parent and tgt:GetPivot()
	local function lift(h)
		if not (b0 and tgt.Parent) then return end
		if tgt:GetAttribute("Dead") then h = 0 end
		local cur = tgt:GetPivot(); local dy = b0.Y + h - cur.Y
		if math.abs(dy) > 0.0001 then tgt:PivotTo(cur + UP * dy) end -- (tight threshold: a 0.005 leftover per cast slowly floated the enemy up)
	end

	-- the bubble: a wobbling ForceField skin around a pink glass heart with a light inside
	local ff = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = C1, Material = Enum.Material.ForceField, Transparency = 0 })
	local core = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, Color = C3, Material = Enum.Material.Glass, Transparency = 0.6 })
	local glow = Instance.new("PointLight"); glow.Color = C1; glow.Range = 6; glow.Brightness = 1; glow.Parent = core
	task.spawn(function()
		local fx, p0 = 0, ctx.myPos() + f * 2
		while el() < IMP - 0.01 do
			local t, tp = el(), ctx.targetPos()
			local hp = head and head.Position or ctx.myPos() + UP * 1.5
			local size, pos
			if t < 0.3 then size = 0.5 + 2.5 * (t / 0.3); pos = hp + f * (0.7 + size / 2) - UP * 0.4; p0 = pos
			elseif t < 0.55 then local k = (t - 0.3) / 0.25; k = k * k * (3 - 2 * k)
				size = 3 + 1.5 * k; pos = p0:Lerp(tp, k) + UP * math.sin(k * math.pi) * 1.2
			else size = 4.5 + 2.5 * math.min(1, (t - 0.55) / 0.08); pos = tp end
			local fast = t > 0.6
			local wob = math.sin(t * (fast and 38 or 20)) * (fast and 0.08 or 0.05)
			ff.Size = Vector3.one * size * (1 + wob); core.Size = Vector3.one * size * (0.86 - wob)
			ff.CFrame = CFrame.new(pos); core.CFrame = ff.CFrame
			glow.Range = size * 2.2; glow.Brightness = t > 0.55 and 2.5 or 1
			lift(t > 0.55 and t < IMP - 0.03 and math.clamp((t - 0.55) / 0.12, 0, 1) * (1 + math.sin(t * 14) * 0.25) or 0)
			if t - fx > 0.04 then fx = t
				if t < 0.3 then Fx.Particles(pos + UP * size * 0.4, { color = C1, count = 2, speed = 2, size = 0.3, lifetime = 0.7, gravity = -4, spread = 50, light = 0.6 })
				elseif t < 0.6 then Fx.Particles(pos, { color = C1, count = 3, speed = 1.5, size = 0.3, lifetime = 0.5, gravity = -3, light = 0.6 })
				else local d = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					Fx.Particles(pos + (d.Magnitude > 0.01 and d.Unit or UP) * size * 0.5, { color = C2, count = 2, speed = 0.8, size = 0.35, lifetime = 0.3, light = 1 })
				end
			end
			ctx.wait(0)
		end
		-- after the pop it lands with a little bounce, then stays planted
		while el() < 1.3 do local t = el(); lift((t > 0.93 and t < 1.13) and math.sin((t - 0.93) / 0.2 * math.pi) * 0.4 or 0); ctx.wait(0) end
	end)
	task.delay(0.55, function() Fx.HitFlash(ctx.target, C1, 0.35) end)

	-- the boop: bubble flashes out to 9 studs, mini glass bubbles ring outward, sparkles, pop rings, white flash
	task.delay(IMP - 0.02, function()
		local tp = ctx.targetPos()
		ctx.impact()
		fade(ff, 0.12, { Size = Vector3.one * 9 }); fade(core, 0.1, { Size = Vector3.one * 8 })
		for i = 1, 8 do
			local d = CFrame.Angles(0, i * math.pi / 4, 0) * f
			local b = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, Color = i % 2 == 0 and C3 or C1, Material = Enum.Material.Glass, Transparency = 0.3, CFrame = CFrame.new(tp + d * 3.5) })
			Fx.Tween(b, 0.6, { CFrame = CFrame.new(tp + d * 7 + UP * (1 + i % 3)) })
			task.delay(0.35, function() fade(b, 0.25, { Size = Vector3.one * 1.1 }) end)
		end
		Fx.Particles(tp, { color = C2, count = 13, speed = 18, size = 0.4, lifetime = 0.55, light = 1 })
		Fx.Particles(tp, { color = C3, count = 12, speed = 15, size = 0.4, lifetime = 0.55, light = 1 })
		Fx.Ring(CFrame.new(tp), C3, 7, 13, 0.35, 0.3); Fx.Ring(CFrame.new(tp + UP * 0.1), C2, 6, 11, 0.25, 0.15)
		Fx.Burst(tp, C2, 4, 0.18, { startSize = 0.5 }); Fx.Light(tp, C1, 18, 3, 0.4)
		Fx.HitFlash(ctx.target, C2, 0.25); ctx.flash(C2, 0.85, 0.12); ctx.shake(0.25, 0.25)
	end)

	-- 0.00 cups both hands to his mouth, head tipped back, cheeks puffed...
	local cup = { RightShoulder = R(75, 0, -25), RightElbow = R(115), LeftShoulder = R(75, 0, 25), LeftElbow = R(115), Neck = R(22), Waist = R(10), Root = T(0, 0.05, 0.1) }
	ctx.pose(cup, to(0.14), "out")
	-- ...then leans in and blows the bubble up
	cup.Neck, cup.Waist, cup.Root = R(-8), R(-15), T(0, -0.1, -0.25)
	ctx.pose(cup, to(0.3), "inout")
	-- 0.30 two-handed push, palms open
	Fx.Trail(ff, C2, 0.3, 1.2)
	ctx.pose({ RightShoulder = R(82, 0, -8), LeftShoulder = R(82, 0, 8), RightElbow = R(0), LeftElbow = R(0), RightWrist = R(-60), LeftWrist = R(-60),
		Waist = R(-15), Root = T(0, -0.2, -0.5), RightHip = R(-15), LeftHip = R(30), LeftKnee = R(-30) }, to(0.4), "snap")
	-- 0.40 rocks back onto his heels
	task.spawn(ctx.moveTo, back, 0.18)
	ctx.pose({ RightShoulder = R(30, 0, 20), LeftShoulder = R(30, 0, -20), RightElbow = R(30), LeftElbow = R(30), Waist = R(10), Neck = R(10),
		Root = T(0, -0.05, 0.25, 10), RightAnkle = R(25), LeftAnkle = R(25) }, to(0.6), "out")
	-- 0.60 two bouncy hops toward the bubble, arms swinging
	for i = 1, 2 do
		task.spawn(ctx.moveTo, back:Lerp(hop, i / 2), 0.12, 1)
		local up = i == 1
		ctx.pose({ Root = T(0, 0.2, 0), RightShoulder = R(up and 140 or 40, 0, 30), LeftShoulder = R(up and 40 or 140, 0, -30), RightElbow = R(20), LeftElbow = R(20),
			RightHip = R(30), RightKnee = R(-50), LeftHip = R(20), LeftKnee = R(-40), RightAnkle = R(-30), LeftAnkle = R(-30), Neck = R(10, 0, up and 10 or -10) }, to(0.6 + i * 0.125 - 0.06), "out")
		ctx.pose({ Root = T(0, -0.3, 0), RightHip = R(25), LeftHip = R(25), RightKnee = R(-40), LeftKnee = R(-40), RightAnkle = R(15), LeftAnkle = R(15),
			RightShoulder = R(20, 0, 25), LeftShoulder = R(20, 0, -25), RightElbow = R(30), LeftElbow = R(30) }, to(0.6 + i * 0.125), "in")
	end
	-- 0.85 up on tiptoe: one-finger boop, head tilted with a grin
	ctx.pose({ Root = T(0, 0.35, -0.15), RightShoulder = R(105, 0, 0), RightElbow = R(0), RightWrist = R(0), LeftShoulder = R(20, 0, -35), LeftElbow = R(40),
		Waist = R(-5, 15, 0), Neck = R(8, 0, 14), RightAnkle = R(-40), LeftAnkle = R(-40), RightHip = R(-5) }, to(IMP), "snap")
	at(1.03)
	-- 1.03 pirouette on one foot while six little bubbles float up and pop one by one
	Fx.Trail(head, C1, 0.25, 0.5)
	local me = ctx.myPos()
	for i = 1, 6 do
		local a = i * math.pi / 3
		local b = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Color = i % 2 == 0 and C3 or C4, Material = Enum.Material.ForceField,
			CFrame = CFrame.new(me + Vector3.new(math.cos(a) * 2, -1.5, math.sin(a) * 2)) })
		Fx.Tween(b, 0.45, { CFrame = b.CFrame + UP * 3 }, Enum.EasingStyle.Sine)
		task.delay(0.12 + i * 0.045, function()
			Fx.Burst(b.Position, C2, 1, 0.15); Fx.Particles(b.Position, { color = C3, count = 4, speed = 4, size = 0.2, lifetime = 0.25, light = 1 }); b:Destroy()
		end)
	end
	task.spawn(ctx.pose, { Root = T(0, 0.15, 0), RightShoulder = R(0, 0, 80), LeftShoulder = R(0, 0, -80), LeftHip = R(40), LeftKnee = R(-90), RightAnkle = R(-30), Neck = R(5) }, 0.08)
	ctx.spin(360, to(1.25))
	ctx.face(ctx.targetPos())
	-- 1.25 peace sign and a happy head tilt
	ctx.pose({ LeftShoulder = R(160, 0, -25), LeftElbow = R(70), RightShoulder = R(0, 0, 35), RightElbow = R(110), Neck = R(0, 0, -15), Waist = R(0, 0, 5),
		LeftHip = R(0, 0, -5), RightKnee = R(-10) }, to(1.33), "back")
	ctx.pose(P.guard, 0.2)
end
