-- Verdant Oriel :: Verdant Genesis Sunblade (impact 1.65s, total 2.50s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(1, 1, 1)
	local t0, start, UP, GLASS, done = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0), Enum.Material.Glass, {}
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local function once(k) if done[k] then return false end; done[k] = true; return true end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local function wedge(c, tr, mat) return Fx.Part({ Shape = Enum.PartType.Wedge, Color = c, Transparency = tr or 1, Material = mat }) end
	local function ball(c, s, mat) return Fx.Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * s, Color = c, Transparency = 1, Material = mat }) end
	local function point(pr, base, w, h, L) -- two wedges = a crystal point, apex along base.UpVector
		pr[1].Size, pr[2].Size = Vector3.new(w, h, L), Vector3.new(w, h, L)
		pr[1].CFrame, pr[2].CFrame = base * CFrame.new(0, h / 2, -L / 2), base * CFrame.new(0, h / 2, L / 2) * CFrame.Angles(0, math.pi, 0) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side, IMP = f:Cross(UP).Unit, 1.65
	local rh, lh, head, wpn = ctx.part("RightHand"), ctx.part("LeftHand"), ctx.part("Head"), ctx.weapon()
	local function hilt() local a, b = rh and rh.Parent and rh.Position, lh and lh.Parent and lh.Position
		return (a and b) and (a + b) / 2 or a or b or ctx.myPos() + UP * 2 end
	task.delay(2.6, function() if wpn then wpn.LocalTransparencyModifier = 0 end end)
	ctx.callout()

	-- phoenix (ForceField-shelled body, 2 wings of 4 layered wedges, beak, eyes, 3-trail tail), sunblade, crystal lotus
	local body, shell, beak, eyes, tails, wings, WC = ball(C2, 3), ball(C2, 3.8, Enum.Material.ForceField), wedge(C3), { ball(C4, 0.5), ball(C4, 0.5) }, {}, {}, { C2, C1, C2:Lerp(C4, 0.35), C3 }
	beak.Size = Vector3.new(0.4, 0.7, 1.2)
	for j = 1, 3 do tails[j] = Fx.Part({ Size = Vector3.one * 0.2, Transparency = 1 }) end
	for i = 1, 8 do wings[i] = wedge(WC[(i - 1) % 4 + 1]) end
	local bird = { body, shell, beak, eyes[1], eyes[2], table.unpack(wings) }
	local core, heart, tipP, edges, tipBall = Fx.Part({ Color = C1, Transparency = 1 }), Fx.Part({ Color = C4, Transparency = 1 }), { wedge(C1), wedge(C1) }, {}, ball(C3, 1)
	for i = 1, 10 do edges[i] = wedge(C1:Lerp(C4, 0.4), 1, GLASS) end
	local blade, petals, lcore = { core, heart, tipP[1], tipP[2], table.unpack(edges) }, {}, ball(C3, 0.1)
	for i = 1, 16 do petals[i] = wedge(math.ceil(i / 2) % 2 == 0 and C1 or C4, 1, GLASS) end
	local pg, ph, cc = ctx.ground() - f * 3.5, start - f * 5 + UP * 12, start + UP * 12
	local tipPos, L, th, thT, prev, dot = start + UP * 6, 4, 0, math.rad(95), nil, 0
	local function drawBlade(b, dir) -- neon core + white heart + crystal point + 10 swept glass edge wedges
		local sc, zb = math.clamp(L / 20, 0.3, 1), side:Cross(dir)
		core.Size, core.CFrame = Vector3.new(0.3, L, 1.3), CFrame.fromMatrix(b + dir * (0.3 + L / 2), side, dir)
		heart.Size, heart.CFrame, tipPos = Vector3.new(0.38, L, 0.35), core.CFrame, b + dir * (0.3 + L)
		point(tipP, CFrame.fromMatrix(tipPos, side, dir), 0.3, 0.6 + 1.6 * sc, 0.65)
		for i, p in edges do local o, fr = zb * (i % 2 == 0 and -1 or 1), 0.12 + math.ceil(i / 2) * 0.15
			p.Size, p.CFrame = Vector3.new(0.14, 1.5 * sc, 0.9 * sc), CFrame.fromMatrix(b + dir * (0.3 + L * fr) - o * (0.65 + 0.45 * sc), dir:Cross(o), dir, o) end
	end
	local function drawBird(pos, t)
		local v = (prev and pos - prev or UP) + f * 0.02; prev = pos
		local cf = CFrame.lookAt(pos, pos + v.Unit)
		body.CFrame, shell.CFrame, beak.CFrame = cf, cf, cf * CFrame.new(0, -0.1, -2.1)
		eyes[1].CFrame, eyes[2].CFrame = cf * CFrame.new(0.6, 0.55, -1.2), cf * CFrame.new(-0.6, 0.55, -1.2)
		for j = 1, 3 do tails[j].CFrame = cf * CFrame.new((j - 2) * 0.9, 0, 1.8) end
		local flap = math.rad(math.sin(t * 16) * 35)
		for sd = -1, 1, 2 do local w = cf * CFrame.Angles(0, 0, -sd * flap)
			local out, fw, up = w.RightVector * sd, w.LookVector, w.UpVector
			for j = 1, 4 do local Lj, p = 7.5 - (j - 1) * 1.4, wings[(sd + 1) * 2 + j] -- 16 studs tip to tip, swept-back layered feathers
				p.Size, p.CFrame = Vector3.new(0.15, 2.8 - j * 0.4, Lj), CFrame.fromMatrix(pos + out * (1.1 + Lj / 2) - fw * (j - 1) * 0.3 + up * (j - 1) * 0.08, fw:Cross(-out), fw, -out) end
		end
	end
	task.spawn(function()
		while el() < 2.4 do
			local t, tp, lg = el(), ctx.targetPos(), ctx.targetGround() + UP * 0.1
			if t >= 0.35 and t < 0.97 then -- phoenix bursts from the ground behind, rises 12 studs, circles once, dives into the sword
				if once("bird") then for _, p in bird do p.Transparency = p == shell and 0.25 or 0 end
					Fx.Trail(tails[1], C2, 0.65, 1.8); Fx.Trail(tails[2], C1, 0.65, 1.1); Fx.Trail(tails[3], C3, 0.6, 0.6) end
				if t < 0.55 then drawBird(pg:Lerp(ph, 1 - (1 - (t - 0.35) / 0.2) ^ 2), t)
				elseif t < 0.85 then local a = (t - 0.55) / 0.3 * math.pi * 2; drawBird(cc + (side * math.sin(a) - f * math.cos(a)) * 5 + UP * math.sin(a * 2) * 0.8, t)
				else drawBird(ph:Lerp(hilt() + UP * 2.5, ((t - 0.85) / 0.12) ^ 2), t) end
			end
			if t >= 0.97 and once("forge") then -- it bursts into emerald flame and the blade grows from 4 to 20 studs
				local hp = done.bird and body.Position or hilt() + UP * 2.5
				for _, p in bird do fade(p, 0.12, { Size = p.Size * 0.3 }) end
				for _, p in tails do task.delay(0.4, function() p:Destroy() end) end
				Fx.Burst(hp, C2, 7, 0.35, { startSize = 1 }); Fx.Light(hp, C2, 22, 4, 0.5)
				Fx.Particles(hp, { color = C2, count = 24, speed = 18, size = 0.5, lifetime = 0.5, gravity = -4, light = 1 })
				if wpn then wpn.LocalTransparencyModifier = 1 end
				for i, p in blade do p.Transparency = i > 4 and 0.2 or 0 end
			end
			if done.forge and t < 2.25 then -- upright overhead, then one vertical arc onto the target, then planted and shrinking
				L = t < 1.2 and 4 + 16 * math.sin(math.clamp((t - 0.97) / 0.23, 0, 1) * math.pi / 2) or (t < 1.8 and 20 or 20 - 16 * math.clamp((t - 1.8) / 0.45, 0, 1))
				local b = hilt()
				if t < 1.6 then local d = tp - b; thT = math.atan2(d:Dot(f), d:Dot(UP)) end
				th = thT * math.clamp((t - 1.5) / 0.15, 0, 1) ^ 2 + math.rad(14) * math.clamp((t - 1.65) / 0.06, 0, 1)
				th += math.max(0, math.rad(150) - th) * math.clamp((t - 1.72) / 0.16, 0, 1)
				drawBlade(b, UP * math.cos(th) + f * math.sin(th))
			elseif done.forge and once("sheathe") then -- shrunk back to a sword: hand the real one back
				for _, p in blade do fade(p, 0.12) end
				if wpn then wpn.LocalTransparencyModifier = 0 end
			end
			if t >= 1.25 and t < 1.52 then -- gold charge ball pulses 1 -> 3 at the tip
				tipBall.Transparency, tipBall.Size, tipBall.CFrame = 0, Vector3.one * (1 + 2 * math.clamp((t - 1.25) / 0.25, 0, 1) + 0.35 * math.sin(t * 45)), CFrame.new(tipPos)
			elseif t >= 1.52 and once("ball") then fade(tipBall, 0.08) end
			if t >= 0.8 and t < 1.72 then -- the lotus opens under the enemy, then snaps shut at the hit
				local sc = math.clamp((t - 0.8) / 0.3, 0, 1)
				local phi = math.rad(t < 1.65 and 8 + 62 * sc or 70 - 65 * math.clamp((t - 1.65) / 0.05, 0, 1))
				for i = 1, 8 do local a = i * math.pi / 4 + t * 0.5
					local rad, tan = Vector3.new(math.cos(a), 0, math.sin(a)), Vector3.new(-math.sin(a), 0, math.cos(a))
					local pd = UP * math.cos(phi) + rad * math.sin(phi)
					point({ petals[i * 2 - 1], petals[i * 2] }, CFrame.fromMatrix(lg + rad * 0.5 * sc, pd:Cross(tan), pd, tan), 0.12, 3.2 * sc + 0.02, 0.75 * sc + 0.01) end
				for _, p in petals do p.Transparency = 0.25 end
				lcore.Transparency, lcore.Size, lcore.CFrame = 0, Vector3.one * (0.3 + 0.9 * sc + 0.15 * math.sin(t * 20)), CFrame.new(lg + UP * 0.6)
			elseif t >= 1.72 and once("bloom") then -- ...and bursts outward in golden light
				for _, p in petals do fade(p, 0.4, { CFrame = p.CFrame + (p.Position - lg) * Vector3.new(1.5, 0, 1.5) + UP * 2.5 }) end
				fade(lcore, 0.25, { Size = Vector3.one * 4 })
				Fx.Burst(lg + UP, C3, 5, 0.35); Fx.Particles(lg + UP, { color = C3, count = 26, speed = 22, size = 0.45, lifetime = 0.7, gravity = 8, light = 1 })
			end
			if t - dot > 0.05 then dot = t -- hair flames, phoenix embers, blade flames then peeling feathers, gold motes drawn to the tip
				local hot = t > 0.35 and t < 1.7
				if head and head.Parent and t < 2.3 then Fx.Particles(head.Position + UP * 0.5, { color = math.random() < 0.5 and C1 or C2, count = hot and 5 or 2, speed = hot and 12 or 5, size = 0.5, lifetime = 0.35, spread = 25, gravity = -14, light = 1 }) end
				if done.bird and not done.forge then Fx.Particles(body.Position, { color = math.random() < 0.5 and C2 or C3, count = 3, speed = 3, size = 0.4, lifetime = 0.5, gravity = 6, light = 1 }) end
				if done.forge and not done.sheathe then local pt = core.Position + core.CFrame.UpVector * (math.random() - 0.5) * L
					if t < 1.8 then Fx.Particles(pt, { color = C2, count = 3, speed = 4, size = 0.45, lifetime = 0.45, gravity = -8, light = 1 })
					else local fe = wedge(C2, 0); fe.Size, fe.CFrame = Vector3.new(0.08, 0.45, 1.1), CFrame.new(pt) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
						fade(fe, 0.5, { CFrame = fe.CFrame + UP * 2.5 + side * (math.random() - 0.5) * 3 }) end
				end
				if t > 1.25 and t < 1.5 then for _ = 1, 2 do
					local m = Fx.Part({ Size = Vector3.one * 0.25, Color = C3, CFrame = CFrame.new(tipPos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * 5) })
					fade(m, 0.18, { CFrame = CFrame.new(tipPos), Size = Vector3.one * 0.08 }) end end
			end
			ctx.wait(0)
		end
	end)

	-- the sun-strike: white flash turning cyan, a 25-stud slash plane, rings, neon cracks racing to the target
	task.delay(IMP - 0.02, function()
		local tp, g = ctx.targetPos(), ctx.targetGround()
		ctx.impact()
		ctx.flash(C4, 0.85, 0.12); task.delay(0.08, function() ctx.flash(C1, 0.45, 0.4) end)
		if ctx.target then Fx.HitFlash(ctx.target, C4, 0.3) end
		Fx.Burst(tp, C4, 5, 0.25, { startSize = 0.5 }); Fx.Burst(tp, C1, 9, 0.45, { transparency = 0.4 }); Fx.Beam(tp + UP * 12, tp - UP * 3, C4, 0.7, 0.2)
		Fx.Ring(CFrame.new(g + UP * 0.2), C2, 2, 18, 0.5, 0.45); Fx.Ring(CFrame.new(tp), C1, 1, 13, 0.4, 0.3); Fx.Shockwave(g, C1, 8, 0.6)
		Fx.Particles(tp, { color = C3, count = 30, speed = 30, size = 0.5, lifetime = 0.7, gravity = 10, light = 1 })
		Fx.Light(tp, C1, 28, 6, 0.6); ctx.shake(0.95, 0.8)
		for sd = -1, 1, 2 do -- the slash plane splits in two and the halves slide apart
			local h = Fx.Part({ Size = Vector3.new(0.16, 25, 1), Color = C1, CFrame = CFrame.fromMatrix(tp + side * sd * 0.08, side, UP) })
			task.delay(0.1, function() fade(h, 0.5, { CFrame = h.CFrame + side * sd * 2.5, Size = Vector3.new(0.05, 25, 1) }) end)
		end
		local a0 = ctx.ground() + f * 2; local run = (g - a0) * Vector3.new(1, 0, 1)
		if run.Magnitude > 1 then for i = 0, 7 do local p0 = a0 + run * ((i + 0.5) / 8) + UP * 0.06
			local c = Fx.Part({ Size = Vector3.new(0.4, 0.12, run.Magnitude / 8 + 0.4), Color = i % 2 == 0 and C1 or C2, Transparency = 1, CFrame = CFrame.lookAt(p0, p0 + run) * CFrame.Angles(0, math.rad(math.random(-18, 18)), 0) })
			task.delay(i * 0.02, function() c.Transparency = 0; task.delay(0.35, function() fade(c, 0.4) end) end)
		end end
	end)

	-- 0.00 power stance: feet wide, sword upright before the face, emerald aura, cyan ground ring
	Fx.HitFlash(ctx.model, C2, 0.6)
	Fx.Ring(CFrame.new(ctx.ground() + UP * 0.1), C1, 2, 10, 0.4, 0.3); Fx.Light(ctx.myPos(), C1, 16, 2.5, 2.4)
	ctx.pose({ Root = T(0, -0.35, 0), Neck = R(-12), RightShoulder = R(70, 0, -30), RightElbow = R(85), LeftShoulder = R(70, 0, 30), LeftElbow = R(85),
		RightHip = R(0, 0, 18), LeftHip = R(0, 0, -18), RightKnee = R(-12), LeftKnee = R(-12), RightAnkle = R(0, 0, -15), LeftAnkle = R(0, 0, 15) }, to(0.3), "out")
	at(0.35)
	-- 0.35 the phoenix erupts from the ground behind him, crystal shards rise around him, knees sink as the sword lifts
	Fx.Burst(pg, C2, 5, 0.35); Fx.Particles(pg, { color = C2, count = 20, speed = 16, size = 0.5, lifetime = 0.6, gravity = -4, light = 1 })
	Fx.Spikes(ctx.ground(), C1, 8, 2.5, 1.0, 3.5)
	ctx.pose({ Root = T(0, -0.8, 0), Neck = R(15), RightShoulder = R(150, 0, -10), RightElbow = R(30), LeftShoulder = R(150, 0, 10), LeftElbow = R(30),
		RightHip = R(30, 0, 18), LeftHip = R(30, 0, -18), RightKnee = R(-55), LeftKnee = R(-55), RightAnkle = R(20, 0, -10), LeftAnkle = R(20, 0, 10) }, to(0.78), "inout")
	-- 0.80 sword straight overhead, braced for the phoenix; the screen dims a dark green
	ctx.flash(Color3.fromRGB(6, 46, 26), 0.3, 0.6)
	local over = { Root = T(0, -0.65, 0), Neck = R(10), RightShoulder = R(178, 0, -6), RightElbow = R(5), LeftShoulder = R(178, 0, 6), LeftElbow = R(5),
		RightHip = R(25, 0, 18), LeftHip = R(25, 0, -18), RightKnee = R(-45), LeftKnee = R(-45), RightAnkle = R(15, 0, -10), LeftAnkle = R(15, 0, 10) }
	ctx.pose(over, to(0.95), "out")
	at(1.25)
	-- 1.25 trembling as power builds: gold rings collapse onto the tip, a white phoenix-cry ring flashes
	for i = 1, 3 do task.delay((i - 1) * 0.06, function() Fx.Ring(CFrame.new(tipPos) * CFrame.Angles(math.rad(i * 55), math.rad(i * 40), 0), C3, 9, 0.4, 0.2, 0.35) end) end
	task.delay(0.2, function() Fx.Ring(CFrame.new(tipPos) * CFrame.Angles(math.rad(90), 0, 0), C4, 1, 9, 0.22, 0.5); Fx.Burst(tipPos, C4, 2.5, 0.15) end)
	for i = 1, 5 do over.Root = T(i % 2 == 0 and 0.07 or -0.07, -0.65, 0); ctx.pose(over, to(1.25 + i * 0.048), "linear") end
	-- 1.50 colossal cleave: one big stride, the 20-stud blade arcs down onto the enemy from afar
	Fx.Trail(tipP[1], C1, 0.35, 3); Fx.Trail(tipP[2], C4, 0.35, 1.2); Fx.Trail(core, C2, 0.3, 5)
	Fx.Slash(CFrame.lookAt(ctx.myPos(), ctx.myPos() + f) * CFrame.Angles(0, 0, math.rad(90)), C1, 12, 140, 0.3, 2.5)
	task.spawn(ctx.moveTo, start + f * 1.5, 0.12)
	local lunge = { Root = T(0, -0.9, -1.0, -12), Waist = R(-30), Neck = R(-5), RightShoulder = R(55, 0, -8), RightElbow = R(0), LeftShoulder = R(55, 0, 8), LeftElbow = R(0),
		LeftHip = R(70), LeftKnee = R(-75), LeftAnkle = R(10), RightHip = R(-35), RightKnee = R(-30), RightAnkle = R(-10) }
	ctx.pose(lunge, to(1.63), "in")
	lunge.Root, lunge.Waist, lunge.RightShoulder, lunge.LeftShoulder = T(0, -1.0, -1.0, -15), R(-38), R(20, 0, -8), R(20, 0, 8)
	ctx.pose(lunge, to(1.7), "out")
	-- 1.70 drop to one knee with the giant blade planted; emerald feathers peel off as it shrinks back
	ctx.pose({ Root = T(0, -1.15, -0.6), Waist = R(-15), Neck = R(-15), RightShoulder = R(40, 0, -10), RightElbow = R(15), LeftShoulder = R(40, 0, 10), LeftElbow = R(15),
		LeftHip = R(85), LeftKnee = R(-85), RightHip = R(-10), RightKnee = R(-95), RightAnkle = R(35) }, to(1.86), "out")
	at(2.0)
	-- 2.00 rise slowly, then flick the sword to the side as the hair settles
	task.spawn(ctx.moveTo, start, 0.3)
	ctx.pose({ Root = T(0, -0.1, 0), Waist = R(0, 10, 0), RightShoulder = R(30, 0, 10), RightElbow = R(20), LeftShoulder = R(10, 0, -10), LeftElbow = R(20) }, to(2.28), "inout")
	ctx.pose({ Waist = R(0, -10, 0), Neck = R(0, -15, 0), RightShoulder = R(25, 0, 65), RightElbow = R(5), LeftShoulder = R(0, 0, -12) }, to(2.4), "back")
	ctx.pose(P.guard, 0.2)
end