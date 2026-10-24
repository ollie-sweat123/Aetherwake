-- Spark Ivy :: Prism Lattice Theorem (impact 1.05s, total 1.70s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(1, 1, 1)
	local t0, start, UP = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0)
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local made = {}
	local function mk(p) local x = Fx.Part(p); table.insert(made, x); return x end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	task.delay(2.1, function() for _, p in made do p:Destroy() end end)
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side = f:Cross(UP).Unit
	local IMP, rh, w, WHITE, CYL = 1.05, ctx.part("RightHand"), ctx.weapon(), Color3.new(1, 1, 1), Enum.PartType.Cylinder
	-- hide the real staff (and its orb/ring pieces in the same hand) while a stand-in hovers
	local L, held, acc = 5, {}, ctx.model:FindFirstChild("Accessories")
	if w then L = math.clamp(math.max(w.Size.X, w.Size.Y, w.Size.Z), 3, 7); held[1] = w
		local j = w:GetAttribute("Joint")
		if acc and j then for _, p in acc:GetChildren() do if p ~= w and p:IsA("BasePart") and p:GetAttribute("Joint") == j then table.insert(held, p) end end end
	end
	for _, p in held do p.LocalTransparencyModifier = 1 end
	local function showW() for _, p in held do p.LocalTransparencyModifier = 0 end end
	task.delay(1.8, showW)
	-- the hovering staff (stand-in for the real one while it floats)
	local shaft = mk({ Shape = CYL, Size = Vector3.new(L, 0.22, 0.22), Color = C4, Material = Enum.Material.Glass, Transparency = 0.2 })
	local orb = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.65, Color = C3 })
	local b1, b2 = mk({ Shape = CYL, Size = Vector3.new(0.14, 0.36, 0.36), Color = C1 }), mk({ Shape = CYL, Size = Vector3.new(0.14, 0.36, 0.36), Color = C1 })
	local sl = Instance.new("PointLight"); sl.Color = C3; sl.Range = 9; sl.Brightness = 2; sl.Parent = orb
	local Z90 = CFrame.Angles(0, 0, math.pi / 2)
	local function placeStaff(cf) shaft.CFrame = cf * Z90; orb.CFrame = cf * CFrame.new(0, L / 2, 0); b1.CFrame = cf * CFrame.new(0, L * 0.3, 0) * Z90; b2.CFrame = cf * CFrame.new(0, -L * 0.32, 0) * Z90 end
	local hand0, hover = rh and rh.Position or start + f, start + f * 1.4 + side * 1.1 + UP * 0.4
	-- holo rings (segment rings) and orbiting glass formula panels
	local function segRing(n) local r = {}; for i = 1, n do r[i] = mk({ Size = Vector3.new(0.5, 0.1, 0.1), Color = C1, Transparency = 1 }) end; return r end
	local function setRing(segs, cf, rad, a, tr)
		for i, p in segs do
			p.Size = Vector3.new(math.max(0.05, 2 * math.pi * rad / #segs * 1.1), 0.1, 0.1); p.Transparency = tr
			p.CFrame = cf * CFrame.Angles(0, a + i * 2 * math.pi / #segs, 0) * CFrame.new(0, 0, -rad)
		end
	end
	local ringW, ringS, panels = segRing(18), segRing(20), {}
	for i = 1, 4 do panels[i] = { mk({ Size = Vector3.new(1.2, 0.8, 0.05), Color = C3, Material = Enum.Material.Glass, Transparency = 1 }),
		mk({ Size = Vector3.new(0.8, 0.06, 0.06), Color = C2, Transparency = 1 }), mk({ Size = Vector3.new(0.5, 0.06, 0.06), Color = WHITE, Transparency = 1 }) } end
	-- the sigil triangle, 3 studs in front of her
	local Ct = start + f * 3 + UP * 1.2
	local V = { Ct + UP * 2.31, Ct - side * 2 - UP * 1.155, Ct + side * 2 - UP * 1.155 }
	local edges, balls, bo, bi = {}, {}, {}, {}
	for i = 1, 3 do
		bo[i] = mk({ Shape = CYL, Size = Vector3.new(1, 0.6, 0.6), Color = C1, Transparency = 1 }); bi[i] = mk({ Shape = CYL, Size = Vector3.new(1, 0.25, 0.25), Color = C3, Transparency = 1 })
		task.delay(0.33 + (i - 1) * 0.13, function()
			local a, b = V[i], V[i % 3 + 1]
			local len = (b - a).Magnitude
			local e = mk({ Size = Vector3.new(0.12, 0.12, 0.05), Color = C2, CFrame = CFrame.lookAt(a, b) })
			Fx.Tween(e, 0.12, { Size = Vector3.new(0.12, 0.12, len), CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2) }, Enum.EasingStyle.Linear)
			local ball = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = WHITE, CFrame = CFrame.new(a) })
			local pl = Instance.new("PointLight"); pl.Color = C2; pl.Range = 7; pl.Brightness = 2.5; pl.Parent = ball
			edges[i], balls[i] = e, ball
			Fx.Particles(a, { color = C2, count = 6, speed = 5, size = 0.2, lifetime = 0.25, light = 1 }); Fx.Burst(a, WHITE, 1.2, 0.15)
		end)
	end
	ctx.callout()

	task.spawn(function()
		local fx = 0
		while el() < 1.68 do
			local t, me = el(), ctx.myPos()
			-- staff: spun off the hand, hovers and bobs, then flies back into her grip
			if t < 0.3 then local k = 1 - (1 - t / 0.3) ^ 2; local p = hand0:Lerp(hover, k)
				placeStaff(CFrame.lookAt(p, p + f) * CFrame.Angles(0, 0, (1 - k) * 2 * math.pi))
			elseif t < 0.7 then local p = hover + UP * 0.15 * math.sin(t * 7); placeStaff(CFrame.lookAt(p, p + f) * CFrame.Angles(0, 0, 0.08 * math.sin(t * 3)))
			elseif t < 0.76 then local p = hover:Lerp(rh and rh.Position or me + f, (t - 0.7) / 0.06); placeStaff(CFrame.lookAt(p, p + f))
			elseif shaft.Transparency < 1 then for _, p in { shaft, orb, b1, b2 } do p.Transparency = 1 end; sl.Enabled = false; showW() end
			-- rings and panels grow in, counter-rotate, then shrink away from 1.25
			local s = math.clamp(t / 0.3, 0, 1) * (1 - math.clamp((t - 1.25) / 0.35, 0, 1))
			local tr = s < 0.03 and 1 or 0.15
			setRing(ringW, CFrame.new(me + UP * 0.1), 2 * s, t * 2.2, tr)
			setRing(ringS, CFrame.new(me + UP * 1.5) * CFrame.Angles(math.rad(8), 0, 0), 2.5 * s, -t * 2.8, tr)
			for i, pn in panels do
				local cf = CFrame.new(me + UP * (0.7 + 0.2 * math.sin(t * 3 + i))) * CFrame.Angles(0, t * 1.5 + i * math.pi / 2, 0) * CFrame.new(0, 0, -3 * s)
				local ss = math.max(s, 0.02)
				pn[1].CFrame, pn[2].CFrame, pn[3].CFrame = cf, cf * CFrame.new(0, 0.17 * ss, -0.04), cf * CFrame.new(-0.15 * ss, -0.12 * ss, -0.04)
				pn[1].Size, pn[2].Size, pn[3].Size = Vector3.new(1.2, 0.8, 0.05) * ss, Vector3.new(0.8 * ss, 0.06, 0.06), Vector3.new(0.5 * ss, 0.06, 0.06)
				pn[1].Transparency, pn[2].Transparency, pn[3].Transparency = s < 0.03 and 1 or 0.5, tr, tr
			end
			-- three converging beams from the triangle corners (violet outer, cyan core, magenta crackle)
			local tp = ctx.targetPos()
			for i = 1, 3 do
				if t >= 0.75 and t < 1.04 then
					local b = V[i]:Lerp(tp, math.min(1, (t - 0.75) / 0.07))
					local cf, d = CFrame.lookAt((V[i] + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), (b - V[i]).Magnitude
					bo[i].Size, bo[i].CFrame, bo[i].Transparency = Vector3.new(d, 0.6, 0.6), cf, 0.25
					bi[i].Size, bi[i].CFrame, bi[i].Transparency = Vector3.new(d, 0.25, 0.25), cf, 0
				else bo[i].Transparency, bi[i].Transparency = 1, 1 end
			end
			if t - fx > 0.04 then fx = t
				if t > 0.78 and t < 1.03 then for i = 1, 3 do Fx.Lightning(V[i], tp, i == 2 and C3 or C2, 4, 0.05, 0.1) end end
				if t < 0.7 then Fx.Particles(orb.Position, { color = C3, count = 1, speed = 2, size = 0.25, lifetime = 0.3, light = 1 }) end
			end
			ctx.wait(0)
		end
	end)

	-- 1.05 IMPACT: a violet crystal prism forms on the target, spins, then shatters into glass shards
	task.delay(math.max(0, IMP - 0.02 - el()), function()
		local tp = ctx.targetPos()
		ctx.impact()
		Fx.HitFlash(ctx.target, C1, 0.3); Fx.Light(tp, C1, 18, 4, 0.5); Fx.Burst(tp, C3, 3, 0.15, { startSize = 0.5 }); ctx.shake(0.35, 0.3)
		local offs = { CFrame.new(0, 0.75, -0.5), CFrame.new(0, 0.75, 0.5) * CFrame.Angles(0, math.pi, 0), CFrame.new(0, -0.75, -0.5) * CFrame.Angles(0, 0, math.pi),
			CFrame.new(0, -0.75, 0.5) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, math.pi) }
		local pr = {}
		for i = 1, 4 do pr[i] = mk({ Shape = Enum.PartType.Wedge, Size = Vector3.new(1.6, 1.5, 1), Color = C1, Material = Enum.Material.Glass, Transparency = 0.25 }) end
		local core = mk({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = C2 })
		local s0 = os.clock()
		while os.clock() - s0 < 0.16 do
			local k = os.clock() - s0
			local cf = CFrame.new(ctx.targetPos()) * CFrame.Angles(0, k * 14, 0) * CFrame.new(0, 0, 0)
			for i, p in pr do p.CFrame = cf * offs[i] end
			core.CFrame = cf; core.Size = Vector3.one * (0.9 + k * 3)
			ctx.wait(0)
		end
		tp = ctx.targetPos()
		for _, p in pr do p:Destroy() end; core:Destroy()
		for i = 1, 12 do
			local d = Vector3.new(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5); d = d.Magnitude > 0.05 and d.Unit or UP
			local sh = mk({ Size = Vector3.new(0.35, 0.35, 0.55), Color = i % 2 == 0 and C3 or C2, Material = Enum.Material.Glass, Transparency = 0.2,
				CFrame = CFrame.new(tp + d * 0.5) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
			fade(sh, 0.45, { CFrame = CFrame.new(tp + d * 6) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6) })
		end
		Fx.Ring(CFrame.new(tp), C2, 1, 7, 0.4, 0.2); Fx.Burst(tp, WHITE, 3.5, 0.2, { startSize = 1 })
		Fx.Particles(tp, { color = C3, count = 14, speed = 12, size = 0.3, lifetime = 0.5, light = 1 }); Fx.Particles(tp, { color = C2, count = 14, speed = 12, size = 0.3, lifetime = 0.5, light = 1 })
		ctx.flash(C4, 0.3, 0.15)
	end)

	-- 0.00 spins the staff off her fingers and leaves it hanging in the air, hand on hip, smirking
	local function with(extra) local o = { LeftShoulder = R(0, 0, -35), LeftElbow = R(110), LeftHip = R(10), RightKnee = R(-12), Root = T(0, -0.05, 0, 0, 0, 3) }
		for k, x in extra do o[k] = x end; return o end
	ctx.pose(with({ RightShoulder = R(70, 0, 15), RightElbow = R(50), Neck = R(0, 0, 10), Waist = R(0, 8, 4) }), to(0.15), "out")
	ctx.pose(with({ RightShoulder = R(35, 0, 25), RightElbow = R(25), RightWrist = R(-30), Neck = R(5, 0, 10), Waist = R(0, 8, 4) }), to(0.3), "inout")
	-- 0.30 traces the sigil: fingertip up, out-left across the body, out-right
	ctx.pose(with({ RightShoulder = R(130, 0, 5), RightElbow = R(5), Waist = R(6), Neck = R(15, 0, 6) }), to(0.43), "out")
	ctx.pose(with({ RightShoulder = R(65, 0, -40), RightElbow = R(5), Waist = R(0, -12, 0), Neck = R(0, -10, 6) }), to(0.56), "inout")
	ctx.pose(with({ RightShoulder = R(65, 0, 45), RightElbow = R(5), Waist = R(0, 12, 0), Neck = R(0, 10, 6) }), to(0.69), "inout")
	-- 0.70 grabs the staff and thrusts it through the triangle, sliding back from the recoil
	ctx.pose({ RightShoulder = R(60, 0, 30), RightElbow = R(60), LeftShoulder = R(40, 0, -20), LeftElbow = R(50), Waist = R(0, 25, 0), Root = T(0, -0.1, 0.1), Neck = R(5) }, to(0.75), "out")
	ctx.flash(C1, 0.25, 0.2); Fx.Trail(w, C3, 0.3, 0.3)
	task.spawn(ctx.moveTo, start - f, 0.18)
	local thrust = { Waist = R(-15, -20, 0), RightShoulder = R(90, 0, 0), RightElbow = R(0), LeftShoulder = R(-35, 0, -30), LeftElbow = R(15), Root = T(0, -0.25, -0.6),
		RightHip = R(-20), LeftHip = R(40), LeftKnee = R(-40), Neck = R(5) }
	ctx.pose(thrust, to(0.82), "snap")
	Fx.Burst(Ct, WHITE, 2.5, 0.2, { startSize = 0.4 }); Fx.Particles(Ct, { color = C3, count = 10, speed = 10, size = 0.25, lifetime = 0.3, light = 1 })
	-- 1.00 holds the thrust, coat swaying
	thrust.Waist = R(-15, -15, 5); ctx.pose(thrust, to(1.12), "inout")
	thrust.Waist = R(-15, -24, -5); ctx.pose(thrust, to(1.25), "inout")
	-- 1.25 the triangle dissolves into sparkles; she twirls the staff and rests it on her shoulder
	for i = 1, 3 do
		local e, b = edges[i], balls[i]
		for k = 0, 2 do Fx.Particles(V[i]:Lerp(V[i % 3 + 1], k / 2), { color = C3, count = 5, speed = 3, size = 0.25, lifetime = 0.4, gravity = -2, light = 1 }) end
		if e then fade(e, 0.3, { Size = Vector3.new(0.02, 0.02, e.Size.Z) }) end
		if b then fade(b, 0.3, { Size = Vector3.one * 0.1 }) end
	end
	task.spawn(ctx.moveTo, start, 0.35)
	local spinS = { RightShoulder = R(95, 0, 25), RightElbow = R(30), LeftShoulder = R(10, 0, -25), LeftElbow = R(30), Waist = R(0, -5, 0), Neck = R(0, 0, -4) }
	for i = 1, 3 do spinS.RightWrist = R(0, (i * 120) % 360, 0); ctx.pose(spinS, to(1.25 + i * 0.06), "linear") end
	ctx.pose({ RightShoulder = R(150, 0, 10), RightElbow = R(120), LeftShoulder = R(0, 0, -35), LeftElbow = R(110), Neck = R(0, 0, -8), Waist = R(0, 5, 0), LeftHip = R(8), RightKnee = R(-8) }, to(1.58), "back")
	at(1.6)
	ctx.pose(P.guard, 0.2)
end
