-- Rift Ranger Kael :: Riftfall Shard (impact 1.35s, total 2.00s)
return function(ctx)
	local Fx, P, R, T, C = ctx.Fx, ctx.P, ctx.R, ctx.T, ctx.palette
	local C1, C2, C3, C4 = C[1] or ctx.accent, C[2] or ctx.accent, C[3] or ctx.accent, C[4] or Color3.new(0.05, 0.16, 0.12)
	local t0, start, UP, WHITE, GLASS = os.clock(), ctx.myPos(), Vector3.new(0, 1, 0), Color3.new(1, 1, 1), Enum.Material.Glass
	local function el() return os.clock() - t0 end
	local function to(t) return math.max(0.03, t - el()) end
	local function at(t) if t > el() then ctx.wait(t - el()) end end
	local function fade(p, d, g) g = g or {}; g.Transparency = 1; Fx.Tween(p, d, g); task.delay(d + 0.05, function() p:Destroy() end) end
	local function line(p, a, b, w) local d = b - a; if d.Magnitude < 0.02 then b = a + UP * 0.02; d = b - a end
		p.Size = Vector3.new(d.Magnitude, w, w); p.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0) end
	local function env(t, a, b, c, d) return math.clamp(math.min((t - a) / (b - a), (d - t) / (d - c)), 0, 1) end
	local function wedge(c, tr, mat) return Fx.Part({ Shape = Enum.PartType.Wedge, Color = c, Transparency = tr or 1, Material = mat }) end
	local function point(pr, base, w, h, L) -- two wedges = a crystal point, apex along base.UpVector
		pr[1].Size, pr[2].Size = Vector3.new(w, h, L), Vector3.new(w, h, L)
		pr[1].CFrame, pr[2].CFrame = base * CFrame.new(0, h / 2, -L / 2), base * CFrame.new(0, h / 2, L / 2) * CFrame.Angles(0, math.pi, 0) end
	local f = (ctx.targetPos() - start) * Vector3.new(1, 0, 1); f = f.Magnitude > 0.1 and f.Unit or ctx.root.CFrame.LookVector
	local side, IMP, rh, lh = f:Cross(UP).Unit, 1.35, ctx.part("RightHand"), ctx.part("LeftHand")
	local knee = ctx.part("RightLowerLeg") or ctx.part("RightFoot")
	ctx.callout()

	-- jagged rift: dark void core, violet + green neon lips, wedge shards jutting out, ForceField glow
	local JAG = { 0, 0.35, -0.3, 0.45, -0.35, 0.3, 0 }
	local function newRift(len) local r = { len = len, e = {}, sh = {}, glow = Fx.Part({ Color = C2, Material = Enum.Material.ForceField, Transparency = 1 }) }
		for i = 1, 18 do r.e[i] = Fx.Part({ Color = i <= 6 and C4 or (i <= 12 and C2 or C1), Transparency = 1 }) end
		for i = 1, 4 do r.sh[i] = wedge(i % 2 == 0 and C1 or C2) end
		return r end
	local function drawRift(r, s, c, u, v)
		local vis = s > 0.02 and 0 or 1
		local function pt(k, sd) local a = (k - 1) / 6; return c + u * (a - 0.5) * r.len * s + v * (JAG[k] + math.sin(a * math.pi) * 0.8 * sd) * s end
		for k = 1, 6 do line(r.e[k], pt(k, 0), pt(k + 1, 0), 0.45 * s + 0.02); line(r.e[k + 6], pt(k, -1), pt(k + 1, -1), 0.16); line(r.e[k + 12], pt(k, 1), pt(k + 1, 1), 0.16) end
		for _, p in r.e do p.Transparency = vis end
		for i, p in r.sh do local Z = v * (i % 2 == 0 and -1 or 1)
			p.Size, p.Transparency = Vector3.new(0.1, 0.6, 1.2) * s + Vector3.one * 0.01, vis
			p.CFrame = CFrame.fromMatrix(pt(i + 1, -Z:Dot(v)) - Z * 0.6 * s, u:Cross(Z), u, Z) end
		r.glow.Size, r.glow.Transparency, r.glow.CFrame = Vector3.new(2.2 * s, r.len * s, 0.3) + Vector3.one * 0.01, vis * 0.9 + 0.1, CFrame.fromMatrix(c, v, u, v:Cross(u))
	end
	local r1, r2, shards = newRift(5), newRift(7), {}
	local shaft, head = Fx.Part({ Color = C3, Material = GLASS, Transparency = 1 }), { wedge(C3, 1, GLASS), wedge(C3, 1, GLASS) }
	local lance = { Fx.Part({ Color = C3, Material = GLASS, Transparency = 1 }), Fx.Part({ Color = C3:Lerp(WHITE, 0.45), Transparency = 1 }), wedge(C3, 1, GLASS), wedge(C3, 1, GLASS) }
	for i = 1, 6 do shards[i] = wedge(C3, 1, GLASS) end
	local fired, shattered, dot, dir, tipPos, r1c = false, false, 0, f, start, start + f * 4
	task.spawn(function()
		while el() < 1.95 do
			local t, tp = el(), ctx.targetPos()
			if not fired and t >= 0.3 and rh and rh.Parent then -- crystal arrow grows on the string while 6 shards spiral in and fuse
				local k, k2 = math.clamp((t - 0.3) / 0.45, 0, 1), math.clamp((t - 0.3) / 0.5, 0, 1)
				local d = lh and lh.Parent and (lh.Position - rh.Position) or f
				dir = d.Magnitude > 0.5 and d.Unit or f
				local L, x = 4 * k + 0.05, dir:Cross(UP).Unit
				local y = x:Cross(dir)
				tipPos = rh.Position + dir * L
				shaft.Transparency, shaft.Size, shaft.CFrame = 0.1, Vector3.new(0.14, 0.14, L), CFrame.lookAt(rh.Position + dir * L / 2, tipPos)
				head[1].Transparency, head[2].Transparency = 0.05, 0.05
				point(head, CFrame.fromMatrix(tipPos - dir * 0.05, x, dir), 0.12, 0.9 * k + 0.02, 0.28 * k + 0.01)
				for i, p in shards do local a, r = t * 9 + i * 1.047, 2.4 * (1 - k2) + 0.05
					p.Size, p.Transparency, p.CFrame = Vector3.new(0.08, 0.35, 0.6), k2 < 1 and 0.1 or 1, CFrame.lookAt(tipPos + (x * math.cos(a) + y * math.sin(a)) * r + dir * r * 0.6, tipPos) end
				if t < 0.8 and t - dot > 0.03 then dot = t -- motes of light drawn into the tip
					local m = Fx.Part({ Size = Vector3.one * 0.18, Color = math.random() < 0.5 and C3 or C1, CFrame = CFrame.new(tipPos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * 3) })
					fade(m, 0.15, { CFrame = CFrame.new(tipPos), Size = Vector3.one * 0.05 }) end
			end
			drawRift(r1, env(t, 0.8, 1.0, 1.4, 1.65), r1c, UP, side); drawRift(r2, env(t, 1.15, 1.25, 1.45, 1.7), tp + UP * 10, side, UP)
			if not shattered and t >= 1.45 then shattered = true -- the lance shatters into glittering falling shards
				for i = 0, 3 do Fx.Particles(lance[1].Position + UP * (i * 1.6 - 2.4), { color = i % 2 == 0 and C3 or WHITE, count = 9, speed = 9, size = 0.35, lifetime = 0.7, gravity = 25, light = 1 }) end
				for _, p in lance do fade(p, 0.18, { Size = p.Size * 0.4 }) end
			elseif not shattered and t >= 1.2 then -- giant crystal lance (glass shell, neon core) plunges out of the sky rift
				local k = math.clamp((t - 1.2) / 0.15, 0, 1)
				local apex, bl = tp + UP * 10 * (1 - k * k), math.clamp(10 * k * k - 2, 0.05, 6)
				local mid = apex + UP * (2 + bl / 2)
				lance[1].Size, lance[1].CFrame, lance[1].Transparency = Vector3.new(1.5, bl, 1.5), CFrame.new(mid) * CFrame.Angles(0, math.rad(45), 0), 0.3
				lance[2].Size, lance[2].CFrame, lance[2].Transparency = Vector3.new(0.6, bl + 0.8, 0.6), CFrame.new(mid - UP * 0.4), 0
				point({ lance[3], lance[4] }, CFrame.new(apex + UP * 2) * CFrame.Angles(math.pi, math.rad(45), 0), 1.06, 2, 0.75)
				lance[3].Transparency, lance[4].Transparency = 0.15, 0.15
			end
			ctx.wait(0)
		end
		for _, r in { r1, r2 } do r.glow:Destroy(); for _, p in r.e do p:Destroy() end; for _, p in r.sh do p:Destroy() end end
		for _, p in { shaft, head[1], head[2], table.unpack(shards) } do p:Destroy() end
	end)

	-- the hit: violet + green bursts, rift lightning crackling down the lance, white flash, heavy shake
	task.delay(IMP - 0.02, function()
		local tp = ctx.targetPos()
		local rc = tp + UP * 10
		ctx.impact()
		Fx.Burst(tp, C2, 6, 0.35, { startSize = 0.5 }); Fx.Burst(tp, C1, 4, 0.3, { startSize = 0.2 }); Fx.Burst(tp, WHITE, 2.5, 0.15)
		Fx.Shockwave(ctx.targetGround(), C2, 6, 0.5); Fx.Light(tp, C3, 22, 5, 0.5)
		Fx.Particles(tp, { color = C3, count = 25, speed = 24, size = 0.4, lifetime = 0.6, gravity = 10, light = 1 })
		Fx.Particles(tp, { color = C1, count = 12, speed = 18, size = 0.35, lifetime = 0.5, light = 1 })
		if ctx.target then Fx.HitFlash(ctx.target, C3, 0.35) end
		ctx.flash(WHITE, 0.6, 0.2); ctx.shake(0.7, 0.45)
		for i = 1, 3 do
			for sd = -1, 1, 2 do Fx.Lightning(rc + side * sd * (1.5 + i * 0.6), tp + UP * (1 + i * 2) + side * sd * 0.5, sd < 0 and C2 or C1, 6, 0.12, 0.18) end
			ctx.wait(0.06)
		end
	end)

	-- 0.00 knee slide 6 studs back: dust + leaves spray, dark green trail, brief green flash
	local KNEEL = { Root = T(0, -1.05, 0), RightHip = R(-15), RightKnee = R(-95), RightAnkle = R(35), LeftHip = R(85), LeftKnee = R(-85), LeftAnkle = R(0) }
	local function kneel(base, extra) local p = table.clone(base or {}); for j, v in KNEEL do p[j] = v end; for j, v in extra or {} do p[j] = v end; return p end
	Fx.HitFlash(ctx.model, C1, 0.25)
	if knee then Fx.Trail(knee, C4, 0.35, 0.7); Fx.Trail(knee, C1, 0.3, 0.25) end
	task.spawn(ctx.moveTo, start - f * 6, 0.28)
	task.spawn(function() for _ = 1, 5 do local kp = knee and knee.Parent and knee.Position or ctx.ground()
		Fx.Particles(kp, { color = "#b9a888", count = 4, speed = 7, size = 0.5, lifetime = 0.4, spread = 50 }); Fx.Particles(kp, { color = C1, count = 2, speed = 6, size = 0.3, lifetime = 0.5, gravity = 6 })
		ctx.wait(0.055) end end)
	ctx.pose(kneel(nil, { Root = T(0, -1.05, 0, -8), Waist = R(8), LeftShoulder = R(35, 0, -40), LeftElbow = R(15), RightShoulder = R(-20, 0, 55), RightElbow = R(25) }), to(0.14), "snap")
	at(0.3)
	-- 0.30 full draw on one knee, bow canted, crystal arrow forming on the string, cyan light brightening
	local draw = kneel(P.bowDraw); draw.LeftWrist = (P.bowDraw.LeftWrist or CFrame.new()) * R(0, 30, 0)
	Fx.Light(ctx.myPos() + f * 2, C3, 10, 1.5, 0.5); task.delay(0.25, function() Fx.Light(tipPos, C3, 14, 3, 0.75) end)
	ctx.pose(draw, to(0.6), "out")
	at(0.8)
	-- 0.80 dead still at full draw: a jagged rift tears open 3 studs ahead of the bow
	r1c = (lh and lh.Parent and lh.Position or ctx.myPos()) + f * 3
	ctx.flash(C2, 0.2, 0.2); Fx.Light(r1c, C2, 12, 3, 0.9); Fx.Burst(tipPos, C3, 1.6, 0.2)
	at(1.0)
	-- 1.00 release: the arrow streaks into the rift; violet ring at the bow, green sparks off the string
	fired = true
	for _, p in { shaft, head[1], head[2] } do fade(p, 0.07, { CFrame = p.CFrame + dir * 5 }) end
	for _, p in shards do p.Transparency = 1 end
	local bow = lh and lh.Parent and lh.Position or ctx.myPos() + f
	Fx.Ring(CFrame.lookAt(bow, bow + f) * CFrame.Angles(math.rad(90), 0, 0), C2, 1, 6, 0.3, 0.25)
	if rh then Fx.Burst(rh.Position, C2, 1.4, 0.15); Fx.Particles(rh.Position, { color = C1, count = 14, speed = 14, size = 0.3, lifetime = 0.35, light = 1 }) end
	task.delay(0.06, function() Fx.Burst(r1c, C2, 3, 0.25, { transparency = 0.3 }) end)
	local rel = kneel(P.bowRelease); rel.Waist = (P.bowRelease.Waist or CFrame.new()) * R(10)
	ctx.pose(rel, to(1.05), "snap")
	at(1.15)
	-- 1.15 eyes to the sky: a second rift splits open above the enemy and the lance drops through it
	rel.Neck = (P.bowRelease.Neck or CFrame.new()) * R(35)
	Fx.Light(ctx.targetPos() + UP * 10, C2, 18, 4, 0.6)
	ctx.pose(rel, to(1.3), "out")
	at(1.42)
	-- 1.42 stand, flick the bow, spin it once and sling it over the shoulder as both rifts zip shut
	task.spawn(ctx.moveTo, start, 0.35, 0.6)
	local stand = { Waist = R(0, -10, 0), Neck = R(5), LeftShoulder = R(75, 0, -25), LeftElbow = R(10), RightShoulder = R(10, 0, 15), RightElbow = R(20) }
	ctx.pose(stand, to(1.55), "back")
	for i = 1, 3 do stand.LeftWrist = R(120 * i, 0, 0); ctx.pose(stand, to(1.55 + i * 0.05), "linear") end
	stand.LeftShoulder, stand.LeftElbow, stand.LeftWrist, stand.Neck = R(160, 0, -15), R(115), R(0), R(5, 15, 0)
	ctx.pose(stand, to(1.82), "out")
	ctx.pose(P.guard, 0.2)
end