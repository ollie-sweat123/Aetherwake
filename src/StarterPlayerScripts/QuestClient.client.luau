-- QuestClient (client): Sensei Hikari and the hands-on tutorial.
--   * talking to Sensei (dialogue box with typewriter text + camera close-up)
--   * "!" / "?" markers over Sensei and her holograms (her idle, wave, head turn and
--     dialogue nod are animated by NpcAnimator; this script only tells it when she talks)
--   * the TRAINING objective tracker (top left): step n/6, what to do now, progress
--   * the starter summon ceremony (pick 1 of 3)
--   * the tutorial GUIDE: a glowing trail on the ground, a bouncing arrow over
--     the target, a tapping hand on the exact thing to press, and camera pans
--     that SHOW the player what to do instead of telling them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Quests = require(Shared:WaitForChild("Quests"))
local Format = require(Shared:WaitForChild("Format"))
local Anim = require(Shared:WaitForChild("Anim"))
local Fx = require(Shared:WaitForChild("Fx"))
local AbilityInfo = require(Shared:WaitForChild("AbilityInfo"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Models = ReplicatedStorage:WaitForChild("ChampionModels")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local R, T = Anim.R, Anim.T

local GOLD = Color3.fromRGB(255, 205, 60)
local STROKE = Color3.fromRGB(10, 10, 20)
local CYAN = Color3.fromRGB(90, 220, 255)
local FONT = Enum.Font.FredokaOne
-- HUD palette: the dialogue and the objective tracker match the HUD's panels
local NAVY = Color3.fromRGB(16, 18, 42)      -- #10122A
local NAVY2 = Color3.fromRGB(34, 32, 78)     -- top of the panel gradients
local VIOLET = Color3.fromRGB(176, 107, 255) -- #B06BFF
local AQUA = Color3.fromRGB(92, 242, 255)    -- #5CF2FF
local SUBTEXT = Color3.fromRGB(190, 196, 235)
local PIP_OFF = Color3.fromRGB(60, 62, 100)

local STARTER_BLURB = {
	KaitoEmberfist = "A hot-headed brawler whose fists burn brighter with every hit.",
	RinTidecutter = "A calm swordswoman who cuts like the turning tide.",
	JunoGaleshot = "A sharp-eyed archer who rides the wind.",
}

----------------------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------------------
local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do if k ~= "Parent" then (inst :: any)[k] = v end end
	for _, c in children or {} do c.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function corner(r: number?) return new("UICorner", { CornerRadius = UDim.new(0, r or 12) }) end
local function stroke(t: number?, c: Color3?) return new("UIStroke", { Thickness = t or 3, Color = c or STROKE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function label(props: { [string]: any }): TextLabel
	local base = { BackgroundTransparency = 1, Font = FONT, TextColor3 = Color3.new(1, 1, 1), TextScaled = true }
	for k, v in props do base[k] = v end
	local l = new("TextLabel", base)
	new("UIStroke", { Thickness = 2, Color = STROKE, Parent = l })
	return l
end

local gui = new("ScreenGui", { Name = "QuestUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })
local canvas = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(1280, 720), Parent = gui })
local uiScale = new("UIScale", { Parent = canvas })
local function rescale()
	local vp = camera.ViewportSize
	local sc = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 2)
	uiScale.Scale = sc
	canvas.Size = UDim2.fromOffset(vp.X / sc, vp.Y / sc)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()
-- unscaled layer for the pointing hand (works in raw screen pixels)
local pointerLayer = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, Parent = gui })

-- Finds a HUD object by name (the guide asks every frame, so the answer is remembered
-- instead of searching the whole HUD each time; a miss is retried once a second).
local hudCache: { [string]: GuiObject } = {}
local hudMissAt: { [string]: number } = {}
local function hud(name: string): GuiObject?
	local cached = hudCache[name]
	if cached and cached:IsDescendantOf(player.PlayerGui) then return cached end
	hudCache[name] = nil
	local now = os.clock()
	if hudMissAt[name] and now - hudMissAt[name] < 1 then return nil end
	local h = player.PlayerGui:FindFirstChild("HUD")
	local found = h and h:FindFirstChild(name, true) :: GuiObject?
	if found then hudCache[name] = found; hudMissAt[name] = nil else hudMissAt[name] = now end
	return found
end

-- only one cinematic / conversation at a time
local busy = false
local function waitIdle()
	while busy do task.wait(0.05) end
end
local cleanup: () -> () = function() end -- set below (closes dialogs, gives the camera back)

-- Runs a cinematic/conversation. If anything inside errors, the camera and
-- controls are handed back instead of staying stuck.
local function guarded(fn: () -> ())
	busy = true
	local ok, err = pcall(fn)
	if not ok then
		warn("[QuestClient] " .. tostring(err))
		cleanup()
	end
	busy = false
end

----------------------------------------------------------------------------
-- quest givers (Sensei + holograms)
----------------------------------------------------------------------------
type Giver = { holder: Model, npc: Model, root: BasePart, marker: TextLabel, baseCf: CFrame, holo: boolean }
local givers: { Giver } = {}

local function addGiver(holder: Model)
	for _, g in givers do if g.holder == holder then return end end
	local npc = holder:WaitForChild("SenseiHikari", 5) :: Model?
	local root = npc and npc:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not npc or not root then return end
	local bb = new("BillboardGui", { Name = "QuestMarker", Size = UDim2.fromScale(2.4, 2.4), StudsOffsetWorldSpace = Vector3.new(0, (npc:GetAttribute("TopOffset") or 2.2) + 3.6, 0),
		MaxDistance = 200, LightInfluence = 0, Adornee = root, Parent = root })
	local marker = label({ Text = "!", Size = UDim2.fromScale(1, 1), TextColor3 = GOLD, Visible = false, Parent = bb })
	marker:FindFirstChildOfClass("UIStroke").Thickness = 4
	-- (only her position is used here: NpcAnimator turns her and bobs the holograms)
	table.insert(givers, { holder = holder, npc = npc, root = root, marker = marker, baseCf = root.CFrame,
		holo = holder:GetAttribute("Hologram") == true })
end
local worlds = workspace:WaitForChild("Worlds")
for _, d in worlds:GetDescendants() do
	if d:IsA("Model") and d:GetAttribute("QuestGiver") then task.spawn(addGiver, d) end
end
worlds.DescendantAdded:Connect(function(d)
	if d:IsA("Model") and d:GetAttribute("QuestGiver") then task.spawn(addGiver, d) end
end)

local function myRoot(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearestGiver(): Giver?
	local root = myRoot()
	if not root then return nil end
	local best, bd = nil, 900
	for _, g in givers do
		if g.root.Parent then
			local d = (g.baseCf.Position - root.Position).Magnitude
			if d < bd then best, bd = g, d end
		end
	end
	return best
end

local function questState(): (number, string, number, any)
	local i = player:GetAttribute("QuestIndex") or 1
	return i, player:GetAttribute("QuestState") or "offer", player:GetAttribute("QuestProgress") or 0, Quests.Get(i)
end

-- Quest markers bounce over Sensei. (Her idle, wave, head turn and dialogue nod live in
-- NpcAnimator, so the two scripts never pose the same rig.)
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local _, s, _, q = questState()
	for _, g in givers do
		-- marker: "!" = new quest to accept / graduation, "?" = reward waiting
		local show, text = false, "!"
		if q and (s == "offer" or q.kind == "starter") then show, text = true, "!"
		elseif q and s == "ready" then show, text = true, "?" end
		g.marker.Visible = show
		g.marker.Text = text
		g.marker.Position = UDim2.fromScale(0, math.sin(t * 4) * 0.12)
	end
end)

----------------------------------------------------------------------------
-- camera helpers
----------------------------------------------------------------------------
local savedCam: CFrame? = nil
local function camTo(cf: CFrame, time: number)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		savedCam = camera.CFrame
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local tw = TweenService:Create(camera, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = cf })
	tw:Play()
	return tw
end
local function camBack(time: number?)
	if camera.CameraType ~= Enum.CameraType.Scriptable then return end
	if savedCam and (time or 0) > 0 then
		local tw = TweenService:Create(camera, TweenInfo.new(time :: number, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = savedCam })
		tw:Play()
		tw.Completed:Wait()
	end
	camera.CameraType = Enum.CameraType.Custom
	savedCam = nil
end

-- Pan the camera over to something, hold, and come back ("look, it's over there!")
local function showPlace(pos: Vector3, hold: number?)
	local root = myRoot()
	if not root then return end
	local dir = (root.Position - pos) * Vector3.new(1, 0, 1)
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, 1)
	local side = dir:Cross(Vector3.yAxis)
	local camPos = pos + dir * 20 + side * 6 + Vector3.new(0, 10, 0)
	camTo(CFrame.lookAt(camPos, pos + Vector3.new(0, 2, 0)), 0.9).Completed:Wait()
	task.wait(hold or 1.4)
	camBack(0.7)
end

----------------------------------------------------------------------------
-- dialogue box
----------------------------------------------------------------------------
-- (styled like the HUD's panels: dark navy, a violet-to-cyan edge; the background is white
-- because a UIGradient multiplies it, so the gradient alone gives the navy colours)
-- (700 wide and nudged right so Sensei's portrait clears the HUD's menu grid on the left
-- and the box clears the multipliers bottom right)
local dialog = new("Frame", { Name = "Dialog", Visible = false, BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 100, 1, -128), Size = UDim2.fromOffset(700, 180), ZIndex = 10, Parent = canvas },
	{ corner(20), new("UIGradient", { Rotation = 90, Color = ColorSequence.new(NAVY2, NAVY) }), new("UIScale", { Name = "Pop" }) })
local dialogEdge = new("UIStroke", { Thickness = 3.5, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = dialog })
new("UIGradient", { Color = ColorSequence.new(VIOLET, AQUA), Parent = dialogEdge })
local portrait = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(-120, -40), Size = UDim2.fromOffset(170, 210),
	ZIndex = 11, Parent = dialog }, { corner(20), stroke(4, VIOLET),
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(150, 120, 235), Color3.fromRGB(44, 40, 104)) }) })
local portraitVp = new("ViewportFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12, Ambient = Color3.fromRGB(210, 210, 220),
	LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = portrait })
local nameTab = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(64, -24), Size = UDim2.fromOffset(240, 44), ZIndex = 12, Parent = dialog },
	{ corner(14), stroke(3), new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(200, 150, 255), Color3.fromRGB(140, 80, 225)) }) })
local nameText = label({ Text = Quests.GiverName, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), ZIndex = 13, Parent = nameTab })
-- (TextSize 30 at 1280x720 stays readable once the UI is scaled down on a phone)
local bodyText = label({ Text = "", TextScaled = false, TextSize = 30, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(70, 36), Size = UDim2.new(1, -100, 1, -78), ZIndex = 12, Parent = dialog })
-- bottom corners: how to continue, and which line of how many
local nextHint = label({ Text = "Tap to continue  \u{25B6}", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -10), Size = UDim2.fromOffset(240, 26),
	TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = AQUA, ZIndex = 12, Parent = dialog })
local lineCount = label({ Text = "", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 70, 1, -10), Size = UDim2.fromOffset(90, 24),
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = SUBTEXT, ZIndex = 12, Parent = dialog })
-- (Selectable = false: a controller continues with A, it should never land on this catcher)
local clickCatcher = new("TextButton", { Text = "", BackgroundTransparency = 1, Selectable = false, Size = UDim2.new(1, 120, 1, 60), Position = UDim2.fromOffset(-120, -40),
	ZIndex = 20, Parent = dialog })
-- the controller's confirm button (A on Xbox, Cross on PlayStation: Roblox picks the right picture)
local padIcon = new("ImageLabel", { Name = "PadIcon", BackgroundTransparency = 1, Visible = false, AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -150, 1, -8), Size = UDim2.fromOffset(30, 30), ZIndex = 13, Parent = dialog })
pcall(function() padIcon.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA) end)

local advance = Instance.new("BindableEvent")
clickCatcher.Activated:Connect(function() advance:Fire() end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not dialog.Visible then return end
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.ButtonA then
		advance:Fire()
	end
end)

-- A clean copy of Sensei for the portrait. The real (non-hologram) Sensei is
-- in Champion City, which may not be loaded while you're in another world,
-- so the first copy we see is kept.
local portraitSource: Model? = nil
local function cleanCopy(npc: Model): Model
	local m = npc:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BillboardGui") or d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Highlight") then
			d:Destroy()
		elseif d:IsA("BasePart") and d.Material == Enum.Material.ForceField then
			-- (ForceField parts don't render inside ViewportFrames)
			d.Material = Enum.Material.SmoothPlastic
		end
	end
	return m
end
local function setPortrait(hologram: boolean)
	portraitVp:ClearAllChildren()
	if not portraitSource then
		for _, g in givers do
			if not g.holo and g.npc.Parent then portraitSource = cleanCopy(g.npc) break end
		end
	end
	local m: Model
	if portraitSource then
		m = portraitSource:Clone()
	elseif givers[1] then
		m = cleanCopy(givers[1].npc)
	else
		return
	end
	m:PivotTo(CFrame.new(0, 0, 0))
	m.Parent = portraitVp
	local head = m:FindFirstChild("AnimeHead") or m:FindFirstChild("Head")
	local hp = head and (head :: BasePart).Position or Vector3.new(0, 1.5, 0)
	local cam = new("Camera", { FieldOfView = 30, Parent = portraitVp })
	cam.CFrame = CFrame.lookAt(hp + Vector3.new(1.2, 0.2, -6.5), hp - Vector3.new(0, 0.7, 0))
	portraitVp.CurrentCamera = cam
	portraitVp.ImageColor3 = if hologram then CYAN else Color3.new(1, 1, 1)
	nameText.Text = Quests.GiverName .. (if hologram then " (holo)" else "")
end

-- NpcAnimator makes Sensei face you and nod along while these attributes are on her model.
-- (Attributes set here stay on this client: the server never sees them.)
local talkingNpc: Model? = nil
local function stopTalking()
	if talkingNpc and talkingNpc.Parent then
		talkingNpc:SetAttribute("Talking", nil)
		talkingNpc:SetAttribute("Speaking", nil)
	end
	talkingNpc = nil
end
local function setTalking(npc: Model?, speaking: boolean)
	if npc ~= talkingNpc then stopTalking() end
	talkingNpc = npc
	if npc and npc.Parent then
		npc:SetAttribute("Talking", true)
		npc:SetAttribute("Speaking", speaking)
	end
end

-- Shows lines one by one. Tap/click/Space to skip the typing, then again to continue.
local function say(lines: { string }, hologram: boolean?)
	if #lines == 0 then return end
	setPortrait(hologram == true)
	-- whoever stands closest is the one talking (Sensei or her hologram)
	local speakerGiver = nearestGiver()
	local speaker = if speakerGiver then speakerGiver.npc else nil
	-- how to continue, for the device you're using (InputMode is set by ControllerSupport)
	local mode = player:GetAttribute("InputMode")
	padIcon.Visible = mode == "Gamepad"
	nextHint.Text = if mode == "Gamepad" then "Continue  \u{25B6}"
		elseif mode == "Touch" or (mode == nil and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then "Tap to continue  \u{25B6}"
		else "Click or Space  \u{25B6}"
	dialog.Visible = true
	local pop = dialog:FindFirstChild("Pop") :: UIScale
	pop.Scale = 0.6
	TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	for index, line in lines do
		bodyText.Text = line
		lineCount.Text = if #lines > 1 then string.format("%d / %d", index, #lines) else ""
		bodyText.MaxVisibleGraphemes = 0
		nextHint.Visible = false
		setTalking(speaker, true)
		local total = utf8.len(line) or #line
		local skipped = false
		local conn = advance.Event:Connect(function() skipped = true end)
		local t0 = os.clock()
		while not skipped do
			local n = math.floor((os.clock() - t0) * 55)
			if n >= total then break end
			bodyText.MaxVisibleGraphemes = n
			RunService.Heartbeat:Wait()
		end
		conn:Disconnect()
		bodyText.MaxVisibleGraphemes = -1
		nextHint.Visible = true
		setTalking(speaker, false)
		local go = false
		local c2 = advance.Event:Connect(function() go = true end)
		local t1 = os.clock()
		while not go and os.clock() - t1 < 9 do
			nextHint.Position = UDim2.new(1, -18 + math.sin(os.clock() * 8) * 4, 1, -10)
			task.wait()
		end
		c2:Disconnect()
	end
	stopTalking()
	dialog.Visible = false
end

----------------------------------------------------------------------------
-- banners ("QUEST COMPLETE!")
----------------------------------------------------------------------------
local function banner(title: string, sub: string?, color: Color3?)
	local f = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(760, 140), ZIndex = 30, Parent = canvas }, { new("UIScale", { Scale = 0.2 }) })
	local t = label({ Text = title, Size = UDim2.new(1, 0, 0, 84), TextColor3 = color or GOLD, ZIndex = 31, Rotation = -3, Parent = f })
	t:FindFirstChildOfClass("UIStroke").Thickness = 5
	local s = sub and label({ Text = sub, Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 40), ZIndex = 31, Parent = f })
	TweenService:Create(f:FindFirstChildOfClass("UIScale"), TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(2.6, function()
		for _, l in { t, s } do
			if l then
				TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				TweenService:Create(l:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.45)
		f:Destroy()
	end)
end

local function rewardText(reward: any?): string?
	if not reward then return nil end
	local parts = {}
	if reward.coins then table.insert(parts, "+$" .. Format.Short(reward.coins)) end
	if reward.gems then table.insert(parts, "+◆" .. reward.gems) end
	return if #parts > 0 then table.concat(parts, "   ") else nil
end

local function confetti()
	local root = myRoot()
	if not root then return end
	for _, c in { GOLD, Color3.fromRGB(255, 110, 150), CYAN, Color3.fromRGB(140, 255, 120) } do
		Fx.Particles(root.Position + Vector3.new(0, 3, 0), { color = c, count = 10, speed = 22, size = 0.45, lifetime = 1.1, spread = 1, gravity = 40 })
	end
end

----------------------------------------------------------------------------
-- the guide: trail + arrow + tapping hand
----------------------------------------------------------------------------
local guide = Instance.new("Folder")
guide.Name = "QuestGuide"
guide.Parent = workspace
local function guidePart(class: string, size: Vector3, color: Color3?): BasePart
	local p = Instance.new(class) :: BasePart
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = color or GOLD; p.Size = size
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- The trail: glowing chevrons on the ground that crawl toward the target, with a shimmer
-- running along them, so they read as "this way" from any camera angle.
local CHEVRONS = 22
local CHEVRON_SPACING = 3.2
local chevrons: { { BasePart } } = {}
for k = 1, CHEVRONS do
	chevrons[k] = { guidePart("Part", Vector3.new(0.42, 0.2, 1.5)), guidePart("Part", Vector3.new(0.42, 0.2, 1.5)) }
end
-- the two arms of a chevron, measured from its tip (the tip points along the trail)
local ARM_L = CFrame.Angles(0, math.rad(40), 0) * CFrame.new(0, 0, 0.62)
local ARM_R = CFrame.Angles(0, math.rad(-40), 0) * CFrame.new(0, 0, 0.62)
local shaft = guidePart("Part", Vector3.new(0.45, 1.9, 0.75))
local headR = guidePart("WedgePart", Vector3.new(0.45, 1.5, 1.05))
local headL = guidePart("WedgePart", Vector3.new(0.45, 1.5, 1.05))
local ring = guidePart("Part", Vector3.new(0.2, 6, 6))
;(ring :: Part).Shape = Enum.PartType.Cylinder
ring.Transparency = 0.35
-- a thin ring that pings outward from the target once a second ("it's HERE")
local ping = guidePart("Part", Vector3.new(0.15, 6, 6))
;(ping :: Part).Shape = Enum.PartType.Cylinder
-- far away: a tall, soft beam of light over the target that you can spot across the map
local beacon = guidePart("Part", Vector3.new(40, 1.4, 1.4))
;(beacon :: Part).Shape = Enum.PartType.Cylinder
local arrowParts = { shaft, headR, headL, ring, ping }

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshRayFilter()
	local list: { Instance } = { guide }
	for _, n in { "ClientChampions", "Enemies", "ClientEffects" } do
		local f = workspace:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	for _, p in Players:GetPlayers() do if p.Character then table.insert(list, p.Character) end end
	-- (Sensei too, so the ring under her lands on her platform, not on her head)
	for _, g in givers do table.insert(list, g.npc) end
	rayParams.FilterDescendantsInstances = list
end

local function groundAt(p: Vector3, fallback: number): number
	local hit = workspace:Raycast(Vector3.new(p.X, fallback + 8, p.Z), Vector3.new(0, -20, 0), rayParams)
	if hit and math.abs(hit.Position.Y - fallback) < 6 then return hit.Position.Y end
	return fallback
end

local function hideWorldGuide()
	for _, c in chevrons do c[1].Parent = nil; c[2].Parent = nil end
	for _, p in arrowParts do p.Parent = nil end
	beacon.Parent = nil
end

local function drawGuide(target: Vector3, top: number, t: number)
	local root = myRoot()
	if not root then hideWorldGuide() return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local footY = root.Position.Y - (hum and hum.HipHeight or 2) - root.Size.Y / 2
	local flat = (target - root.Position) * Vector3.new(1, 0, 1)
	local len = flat.Magnitude
	local dir = if len > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local offset = (t * 6) % CHEVRON_SPACING
	for k, c in chevrons do
		local dist = 2.5 + offset + (k - 1) * CHEVRON_SPACING
		if dist < len - 3 then
			local p = root.Position + dir * dist
			local y = groundAt(p, footY)
			local tip = Vector3.new(p.X, y + 0.3, p.Z)
			local base = CFrame.lookAt(tip, tip + dir)
			c[1].CFrame = base * ARM_L
			c[2].CFrame = base * ARM_R
			-- fade in near your feet and out near the target; the shimmer runs toward the target
			local fade = math.clamp((dist - 2.5) / 5, 0, 1) * math.clamp((len - 3 - dist) / 6, 0, 1)
			local shimmer = 0.5 + 0.5 * math.sin(t * 7 - dist * 0.35)
			local tr = 1 - fade * (0.55 + 0.4 * shimmer)
			c[1].Transparency = tr
			c[2].Transparency = tr
			c[1].Parent = guide
			c[2].Parent = guide
		else
			c[1].Parent = nil
			c[2].Parent = nil
		end
	end
	-- bouncing arrow over the target, always facing the camera
	local bounce = math.abs(math.sin(t * 4)) * 1.2
	local tip = target + Vector3.new(0, top + 1.2 + bounce, 0)
	local toCam = (camera.CFrame.Position - tip) * Vector3.new(1, 0, 1)
	toCam = if toCam.Magnitude > 0.01 then toCam.Unit else Vector3.new(0, 0, 1)
	local base = CFrame.fromMatrix(tip, toCam, Vector3.yAxis)
	local w = headR.Size.Z
	headR.CFrame = base * CFrame.new(0, 0.75, w / 2) * CFrame.Angles(math.pi, 0, 0)
	headL.CFrame = base * CFrame.new(0, 0.75, -w / 2) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.pi, 0, 0)
	shaft.CFrame = base * CFrame.new(0, 1.5 + 0.95, 0)
	local g = groundAt(target, target.Y - 2)
	local pulse = 1 + math.sin(t * 5) * 0.15
	ring.Size = Vector3.new(0.2, 7 * pulse, 7 * pulse)
	ring.CFrame = CFrame.new(target.X, g + 0.15, target.Z) * CFrame.Angles(0, t, math.rad(90))
	local ph = (t * 0.9) % 1
	ping.Size = Vector3.new(0.15, 5 + ph * 11, 5 + ph * 11)
	ping.Transparency = 0.25 + ph * 0.75
	ping.CFrame = CFrame.new(target.X, g + 0.2, target.Z) * CFrame.Angles(0, 0, math.rad(90))
	for _, p in arrowParts do p.Parent = guide end
	-- the beacon fades in once the target is more than ~30 studs away; it starts just above
	-- the bouncing arrow, so it never covers the thing you're walking to
	local far = math.clamp((len - 30) / 40, 0, 1)
	if far > 0 then
		local w = 1.4 + math.sin(t * 3) * 0.15
		beacon.Size = Vector3.new(40, w, w)
		beacon.CFrame = CFrame.new(target.X, target.Y + top + 4 + 20, target.Z) * CFrame.Angles(0, 0, math.rad(90))
		beacon.Transparency = 1 - 0.35 * far
		beacon.Parent = guide
	else
		beacon.Parent = nil
	end
end

-- tapping hand (screen space)
local hand = label({ Text = "👆", Size = UDim2.fromOffset(84, 84), AnchorPoint = Vector2.new(0.32, 0), Visible = false, ZIndex = 60,
	TextColor3 = Color3.new(1, 1, 1), Parent = pointerLayer })
hand:FindFirstChildOfClass("UIStroke").Thickness = 3
local handScale = new("UIScale", { Parent = hand })
local lastRipple = 0
local function ripple(x: number, y: number)
	local r = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(16, 16),
		ZIndex = 59, Parent = pointerLayer }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), new("UIStroke", { Thickness = 5, Color = GOLD }) })
	TweenService:Create(r, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(90, 90) }):Play()
	TweenService:Create(r:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.6), { Transparency = 1 }):Play()
	task.delay(0.65, function() r:Destroy() end)
end
local function pointAt(x: number, y: number, t: number)
	local phase = (t * 1.6) % 1
	local press = if phase < 0.25 then phase / 0.25 elseif phase < 0.5 then 1 - (phase - 0.25) / 0.25 else 0
	hand.Position = UDim2.fromOffset(x, y + 6 + (1 - press) * 22)
	handScale.Scale = 1 - press * 0.15
	hand.Visible = true
	if phase >= 0.25 and phase < 0.3 and t - lastRipple > 0.4 then
		lastRipple = t
		ripple(x, y)
	end
end
local function pointAtWorld(pos: Vector3, t: number): boolean
	local v, onScreen = camera:WorldToViewportPoint(pos)
	if not onScreen or v.Z <= 0 then hand.Visible = false return false end
	pointAt(v.X, v.Y, t)
	return true
end
-- Is a HUD object really on screen? (it AND all its parents visible, its ScreenGui on)
local function guiShown(g: GuiObject?): boolean
	local o: Instance? = g
	while o do
		if o:IsA("GuiObject") and not o.Visible then return false end
		if o:IsA("LayerCollector") then return (o :: any).Enabled end
		o = o.Parent
	end
	return false
end
-- HUD AbsolutePositions are measured from just below Roblox's top bar, but the hand layer
-- starts at the very top of the screen, so convert (otherwise the hand and the glow sit
-- one top-bar height above the button)
local function toPointerSpace(v: Vector2): Vector2
	return v - pointerLayer.AbsolutePosition
end
local function pointAtGui(g: GuiObject, t: number): boolean
	if not guiShown(g) then return false end
	local p = toPointerSpace(g.AbsolutePosition + g.AbsoluteSize / 2)
	pointAt(p.X, p.Y, t)
	return true
end

-- Pulsing highlight that hugs the HUD button to press: a glowing gold edge plus a cyan
-- ring that grows out of it and fades once a second. (Raw screen pixels, like the hand.)
local hl = new("Frame", { Name = "TargetHighlight", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 58,
	Parent = pointerLayer })
local hlCorner = new("UICorner", { CornerRadius = UDim.new(0, 16), Parent = hl })
local hlEdge = new("UIStroke", { Thickness = 4, Color = GOLD, Parent = hl })
local hlPing = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 57, Parent = pointerLayer })
local hlPingCorner = new("UICorner", { CornerRadius = UDim.new(0, 16), Parent = hlPing })
local hlPingEdge = new("UIStroke", { Thickness = 3, Color = AQUA, Parent = hlPing })
local hlTarget: GuiObject? = nil
local function glowAround(g: GuiObject?, t: number)
	if not g or not guiShown(g) then
		hl.Visible = false
		hlPing.Visible = false
		hlTarget = nil
		return
	end
	if g ~= hlTarget then
		-- copy the button's own corner (scaled like the HUD) so the glow hugs its shape
		hlTarget = g
		local c = g:FindFirstChildOfClass("UICorner")
		local r = if c then c.CornerRadius else UDim.new(0, 12)
		local radius = UDim.new(r.Scale, r.Offset * uiScale.Scale + 6)
		hlCorner.CornerRadius = radius
		hlPingCorner.CornerRadius = radius
	end
	local size = g.AbsoluteSize
	local p = toPointerSpace(g.AbsolutePosition + size / 2)
	local pulse = (math.sin(t * 6) + 1) / 2
	local pad = 10 + pulse * 8
	hl.Position = UDim2.fromOffset(p.X, p.Y)
	hl.Size = UDim2.fromOffset(size.X + pad, size.Y + pad)
	hlEdge.Thickness = 3 + pulse * 3
	hlEdge.Color = GOLD:Lerp(Color3.new(1, 1, 1), pulse * 0.45)
	hl.Visible = true
	local ph = (t * 1.1) % 1
	hlPing.Position = hl.Position
	hlPing.Size = UDim2.fromOffset(size.X + 12 + ph * 50, size.Y + 12 + ph * 50)
	hlPingEdge.Transparency = ph
	hlPing.Visible = true
end

----------------------------------------------------------------------------
-- what should the guide point at right now?
----------------------------------------------------------------------------
local enemiesFolder = workspace:WaitForChild("Enemies")
local function nearestEnemy(key: string, range: number): Model?
	local root = myRoot()
	if not root then return nil end
	local best, bd = nil, range
	for _, m in enemiesFolder:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart and m:GetAttribute("EnemyType") == key and not m:GetAttribute("Dead") then
			local d = (m.PrimaryPart.Position - root.Position).Magnitude
			if d < bd then best, bd = m, d end
		end
	end
	return best
end
local function zoneFor(key: string): BasePart?
	local root = myRoot()
	if not root then return nil end
	local best, bd = nil, 700
	for _, w in worlds:GetChildren() do
		local zones = w:FindFirstChild("Zones")
		if zones then
			for _, z in zones:GetChildren() do
				if z:IsA("BasePart") and z:GetAttribute("Enemy") == key then
					local d = (z.Position - root.Position).Magnitude
					if d < bd then best, bd = z, d end
				end
			end
		end
	end
	return best
end
-- How far above its pivot a station reaches, name label included (cached for a few
-- seconds), so the arrow floats over big models like the Teleporter and the Orb Shrine
-- instead of hiding inside them.
local heightCache: { [Model]: { top: number, at: number } } = {}
local function heightAbove(m: Model): number
	local now = os.clock()
	local c = heightCache[m]
	if c and now - c.at < 5 then return c.top end
	local cf, size = m:GetBoundingBox()
	local top = cf.Position.Y + size.Y / 2
	for _, d in m:GetDescendants() do
		if d:IsA("BillboardGui") and d.Parent and d.Parent:IsA("BasePart") and d.Size.Y.Scale > 0 then
			local y = (d.Parent :: BasePart).Position.Y + d.StudsOffsetWorldSpace.Y + d.StudsOffset.Y + d.Size.Y.Scale / 2
			top = math.max(top, y)
		end
	end
	local h = top - m:GetPivot().Position.Y
	heightCache[m] = { top = h, at = now }
	return h
end
local function nearestStation(name: string, worldId: number?): Model?
	local root = myRoot()
	if not root then return nil end
	local best, bd = nil, 700
	for _, w in worlds:GetChildren() do
		local s = w:FindFirstChild(name)
		if s and s:IsA("Model") and (worldId == nil or s:GetAttribute("WorldId") == worldId) then
			local d = (s:GetPivot().Position - root.Position).Magnitude
			if d < bd then best, bd = s, d end
		end
	end
	return best
end

-- (hint = one short line for the objective tracker: what to do right now)
type Plan = { world: Vector3?, top: number?, tapWorld: Vector3?, tapGui: GuiObject?, glowGui: GuiObject?, hint: string? }
local function currentPlan(): Plan?
	local i, s, _, q = questState()
	if not q or s == "finished" then return nil end
	local tutorial = i <= Quests.TutorialCount + 1
	local root = myRoot()
	if not root then return nil end
	local plan: Plan = {}
	local function near(pos: Vector3, r: number) return (pos - root.Position).Magnitude < r end

	if s == "offer" or s == "ready" or q.kind == "starter" then
		local g = nearestGiver()
		if g then
			plan.world, plan.top = g.baseCf.Position, 4.5
			if near(g.baseCf.Position, 26) then
				plan.tapWorld = g.baseCf.Position + Vector3.new(0, 1.5, 0)
				plan.hint = "Walk up to Sensei and talk to her"
			else
				plan.hint = "Follow the glowing arrows to Sensei"
			end
		end
	elseif q.kind == "ability" or q.kind == "kill" then
		local e = nearestEnemy(q.key or "TrainingDummy", 260)
		if e and e.PrimaryPart then
			plan.world, plan.top = e.PrimaryPart.Position, (e:GetAttribute("TopOffset") or 2.5) + 2.2
			if tutorial and not player:GetAttribute("Target") and near(e.PrimaryPart.Position, 60) then
				plan.tapWorld = e.PrimaryPart.Position
			end
			if q.kind == "ability" then
				plan.hint = if player:GetAttribute("Target") then "5 hits charge your partner's ability" else "Tap a training dummy to attack it"
			else
				plan.hint = "Tap an enemy: your team does the fighting"
			end
		else
			local z = zoneFor(q.key or "TrainingDummy")
			if z then plan.world, plan.top = z.Position, 3 end
			plan.hint = "Follow the glowing arrows"
		end
	elseif q.kind == "orb" then
		local reveal = hud("Reveal")
		local orbPanel = hud("Orb")
		if reveal and reveal.Visible then
			-- the reveal closes by itself after a moment, so there's nothing to tap: just wait
			plan.hint = "A new champion is joining you!"
		elseif orbPanel and orbPanel.Visible then
			if tutorial then plan.tapGui = hud("OpenOne") end
			plan.hint = "Tap SUMMON 1X to summon a champion"
		else
			local shrine = nearestStation("OrbShrine", q.key)
			if shrine then
				plan.world, plan.top = shrine:GetPivot().Position, math.max(7, heightAbove(shrine) + 0.3)
				local close = near(shrine:GetPivot().Position, 16)
				if tutorial and close then plan.tapWorld = shrine:GetPivot().Position + Vector3.new(0, 2, 0) end
				plan.hint = if close then "Use the Orb Shrine to open an orb" else "Follow the arrows to the Orb Shrine"
			end
		end
	elseif q.kind == "equip" then
		plan.tapGui = hud("BestButton")
		plan.glowGui = plan.tapGui
		plan.hint = "Tap BEST to equip your strongest team"
	elseif q.kind == "travel" or q.kind == "unlock" then
		local worldId = if q.kind == "travel" then q.key else tonumber(string.sub(q.key, 2))
		local panel = hud("Worlds")
		if panel and panel.Visible then
			-- Galaxy Map: point at the target planet until it's selected (the HUD keeps the
			-- selection in the panel's SelectedWorld attribute), then at the big FastTravel button
			local picked = worldId ~= nil and tonumber(panel:GetAttribute("SelectedWorld")) == worldId
			if tutorial then plan.tapGui = hud(if picked then "FastTravel" else "Travel" .. tostring(worldId)) end
			local w = worldId and Config.WorldById(worldId)
			local name = if w then w.name else "the next world"
			plan.hint = if picked then "Tap " .. (if q.kind == "unlock" then "UNLOCK" else "FAST TRAVEL") .. " to go to " .. name
				else "Pick " .. name .. " on the map"
		else
			local tp = nearestStation("Teleporter")
			if tp and (player:GetAttribute("World") or 0) == 0 then
				plan.world, plan.top = tp:GetPivot().Position, math.max(8, heightAbove(tp) + 0.3)
				local close = near(tp:GetPivot().Position, 18)
				if tutorial and close then plan.tapWorld = tp:GetPivot().Position + Vector3.new(0, 2, 0) end
				plan.hint = if close then "Use the Teleporter to pick a world" else "Follow the arrows to the Teleporter"
			else
				plan.tapGui = if tutorial then hud("TeleportButton") else nil
				plan.glowGui = hud("TeleportButton")
				plan.hint = "Tap TELEPORT to travel"
			end
		end
	end
	return plan
end

----------------------------------------------------------------------------
-- objective tracker (top left): "TRAINING 3/6", what to do now, and progress
----------------------------------------------------------------------------
local TRAINING_STEPS = Quests.TutorialCount + 1 -- the 5 tutorial quests + the trip to Verdant Rift
-- Friendlier wording for each training step. (Display only: the quest data is unchanged.)
local STEP_TEXT: { [string]: string } = {
	FirstAbility = "Unleash your partner's ability",
	Dummies = "Defeat 5 training dummies",
	FirstOrb = "Open your first orb",
	EquipTeam = "Equip your best team",
	Graduation = "Return to Sensei Hikari",
	GoVerdant = "Travel to Verdant Rift",
}
-- (top right, in the HUD's goal-box spot: the HUD hides its own goal box while this card is
-- up, so the goal is always in the same place and nothing covers the menu on the left)
local tracker = new("Frame", { Name = "Objective", Visible = false, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.05,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 64), Size = UDim2.fromOffset(318, 140), ZIndex = 2, Parent = canvas },
	{ corner(14), new("UIGradient", { Rotation = 90, Color = ColorSequence.new(NAVY2, NAVY) }), new("UIScale", { Name = "Pop" }) })
local trackerEdge = new("UIStroke", { Thickness = 2.5, Color = Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = tracker })
new("UIGradient", { Color = ColorSequence.new(VIOLET, AQUA), Parent = trackerEdge })
local stepChip = new("Frame", { BackgroundColor3 = VIOLET, Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(140, 26), ZIndex = 3, Parent = tracker },
	{ corner(13) })
local stepText = label({ Text = "TRAINING", Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), ZIndex = 4, Parent = stepChip })
local pipRow = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 16), Size = UDim2.fromOffset(130, 14),
	ZIndex = 3, Parent = tracker }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
local pips: { Frame } = {}
local pipScales: { UIScale } = {}
for k = 1, TRAINING_STEPS do
	pipScales[k] = new("UIScale", {})
	pips[k] = new("Frame", { BackgroundColor3 = PIP_OFF, Size = UDim2.fromOffset(13, 13), LayoutOrder = k, ZIndex = 4, Parent = pipRow },
		{ new("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(1.5), pipScales[k] })
end
local stepTitle = label({ Text = "", TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, 29),
	ZIndex = 3, Parent = tracker })
local barBack = new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 9, 22), Position = UDim2.fromOffset(12, 77), Size = UDim2.new(1, -84, 0, 12), ZIndex = 3,
	Parent = tracker }, { corner(6) })
local barFill = new("Frame", { BackgroundColor3 = AQUA, Size = UDim2.fromScale(0, 1), ZIndex = 4, Parent = barBack }, { corner(6) })
local countText = label({ Text = "", TextColor3 = AQUA, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 71), Size = UDim2.fromOffset(64, 24), ZIndex = 3, Parent = tracker })
-- (the hint is the line players read most: a long one wraps onto a second line instead of
-- shrinking to fit, so it stays legible on phones; the size cap keeps short ones from
-- growing bigger than the step title)
local hintText = label({ Text = "", TextColor3 = SUBTEXT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true, Position = UDim2.fromOffset(12, 96), Size = UDim2.new(1, -24, 0, 38), ZIndex = 3, Parent = tracker })
hintText:FindFirstChildOfClass("UIStroke").Thickness = 1.5
new("UITextSizeConstraint", { MaxTextSize = 16, Parent = hintText })

local trackerReady = false  -- true once the loading screen is gone (nothing pops up behind it)
local trackerOn = false     -- should the card be up?
local trackerStep = 0       -- the training step it shows (TRAINING_STEPS + 1 = "complete")
local trackerHint = ""
local currentHint: string? = nil -- what the guide says to do right now (set every frame below)

local function titleFor(s: string, q: any): string
	if s == "offer" then return "Talk to " .. Quests.GiverName end
	if s == "ready" then return "Return to " .. Quests.GiverName end
	return STEP_TEXT[q.id] or q.title
end

-- On small screens (phones) the whole UI is scaled down a lot, so the card is drawn a bit
-- bigger there to keep its text readable (it has the top right corner to itself).
-- (worked out from the screen size directly, so it never depends on rescale() running first)
local function trackerBase(): number
	local vp = camera.ViewportSize
	local sc = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.5, 2)
	return if sc < 0.75 then 1.35 else 1
end
local trackerPop = tracker:FindFirstChild("Pop") :: UIScale
trackerPop.Scale = trackerBase()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() trackerPop.Scale = trackerBase() end)

-- a little bounce + a brighter edge for a moment ("look here, this is new")
local function popTracker()
	local base = trackerBase()
	trackerPop.Scale = 0.85 * base
	TweenService:Create(trackerPop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = base }):Play()
	trackerEdge.Thickness = 4.5
	TweenService:Create(trackerEdge, TweenInfo.new(0.5), { Thickness = 2.5 }):Play()
end

local function setTrackerOn(on: boolean)
	if on == trackerOn then return end
	trackerOn = on
	-- other UI (like the HUD's goal box) can read this to avoid showing the same goal twice
	player:SetAttribute("TutorialTracker", on)
end

-- Redraws the card from the quest attributes (only when they change).
local function refreshTracker()
	if not trackerReady then return end
	local i, s, p, q = questState()
	if q and i <= TRAINING_STEPS and s ~= "finished" then
		if i ~= trackerStep then
			-- a new step: earlier pips are done (cyan), this one is gold
			for k = 1, TRAINING_STEPS do
				pips[k].BackgroundColor3 = if k < i then AQUA elseif k == i then GOLD else PIP_OFF
				pipScales[k].Scale = 1
			end
			local finished = pipScales[trackerStep]
			if finished and i > trackerStep then
				finished.Scale = 1.9
				TweenService:Create(finished, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
			trackerStep = i
			stepText.Text = string.format("TRAINING %d/%d", i, TRAINING_STEPS)
			stepTitle.TextColor3 = Color3.new(1, 1, 1)
			if tracker.Visible then popTracker() end
		end
		stepTitle.Text = titleFor(s, q)
		local need = math.max(tonumber(q.need) or 1, 1)
		local done = if s == "ready" then need elseif s == "offer" then 0 else math.clamp(p, 0, need)
		countText.Text = string.format("%d/%d", done, need)
		TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(done / need, 1) }):Play()
		setTrackerOn(true)
	elseif trackerStep >= 1 and trackerStep <= TRAINING_STEPS and i > TRAINING_STEPS then
		-- the last step is done: a short "complete!" moment, then the card goes away
		trackerStep = TRAINING_STEPS + 1
		for k = 1, TRAINING_STEPS do
			pips[k].BackgroundColor3 = AQUA
			pipScales[k].Scale = 1
		end
		stepText.Text = "TRAINING"
		stepTitle.Text = "Training complete!"
		stepTitle.TextColor3 = GOLD
		hintText.Text = "Sensei's quests go on in every world"
		countText.Text = string.format("%d/%d", TRAINING_STEPS, TRAINING_STEPS)
		TweenService:Create(barFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(1, 1) }):Play()
		if tracker.Visible then popTracker() end
		task.delay(3.5, function()
			if trackerStep > TRAINING_STEPS then setTrackerOn(false) end
		end)
	elseif trackerStep <= TRAINING_STEPS then
		setTrackerOn(false)
	end
end
for _, a in { "QuestIndex", "QuestState", "QuestProgress" } do
	player:GetAttributeChangedSignal(a):Connect(refreshTracker)
end

-- Every frame: show/hide (it steps aside while Sensei talks or a cinematic plays), the
-- live hint, and the current step's pip pulsing.
local function updateTracker(t: number)
	local show = trackerOn and not busy and not dialog.Visible
	if show ~= tracker.Visible then
		tracker.Visible = show
		if show then popTracker() end
	end
	if not show or trackerStep > TRAINING_STEPS then return end
	local h = currentHint or ""
	if h ~= trackerHint then
		trackerHint = h
		hintText.Text = h
	end
	local cur = pipScales[trackerStep]
	if cur then cur.Scale = 1 + 0.22 * (0.5 + 0.5 * math.sin(t * 5)) end
end

-- The loading screen (ReplicatedFirst) sets the Player attribute LoadingDone once it has
-- faded out. Wait for it, so the tutorial never starts behind it. (No loading screen, or
-- it is taking very long: carry on anyway.)
local function waitForLoadingScreen()
	if player:GetAttribute("LoadingDone") then return end
	local hasLoadingScreen = game:GetService("ReplicatedFirst"):FindFirstChildWhichIsA("LocalScript") ~= nil
		or player.PlayerGui:FindFirstChild("LoadingScreen") ~= nil
	if not hasLoadingScreen then return end
	local t0 = os.clock()
	while not player:GetAttribute("LoadingDone") and os.clock() - t0 < 30 do task.wait(0.1) end
end

local lastFilter = 0
local padFocusTarget: GuiObject? = nil -- the guide's button that last got the controller focus
-- (it and everything above it visible)
local function fullyShown(g: Instance): boolean
	local a: Instance? = g
	while a and a:IsA("GuiObject") do
		if not a.Visible then return false end
		a = a.Parent
	end
	return a ~= nil and (not a:IsA("LayerCollector") or a.Enabled)
end
-- the HUD menu (or HUD part) a button belongs to: the child of the HUD's canvas it's in
local function menuOf(g: Instance): Instance?
	local a: Instance? = g
	while a and a.Parent and a.Parent.Name ~= "Canvas" do a = a.Parent end
	return a
end
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	if t - lastFilter > 1 then lastFilter = t; refreshRayFilter() end
	local plan = (not busy and not dialog.Visible) and currentPlan() or nil
	local onPad = player:GetAttribute("InputMode") == "Gamepad"
	if plan then
		-- (a controller doesn't tap: "Tap BEST..." reads "Select BEST...")
		currentHint = if onPad and type(plan.hint) == "string" then (string.gsub(plan.hint, "^Tap ", "Select ")) else plan.hint
	end
	-- With a controller during the tutorial, the button the guide points at gets the controller's
	-- focus: once per button, only when it's really on screen, and only if the focus isn't already
	-- somewhere else (or is in the same menu), so it never yanks the focus away from the player
	local target = plan and plan.tapGui
	if onPad and target and target ~= padFocusTarget and target:IsA("GuiButton") and player:GetAttribute("TutorialTracker") == true
		and fullyShown(target) then
		local GuiService = game:GetService("GuiService")
		local sel = GuiService.SelectedObject
		if sel == nil or menuOf(sel) == menuOf(target) then
			padFocusTarget = target
			pcall(function() GuiService.SelectedObject = target end)
		end
	elseif not target then
		padFocusTarget = nil
	end
	local root = myRoot()
	if plan and plan.world and root and (plan.world - root.Position).Magnitude > 7 then
		drawGuide(plan.world, plan.top or 3, t)
	else
		hideWorldGuide()
	end
	local shown = false
	if plan and plan.tapGui then shown = pointAtGui(plan.tapGui, t)
	elseif plan and plan.tapWorld then shown = pointAtWorld(plan.tapWorld, t) end
	if not shown then hand.Visible = false end
	-- the button to press gets the pulsing highlight too, not just the tapping hand
	glowAround(plan and (plan.glowGui or plan.tapGui) or nil, t)
	updateTracker(t)
end)

----------------------------------------------------------------------------
-- "ABILITY!" spotlight the first time your champion uses one (tutorial)
----------------------------------------------------------------------------
local function myChampionModel(slot: number): Model?
	local f = workspace:FindFirstChild("ClientChampions")
	if not f then return nil end
	for _, m in f:GetChildren() do
		if m:GetAttribute("OwnerId") == player.UserId and m:GetAttribute("Slot") == slot then return m end
	end
	return nil
end
local spotlightUsed = false
Remotes:WaitForChild("ChampionAction").OnClientEvent:Connect(function(a)
	if a.u ~= player.UserId or a.k ~= "ability" or spotlightUsed or busy then return end
	local i, s = questState()
	if i ~= 1 or s ~= "active" then return end
	spotlightUsed = true
	local model = myChampionModel(a.s)
	local info = AbilityInfo[a.c]
	if not model then return end
	busy = true
	task.spawn(guarded, function()
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		local enemy = enemiesFolder:FindFirstChild(a.tg)
		local focus = root.Position
		local other = if enemy and enemy.PrimaryPart then enemy.PrimaryPart.Position else focus + root.CFrame.LookVector * 6
		local mid = focus:Lerp(other, 0.4)
		local across = ((other - focus) * Vector3.new(1, 0, 1))
		across = if across.Magnitude > 0.1 then across.Unit:Cross(Vector3.yAxis) else Vector3.new(1, 0, 0)
		camTo(CFrame.lookAt(mid + across * 11 + Vector3.new(0, 3.5, 0), mid + Vector3.new(0, 0.5, 0)), 0.3)
		local stamp = label({ Text = "ABILITY!", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.22), Size = UDim2.fromOffset(620, 110),
			TextColor3 = if info then Color3.fromHex(info.palette[2] or info.palette[1]) else GOLD, Rotation = -6, ZIndex = 40, Parent = canvas })
		stamp:FindFirstChildOfClass("UIStroke").Thickness = 6
		local sub = info and label({ Text = info.name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.31), Size = UDim2.fromOffset(620, 44),
			ZIndex = 40, Parent = canvas })
		local sc = new("UIScale", { Scale = 3, Parent = stamp })
		TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		task.delay(math.clamp((info and info.duration or 1.6) + 0.2, 1.2, 2.6), function()
			stamp:Destroy()
			if sub then sub:Destroy() end
		end)
		task.wait(math.clamp((info and info.duration or 1.6) + 0.2, 1.2, 2.6))
		camBack(0.4)
	end)
end)

----------------------------------------------------------------------------
-- starter summon (pick 1 of 3)
----------------------------------------------------------------------------
local picker = new("Frame", { Name = "StarterPicker", Visible = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3,
	Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = canvas })
label({ Text = "Choose your partner!", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 28), Size = UDim2.fromOffset(700, 64),
	TextColor3 = GOLD, ZIndex = 21, Parent = picker })
label({ Text = "This champion will fight by your side from now on.", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92),
	Size = UDim2.fromOffset(700, 30), TextColor3 = Color3.fromRGB(200, 205, 235), ZIndex = 21, Parent = picker })
local cardRow = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56),
	Size = UDim2.fromOffset(1020, 470), ZIndex = 21, Parent = picker }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 26) }),
})
local spinning: { Model } = {}
local chosen: string? = nil
local choosing = false

local function buildCards()
	for _, c in cardRow:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
	table.clear(spinning)
	for n, id in Config.Starters do
		local def = Config.ChampionById[id]
		local info = AbilityInfo[id]
		local col = info and Color3.fromHex(info.palette[1]) or GOLD
		local light = info and Color3.fromHex(info.palette[3] or info.palette[2]) or Color3.new(1, 1, 1)
		local card = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = col, Size = UDim2.fromOffset(310, 450), LayoutOrder = n, ZIndex = 22, Parent = cardRow },
			{ corner(22), stroke(5, light), new("UIGradient", { Rotation = 90, Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.15), col:Lerp(Color3.new(0, 0, 0), 0.65)) }),
				new("UIScale", { Name = "Hover", Scale = 0 }) })
		local vp = new("ViewportFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 250), ZIndex = 23,
			Ambient = Color3.fromRGB(200, 200, 210), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = card })
		local template = Models:FindFirstChild(id)
		if template then
			local m = template:Clone()
			m:PivotTo(CFrame.new())
			m.Parent = vp
			local rig = Anim.Rig(m)
			Anim.Blend(rig, Anim.P.handsOnHips, 1)
			local cam = new("Camera", { FieldOfView = 32, Parent = vp })
			cam.CFrame = CFrame.lookAt(Vector3.new(0, 0.1, -10.5), Vector3.new(0, -0.35, 0))
			vp.CurrentCamera = cam
			table.insert(spinning, m)
		end
		label({ Text = def.name, Position = UDim2.fromOffset(12, 262), Size = UDim2.new(1, -24, 0, 40), ZIndex = 23, Parent = card })
		local pill = new("Frame", { BackgroundColor3 = light, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 306), Size = UDim2.fromOffset(120, 28),
			ZIndex = 23, Parent = card }, { corner(14), stroke(2) })
		local elem = label({ Text = info and info.element or "", Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), TextColor3 = col:Lerp(Color3.new(0, 0, 0), 0.4), ZIndex = 24, Parent = pill })
		elem:FindFirstChildOfClass("UIStroke"):Destroy()
		label({ Text = "Ability: " .. (info and info.name or "?"), Position = UDim2.fromOffset(12, 340), Size = UDim2.new(1, -24, 0, 26), TextColor3 = light, ZIndex = 23, Parent = card })
		label({ Text = STARTER_BLURB[id] or "", TextScaled = false, TextSize = 19, TextWrapped = true, Position = UDim2.fromOffset(14, 370), Size = UDim2.new(1, -28, 0, 48),
			TextColor3 = Color3.fromRGB(235, 235, 245), ZIndex = 23, Parent = card })
		local pick = new("TextButton", { Name = "Choose", Text = "CHOOSE", Font = FONT, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(80, 215, 105),
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 18), Size = UDim2.fromOffset(170, 50), ZIndex = 25, Parent = card },
			{ corner(16), stroke(3), new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }) })
		new("UIStroke", { Thickness = 2, Color = STROKE, Parent = pick })
		local hover = card:FindFirstChild("Hover") :: UIScale
		TweenService:Create(hover, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		card.MouseEnter:Connect(function() TweenService:Create(hover, TweenInfo.new(0.15), { Scale = 1.05 }):Play() end)
		card.MouseLeave:Connect(function() TweenService:Create(hover, TweenInfo.new(0.15), { Scale = 1 }):Play() end)
		local function choose()
			if choosing then return end
			choosing = true
			local ok, msg = Remotes.ChooseStarter:InvokeServer(id)
			if ok then
				chosen = id
			else
				banner("Hmm...", msg or "Try again.", Color3.fromRGB(255, 85, 85))
				choosing = false
			end
		end
		pick.Activated:Connect(choose)
		card.Activated:Connect(choose)
	end
end
RunService.RenderStepped:Connect(function(dt)
	if not picker.Visible then return end
	for _, m in spinning do m:PivotTo(m:GetPivot() * CFrame.Angles(0, dt * 0.9, 0)) end
end)

-- After the ceremony: wait until the server has really added the starter to your team
-- (it does that ~6 s after the pick, maybe a bit later on a slow connection),
-- then sparkle it in next to you.
local function welcomeStarter(id: string, col: Color3, col2: Color3)
	local function joined(): boolean
		return table.find(string.split(tostring(player:GetAttribute("EquippedIds") or ""), ","), id) ~= nil
	end
	local t0 = os.clock()
	while not joined() and os.clock() - t0 < 12 do task.wait(0.1) end
	if not joined() then return end
	task.wait(0.2) -- give the follower a moment to spawn
	local root = myRoot()
	if not root then return end
	local pos = root.Position
	pcall(function()
		Fx.Ring(CFrame.new(pos - Vector3.new(0, 2.6, 0)), col, 2, 12, 0.6, 0.3)
		Fx.Burst(pos, col2, 8, 0.5)
		Fx.Particles(pos, { color = col2, count = 18, speed = 14, size = 0.4, lifetime = 0.9, spread = 1, gravity = 10, light = true })
	end)
end

-- The summon show. Timing matters: the server only adds the champion to your team
-- ~6 s after the pick (QuestService STARTER_DELAY), and this show takes about 5 s,
-- so the real champion appears once the show is over, never during it.
local function ceremony(id: string)
	local def = Config.ChampionById[id]
	local info = AbilityInfo[id]
	local col = info and Color3.fromHex(info.palette[1]) or GOLD
	local col2 = info and Color3.fromHex(info.palette[2]) or Color3.new(1, 1, 1)
	local g = nearestGiver()
	local root = myRoot()
	if not g or not root then return end
	local toMe = (root.Position - g.baseCf.Position) * Vector3.new(1, 0, 1)
	toMe = if toMe.Magnitude > 0.1 then toMe.Unit else Vector3.new(0, 0, 1)
	local ground = groundAt(g.baseCf.Position + toMe * 7, g.baseCf.Position.Y - 3)
	local spot = Vector3.new(g.baseCf.Position.X, ground, g.baseCf.Position.Z) + toMe * 7
	local side = toMe:Cross(Vector3.yAxis)
	camTo(CFrame.lookAt(spot + toMe * 15 + side * 4 + Vector3.new(0, 6, 0), spot + Vector3.new(0, 2.5, 0)), 0.8).Completed:Wait()
	-- summoning circle charges up
	Fx.Ring(CFrame.new(spot + Vector3.new(0, 0.2, 0)), col, 2, 14, 1.2, 0.4)
	Fx.Orbit(function() return spot + Vector3.new(0, 2, 0) end, col2, 6, 4, 1.4, 0.6, 5)
	Fx.Particles(spot, { color = col2, count = 24, speed = 10, size = 0.4, lifetime = 1.2, spread = 1, gravity = -10, light = true })
	task.wait(1.1)
	Fx.Pillar(spot, col, 40, 4.5, 1.6)
	Fx.Flash(Color3.new(1, 1, 1), 0.15, 0.5)
	Fx.Shockwave(spot, col, 16, 0.9)
	Fx.Burst(spot + Vector3.new(0, 3, 0), col2, 12, 0.7)
	Fx.Light(spot + Vector3.new(0, 3, 0), col, 30, 6, 1.6)
	-- the champion appears in a victory pose
	local display: Model? = nil
	local template = Models:FindFirstChild(id)
	if template then
		display = template:Clone()
		local m = display :: Model
		local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart
		hrp.Anchored = true
		for _, d in m:GetDescendants() do if d:IsA("BasePart") then d.CanCollide = false; d.CanQuery = false end end
		m:PivotTo(CFrame.lookAt(spot + Vector3.new(0, m:GetAttribute("GroundOffset") or 3, 0), spot + toMe * 10 + Vector3.new(0, m:GetAttribute("GroundOffset") or 3, 0)))
		m.Parent = workspace
		local rig = Anim.Rig(m)
		Anim.Blend(rig, Anim.P.victory, 1)
		m:ScaleTo(0.2)
		for k = 1, 12 do m:ScaleTo(0.2 + 0.8 * Anim.EASE.back(k / 12)) task.wait(1 / 40) end
	end
	banner("NEW PARTNER!", def.name .. " is joining your team!", col2)
	confetti()
	task.wait(2.3)
	if display then
		Fx.Burst((display :: Model):GetPivot().Position, col2, 6, 0.4)
		display:Destroy()
	end
	camBack(0.7)
	task.spawn(welcomeStarter, id, col, col2)
end

local function runStarterPick()
	chosen = nil
	choosing = false
	buildCards()
	picker.Visible = true
	local t0 = os.clock()
	while not chosen and os.clock() - t0 < 300 do task.wait(0.1) end
	picker.Visible = false
	if chosen then ceremony(chosen) end
end

----------------------------------------------------------------------------
-- talking to Sensei
----------------------------------------------------------------------------
local talkQueue = 0
local function linesFor(q: any): { string }
	return q and q.lines or {}
end

local function focusGiver(g: Giver?)
	local root = myRoot()
	if not g or not root then return end
	local head = g.npc:FindFirstChild("AnimeHead") or g.npc:FindFirstChild("Head")
	local hp = if head then (head :: BasePart).Position else g.baseCf.Position + Vector3.new(0, 1.5, 0)
	local dir = (root.Position - hp) * Vector3.new(1, 0, 1)
	dir = if dir.Magnitude > 0.1 then dir.Unit else g.baseCf.LookVector
	local side = dir:Cross(Vector3.yAxis)
	-- three-quarter shot of Sensei's face from beside the player (keeps your avatar out of the way)
	camTo(CFrame.lookAt(hp + dir * 7 + side * 5.5 + Vector3.new(0, 0.9, 0), hp - Vector3.new(0, 1, 0) + side * 1.2), 0.6)
end

local function talk()
	local g = nearestGiver()
	local holo = g ~= nil and g.holo
	local res = Remotes.QuestTalk:InvokeServer()
	if not res or res.result == "far" then return end
	focusGiver(g)
	task.wait(0.3)
	local q = res.index and Quests.Get(res.index)
	if res.result == "accepted" then
		say(linesFor(q), holo)
		camBack(0.5)
		-- show where to go
		if q and (q.kind == "ability" or q.kind == "kill") then
			local e = nearestEnemy(q.key or "TrainingDummy", 400)
			if e and e.PrimaryPart then showPlace(e.PrimaryPart.Position, 1.6) end
		end
	elseif res.result == "claimed" then
		local lines = table.clone(q and q.done or { "Great work!" })
		local rt = rewardText(q and q.reward)
		if rt then table.insert(lines, "Here's your reward: " .. rt) end
		say(lines, holo)
		banner("QUEST CLAIMED!", rt, GOLD)
		confetti()
		local nq = Quests.Get(res.next)
		if nq then say(linesFor(nq), holo) end
		camBack(0.5)
	elseif res.result == "starter" then
		say(q and q.done or { "Choose your partner!" }, holo)
		camBack(0.3)
		runStarterPick()
	elseif res.result == "active" then
		local _, _, p = questState()
		local progress = if q and q.need > 1 then string.format(" (%d/%d)", p, q.need) else ""
		say({ "Keep going! " .. (q and q.title or "") .. progress .. "." }, holo)
		camBack(0.5)
	else
		say({ "You've learned everything I can teach you... for now!", "New quests arrive with every update." }, holo)
		camBack(0.5)
	end
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "TalkPrompt" and not busy then task.spawn(guarded, talk) end
end)

cleanup = function()
	stopTalking()
	dialog.Visible = false
	picker.Visible = false
	choosing = false
	camBack(0)
end

----------------------------------------------------------------------------
-- quest events from the server
----------------------------------------------------------------------------
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind, info)
	if kind ~= "Quest" then return end
	local q = Quests.Get(info.index)
	if info.event == "complete" then
		banner("QUEST COMPLETE!", rewardText(info.reward), GOLD)
		confetti()
	elseif info.event == "ready" then
		banner("QUEST COMPLETE!", "Return to " .. Quests.GiverName, GOLD)
		confetti()
	elseif info.event == "new" and q then
		-- quests that start on their own (after an auto quest) get a radio call from Sensei
		local prev = Quests.Get(info.index - 1)
		if not (prev and prev.auto) then return end
		talkQueue += 1
		local myTurn = talkQueue
		task.spawn(function()
			task.wait(0.8)
			waitIdle()
			if myTurn ~= talkQueue then return end
			guarded(function()
				local g0 = nearestGiver()
				say(linesFor(q), g0 ~= nil and g0.holo)
				-- show where the next thing is
				if q.kind == "orb" then
					local shrine = nearestStation("OrbShrine", q.key)
					if shrine then showPlace(shrine:GetPivot().Position, 1.4) end
				elseif q.kind == "starter" then
					local g = nearestGiver()
					if g then showPlace(g.baseCf.Position, 1.2) end
				elseif q.kind == "travel" and (player:GetAttribute("World") or 0) == 0 then
					local tp = nearestStation("Teleporter")
					if tp then showPlace(tp:GetPivot().Position, 1.4) end
				end
			end)
		end)
	end
end)

----------------------------------------------------------------------------
-- first join: Sensei waves you over
----------------------------------------------------------------------------
if not player:GetAttribute("DataLoaded") then player:GetAttributeChangedSignal("DataLoaded"):Wait() end
if not player.Character then player.CharacterAdded:Wait() end
-- the TRAINING card is set up while the loading screen still covers everything, so the
-- HUD's own goal box (it steps aside for the card) never flashes up as the screen fades
trackerReady = true
refreshTracker()
-- nothing that MOVES starts behind the loading screen (banner, camera pan): wait until it has faded away
waitForLoadingScreen()
task.wait(1.5)
-- keep a copy of the real Sensei for the dialogue portrait (Champion City may unload later)
for _, g in givers do
	if not g.holo and not portraitSource then portraitSource = cleanCopy(g.npc) end
end
local i0, s0 = questState()
if i0 == 1 and s0 == "offer" then
	local t0 = os.clock()
	while #givers == 0 and os.clock() - t0 < 5 do task.wait(0.2) end
	local g = nearestGiver()
	if g and not busy then
		guarded(function()
			banner("WELCOME, ROOKIE!", "Someone wants to meet you...", GOLD)
			-- Sensei waves as the camera reaches her (NpcAnimator plays the wave)
			task.delay(0.7, function()
				if g.npc.Parent then g.npc:SetAttribute("WaveAt", os.clock()) end
			end)
			showPlace(g.baseCf.Position, 1.8)
		end)
	end
end
