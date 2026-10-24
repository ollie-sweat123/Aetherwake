-- NpcAnimator (client): idle life for the NPC rigs: Sensei Hikari in Champion City and
-- her holograms in every world (any model with a QuestGiver attribute, plus any model
-- given an `Npc` attribute later). Purely visual, and only on this client:
--   * breathing and a slow weight shift, and the odd look around while nobody's near
--   * her head follows you within ~20 studs; closer than ~14 she turns to face you
--   * a short wave the first time you walk up, or when QuestClient asks for one
--     (it sets the "WaveAt" attribute during the welcome camera pan)
--   * while the quest dialogue is open she faces you and nods along (QuestClient sets
--     "Talking" on her model, and "Speaking" while the words are typing out)
--   * holograms bob gently in the air
-- QuestClient no longer poses her, so the two scripts never fight over the rig.
-- One RenderStepped loop; NPCs more than 120 studs from you and the camera are skipped.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anim = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Anim"))
local R, T = Anim.R, Anim.T
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local RANGE = 120       -- animate NPCs this close to you or the camera (studs)
local LOOK_RANGE = 20   -- her head follows you inside this
local TURN_RANGE = 14   -- inside this she turns to face you (and waves hello)
local REARM_RANGE = 26  -- walk this far away and she'll wave again next time
local WAVE_TIME = 1.8   -- seconds

type Npc = {
	holder: Model, model: Model, root: BasePart, rig: any, holo: boolean, seed: number,
	baseCf: CFrame, bodyYaw: number, baseYaw: number, headHeight: number,
	waveAt: number, waveArmed: boolean,
	lookYaw: number, lookPitch: number,
	glanceYaw: number, glancePitch: number, glanceUntil: number, nextGlance: number,
}
local npcs: { Npc } = {}

-- frame-rate independent smoothing: the fraction to move this frame at `rate` per second
local function smooth(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end
-- turn from angle a toward angle b by fraction k, the short way round
local function turnToward(a: number, b: number, k: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * k
end

-- the animated body: the model itself, or the first model inside it with a HumanoidRootPart
local function bodyOf(holder: Model): Model?
	if holder:FindFirstChild("HumanoidRootPart") then return holder end
	for _, d in holder:GetDescendants() do
		if d:IsA("Model") and d:FindFirstChild("HumanoidRootPart") then return d end
	end
	return nil
end

local function add(holder: Model)
	for _, n in npcs do
		if n.holder == holder then return end
	end
	-- (streaming may still be sending her parts: give it a few seconds)
	local model: Model? = nil
	for _ = 1, 25 do
		model = bodyOf(holder)
		if model then break end
		task.wait(0.2)
	end
	if not model then return end
	local root = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then return end
	local head = model:FindFirstChild("Head") :: BasePart?
	local _, yaw = root.CFrame:ToOrientation()
	local now = os.clock()
	local n: Npc = {
		holder = holder, model = model, root = root, rig = Anim.Rig(model), seed = math.random() * 20,
		holo = holder:GetAttribute("Hologram") == true or model:GetAttribute("Hologram") == true,
		baseCf = root.CFrame, bodyYaw = yaw, baseYaw = yaw,
		headHeight = if head then head.Position.Y - root.Position.Y else 1.6,
		waveAt = -math.huge, waveArmed = true,
		lookYaw = 0, lookPitch = 0,
		glanceYaw = 0, glancePitch = 0, glanceUntil = 0, nextGlance = now + 2 + math.random() * 4,
	}
	-- QuestClient asks for a wave (e.g. "Someone wants to meet you..." on your first visit)
	model:GetAttributeChangedSignal("WaveAt"):Connect(function() n.waveAt = os.clock() end)
	table.insert(npcs, n)
end

local function isNpc(d: Instance): boolean
	return d:IsA("Model") and (d:GetAttribute("QuestGiver") ~= nil or d:GetAttribute("Npc") == true)
end
local worlds = workspace:WaitForChild("Worlds")
for _, d in worlds:GetDescendants() do
	if isNpc(d) then task.spawn(add, d) end
end
worlds.DescendantAdded:Connect(function(d)
	if isNpc(d) then task.spawn(add, d) end
end)

local myRoot: BasePart? = nil
local function onCharacter(c: Model) myRoot = c:WaitForChild("HumanoidRootPart", 10) :: BasePart? end
if player.Character then task.spawn(onCharacter, player.Character) end
player.CharacterAdded:Connect(onCharacter)

----------------------------------------------------------------------------
-- one NPC, one frame
----------------------------------------------------------------------------
local function animateNpc(n: Npc, now: number, dt: number, me: BasePart?, flat: Vector3, dist: number)
	local t = now + n.seed
	local talking = n.model:GetAttribute("Talking") == true
	local speaking = talking and n.model:GetAttribute("Speaking") == true

	-- wave hello the first time you walk up (and again after you've gone away)
	if dist < TURN_RANGE and n.waveArmed and not talking then
		n.waveArmed = false
		n.waveAt = now
	elseif dist > REARM_RANGE then
		n.waveArmed = true
	end

	-- base: breathing (Anim.Idle) + a slow weight shift from foot to foot
	local pose = Anim.Idle(t)
	local shift = math.sin(t * 0.55)
	pose.Root = T(shift * 0.06, math.sin(t * 2.2) * 0.04 - math.abs(shift) * 0.02, 0, 0, 0, shift * 1.5)
	pose.RightHip = R(0, 0, -shift * 1.5)
	pose.LeftHip = R(0, 0, -shift * 1.5)
	pose.RightKnee = R(-3 - math.max(0, shift) * 6)
	pose.LeftKnee = R(-3 - math.max(0, -shift) * 6)

	-- where to look: at you when you're close (or talking to her), otherwise a glance
	-- around now and then
	local wantYaw, wantPitch = 0, 0
	local wantBody = n.baseYaw
	local close = me ~= nil and (dist < TURN_RANGE or talking)
	if me and (dist < LOOK_RANGE or talking) then
		if close and dist > 0.5 then wantBody = math.atan2(-flat.X, -flat.Z) end
		-- the head takes what's left of the turn, measured from where the body faces now
		local body = CFrame.new(n.root.Position) * CFrame.Angles(0, n.bodyYaw, 0)
		local v = body:PointToObjectSpace(me.Position + Vector3.new(0, 1.5, 0))
		wantYaw = math.clamp(math.atan2(-v.X, -v.Z), -1.2, 1.2)
		wantPitch = math.clamp(math.atan2(v.Y - n.headHeight, math.sqrt(v.X * v.X + v.Z * v.Z)), -0.35, 0.3)
	elseif now < n.glanceUntil then
		wantYaw, wantPitch = n.glanceYaw, n.glancePitch
	elseif now > n.nextGlance then
		n.glanceYaw = math.rad(math.random(-50, 50))
		n.glancePitch = math.rad(math.random(-6, 8))
		n.glanceUntil = now + 1.2 + math.random() * 1.2
		n.nextGlance = n.glanceUntil + 3 + math.random() * 5
	end
	n.lookYaw += (wantYaw - n.lookYaw) * smooth(6, dt)
	n.lookPitch += (wantPitch - n.lookPitch) * smooth(6, dt)
	n.bodyYaw = turnToward(n.bodyYaw, wantBody, smooth(if close then 5 else 1.5, dt))
	-- the turn is shared: a little in the waist, most in the neck
	pose.Waist = (pose.Waist :: CFrame) * CFrame.Angles(0, n.lookYaw * 0.3, 0)
	pose.Neck = CFrame.fromEulerAnglesYXZ(n.lookPitch, n.lookYaw * 0.7, 0) * R(-math.sin(t * 2.2) * 1.5)

	if talking then
		-- nod along while the words type out, then a slow nod now and then while you read
		local nod = if speaking then math.abs(math.sin(t * 6)) * 7 else (math.max(0, math.sin(t * 2.2)) ^ 6) * 9
		pose.Neck = (pose.Neck :: CFrame) * R(-nod)
		if speaking then
			-- explaining with her free hand (the right one holds her staff)
			pose.LeftShoulder = R(28 + math.sin(t * 3) * 10, 0, -14)
			pose.LeftElbow = R(65 + math.sin(t * 3 + 1) * 12)
		end
	end

	-- the wave, with her free (left) hand
	local wu = now - n.waveAt
	if wu < WAVE_TIME then
		local w = math.min(1, wu / 0.25) * math.min(1, (WAVE_TIME - wu) / 0.35)
		pose.LeftShoulder = (pose.LeftShoulder :: CFrame):Lerp(R(0, 0, -145 - math.sin(t * 9) * 14), w)
		pose.LeftElbow = (pose.LeftElbow :: CFrame):Lerp(R(20 + math.sin(t * 9 + 1) * 20), w)
		pose.Neck = (pose.Neck :: CFrame):Lerp((pose.Neck :: CFrame) * R(6, 0, -6), w) -- a friendly head tilt
	end

	-- holograms bob; the body turn is the root's yaw (her root is anchored, nothing else moves it)
	local bob = if n.holo then math.sin(t * 1.6) * 0.25 else 0
	n.root.CFrame = CFrame.new(n.baseCf.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, n.bodyYaw, 0)
	Anim.Blend(n.rig, pose, smooth(10, dt))
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local me = myRoot
	if me and not me.Parent then me = nil end
	local camPos = camera.CFrame.Position
	for i = #npcs, 1, -1 do
		local n = npcs[i]
		if not n.root:IsDescendantOf(workspace) then
			table.remove(npcs, i) -- streamed out (it's added again when it streams back in)
			continue
		end
		local basePos = n.baseCf.Position
		local flat = if me then (me.Position - basePos) * Vector3.new(1, 0, 1) else Vector3.zero
		local dist = if me then flat.Magnitude else math.huge
		if math.min(dist, (camPos - basePos).Magnitude) <= RANGE then
			animateNpc(n, now, dt, me, flat, dist)
		end
	end
end)
