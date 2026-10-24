-- Movement (client): dash, multi-jump and the AFK rejoin helper.
--   * Q (or the round DASH button on phones) = quick burst in the direction you're moving.
--     Charges come from the DashCharges attribute (upgrade in the Upgrades menu).
--   * Press jump again in the air for a double jump. JumpCount = total jumps (2 = double, 3 = triple).
--   * Sprint: hold Left Ctrl (keyboard) or click the left stick (controller). The SERVER sets the
--     speed (SettingsService: the Sprint Speed setting, or always with Auto-Sprint on); this only
--     tells it while the key is held (Remotes.SetSprint).
--   * AFK: Roblox kicks idle players after 20 minutes, so after 16 idle minutes we ask the
--     server (AfkRejoin) to rejoin us. The server keeps our world, spot and auto toggles.
-- Movement runs on the client because the player owns their character's physics,
-- so velocity changes here replicate to everyone automatically.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Fx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Fx"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

-- tuning (feel free to tweak)
local DASH_SPEED = 66          -- studs per second during the burst
local DASH_TIME = 0.18         -- seconds the burst lasts
local DASH_RECHARGE = 1.6      -- seconds to get one charge back
local AIR_JUMP_BOOST = 1.08    -- extra jumps are a little stronger than a normal jump
local AFK_SECONDS = 16 * 60    -- rejoin before Roblox's 20-minute idle kick

local DASH_COLOR = Color3.fromRGB(110, 220, 255)
local PANEL = Color3.fromRGB(24, 26, 44)
local STROKE = Color3.fromRGB(10, 10, 20)
local FONT = Enum.Font.FredokaOne

----------------------------------------------------------------------------
-- character state
----------------------------------------------------------------------------
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local trail: Trail? = nil

local charges = 1
local rechargeTimer = 0
local dashing = false
local airJumpsUsed = 0
local lastJumpTime = 0
local lastJumpRequest = 0

local function maxCharges(): number
	return math.max(1, math.floor(tonumber(player:GetAttribute("DashCharges")) or 1))
end
local function maxJumps(): number
	return math.max(1, math.floor(tonumber(player:GetAttribute("JumpCount")) or 2))
end

-- Dead, sitting or ragdolled characters shouldn't dash or air-jump.
local BLOCKED_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
}
local function canMove(): boolean
	local hum = humanoid
	if not hum or not root or not root.Parent or hum.Health <= 0 or hum.Sit then return false end
	if root.Anchored then return false end -- cutscenes / teleports anchor the root
	return not BLOCKED_STATES[hum:GetState()]
end
local function isAirborne(): boolean
	local hum = humanoid
	if not hum then return false end
	local s = hum:GetState()
	return hum.FloorMaterial == Enum.Material.Air and (s == Enum.HumanoidStateType.Freefall or s == Enum.HumanoidStateType.Jumping)
end

local function onCharacter(c: Model)
	character = c
	humanoid = c:WaitForChild("Humanoid", 10) :: Humanoid?
	root = c:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	dashing = false
	airJumpsUsed = 0
	charges = maxCharges()
	rechargeTimer = 0
	if not humanoid or not root then return end
	-- the dash trail lives on the root and is only switched on while dashing
	local a0 = Instance.new("Attachment"); a0.Name = "DashTrailTop"; a0.Position = Vector3.new(0, 1.1, 0); a0.Parent = root
	local a1 = Instance.new("Attachment"); a1.Name = "DashTrailBottom"; a1.Position = Vector3.new(0, -1.1, 0); a1.Parent = root
	local tr = Instance.new("Trail")
	tr.Name = "DashTrail"
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.25
	tr.LightEmission = 1
	tr.FaceCamera = true
	tr.Color = ColorSequence.new(Color3.new(1, 1, 1), DASH_COLOR)
	tr.Transparency = NumberSequence.new(0.25, 1)
	tr.Enabled = false
	tr.Parent = root
	trail = tr
	-- landing gives the extra jumps back
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running
			or new == Enum.HumanoidStateType.Swimming or new == Enum.HumanoidStateType.Climbing then
			airJumpsUsed = 0
		end
		if new == Enum.HumanoidStateType.Jumping then lastJumpTime = os.clock() end
	end)
end
if player.Character then task.spawn(onCharacter, player.Character) end
player.CharacterAdded:Connect(onCharacter)

----------------------------------------------------------------------------
-- effects
----------------------------------------------------------------------------
local fxFolder = workspace:FindFirstChild("ClientEffects") or workspace

-- A see-through neon copy of the character that fades away (the "afterimage").
local function afterimage()
	local c = character
	if not c then return end
	for _, d in c:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 then
			local ok, ghost = pcall(function() return d:Clone() end)
			if ok and ghost then
				ghost:ClearAllChildren() -- drop joints, welds, scripts, decals
				ghost.Anchored = true
				ghost.CanCollide = false
				ghost.CanQuery = false
				ghost.CanTouch = false
				ghost.CastShadow = false
				ghost.Massless = true
				ghost.Material = Enum.Material.Neon
				ghost.Color = DASH_COLOR
				ghost.Transparency = 0.55
				if ghost:IsA("MeshPart") then ghost.TextureID = "" end
				ghost.CFrame = d.CFrame
				ghost.Parent = fxFolder
				TweenService:Create(ghost, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				Debris:AddItem(ghost, 0.35)
			end
		end
	end
end

local function feetPosition(): Vector3?
	local r, hum = root, humanoid
	if not r or not hum then return nil end
	return r.Position - Vector3.new(0, r.Size.Y / 2 + hum.HipHeight, 0)
end

-- small white puff under your feet (air jumps)
local function puff()
	local feet = feetPosition()
	if not feet then return end
	pcall(function()
		Fx.Ring(CFrame.new(feet + Vector3.new(0, 0.3, 0)), Color3.new(1, 1, 1), 1.5, 7, 0.3, 0.15)
		Fx.Particles(feet + Vector3.new(0, 0.4, 0), { color = Color3.fromRGB(235, 245, 255), count = 10, speed = 9, size = 0.45, lifetime = 0.4, spread = 70, gravity = 10 })
	end)
end

----------------------------------------------------------------------------
-- dash
----------------------------------------------------------------------------
local refreshDashButton: () -> () = function() end -- set by the touch button below

local function dash()
	if dashing or charges <= 0 or not canMove() then return end
	local r, hum = root :: BasePart, humanoid :: Humanoid
	-- dash where you're walking; standing still = dash the way you're facing
	local dir = hum.MoveDirection * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.1 then dir = r.CFrame.LookVector * Vector3.new(1, 0, 1) end
	if dir.Magnitude < 0.01 then return end
	dir = dir.Unit

	charges -= 1
	dashing = true
	refreshDashButton()
	if trail then trail.Enabled = true end
	pcall(function()
		Fx.Ring(CFrame.lookAt(r.Position, r.Position + dir) * CFrame.Angles(math.rad(90), 0, 0), DASH_COLOR, 2, 6, 0.25, 0.15)
	end)

	local start = os.clock()
	local lastGhost = 0
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - start
		if elapsed >= DASH_TIME or not canMove() then
			conn:Disconnect()
			dashing = false
			if trail then task.delay(0.12, function() if not dashing and trail then trail.Enabled = false end end) end
			-- ease out to walking speed so you don't slide across the map
			if r.Parent then
				local v = r.AssemblyLinearVelocity
				local keep = dir * hum.WalkSpeed
				r.AssemblyLinearVelocity = Vector3.new(keep.X, math.min(v.Y, 20), keep.Z)
			end
			return
		end
		-- keep the burst flat: override sideways speed, keep (but soften) falling
		local v = r.AssemblyLinearVelocity
		r.AssemblyLinearVelocity = Vector3.new(dir.X * DASH_SPEED, math.max(v.Y, -8), dir.Z * DASH_SPEED)
		if elapsed - lastGhost >= 0.05 then
			lastGhost = elapsed
			afterimage()
		end
	end)
end

-- charges come back one at a time
RunService.Heartbeat:Connect(function(dt)
	local cap = maxCharges()
	if charges > cap then charges = cap end
	if charges < cap then
		rechargeTimer += dt
		if rechargeTimer >= DASH_RECHARGE then
			rechargeTimer = 0
			charges += 1
		end
	else
		rechargeTimer = 0
	end
	refreshDashButton()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end -- typing in chat / a TextBox
	-- Q on a keyboard, RT / R2 on a controller (X / Square is the interact button: every
	-- proximity prompt uses it, so a dash there would fire whenever you talk or summon)
	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonR2 then dash() end
end)

----------------------------------------------------------------------------
-- sprint (hold)
----------------------------------------------------------------------------
local SPRINT_KEYS = { [Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.ButtonL3] = true }
local sprintHeld = false
local function setSprint(on: boolean)
	if on == sprintHeld then return end
	sprintHeld = on
	local remote = Remotes:FindFirstChild("SetSprint")
	if remote and remote:IsA("RemoteEvent") then remote:FireServer(on) end
end
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if SPRINT_KEYS[input.KeyCode] then setSprint(true) end
end)
UserInputService.InputEnded:Connect(function(input)
	if SPRINT_KEYS[input.KeyCode] then setSprint(false) end
end)
-- (a key let go while the game window wasn't focused never sends InputEnded)
UserInputService.WindowFocusReleased:Connect(function() setSprint(false) end)

----------------------------------------------------------------------------
-- multi-jump
----------------------------------------------------------------------------
UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	-- JumpRequest repeats every frame while jump is held; only count fresh presses
	local fresh = now - lastJumpRequest > 0.12
	lastJumpRequest = now
	if not fresh or not canMove() or not isAirborne() then return end
	if now - lastJumpTime < 0.18 then return end -- the ground jump just happened
	if airJumpsUsed >= maxJumps() - 1 then return end
	local r, hum = root :: BasePart, humanoid :: Humanoid
	airJumpsUsed += 1
	lastJumpTime = now
	local up = if hum.UseJumpPower then hum.JumpPower else math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
	local v = r.AssemblyLinearVelocity
	r.AssemblyLinearVelocity = Vector3.new(v.X, up * AIR_JUMP_BOOST, v.Z)
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	puff()
end)

----------------------------------------------------------------------------
-- UI: round DASH button (touch) + small toast
----------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MovementUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 2
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner"); c.CornerRadius = radius; c.Parent = parent
end
local function stroke(parent: Instance, thickness: number, color: Color3)
	local s = Instance.new("UIStroke"); s.Thickness = thickness; s.Color = color
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = parent
	return s
end
local function textStroke(parent: Instance)
	local s = Instance.new("UIStroke"); s.Thickness = 2; s.Color = STROKE; s.Parent = parent
end

local dashButton = Instance.new("TextButton")
dashButton.Name = "DashButton"
dashButton.Text = ""
dashButton.AutoButtonColor = true
dashButton.BackgroundColor3 = PANEL
dashButton.AnchorPoint = Vector2.new(0.5, 1)
dashButton.Size = UDim2.fromOffset(70, 70)
dashButton.Position = UDim2.new(1, -60, 1, -170)
dashButton.Visible = false
dashButton.Parent = gui
corner(dashButton, UDim.new(1, 0))
local dashStroke = stroke(dashButton, 4, DASH_COLOR)
local grad = Instance.new("UIGradient")
grad.Rotation = 90
grad.Color = ColorSequence.new(Color3.fromRGB(70, 90, 140), Color3.fromRGB(20, 22, 40))
grad.Parent = dashButton

local dashIcon = Instance.new("TextLabel")
dashIcon.BackgroundTransparency = 1
dashIcon.Font = FONT
dashIcon.TextScaled = true
dashIcon.TextColor3 = Color3.new(1, 1, 1)
dashIcon.Text = "💨"
dashIcon.Size = UDim2.fromScale(0.55, 0.5)
dashIcon.Position = UDim2.fromScale(0.225, 0.1)
dashIcon.Parent = dashButton

local dashText = Instance.new("TextLabel")
dashText.BackgroundTransparency = 1
dashText.Font = FONT
dashText.TextScaled = true
dashText.TextColor3 = DASH_COLOR
dashText.Text = "DASH"
dashText.Size = UDim2.fromScale(0.8, 0.24)
dashText.Position = UDim2.fromScale(0.1, 0.62)
dashText.Parent = dashButton
textStroke(dashText)

-- charge counter bubble (only shown when you have more than one charge)
local countBubble = Instance.new("Frame")
countBubble.BackgroundColor3 = DASH_COLOR
countBubble.AnchorPoint = Vector2.new(0.5, 0.5)
countBubble.Position = UDim2.fromScale(0.88, 0.12)
countBubble.Size = UDim2.fromScale(0.36, 0.36)
countBubble.Parent = dashButton
corner(countBubble, UDim.new(1, 0))
stroke(countBubble, 2, STROKE)
local countText = Instance.new("TextLabel")
countText.BackgroundTransparency = 1
countText.Font = FONT
countText.TextScaled = true
countText.TextColor3 = Color3.new(1, 1, 1)
countText.Size = UDim2.fromScale(0.8, 0.8)
countText.Position = UDim2.fromScale(0.1, 0.1)
countText.Parent = countBubble
textStroke(countText)

-- recharge bar under the button
local barBack = Instance.new("Frame")
barBack.BackgroundColor3 = STROKE
barBack.AnchorPoint = Vector2.new(0.5, 0)
barBack.Position = UDim2.new(0.5, 0, 1, 4)
barBack.Size = UDim2.new(0.8, 0, 0, 6)
barBack.Parent = dashButton
corner(barBack, UDim.new(1, 0))
local barFill = Instance.new("Frame")
barFill.BackgroundColor3 = DASH_COLOR
barFill.Size = UDim2.fromScale(1, 1)
barFill.Parent = barBack
corner(barFill, UDim.new(1, 0))

dashButton.Activated:Connect(function()
	local sc = dashButton:FindFirstChild("ClickScale") :: UIScale?
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = "ClickScale"
		sc.Parent = dashButton
	end
	local scale = sc :: UIScale
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	dash()
end)

refreshDashButton = function()
	local cap = maxCharges()
	local ready = charges > 0
	dashButton.BackgroundTransparency = if ready then 0 else 0.35
	dashIcon.TextTransparency = if ready then 0 else 0.5
	dashStroke.Color = if ready then DASH_COLOR else Color3.fromRGB(90, 95, 120)
	countBubble.Visible = cap > 1
	countText.Text = tostring(charges)
	barBack.Visible = charges < cap
	barFill.Size = UDim2.fromScale(math.clamp(rechargeTimer / DASH_RECHARGE, 0, 1), 1)
end

-- Sit the DASH button right above Roblox's touch jump button (its size and spot
-- change with screen size), or use a sensible bottom-right spot if it isn't there.
local function placeDashButton()
	local last = UserInputService:GetLastInputType()
	local touch = last == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	dashButton.Visible = touch
	if not touch then return end
	local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
	local jump = touchGui and touchGui:FindFirstChild("JumpButton", true) :: GuiObject?
	if touchGui and jump and jump.AbsoluteSize.X > 0 then
		gui.IgnoreGuiInset = (touchGui :: ScreenGui).IgnoreGuiInset -- same coordinate space as the jump button
		local size = math.floor(jump.AbsoluteSize.X * 0.78)
		dashButton.Size = UDim2.fromOffset(size, size)
		dashButton.Position = UDim2.fromOffset(jump.AbsolutePosition.X + jump.AbsoluteSize.X / 2, jump.AbsolutePosition.Y - 14)
	else
		dashButton.Size = UDim2.fromOffset(70, 70)
		dashButton.Position = UDim2.new(1, -60, 1, -170)
	end
end
task.spawn(function()
	while true do
		placeDashButton()
		task.wait(1)
	end
end)
UserInputService.LastInputTypeChanged:Connect(placeDashButton)

local function toast(text: string)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = PANEL
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 150)
	f.Size = UDim2.fromOffset(520, 48)
	f.Parent = gui
	corner(f, UDim.new(0, 14))
	stroke(f, 3, DASH_COLOR)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.Size = UDim2.new(1, -24, 1, -12)
	l.Position = UDim2.fromOffset(12, 6)
	l.Parent = f
	textStroke(l)
	local sc = Instance.new("UIScale"); sc.Scale = 0.6; sc.Parent = f
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Debris:AddItem(f, 6)
end

----------------------------------------------------------------------------
-- AFK rejoin
----------------------------------------------------------------------------
-- Idled fires after ~2 idle minutes (and again later) with how long we've been idle.
-- We remember when idling started and check the clock ourselves, so we never miss 16 min.
local idleSince: number? = nil
local rejoinSentAt: number? = nil
player.Idled:Connect(function(idleTime: number)
	idleSince = os.clock() - (tonumber(idleTime) or 0)
end)
local function active() idleSince = nil end
UserInputService.InputBegan:Connect(active)
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then active() end
end)

task.spawn(function()
	while true do
		task.wait(5)
		-- if a rejoin failed (e.g. in Studio) allow another try after 90 seconds
		if rejoinSentAt and os.clock() - rejoinSentAt > 90 then rejoinSentAt = nil end
		if idleSince and not rejoinSentAt and os.clock() - idleSince >= AFK_SECONDS then
			local remote = Remotes:FindFirstChild("AfkRejoin")
			if remote and remote:IsA("RemoteEvent") then
				rejoinSentAt = os.clock()
				toast("Reconnecting so you can keep AFK farming...")
				remote:FireServer()
			end
		end
	end
end)
