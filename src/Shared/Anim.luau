--!strict
-- Anim: procedural animation for R15 rigs that use Motor6D joints.
-- We never upload animations: every pose is a table of joint rotations and
-- clips are keyframes we blend between in code. This runs on the CLIENT only.
--
-- Joint axes (relative to the parent part):
--   +X rotation on a Shoulder/Hip  = swing the limb FORWARD
--   +Z rotation on RightShoulder   = raise the right arm OUT to the side (use -Z for the left)
--   +X rotation on an Elbow        = bend the forearm forward
--   -X rotation on a Knee          = bend the knee
--   Waist Y rotation = twist, Waist -X = lean forward
--   Root (HRP -> LowerTorso) also takes translations: CFrame.new(0, -0.6, 0) = crouch

local Anim = {}

Anim.JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }

-- R(x, y, z) in DEGREES -> CFrame rotation; T(x, y, z) translation (+ optional rotation)
function Anim.R(x: number?, y: number?, z: number?): CFrame
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end
function Anim.T(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * Anim.R(rx, ry, rz)
end
local R, T = Anim.R, Anim.T

export type Rig = {
	model: Model,
	motors: { [string]: Motor6D },
	current: { [string]: CFrame },
}

function Anim.Rig(model: Model): Rig
	local motors = {}
	for _, m in model:GetDescendants() do
		if m:IsA("Motor6D") then motors[m.Name] = m end
	end
	local cur = {}
	for name in motors do cur[name] = CFrame.identity end
	return { model = model, motors = motors, current = cur }
end

-- Blend the rig toward a pose. alpha 1 = snap.
function Anim.Blend(rig: Rig, pose: { [string]: CFrame }, alpha: number)
	for name, m in rig.motors do
		local goal = pose[name] or CFrame.identity
		local cur = rig.current[name] or CFrame.identity
		local nxt = cur:Lerp(goal, alpha)
		rig.current[name] = nxt
		m.Transform = nxt
	end
end

-- Mix two poses (t = 0 -> a, t = 1 -> b)
function Anim.Mix(a: { [string]: CFrame }, b: { [string]: CFrame }, t: number): { [string]: CFrame }
	local out = {}
	for _, j in Anim.JOINTS do
		local ca, cb = a[j] or CFrame.identity, b[j] or CFrame.identity
		out[j] = ca:Lerp(cb, t)
	end
	return out
end

local EASE = {
	linear = function(t) return t end,
	out = function(t) return 1 - (1 - t) ^ 3 end,
	["in"] = function(t) return t ^ 3 end,
	inout = function(t) return t < 0.5 and 4 * t ^ 3 or 1 - (-2 * t + 2) ^ 3 / 2 end,
	back = function(t) local c = 1.70158; return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2 end,
	snap = function(t) return 1 - (1 - t) ^ 6 end,
}
Anim.EASE = EASE

-- Clip = { {t = seconds, pose = {...}, ease = "out"}, ... } sorted by t
function Anim.Sample(clip: { any }, time: number): { [string]: CFrame }
	if time <= clip[1].t then return clip[1].pose end
	for i = 1, #clip - 1 do
		local a, b = clip[i], clip[i + 1]
		if time <= b.t then
			local k = (time - a.t) / math.max(b.t - a.t, 1e-4)
			k = (EASE[b.ease or "out"] or EASE.out)(math.clamp(k, 0, 1))
			return Anim.Mix(a.pose, b.pose, k)
		end
	end
	return clip[#clip].pose
end

function Anim.Length(clip: { any }): number
	return clip[#clip].t
end

----------------------------------------------------------------------------
-- Pose library (everything relative to the default standing pose)
----------------------------------------------------------------------------
local P = {}
Anim.P = P
P.idle = {}
P.guard = { RightShoulder = R(35, 0, 10), RightElbow = R(70), LeftShoulder = R(35, 0, -10), LeftElbow = R(70), Waist = R(0, 10, 0),
	RightHip = R(10), LeftHip = R(-5), RightKnee = R(-15), LeftKnee = R(-10), Root = T(0, -0.15, 0) }
P.crouch = { Root = T(0, -0.7, 0, -10), RightHip = R(55), LeftHip = R(55), RightKnee = R(-80), LeftKnee = R(-80), RightAnkle = R(25), LeftAnkle = R(25),
	Waist = R(-15), RightShoulder = R(20, 0, 15), LeftShoulder = R(20, 0, -15), RightElbow = R(40), LeftElbow = R(40) }
P.jump = { Root = T(0, 0.3, 0), RightHip = R(40), RightKnee = R(-70), LeftHip = R(-15), LeftKnee = R(-30),
	RightShoulder = R(0, 0, 60), LeftShoulder = R(0, 0, -60) }
P.land = { Root = T(0, -0.45, 0, -12), RightHip = R(35), LeftHip = R(35), RightKnee = R(-55), LeftKnee = R(-55), RightShoulder = R(10, 0, 30), LeftShoulder = R(10, 0, -30) }
P.punchRWind = { Waist = R(0, 30, 0), RightShoulder = R(20, 0, 25), RightElbow = R(110), LeftShoulder = R(70, 0, -10), LeftElbow = R(40), Root = T(0, -0.1, 0.2), RightHip = R(-10), LeftHip = R(15), LeftKnee = R(-15) }
P.punchR = { Waist = R(-5, -35, 0), RightShoulder = R(95, -10, 5), RightElbow = R(0), LeftShoulder = R(20, 0, -20), LeftElbow = R(90), Root = T(0, -0.15, -0.6), RightHip = R(-20), LeftHip = R(25), LeftKnee = R(-25) }
P.punchLWind = { Waist = R(0, -30, 0), LeftShoulder = R(20, 0, -25), LeftElbow = R(110), RightShoulder = R(70, 0, 10), RightElbow = R(40), Root = T(0, -0.1, 0.2) }
P.punchL = { Waist = R(-5, 35, 0), LeftShoulder = R(95, 10, -5), LeftElbow = R(0), RightShoulder = R(20, 0, 20), RightElbow = R(90), Root = T(0, -0.15, -0.6), LeftHip = R(-20), RightHip = R(25), RightKnee = R(-25) }
P.kickWind = { Root = T(0, 0, 0.2, 5), RightHip = R(60), RightKnee = R(-100), LeftKnee = R(-15), RightShoulder = R(30, 0, 30), LeftShoulder = R(30, 0, -30) }
P.kick = { Root = T(0, 0.1, -0.3, -15), RightHip = R(100), RightKnee = R(0), LeftKnee = R(-10), Waist = R(15), RightShoulder = R(-20, 0, 40), LeftShoulder = R(40, 0, -40) }
P.slashWind = { Waist = R(0, 55, 0), RightShoulder = R(150, 0, 40), RightElbow = R(30), RightWrist = R(0, 0, 0), LeftShoulder = R(40, 0, -20), LeftElbow = R(60), Root = T(0, -0.15, 0.3), RightHip = R(-10), LeftHip = R(20), LeftKnee = R(-20) }
P.slash = { Waist = R(-10, -50, 0), RightShoulder = R(40, -30, -30), RightElbow = R(10), LeftShoulder = R(10, 0, -40), LeftElbow = R(40), Root = T(0, -0.3, -0.7), RightHip = R(-25), LeftHip = R(35), LeftKnee = R(-40), RightKnee = R(-10) }
P.overWind = { Waist = R(15, 0, 0), RightShoulder = R(170, 0, 10), RightElbow = R(40), LeftShoulder = R(170, 0, -10), LeftElbow = R(40), Root = T(0, 0, 0.3) }
P.overSlam = { Waist = R(-30, 0, 0), RightShoulder = R(60, 0, 5), RightElbow = R(5), LeftShoulder = R(60, 0, -5), LeftElbow = R(5), Root = T(0, -0.6, -0.5, -8),
	RightHip = R(40), LeftHip = R(40), RightKnee = R(-60), LeftKnee = R(-60) }
P.thrustWind = { Waist = R(0, 40, 0), RightShoulder = R(60, 0, 20), RightElbow = R(100), LeftShoulder = R(60, 0, -10), LeftElbow = R(60), Root = T(0, -0.2, 0.4) }
P.thrust = { Waist = R(-10, -20, 0), RightShoulder = R(90, 0, 0), RightElbow = R(0), LeftShoulder = R(80, 0, -10), LeftElbow = R(20), Root = T(0, -0.25, -1.0), RightHip = R(-20), LeftHip = R(40), LeftKnee = R(-40) }
P.castRaise = { RightShoulder = R(165, 0, 15), RightElbow = R(10), LeftShoulder = R(40, 0, -30), LeftElbow = R(50), Waist = R(10, 10, 0), Neck = R(15) }
P.castPoint = { RightShoulder = R(95, 0, 0), RightElbow = R(0), LeftShoulder = R(70, 0, -15), LeftElbow = R(30), Waist = R(-10, -15, 0), Root = T(0, -0.1, -0.3) }
P.bowDraw = { Waist = R(0, 70, 0), LeftShoulder = R(90, 0, 0), LeftElbow = R(0), RightShoulder = R(90, 0, 40), RightElbow = R(140), Neck = R(0, -60, 0), Root = T(0, -0.1, 0) }
P.bowRelease = { Waist = R(0, 70, 0), LeftShoulder = R(95, 0, 0), LeftElbow = R(0), RightShoulder = R(70, 0, 80), RightElbow = R(30), Neck = R(0, -60, 0), Root = T(0, -0.1, 0.15) }
P.clawWind = { RightShoulder = R(150, 0, 50), RightElbow = R(40), LeftShoulder = R(150, 0, -50), LeftElbow = R(40), Waist = R(10), Root = T(0, -0.2, 0.2) }
P.claw = { RightShoulder = R(40, 0, -20), RightElbow = R(20), LeftShoulder = R(40, 0, 20), LeftElbow = R(20), Waist = R(-25), Root = T(0, -0.4, -0.6), RightHip = R(30), LeftHip = R(30), RightKnee = R(-40), LeftKnee = R(-40) }
P.handsOnHips = { RightShoulder = R(0, 0, 35), RightElbow = R(110, 0, 0), LeftShoulder = R(0, 0, -35), LeftElbow = R(110, 0, 0), Neck = R(10) }
P.victory = { RightShoulder = R(170, 0, 20), RightElbow = R(0), LeftShoulder = R(0, 0, -30), Waist = R(5, 0, 0), Neck = R(15) }
P.spin = { Waist = R(0, 180, 0), RightShoulder = R(0, 0, 80), LeftShoulder = R(0, 0, -80) }

-- Walk/run cycle: phase in radians, speed 0..1
function Anim.Walk(phase: number, amount: number): { [string]: CFrame }
	local s = math.sin(phase) * amount
	local c = math.cos(phase) * amount
	return {
		RightHip = R(35 * s), LeftHip = R(-35 * s),
		RightKnee = R(-25 - 25 * math.max(0, -s)), LeftKnee = R(-25 - 25 * math.max(0, s)),
		RightShoulder = R(-30 * s, 0, 5), LeftShoulder = R(30 * s, 0, -5),
		RightElbow = R(25 * amount), LeftElbow = R(25 * amount),
		Root = T(0, math.abs(c) * 0.25 - 0.1 * amount, 0, -8 * amount),
		Waist = R(0, 6 * s, 0),
	}
end

-- Breathing idle: t = seconds
function Anim.Idle(t: number): { [string]: CFrame }
	local b = math.sin(t * 2.2)
	return {
		Root = T(0, b * 0.04, 0),
		Waist = R(b * 1.5, 0, 0),
		Neck = R(-b * 1.5, math.sin(t * 0.7) * 6, 0),
		RightShoulder = R(-b * 2, 0, 4 + b * 1.5), LeftShoulder = R(-b * 2, 0, -4 - b * 1.5),
		RightElbow = R(8), LeftElbow = R(8),
	}
end

return Anim
