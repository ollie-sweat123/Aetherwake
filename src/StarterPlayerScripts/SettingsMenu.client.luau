-- SettingsMenu (client): the Settings window (the ⚙️ Settings button on the HUD's menu grid)
-- and the volume of every sound.
--
--   * The list of settings is ReplicatedStorage.Shared.Settings: this script only draws it.
--     Sections Graphics, Notifications, Sound and Gameplay, with gold toggles, sliders and the
--     orange Config buttons (each opens its own panel over the menu).
--   * The server owns every value (SettingsService). It publishes them as the player attributes
--     "Pref_<key>"; a toggle or slider here only ASKS for a change (Remotes.SetPreference) and
--     shows it straight away. The scripts that react to a setting read those attributes:
--       HUD (coin popups, rare-summon banner), ChampionController (auras, other players'
--       champions, ability effects), WorldAmbience (HD Mode), SettingsService (sprint speed).
--   * Sound: three SoundGroups in SoundService (MusicGroup, AmbienceGroup, GuiGroup) follow the
--     Music / Ambience / GUI Volume sliders. A sound joins a group by itself:
--       Music     inside anything named "Music", or AudioCategory = "Music" on it or a parent
--       Ambience  inside anything named "Ambience" / "Ambient", or AudioCategory = "Ambience"
--       GUI       any other sound in SoundService or the PlayerGui (clicks, summon, travel)
--     (Sounds that already have a SoundGroup, and sounds in the world without a category, such
--     as footsteps, are left alone.) So new music only needs to live in a folder called Music.
--   * The window is a normal HUD panel (the HUD's "register" command), so it opens and closes
--     like the other menus, one at a time, and the controller focus works the same way.
--   * Also hides Roblox's Backpack hotbar (players never hold tools: see NoWeapons).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Settings"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- (SetCoreGuiEnabled can fail while Roblox's own scripts are still starting: try a few times)
task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then return end
		task.wait(1)
	end
end)

-- The value of a setting: what the server published, or the default until the save has loaded.
local function pref(key: string): any
	local v = player:GetAttribute("Pref_" .. key)
	if v == nil then
		local d = Settings.ByKey[key]
		return d and d.default
	end
	return v
end

----------------------------------------------------------------------------
-- sound groups
----------------------------------------------------------------------------
local GROUP_KEYS = { Music = "MusicVolume", Ambience = "AmbienceVolume", GUI = "GuiVolume" }
local GROUP_NAMES = { Music = "MusicGroup", Ambience = "AmbienceGroup", GUI = "GuiGroup" }
local groups: { [string]: SoundGroup } = {}
for category, name in GROUP_NAMES do
	local g = SoundService:FindFirstChild(name)
	if not (g and g:IsA("SoundGroup")) then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	groups[category] = g :: SoundGroup
end

-- a slider being dragged plays its volume at once (the server's copy follows a moment later)
local liveVolume: { [string]: number } = {}
local function applyVolumes()
	for category, key in GROUP_KEYS do
		local v = liveVolume[key] or tonumber(pref(key)) or 100
		groups[category].Volume = math.clamp(v, 0, 100) / 100
	end
end
applyVolumes()

local function categoryOf(s: Sound): string?
	local a: Instance? = s
	while a and a ~= game do
		local tag = a:GetAttribute("AudioCategory")
		if tag == "Music" or tag == "Ambience" or tag == "GUI" then return tag end
		if a.Name == "Music" then return "Music" end
		if a.Name == "Ambience" or a.Name == "Ambient" then return "Ambience" end
		a = a.Parent
	end
	if s:IsDescendantOf(SoundService) or s:IsDescendantOf(playerGui) then return "GUI" end
	return nil
end
local function sortSound(d: Instance)
	if not d:IsA("Sound") or d.SoundGroup ~= nil then return end
	local category = categoryOf(d)
	if category then d.SoundGroup = groups[category] end
end
for _, root in { SoundService, playerGui, workspace } do
	for _, d in root:GetDescendants() do sortSound(d) end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") then task.defer(sortSound, d) end -- (deferred: the parent may still be filling in)
	end)
end

----------------------------------------------------------------------------
-- talking to the server
----------------------------------------------------------------------------
local function fire(name: string, ...: any)
	local r = Remotes:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then r:FireServer(...) end
end

-- Slider drags send at most ~6 values a second (SettingsService has a rate limit), and always
-- the last one.
local pendingSend: { [string]: any } = {}
local sendScheduled: { [string]: boolean } = {}
local function sendPref(key: string, value: any, now: boolean?)
	pendingSend[key] = value
	if now then
		fire("SetPreference", key, value)
		pendingSend[key] = nil
		return
	end
	if sendScheduled[key] then return end
	sendScheduled[key] = true
	task.delay(0.18, function()
		sendScheduled[key] = nil
		if pendingSend[key] ~= nil then
			fire("SetPreference", key, pendingSend[key])
			pendingSend[key] = nil
		end
	end)
end

----------------------------------------------------------------------------
-- look
----------------------------------------------------------------------------
local rgb = Color3.fromRGB
local C = {
	bg = rgb(11, 11, 13),
	row = rgb(29, 29, 32),
	rowHover = rgb(40, 40, 45),
	border = rgb(255, 172, 28),
	gold = rgb(255, 196, 30),
	goldLight = rgb(255, 222, 80),
	orange = rgb(255, 138, 20),
	crack = rgb(214, 118, 8),
	red = rgb(226, 38, 48),
	text = rgb(255, 255, 255),
	sub = rgb(170, 170, 182),
	dim = rgb(118, 118, 126),
	ink = rgb(14, 10, 6),
	trackOff = rgb(52, 52, 57),
	knobOff = rgb(96, 96, 104),
	trackOn = rgb(92, 72, 26),
	green = rgb(110, 225, 120),
	dots = rgb(36, 36, 40),
}
local FONT = Enum.Font.FredokaOne
local W, H = 860, 590         -- the window, in HUD design pixels (the HUD scales it to the screen)
local ROW_H = 54
local QUICK = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	for _, c in children or {} do c.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function corner(r: number?) return new("UICorner", { CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0) }) end
local function text(props: { [string]: any }, strokeThickness: number?): TextLabel
	local base: { [string]: any } = { BackgroundTransparency = 1, Font = FONT, TextColor3 = C.text, TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in props do base[k] = v end
	local l = new("TextLabel", base)
	if strokeThickness ~= 0 then new("UIStroke", { Thickness = strokeThickness or 1.5, Color = C.ink, Parent = l }) end
	return l
end

-- Fills the side of the line a -> b that is clockwise of it (screen space) with a big rotated
-- square, inside `clip` (a ClipsDescendants frame). Used for the slanted ends of the header.
local function halfPlane(clip: GuiObject, a: Vector2, b: Vector2, color: Color3)
	local d = (b - a).Unit
	local size = 400
	local center = (a + b) / 2 + Vector2.new(-d.Y, d.X) * size / 2
	new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y), Size = UDim2.fromOffset(size, size),
		Rotation = math.deg(math.atan2(d.Y, d.X)), Parent = clip })
end
-- A triangle (or any slanted piece) = a clipping box + one half-plane. Points are box-relative.
local function slantPiece(parent: Instance, name: string, pos: Vector2, size: Vector2, a: Vector2, b: Vector2, color: Color3, z: number?): Frame
	local clip = new("Frame", { Name = name, BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z or 1,
		Position = UDim2.fromOffset(pos.X, pos.Y), Size = UDim2.fromOffset(size.X, size.Y), Parent = parent })
	halfPlane(clip, a, b, color)
	return clip
end

-- Hover grow + press squash, like the HUD's buttons (no hover on touch screens).
local function feedback(b: GuiButton, target: GuiObject?)
	local g = target or b
	local sc = new("UIScale", { Name = "ClickScale", Parent = g })
	b.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		TweenService:Create(sc, QUICK, { Scale = 1.04 }):Play()
	end)
	b.MouseLeave:Connect(function() TweenService:Create(sc, QUICK, { Scale = 1 }):Play() end)
	b.Activated:Connect(function()
		sc.Scale = 0.92
		TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
end

-- The HUD's click sound, if it made one (it lives in SoundService, so the GUI Volume applies).
local function click()
	local s = SoundService:FindFirstChild("HUD_click")
	if s and s:IsA("Sound") then
		s.TimePosition = 0
		s:Play()
	end
end

-- Small halftone dots in a corner (the "patterned" dark detail).
local function dotPattern(parent: Instance, origin: Vector2, cols: number, rows: number, z: number)
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local size = math.max(1, 7 - row * 2 - col * 0.25)
			if size > 1.5 then
				new("Frame", { BackgroundColor3 = C.dots, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z,
					Position = UDim2.fromOffset(origin.X + col * 13, origin.Y - row * 11), Size = UDim2.fromOffset(size, size), Parent = parent }, { corner() })
			end
		end
	end
end

----------------------------------------------------------------------------
-- the window
----------------------------------------------------------------------------
local hud = playerGui:WaitForChild("HUD")
local canvas = hud:WaitForChild("Canvas")
local command = hud:WaitForChild("Command") :: BindableFunction

local panel = new("Frame", { Name = "Settings", Visible = false, Active = true, BackgroundColor3 = C.bg, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 50, 0.5, 30), Size = UDim2.fromOffset(W, H), Parent = canvas },
	{ corner(16), new("UIStroke", { Thickness = 3, Color = C.border }), new("UIScale", { Name = "OpenScale" }) })
dotPattern(panel, Vector2.new(18, H - 12), 24, 3, 1)

-- header: a slanted gold banner sticking out over the top of the window, a white sliver and
-- the red close button (stays put while the list scrolls under it)
local header = new("Frame", { Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -62), Size = UDim2.fromOffset(W, 84),
	ZIndex = 5, Parent = panel })
new("Frame", { Name = "Banner", BackgroundColor3 = C.gold, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(744, 84),
	ZIndex = 1, Parent = header })
slantPiece(header, "LeftEnd", Vector2.new(-40, 0), Vector2.new(49, 84), Vector2.new(48, 84), Vector2.new(0, 0), C.gold)
slantPiece(header, "RightEnd", Vector2.new(751, 0), Vector2.new(40, 84), Vector2.new(39, 0), Vector2.new(0, 84), C.gold)
slantPiece(header, "Sliver", Vector2.new(762, 16), Vector2.new(30, 68), Vector2.new(0, 68), Vector2.new(30, 0), C.text)
-- a few dark "cracks" across the banner (the comic-panel look)
for _, c in { { 150, 0, 52, 14 }, { 372, 0, 40, -10 }, { 70, 54, 30, 18 }, { 296, 58, 26, 12 } } do
	new("Frame", { Name = "Crack", BackgroundColor3 = C.crack, BorderSizePixel = 0, ZIndex = 3, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(c[1], c[2]), Size = UDim2.fromOffset(3, c[3]), Rotation = c[4], Parent = header })
end
-- title: white with an orange outline, on a soft cream halo
local glow = text({ Name = "TitleGlow", Text = "Settings", TextSize = 60, TextColor3 = rgb(255, 236, 196), ZIndex = 4,
	Position = UDim2.fromOffset(34, 4), Size = UDim2.fromOffset(330, 74), Parent = header }, 0)
new("UIStroke", { Thickness = 7, Color = rgb(255, 228, 170), Parent = glow })
local title = text({ Name = "Title", Text = "Settings", TextSize = 60, ZIndex = 5, Position = UDim2.fromOffset(34, 4), Size = UDim2.fromOffset(330, 74),
	Parent = header }, 0)
new("UIStroke", { Thickness = 3.5, Color = rgb(238, 112, 14), Parent = title })

local closeBtn = new("TextButton", { Name = "Close", Text = "X", Font = FONT, TextSize = 40, TextColor3 = C.text, AutoButtonColor = true,
	BackgroundColor3 = C.red, BorderSizePixel = 0, Position = UDim2.fromOffset(798, 12), Size = UDim2.fromOffset(64, 62), ZIndex = 6, Parent = header },
	{ new("UIStroke", { Thickness = 2, Color = C.ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }) })
slantPiece(header, "CloseTip", Vector2.new(798, 0), Vector2.new(64, 12), Vector2.new(0, 12), Vector2.new(64, 0), C.red, 6)
feedback(closeBtn)

-- the list
local scroll = new("ScrollingFrame", { Name = "List", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(18, 30),
	Size = UDim2.new(1, -32, 1, -30 - 46), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = C.gold, ElasticBehavior = Enum.ElasticBehavior.Always,
	VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, ZIndex = 2, Parent = panel }, {
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 6) }),
})

-- footer: what the setting under the mouse / controller focus does
local DEFAULT_HINT = "Tap or hover a setting to see what it does."
local hintLabel = text({ Name = "Hint", Text = DEFAULT_HINT, TextSize = 18, TextColor3 = C.sub, TextWrapped = true, ZIndex = 3,
	Position = UDim2.new(0, 24, 1, -44), Size = UDim2.new(1, -48, 0, 38), Parent = panel }, 0)
local function showHint(s: string?)
	hintLabel.Text = if s and s ~= "" then s else DEFAULT_HINT
end

----------------------------------------------------------------------------
-- building blocks
----------------------------------------------------------------------------
local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function sectionTitle(parent: Instance, name: string, layoutOrder: number)
	local f = new("Frame", { Name = name .. "Section", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = layoutOrder, Parent = parent })
	local l = text({ Text = name, TextSize = 36, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextColor3 = C.text, Parent = f }, 2)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.goldLight, C.orange), Parent = l })
	local line = new("Frame", { BackgroundColor3 = C.gold, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(1, 0, 0, 3),
		Parent = f }, { new("UIGradient", { Transparency = NumberSequence.new(0, 0.85) }) })
	local function place()
		local w = l.TextBounds.X + 34
		line.Position = UDim2.new(0, w, 0.55, 0)
		line.Size = UDim2.new(1, -w - 10, 0, 3)
	end
	l:GetPropertyChangedSignal("TextBounds"):Connect(place)
	place()
end

-- a dark rounded row; the whole row is the button (easy to hit on a phone)
local function rowFrame(parent: Instance, name: string, label: string, layoutOrder: number, hint: string?): (TextButton, TextLabel)
	local row = new("TextButton", { Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = C.row, Size = UDim2.new(1, 0, 0, ROW_H),
		LayoutOrder = layoutOrder, Parent = parent }, { corner(10) })
	local l = text({ Name = "Label", Text = label, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0.62, -22, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row })
	local function hover(on: boolean)
		TweenService:Create(row, QUICK, { BackgroundColor3 = if on then C.rowHover else C.row }):Play()
		if on then showHint(hint) end
	end
	row.MouseEnter:Connect(function() hover(true) end)
	row.MouseLeave:Connect(function() hover(false) end)
	row.SelectionGained:Connect(function() hover(true) end)
	row.SelectionLost:Connect(function() hover(false) end)
	return row, l
end

local function tag(row: GuiObject, s: string, color: Color3, rightInset: number)
	text({ Name = "Tag", Text = s, TextSize = 16, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -rightInset, 0.5, 0), Size = UDim2.fromOffset(140, 24), Parent = row }, 1)
end

-- the gold pill switch: knob right + gold = ON, knob left + grey = OFF
type Switch = { set: (on: boolean, instant: boolean?) -> (), frame: Frame }
local function switch(parent: GuiObject, dimmed: boolean?): Switch
	local track = new("Frame", { Name = "Switch", BackgroundColor3 = C.trackOff, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(58, 28), Parent = parent }, { corner() })
	local knob = new("Frame", { Name = "Knob", BackgroundColor3 = C.knobOff, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(22, 22), Parent = track }, { corner(), new("UIStroke", { Thickness = 1, Color = C.ink, Transparency = 0.4 }) })
	local fade = if dimmed then 0.55 else 0
	track.BackgroundTransparency = fade
	knob.BackgroundTransparency = fade
	local current: boolean? = nil
	local function set(on: boolean, instant: boolean?)
		if on == current and not instant then return end
		current = on
		local goalTrack = { BackgroundColor3 = if on then C.trackOn else C.trackOff }
		local goalKnob = { BackgroundColor3 = if on then C.gold else C.knobOff, Position = UDim2.new(0, if on then 33 else 3, 0.5, 0) }
		if instant then
			for k, v in goalTrack do (track :: any)[k] = v end
			for k, v in goalKnob do (knob :: any)[k] = v end
		else
			TweenService:Create(track, QUICK, goalTrack):Play()
			TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), goalKnob):Play()
		end
	end
	return { set = set, frame = track }
end

-- rows that show a server value: refresh(key) redraws them when "Pref_<key>" changes.
-- localUntil: after a tap or drag the row keeps what the player chose for a moment, so the
-- server's (slightly older) echo can't make it jump back while they're still moving it.
local refreshers: { [string]: { () -> () } } = {}
local localUntil: { [string]: number } = {}
local function onRefresh(key: string, fn: () -> ())
	refreshers[key] = refreshers[key] or {}
	table.insert(refreshers[key], fn)
	fn()
end
local function refresh(key: string)
	if (localUntil[key] or 0) > os.clock() then return end
	for _, fn in refreshers[key] or {} do fn() end
end
local function holdLocal(key: string, seconds: number)
	localUntil[key] = os.clock() + seconds
	task.delay(seconds + 0.05, function() refresh(key) end) -- then show the server's real value
end

local function toggleRow(parent: Instance, d: any, layoutOrder: number)
	local row, label = rowFrame(parent, d.key, d.label, layoutOrder, d.hint)
	if d.status == "live" then
		local sw = switch(row)
		local on = false
		onRefresh(d.key, function()
			on = pref(d.key) == true
			sw.set(on, true)
		end)
		feedback(row, sw.frame)
		row.Activated:Connect(function()
			click()
			on = not on
			sw.set(on)
			holdLocal(d.key, 1.2)
			sendPref(d.key, on, true)
			showHint(d.hint)
		end)
	else
		-- "always" (always on, nothing to change) or "soon" (the game system isn't in yet):
		-- the switch shows the truth but can't be moved, and says why
		local always = d.status == "always"
		local sw = switch(row, true)
		sw.set(always, true)
		label.TextColor3 = C.sub
		tag(row, if always then "ALWAYS ON" else "COMING SOON", if always then C.green else C.orange, 92)
		row.Activated:Connect(function()
			click()
			showHint(d.hint)
			local s = sw.frame
			TweenService:Create(s, TweenInfo.new(0.05), { Position = UDim2.new(1, -26, 0.5, 0) }):Play()
			task.delay(0.05, function() TweenService:Create(s, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Position = UDim2.new(1, -20, 0.5, 0) }):Play() end)
		end)
	end
	return row
end

-- slider: drag the knob (mouse / touch), or D-pad / arrow keys left and right on it
local activeAdjust: ((step: number) -> ())? = nil
local ADJUST_ACTION = "AetherwakeSettingsSlider"
local function bindAdjust(fn: ((number) -> ())?)
	activeAdjust = fn
	ContextActionService:UnbindAction(ADJUST_ACTION)
	if not fn then return end
	ContextActionService:BindActionAtPriority(ADJUST_ACTION, function(_, state, input)
		if state ~= Enum.UserInputState.Begin or not activeAdjust then return Enum.ContextActionResult.Pass end
		local left = input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left
		activeAdjust(if left then -1 else 1)
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 8, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.Left, Enum.KeyCode.Right)
end

local dragging: { input: InputObject, move: (x: number) -> (), finish: () -> () }? = nil -- (the slider being dragged)
local function sliderRow(parent: Instance, d: any, layoutOrder: number)
	local row = rowFrame(parent, d.key, d.label, layoutOrder, d.hint)
	local area = new("Frame", { Name = "Slider", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -104, 0, 0),
		Size = UDim2.new(0.56, -110, 1, 0), Parent = row })
	local track = new("Frame", { Name = "Track", BackgroundColor3 = C.trackOff, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 6), Parent = area }, { corner() })
	local fill = new("Frame", { Name = "Fill", BackgroundColor3 = C.gold, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track },
		{ corner(), new("UIGradient", { Color = ColorSequence.new(C.orange, C.gold) }) })
	local knob = new("Frame", { Name = "Knob", BackgroundColor3 = C.gold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(22, 22), ZIndex = 2, Parent = track }, { corner(), new("UIStroke", { Thickness = 2, Color = C.ink }) })
	local valueLabel = text({ Name = "Value", Text = "", TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(74, 30), Parent = row })
	local min, max, step = d.min :: number, d.max :: number, (d.step or 1) :: number
	local shown = tonumber(pref(d.key)) or d.default

	local function draw(v: number, instant: boolean?)
		local frac = (v - min) / (max - min)
		local goalPos = UDim2.fromScale(frac, 0.5)
		if instant then
			knob.Position = goalPos
			fill.Size = UDim2.fromScale(frac, 1)
		else
			TweenService:Create(knob, TweenInfo.new(0.06), { Position = goalPos }):Play()
			TweenService:Create(fill, TweenInfo.new(0.06), { Size = UDim2.fromScale(frac, 1) }):Play()
		end
		valueLabel.Text = Settings.Display(d.key, v)
	end
	local function setLocal(v: number)
		v = math.clamp(min + math.floor((v - min) / step + 0.5) * step, min, max)
		if v == shown then return end
		shown = v
		draw(v)
		holdLocal(d.key, 0.9)
		if GROUP_KEYS.Music == d.key or GROUP_KEYS.Ambience == d.key or GROUP_KEYS.GUI == d.key then
			liveVolume[d.key] = v
			applyVolumes()
		end
		sendPref(d.key, v)
	end
	local function fromX(x: number)
		local frac = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		setLocal(min + frac * (max - min))
	end
	local function finish()
		TweenService:Create(knob, QUICK, { Size = UDim2.fromOffset(22, 22) }):Play()
		sendPref(d.key, shown, true)
		task.delay(1, function()
			if (localUntil[d.key] or 0) <= os.clock() then
				liveVolume[d.key] = nil
				applyVolumes()
			end
		end)
	end
	onRefresh(d.key, function()
		shown = tonumber(pref(d.key)) or d.default
		draw(shown, true)
	end)

	row.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
		-- only a press on the slider part of the row (or near it) starts a drag
		local x = input.Position.X
		if x < track.AbsolutePosition.X - 30 then return end
		dragging = { input = input, move = fromX, finish = finish }
		scroll.ScrollingEnabled = false -- (a sideways drag on a phone mustn't scroll the list too)
		TweenService:Create(knob, QUICK, { Size = UDim2.fromOffset(28, 28) }):Play()
		fromX(x)
		showHint(d.hint)
	end)
	row.Activated:Connect(function() showHint(d.hint) end)
	row.SelectionGained:Connect(function()
		bindAdjust(function(dir: number)
			setLocal(shown + dir * math.max(step, (max - min) / 20))
			finish()
		end)
	end)
	row.SelectionLost:Connect(function() bindAdjust(nil) end)
	return row
end

UserInputService.InputChanged:Connect(function(input)
	local drag = dragging
	if not drag then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input == drag.input then
		drag.move(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	local drag = dragging
	if not drag then return end
	if input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = nil
		scroll.ScrollingEnabled = true
		drag.finish()
	end
end)

-- orange "Config" button on the right of a row
local function configButton(row: GuiObject, onClick: () -> ()): TextButton
	local b = new("TextButton", { Name = "Config", Text = "Config", Font = FONT, TextSize = 22, TextColor3 = C.text, AutoButtonColor = true,
		BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 40),
		Parent = row }, {
		corner(6),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 206, 52), rgb(240, 128, 16)) }),
		new("UIStroke", { Thickness = 2, Color = rgb(150, 70, 0), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	new("UIStroke", { Thickness = 1.5, Color = C.ink, Parent = b })
	feedback(b)
	b.Activated:Connect(function()
		click()
		onClick()
	end)
	return b
end

----------------------------------------------------------------------------
-- Config panels (open over the menu; the menu underneath keeps its scroll and values)
----------------------------------------------------------------------------
local layer = new("Frame", { Name = "ConfigLayer", Visible = false, Active = true, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
	BorderSizePixel = 0, Position = UDim2.fromOffset(-4, -66), Size = UDim2.new(1, 8, 1, 70), ZIndex = 20, Parent = panel }, { corner(16) })
local modals: { [string]: Frame } = {}
local openModal: string? = nil
local returnFocus: GuiObject? = nil
local MODAL_BACK = "AetherwakeSettingsConfigBack"

local function onPad(): boolean
	return player:GetAttribute("InputMode") == "Gamepad"
end
local function firstButtonIn(root: Instance): GuiObject?
	local best, bestY = nil, math.huge
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Selectable and d.Name ~= "Close" and d.AbsolutePosition.Y < bestY then
			best, bestY = d, d.AbsolutePosition.Y
		end
	end
	return best
end

local function closeModal()
	local name = openModal
	if not name then return end
	openModal = nil
	ContextActionService:UnbindAction(MODAL_BACK)
	local m = modals[name]
	local sc = m:FindFirstChild("PopScale") :: UIScale
	TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.88 }):Play()
	TweenService:Create(layer, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
	task.delay(0.12, function()
		if openModal ~= nil then return end
		layer.Visible = false
		m.Visible = false
	end)
	if returnFocus and onPad() then
		local back = returnFocus
		task.defer(function() pcall(function() GuiService.SelectedObject = back end) end)
	end
	returnFocus = nil
end

local modalRefresh: { [string]: () -> () } = {}
local function showModal(name: string)
	local m = modals[name]
	if not m then return end
	returnFocus = GuiService.SelectedObject
	for n, other in modals do other.Visible = n == name end
	openModal = name
	layer.Visible = true
	layer.BackgroundTransparency = 1
	TweenService:Create(layer, QUICK, { BackgroundTransparency = 0.35 }):Play()
	local sc = m:FindFirstChild("PopScale") :: UIScale
	sc.Scale = 0.85
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	if modalRefresh[name] then modalRefresh[name]() end
	-- B (controller) closes the Config panel first, not the whole menu
	ContextActionService:BindActionAtPriority(MODAL_BACK, function(_, state)
		if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		closeModal()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.ButtonB)
	if onPad() then
		task.delay(0.05, function()
			local first = firstButtonIn(m)
			if first and openModal == name then pcall(function() GuiService.SelectedObject = first end) end
		end)
	end
end

-- a Config panel: same black + gold look, its own header and close button, a scrolling body
local function makeModal(name: string, titleText: string): ScrollingFrame
	local m = new("Frame", { Name = name, Visible = false, Active = true, BackgroundColor3 = C.bg, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 460), ZIndex = 21, SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop, SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop, SelectionBehaviorRight = Enum.SelectionBehavior.Stop, Parent = layer },
		{ corner(14), new("UIStroke", { Thickness = 3, Color = C.border }), new("UIScale", { Name = "PopScale" }) })
	dotPattern(m, Vector2.new(16, 448), 14, 3, 21)
	local head = new("Frame", { Name = "Header", BackgroundColor3 = C.gold, Size = UDim2.new(1, 0, 0, 56), ZIndex = 22, Parent = m },
		{ corner(14), new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.goldLight, C.gold) }) })
	-- (square off the header's bottom corners)
	new("Frame", { BackgroundColor3 = C.gold, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), ZIndex = 22, Parent = head })
	local t = text({ Text = titleText, TextSize = 36, ZIndex = 23, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -100, 1, 0), Parent = head }, 0)
	new("UIStroke", { Thickness = 3, Color = rgb(238, 112, 14), Parent = t })
	local x = new("TextButton", { Name = "Close", Text = "X", Font = FONT, TextSize = 30, TextColor3 = C.text, AutoButtonColor = true, BackgroundColor3 = C.red,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(44, 44), ZIndex = 24, Parent = head },
		{ corner(8), new("UIStroke", { Thickness = 2, Color = C.ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	feedback(x)
	x.Activated:Connect(function()
		click()
		closeModal()
	end)
	local body = new("ScrollingFrame", { Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -26, 1, -78), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.gold, ZIndex = 22, Parent = m }, {
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }),
	})
	modals[name] = m
	return body
end

local function note(parent: Instance, s: string, layoutOrder: number, color: Color3?)
	local l = text({ Name = "Note", Text = s, TextSize = 18, TextColor3 = color or C.sub, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -8, 0, 0), LayoutOrder = layoutOrder, ZIndex = 23, Parent = parent }, 0)
	return l
end

-- Auto Attack: on / off (needs the pass) and which enemy it picks (the AttackPriority setting)
do
	local body = makeModal("AutoAttackConfig", "Auto Attack")
	local row, label = rowFrame(body, "AutoAttackToggle", "Auto Attack", 1, "Your champions find and fight enemies by themselves.")
	row.ZIndex = 23
	label.ZIndex = 24
	local sw = switch(row)
	sw.frame.ZIndex = 24
	sw.frame:FindFirstChild("Knob").ZIndex = 25
	local passTag = text({ Name = "Tag", Text = "NEEDS PASS", TextSize = 16, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -92, 0.5, 0), Size = UDim2.fromOffset(140, 24), ZIndex = 24, Parent = row }, 1)
	local function refreshToggle()
		local owned = player:GetAttribute("PassAutoAttack") == true
		passTag.Visible = not owned
		sw.set(owned and player:GetAttribute("AutoAttack") == true)
	end
	feedback(row, sw.frame)
	row.Activated:Connect(function()
		click()
		if player:GetAttribute("PassAutoAttack") ~= true then
			-- same as the HUD's AUTO button without the pass: off to the Store
			pcall(function() command:Invoke("toast", "Unlock Auto Attack in the Store!") end)
			closeModal()
			pcall(function() command:Invoke("toggle", "Store") end)
			return
		end
		local want = player:GetAttribute("AutoAttack") ~= true
		sw.set(want)
		fire("SetToggle", "autoAttack", want)
		task.delay(1.5, refreshToggle)
	end)
	for _, a in { "PassAutoAttack", "AutoAttack" } do player:GetAttributeChangedSignal(a):Connect(refreshToggle) end

	local d = Settings.ByKey.AttackPriority
	note(body, "TARGET PRIORITY: which enemy Auto Attack picks next", 2, C.gold).TextSize = 20
	local DESCRIBE = {
		Nearest = "The closest enemy first.",
		["Bosses First"] = "The boss whenever it's in range, then the closest.",
		Weakest = "Lowest health first: lots of quick kills.",
		Strongest = "Highest health first.",
	}
	local grid = new("Frame", { Name = "Options", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3, ZIndex = 23, Parent = body }, {
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 78), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local chips: { [string]: { b: TextButton, stroke: UIStroke, name: TextLabel } } = {}
	local function refreshChips()
		local current = pref("AttackPriority")
		for option, chip in chips do
			local on = option == current
			TweenService:Create(chip.b, QUICK, { BackgroundColor3 = if on then rgb(70, 54, 18) else C.row }):Play()
			chip.stroke.Color = if on then C.gold else rgb(60, 60, 66)
			chip.name.TextColor3 = if on then C.goldLight else C.text
		end
	end
	for i, option in d.options :: { string } do
		local b = new("TextButton", { Name = option, Text = "", AutoButtonColor = false, BackgroundColor3 = C.row, LayoutOrder = i, ZIndex = 23, Parent = grid },
			{ corner(10) })
		local st = new("UIStroke", { Thickness = 2, Color = rgb(60, 60, 66), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
		local n = text({ Text = option, TextSize = 24, ZIndex = 24, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -24, 0, 28), Parent = b })
		text({ Text = DESCRIBE[option] or "", TextSize = 16, TextColor3 = C.sub, TextWrapped = true, ZIndex = 24, Position = UDim2.fromOffset(16, 38),
			Size = UDim2.new(1, -24, 0, 34), TextYAlignment = Enum.TextYAlignment.Top, Parent = b }, 0)
		chips[option] = { b = b, stroke = st, name = n }
		feedback(b)
		b.Activated:Connect(function()
			click()
			holdLocal("AttackPriority", 1.2)
			sendPref("AttackPriority", option, true)
			local current = option
			for o, chip in chips do
				local on = o == current
				chip.stroke.Color = if on then C.gold else rgb(60, 60, 66)
				chip.name.TextColor3 = if on then C.goldLight else C.text
				TweenService:Create(chip.b, QUICK, { BackgroundColor3 = if on then rgb(70, 54, 18) else C.row }):Play()
			end
		end)
	end
	onRefresh("AttackPriority", refreshChips)
	note(body, "Abilities need no setting: every champion casts its own after 5 hits. Clicking an enemy still picks your target, Auto Attack or not.", 4)
	modalRefresh.AutoAttackConfig = function()
		refreshToggle()
		refreshChips()
	end
end

-- Orb Config: pick champions to delete the moment they're summoned (75% of the orb price back)
do
	local body = makeModal("OrbConfig", "Orb Config")
	note(body, string.format("Picked champions are deleted the moment you summon them, and you get %d%% of the orb's price back. "
		.. "They still count for the Index. Legendary and Mythic champions can't be picked, so a great pull is never lost.",
		math.floor(Settings.AutoDeleteRefund * 100 + 0.5)), 1)
	local picked: { [string]: boolean } = {}
	local function readPicked()
		table.clear(picked)
		for id in string.gmatch(tostring(player:GetAttribute("Pref_AutoDelete") or ""), "[^,]+") do picked[id] = true end
	end
	local switches: { [string]: Switch } = {}
	local shownPick: { [string]: boolean } = {} -- what each switch shows
	local localPick: { [string]: number } = {}  -- (a tapped switch keeps its new state this long)
	local function refreshAll()
		readPicked()
		for id, sw in switches do
			if (localPick[id] or 0) <= os.clock() then
				shownPick[id] = picked[id] == true
				sw.set(shownPick[id], true)
			end
		end
	end
	local n = 1
	for _, w in Config.Worlds do
		local list = {}
		for _, c in Config.Champions do
			if c.world == w.id and not Config.RarityAtLeast(c.rarity, "Legendary") then table.insert(list, c) end
		end
		if #list > 0 then
			table.sort(list, function(a, b)
				local ra, rb = Config.RarityById[a.rarity].rank, Config.RarityById[b.rarity].rank
				if ra ~= rb then return ra < rb end
				return a.name < b.name
			end)
			n += 1
			local h = text({ Name = w.key .. "Title", Text = w.orb.name .. "  ·  " .. w.name, TextSize = 26, ZIndex = 23, Size = UDim2.new(1, 0, 0, 36),
				LayoutOrder = n, Parent = body }, 2)
			new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.goldLight, C.orange), Parent = h })
			for _, c in list do
				n += 1
				local rarity = Config.RarityById[c.rarity]
				local row, label = rowFrame(body, c.id, c.name, n, "On = " .. c.name .. " is deleted when you summon it (" .. w.orb.name .. ").")
				row.ZIndex = 23
				label.ZIndex = 24
				label.Size = UDim2.new(0.5, -22, 1, 0)
				text({ Name = "Rarity", Text = c.rarity, TextSize = 18, TextColor3 = rarity.color, ZIndex = 24, Position = UDim2.new(0.5, 0, 0, 0),
					Size = UDim2.new(0.3, 0, 1, 0), Parent = row })
				local sw = switch(row)
				sw.frame.ZIndex = 24
				sw.frame:FindFirstChild("Knob").ZIndex = 25
				switches[c.id] = sw
				feedback(row, sw.frame)
				row.Activated:Connect(function()
					click()
					local want = not shownPick[c.id]
					shownPick[c.id] = want
					sw.set(want)
					localPick[c.id] = os.clock() + 1.2
					task.delay(1.25, refreshAll)
					fire("SetAutoDelete", c.id, want)
				end)
			end
		end
	end
	player:GetAttributeChangedSignal("Pref_AutoDelete"):Connect(refreshAll)
	refreshAll()
	modalRefresh.OrbConfig = refreshAll
end

-- Config panels for systems the game doesn't have yet: clearly marked, nothing to change
local function placeholder(cfg: any, icon: string, what: string)
	local body = makeModal(cfg.key, cfg.label)
	local box = new("Frame", { Name = "ComingSoon", BackgroundColor3 = C.row, Size = UDim2.new(1, 0, 0, 300), LayoutOrder = 1, ZIndex = 23, Parent = body },
		{ corner(12) })
	text({ Text = icon, TextSize = 80, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24, Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 100), Parent = box }, 0)
	local t = text({ Text = "COMING SOON", TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24, Position = UDim2.fromOffset(0, 130),
		Size = UDim2.new(1, 0, 0, 48), Parent = box }, 2)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.goldLight, C.orange), Parent = t })
	text({ Text = what, TextSize = 20, TextColor3 = C.sub, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 24,
		Position = UDim2.fromOffset(30, 190), Size = UDim2.new(1, -60, 0, 90), Parent = box }, 0)
end

----------------------------------------------------------------------------
-- the main list, from Settings.List (Gameplay puts the Config buttons after Auto Click,
-- like the reference layout)
----------------------------------------------------------------------------
local configsBySection = { Gameplay = Settings.Configs }
local CONFIGS_AFTER = "AutoClick"
local PLACEHOLDER = {
	GearConfig = { "🛡️", "Gear isn't in Aetherwake yet. When it arrives, this is where you'll choose what to keep and what to auto-equip." },
	RuneConfig = { "🔮", "Runes aren't in Aetherwake yet. When they arrive, this is where you'll set them up." },
}

local function addConfigRows(section: string)
	for _, cfg in configsBySection[section] or {} do
		local row = rowFrame(scroll, cfg.key, cfg.label, nextOrder(), cfg.hint)
		if not modals[cfg.key] then
			local p = PLACEHOLDER[cfg.key] or { "✨", cfg.label .. " isn't in Aetherwake yet." }
			placeholder(cfg, p[1], p[2])
		end
		if cfg.status ~= "live" then tag(row, "COMING SOON", C.orange, 172) end
		local b = configButton(row, function()
			showHint(cfg.hint)
			showModal(cfg.key)
		end)
		row.Selectable = false -- (the controller lands on the Config button itself)
		row.Activated:Connect(function()
			showHint(cfg.hint)
			click()
			showModal(cfg.key)
		end)
		b.SelectionGained:Connect(function() showHint(cfg.hint) end)
	end
end

for _, section in Settings.Sections do
	sectionTitle(scroll, section, nextOrder())
	local configsPlaced = false
	for _, d in Settings.List do
		if d.section == section and not d.panel then
			if d.kind == "toggle" then
				toggleRow(scroll, d, nextOrder())
			elseif d.kind == "slider" then
				sliderRow(scroll, d, nextOrder())
			end
			if d.key == CONFIGS_AFTER then
				addConfigRows(section)
				configsPlaced = true
			end
		end
	end
	if not configsPlaced then addConfigRows(section) end
end

----------------------------------------------------------------------------
-- keeping it in sync, opening and closing
----------------------------------------------------------------------------
player.AttributeChanged:Connect(function(name: string)
	if string.sub(name, 1, 5) ~= "Pref_" then return end
	local key = string.sub(name, 6)
	refresh(key)
	if key == GROUP_KEYS.Music or key == GROUP_KEYS.Ambience or key == GROUP_KEYS.GUI then applyVolumes() end
end)
player:GetAttributeChangedSignal("PrefsReady"):Connect(function()
	for key in refreshers do refresh(key) end
	applyVolumes()
end)

closeBtn.Activated:Connect(function()
	click()
	pcall(function() command:Invoke("toggle", "Settings") end)
end)

panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if not panel.Visible then
		-- (closing the menu closes its Config panel too; the list keeps its scroll position)
		if openModal then
			local m = modals[openModal]
			openModal = nil
			ContextActionService:UnbindAction(MODAL_BACK)
			layer.Visible = false
			m.Visible = false
		end
		bindAdjust(nil)
		showHint(nil)
	end
end)

-- join the HUD's menu system (the ⚙️ button and the controller go through it)
local ok, registered = pcall(function() return command:Invoke("register", panel) end)
if not ok or registered ~= true then
	warn("[SettingsMenu] the HUD doesn't know the \"register\" command yet, so the Settings button can't open this menu")
end
