-- HUD (client): every menu and on-screen display.
-- Layout (like big anime simulators): stats + 3x3 menu grid on the left,
-- auto-attack button bottom-centre, multipliers bottom-right, goal tracker right.
-- Built in code so it's easy to restyle in one place (see THEME).
-- Designed at 1280x720 and scaled to fit any screen (phones included).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Lighting = game:GetService("Lighting")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage.Shared:WaitForChild("Format"))
local Quests = require(ReplicatedStorage.Shared:WaitForChild("Quests"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityInfo = require(ReplicatedStorage.Shared:WaitForChild("AbilityInfo"))
local Models = ReplicatedStorage:WaitForChild("ChampionModels")
local player = Players.LocalPlayer

-- Newer Config tables (Passes, Shop, Fusion, UpdateLog...) are read through CFG so a
-- missing or renamed one never breaks the HUD: every use below has a fallback.
local CFG = Config :: any

-- Remotes are created by the server when it starts, so look them up when they're needed.
local function getRemote(name: string): Instance?
	return Remotes:FindFirstChild(name) or Remotes:WaitForChild(name, 3)
end
-- Calls a RemoteFunction safely. Returns ok, message (never errors).
local function invoke(name: string, ...: any): (boolean, any)
	local rf = getRemote(name)
	if not rf or not rf:IsA("RemoteFunction") then return false, "That isn't ready yet. Try again in a moment!" end
	local ok, a, b = pcall((rf :: RemoteFunction).InvokeServer, rf, ...)
	if not ok then return false, "Something went wrong. Try again." end
	return a == true, b
end
-- Fires a RemoteEvent if it exists. Returns whether it was sent.
local function fire(name: string, ...: any): boolean
	local re = getRemote(name)
	if not re or not re:IsA("RemoteEvent") then return false end
	(re :: RemoteEvent):FireServer(...)
	return true
end

local THEME = {
	panel = Color3.fromRGB(24, 26, 44),
	panel2 = Color3.fromRGB(38, 42, 72),
	stroke = Color3.fromRGB(10, 10, 20),
	orange = Color3.fromRGB(255, 150, 40),
	text = Color3.fromRGB(255, 255, 255),
	sub = Color3.fromRGB(180, 190, 230),
	gold = Color3.fromRGB(255, 200, 50),
	gem = Color3.fromRGB(80, 200, 255),
	red = Color3.fromRGB(255, 85, 85),
	green = Color3.fromRGB(80, 215, 105),
	purple = Color3.fromRGB(150, 110, 255),
	font = Enum.Font.FredokaOne,
}

----------------------------------------------------------------------------
-- tiny UI helpers
----------------------------------------------------------------------------
local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	for _, c in children or {} do c.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end
local function corner(r: number?) return new("UICorner", { CornerRadius = UDim.new(0, r or 12) }) end
local function stroke(t: number?, c: Color3?) return new("UIStroke", { Thickness = t or 3, Color = c or THEME.stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function gradient(top: Color3, bottom: Color3) return new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom) }) end

local function label(props: { [string]: any }): TextLabel
	local base = { BackgroundTransparency = 1, Font = THEME.font, TextColor3 = THEME.text, TextScaled = true }
	for k, v in props do base[k] = v end
	local l = new("TextLabel", base)
	new("UIStroke", { Thickness = 2, Color = THEME.stroke, Parent = l })
	return l
end

-- Sounds from SummonTiers (only verified ids live there): a soft click for every button
-- and a chime for boss rewards. (Optional: if the module is missing, the HUD stays silent.)
local UI_SOUNDS: { [string]: Sound } = {}
do
	local mod = ReplicatedStorage.Shared:FindFirstChild("SummonTiers")
	local ok, tiers = pcall(function() return mod and require(mod) end)
	local sfx = if ok and type(tiers) == "table" and type(tiers.SFX) == "table" then tiers.SFX else {}
	for key, info in { click = { sfx.uiClick, 0.25 }, chime = { sfx.chimeBright, 0.45 } } do
		if type(info[1]) == "string" then
			UI_SOUNDS[key] = new("Sound", { Name = "HUD_" .. key, SoundId = info[1], Volume = info[2], Parent = game:GetService("SoundService") })
		end
	end
end
local lastClickAt = 0
local function playUiSound(key: string)
	local s = UI_SOUNDS[key]
	if not s then return end
	if key == "click" then
		-- (one click per press, even when two handlers ask for it)
		if os.clock() - lastClickAt < 0.06 then return end
		lastClickAt = os.clock()
	end
	s.TimePosition = 0
	s:Play()
end

-- Button feedback: a button grows a little under the mouse, squashes when pressed and
-- clicks. One UIScale ("ClickScale") per button does both, so they never fight.
local hoveredButtons: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function clickScaleOf(g: GuiObject): UIScale
	return g:FindFirstChild("ClickScale") or new("UIScale", { Name = "ClickScale", Parent = g })
end
local function bounce(g: GuiObject)
	local sc = clickScaleOf(g)
	sc.Scale = 0.88
	TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = if hoveredButtons[g] then 1.05 else 1 }):Play()
	if g:IsA("GuiButton") then playUiSound("click") end
end
-- (no hover on touch screens: a tap would leave the button stuck big)
local function feedback(b: GuiButton)
	b.MouseEnter:Connect(function()
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		hoveredButtons[b] = true
		TweenService:Create(clickScaleOf(b), TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		hoveredButtons[b] = nil
		TweenService:Create(clickScaleOf(b), TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	end)
end

local function button(props: { [string]: any }, onClick: () -> ()): TextButton
	local color = props.Color or THEME.panel2
	props.Color = nil
	local base = { BackgroundColor3 = color, Font = THEME.font, TextColor3 = THEME.text, TextScaled = true, AutoButtonColor = true, Text = "" }
	for k, v in props do base[k] = v end
	local b = new("TextButton", base, { corner(12), stroke(3) })
	new("UIStroke", { Thickness = 2, Color = THEME.stroke, Parent = b })
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = b })
	feedback(b)
	b.Activated:Connect(function() bounce(b); onClick() end)
	return b
end

----------------------------------------------------------------------------
-- root
----------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "HUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui") })
local canvas = new("Frame", { Name = "Canvas", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1280, 720), Parent = gui })
local uiScale = new("UIScale", { Parent = canvas })
-- Consoles (Xbox / PlayStation on a TV): TVs can cut off the edges of the picture, so the HUD is
-- kept inside a safe area 5% in from every edge. canvasSafe = that margin in canvas units
-- (full-screen panels still paint their background over it; see makeFullscreen).
local canvasSafe = { x = 0, y = 0, changed = new("BindableEvent", {}) }
local function rescale()
	local vp = workspace.CurrentCamera.ViewportSize
	local tv = game:GetService("GuiService"):IsTenFootInterface()
	local margin = if tv then 0.05 else 0
	local usable = vp * (1 - margin * 2)
	local sc = math.clamp(math.min(usable.X / 1280, usable.Y / 720), 0.5, 2)
	uiScale.Scale = sc
	canvas.Size = UDim2.fromOffset(usable.X / sc, usable.Y / sc)
	canvasSafe.x, canvasSafe.y = vp.X * margin / sc, vp.Y * margin / sc
	canvasSafe.changed:Fire()
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

----------------------------------------------------------------------------
-- toast messages
----------------------------------------------------------------------------
-- (ZIndex 10 so toasts show on top of any open menu)
local toastHolder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.fromOffset(520, 200), ZIndex = 10, Parent = canvas }, {
	new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
-- Tidy stacking: at most 3 toasts on screen (the oldest leaves first), and the same message
-- again just refreshes the one already showing ("x2") instead of stacking a copy.
local TOAST = { max = 3, life = 2.6 }
local liveToasts: { any } = {}
local toastOrder = 0
local function removeToast(t: any)
	local i = table.find(liveToasts, t)
	if not i then return end
	table.remove(liveToasts, i)
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(t.scale, info, { Scale = 0.85 }):Play()
	TweenService:Create(t.frame, info, { BackgroundTransparency = 1 }):Play()
	for _, d in t.frame:GetDescendants() do
		if d:IsA("TextLabel") then TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("Frame") then TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then TweenService:Create(d, info, { Transparency = 1 }):Play() end
	end
	task.delay(0.24, function() t.frame:Destroy() end)
end
local function toast(text: string, color: Color3?)
	text = tostring(text)
	for _, t in liveToasts do
		if t.text == text then
			t.count += 1
			t.label.Text = text .. "  x" .. t.count
			t.expires = os.clock() + TOAST.life
			t.scale.Scale = 1.08
			TweenService:Create(t.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			return
		end
	end
	while #liveToasts >= TOAST.max do removeToast(liveToasts[1]) end
	toastOrder += 1
	-- long messages get two lines instead of shrinking to tiny text
	local tall = #text > 44
	local f = new("Frame", { Name = "Toast", BackgroundColor3 = THEME.panel, Size = UDim2.fromOffset(480, if tall then 62 else 44), LayoutOrder = toastOrder,
		Parent = toastHolder }, { corner(14), stroke(3, color or THEME.stroke) })
	new("Frame", { Name = "Accent", BackgroundColor3 = color or THEME.purple, Position = UDim2.fromOffset(9, 9), Size = UDim2.new(0, 6, 1, -18), Parent = f }, { corner(3) })
	local l = label({ Text = text, TextWrapped = true, Size = UDim2.new(1, -40, 1, -10), Position = UDim2.fromOffset(26, 5), TextColor3 = color or THEME.text, Parent = f })
	new("UITextSizeConstraint", { MaxTextSize = 26, Parent = l })
	local sc = new("UIScale", { Scale = 0.8, Parent = f })
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local t = { frame = f, label = l, scale = sc, text = text, count = 1, expires = os.clock() + TOAST.life }
	table.insert(liveToasts, t)
	task.spawn(function()
		while f.Parent and os.clock() < t.expires do task.wait(0.1) end
		removeToast(t)
	end)
end

-- Reads a number attribute, or `fallback` while the server hasn't set it yet.
local function attrNumber(name: string, fallback: number): number
	local v = player:GetAttribute(name)
	return if type(v) == "number" then v else fallback
end
-- "equip=0,inventory=1" (or "W1=3,W2=0") -> { equip = 0, inventory = 1 }
local function parsePairs(text: any): { [string]: number }
	local out = {}
	for k, v in string.gmatch(tostring(text or ""), "([%w_]+)=(%d+)") do out[k] = tonumber(v) :: number end
	return out
end
-- Fades a piece of UI (and everything inside it) to invisible.
local function fadeAway(g: Instance, time: number)
	local info = TweenInfo.new(time)
	local function fadeOne(d: Instance)
		if d:IsA("TextLabel") or d:IsA("TextButton") then TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("ViewportFrame") then TweenService:Create(d, info, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("Frame") then TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then TweenService:Create(d, info, { Transparency = 1 }):Play() end
	end
	fadeOne(g)
	for _, d in g:GetDescendants() do fadeOne(d) end
end

----------------------------------------------------------------------------
-- LEFT SIDE: DPS, currencies, 3x3 menu grid
----------------------------------------------------------------------------
local left = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.56, 0),
	Size = UDim2.fromOffset(250, 420), Parent = canvas }, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local dpsPill = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Size = UDim2.fromOffset(150, 30), LayoutOrder = 1, Parent = left }, { corner(8) })
local dpsText = label({ Text = "DPS : 0", Size = UDim2.new(1, -16, 0.8, 0), Position = UDim2.new(0, 8, 0.1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = dpsPill })

local function currencyPill(order: number, icon: string, color: Color3, onPlus: () -> ())
	local f = new("Frame", { BackgroundColor3 = THEME.panel, Size = UDim2.fromOffset(240, 50), LayoutOrder = order, Parent = left },
		{ corner(25), stroke(3, color:Lerp(Color3.new(0, 0, 0), 0.35)), gradient(Color3.fromRGB(40, 36, 30), Color3.fromRGB(18, 16, 22)) })
	local badge = new("Frame", { BackgroundColor3 = color, Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(6, 5), Parent = f }, { corner(20), stroke(2) })
	label({ Text = icon, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), Parent = badge })
	local value = label({ Text = "0", Size = UDim2.new(1, -100, 0.7, 0), Position = UDim2.new(0, 52, 0.15, 0), TextColor3 = color, Parent = f })
	local plus = button({ Color = color, Text = "+", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(38, 38), Parent = f }, onPlus)
	plus:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	return value
end
local grid = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 240), LayoutOrder = 4, Parent = left }, {
	new("UIGridLayout", { CellSize = UDim2.fromOffset(72, 72), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local panels: { [string]: Frame } = {}
local openPanel: string? = nil
local refreshers: { [string]: () -> () } = {}
-- Summon state (the summon UI further down drives it): "idle", "cinematic" (the summon
-- sequence is playing at the altar) or "results" (the result screen is up).
local summonPhase = "idle"
local closeSummonResults: (boolean?, boolean?) -> () = function() end -- set by the summon UI
-- Full-screen panels (the Galaxy Map, the summon overlay) are registered here by
-- makeFullscreen (below the panel helper). While one is open the rest of the HUD hides.
local fullscreen: { [string]: any } = {
	panels = {},                           -- name -> its controls (opening, closing, animateIn)
	on = false,                            -- true while a full-screen panel is open
	setChrome = function(_on: boolean) end, -- hides / restores the rest of the HUD (set below)
}

-- (each panel's close animation has a token, so opening it again mid-close cancels the hide)
local panelCloseToken: { [string]: number } = {}
local function showPanel(name: string?)
	if name and not panels[name] then return end
	-- no menus over the summon cinematic (they'd cover the altar and the champion);
	-- opening a menu from the result screen closes the result screen first
	if name and summonPhase == "cinematic" then return end
	if name and summonPhase == "results" then closeSummonResults(true) end
	for n, p in panels do
		panelCloseToken[n] = (panelCloseToken[n] or 0) + 1
		if n == name then
			p.Visible = true
		elseif p.Visible and name == nil then
			-- closing (X, the same button again, a teleport...): a quick shrink, then hide.
			-- (switching straight to another menu hides the old one at once, so two never overlap)
			local token = panelCloseToken[n]
			if fullscreen.panels[n] then
				-- (full-screen panels fade instead: a shrink would show the world at the edges)
				fullscreen.panels[n].closing(0.12)
			else
				local sc = p:FindFirstChild("OpenScale") :: UIScale
				TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.86 }):Play()
			end
			task.delay(0.12, function()
				if panelCloseToken[n] == token then p.Visible = false end
			end)
		else
			if p.Visible and fullscreen.panels[n] then fullscreen.panels[n].closing(0) end
			p.Visible = false
		end
	end
	openPanel = name
	gui:SetAttribute("OpenPanel", name) -- (ControllerSupport reads it to move the controller focus)
	-- A full-screen panel hides the rest of the HUD. Closing it puts the HUD back straight away,
	-- not after its fade: the summon cinematic saves the HUD's state right after showPanel(nil).
	local fsOpen = if name then fullscreen.panels[name] else nil
	-- (asking again for the full-screen panel that's already open, e.g. the shrine's E pressed
	-- again, only refreshes it: no second opening and no flash)
	local fsAlready = fsOpen ~= nil and fsOpen.isOpen()
	fullscreen.setChrome(fsOpen ~= nil)
	if fsOpen and not fsAlready then fsOpen.opening() end
	if name and refreshers[name] then refreshers[name]() end
	if fsOpen then
		if not fsAlready then fsOpen.animateIn() end
	elseif name then
		local sc = panels[name]:FindFirstChild("OpenScale") :: UIScale
		sc.Scale = 0.85
		TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end
local function togglePanel(name: string) showPanel(if openPanel == name then nil else name) end

local function gridButton(order: number, icon: string, text: string, onClick: () -> ())
	local b = new("TextButton", { Name = text .. "Button", Text = "", AutoButtonColor = true, BackgroundColor3 = THEME.panel, LayoutOrder = order, Parent = grid },
		{ corner(14), stroke(4, THEME.orange), gradient(Color3.fromRGB(60, 50, 40), Color3.fromRGB(20, 18, 26)) })
	label({ Text = icon, Size = UDim2.new(1, -16, 0.62, 0), Position = UDim2.new(0, 8, 0.06, 0), Parent = b })
	label({ Text = text, Size = UDim2.new(1, -6, 0.26, 0), Position = UDim2.new(0, 3, 0.7, 0), Parent = b })
	feedback(b)
	b.Activated:Connect(function() bounce(b); onClick() end)
	return b
end
local function soon(feature: string) return function() toast(feature .. " is coming soon!", THEME.orange) end end
-- the + on coins / gems opens the Store
local coinsText = currencyPill(2, "$", THEME.gold, function() togglePanel("Store") end)
local gemsText = currencyPill(3, "◆", THEME.gem, function() togglePanel("Store") end)
gridButton(1, "🛒", "Shop", function() togglePanel("Store") end)
gridButton(2, "🎒", "Champions", function() togglePanel("Champions") end)
gridButton(3, "📖", "Index", function() togglePanel("Index") end)
gridButton(4, "🌀", "Teleport", function() togglePanel("Worlds") end)
gridButton(5, "⏫", "Upgrades", function() togglePanel("Upgrades") end)
gridButton(6, "📜", "Quests", function() togglePanel("Quests") end)
gridButton(7, "📰", "Updates", function() togglePanel("Updates") end)
gridButton(8, "⚙️", "Settings", soon("Settings"))
gridButton(9, "❓", "Help", function() togglePanel("Help") end)

----------------------------------------------------------------------------
-- TOP: world name + version
----------------------------------------------------------------------------
local worldPill = new("Frame", { BackgroundColor3 = THEME.panel, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(300, 46), Parent = canvas }, { corner(23), stroke(3, THEME.purple) })
local worldText = label({ Text = "", Size = UDim2.new(1, -24, 0.8, 0), Position = UDim2.new(0, 12, 0.1, 0), Parent = worldPill })
local version = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(150, 42), Parent = canvas }, { corner(8) })
-- newest update first, whatever order Config.UpdateLog is written in
local function versionNumbers(v: any): { number }
	local nums = {}
	for part in string.gmatch(tostring(v or "0"), "%d+") do table.insert(nums, tonumber(part) :: number) end
	return nums
end
local function updateLog(): { any }
	local list = {}
	if type(CFG.UpdateLog) == "table" then
		for _, e in CFG.UpdateLog do if type(e) == "table" then table.insert(list, e) end end
	end
	table.sort(list, function(a, b)
		local va, vb = versionNumbers(a.version), versionNumbers(b.version)
		for i = 1, math.max(#va, #vb) do
			local x, y = va[i] or 0, vb[i] or 0
			if x ~= y then return x > y end
		end
		return false
	end)
	return list
end
local latestUpdate = updateLog()[1]
label({ Text = "Update " .. tostring(latestUpdate and latestUpdate.version or "1.1"), Size = UDim2.new(1, -12, 0.8, 0), Position = UDim2.new(0, 6, 0.1, 0), Parent = version })
-- tapping the version pill opens the update log
new("TextButton", { Name = "VersionButton", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = version }).Activated:Connect(function()
	bounce(version)
	playUiSound("click")
	togglePanel("Updates")
end)

----------------------------------------------------------------------------
-- RIGHT: goal tracker
----------------------------------------------------------------------------
local goal = new("Frame", { BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 64),
	Size = UDim2.fromOffset(290, 116), Parent = canvas }, { corner(14), stroke(3, THEME.gold) })
local goalTitle = label({ Text = "TUTORIAL", Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(12, 8), TextColor3 = THEME.gold, TextXAlignment = Enum.TextXAlignment.Left, Parent = goal })
local goalText = label({ Text = "", Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(12, 34), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = goal })
local goalBarBack = new("Frame", { BackgroundColor3 = THEME.stroke, Position = UDim2.new(0, 12, 1, -28), Size = UDim2.new(1, -24, 0, 16), Parent = goal }, { corner(8) })
local goalBar = new("Frame", { BackgroundColor3 = THEME.gold, Size = UDim2.fromScale(0, 1), Parent = goalBarBack }, { corner(8) })
-- During the tutorial QuestClient shows the same goal in its TRAINING card (top left) and
-- sets the TutorialTracker attribute while that card is up, so this box steps aside then
-- (one goal on screen, not two). It also stays hidden while a summon is playing or a
-- full-screen panel (Galaxy Map, summon overlay) is open.
local function applyGoalVisibility()
	goal.Visible = summonPhase == "idle" and not fullscreen.on and player:GetAttribute("TutorialTracker") ~= true
end
player:GetAttributeChangedSignal("TutorialTracker"):Connect(applyGoalVisibility)
applyGoalVisibility()

----------------------------------------------------------------------------
-- BOTTOM RIGHT: multipliers
----------------------------------------------------------------------------
local mults = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.fromOffset(170, 170), Parent = canvas }, { new("UIListLayout", { Padding = UDim.new(0, 5), VerticalAlignment = Enum.VerticalAlignment.Bottom }) })
local function multRow(name: string, color: Color3)
	local f = new("Frame", { BackgroundColor3 = Color3.fromRGB(20, 22, 34), Size = UDim2.fromOffset(170, 34), Parent = mults },
		{ corner(6), new("UIGradient", { Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.35), Color3.fromRGB(20, 22, 34)) }) })
	label({ Text = name, Size = UDim2.new(0.55, 0, 0.75, 0), Position = UDim2.new(0, 8, 0.125, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3), Parent = f })
	return label({ Text = "1x", Size = UDim2.new(0.4, 0, 0.75, 0), Position = UDim2.new(0.55, 0, 0.125, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = f })
end
local luckText = multRow("Luck", Color3.fromRGB(80, 220, 120))
local coinMultText = multRow("Coins", Color3.fromRGB(255, 200, 60))
local damageMultText = multRow("Damage", Color3.fromRGB(255, 90, 90))
local slotsText = multRow("Equip", Color3.fromRGB(150, 120, 255))

----------------------------------------------------------------------------
-- BOTTOM CENTRE: auto hatch + auto attack + equip best
----------------------------------------------------------------------------
local bottom = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(300, 100), Parent = canvas })
local autoBtn = new("TextButton", { Name = "AutoButton", Text = "", AutoButtonColor = true, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.fromOffset(96, 96), BackgroundColor3 = THEME.panel, Parent = bottom }, { corner(48), stroke(5, THEME.orange) })
local autoIcon = label({ Text = "⚔️", Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.12), Parent = autoBtn })
local autoLabel = label({ Text = "AUTO OFF", Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.72), TextColor3 = THEME.sub, Parent = autoBtn })
-- AUTO HATCH sits left of AUTO (same look, a bit smaller, like BEST on the right)
local hatchBtn = new("TextButton", { Name = "AutoHatchButton", Text = "", AutoButtonColor = true, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -58, 1, -8),
	Size = UDim2.fromOffset(70, 70), BackgroundColor3 = THEME.panel, Parent = bottom }, { corner(35), stroke(4, THEME.orange) })
local hatchIcon = label({ Text = "🥚", Size = UDim2.fromScale(0.55, 0.55), Position = UDim2.fromScale(0.225, 0.1), Parent = hatchBtn })
local hatchLabel = label({ Text = "HATCH OFF", Size = UDim2.new(1, -4, 0.24, 0), Position = UDim2.new(0, 2, 0.68, 0), TextColor3 = THEME.sub, Parent = hatchBtn })

-- Both toggles work the same way: locked (🔒) until you own the pass (a tap then opens
-- the Store), after that a tap switches it on/off. The server owns the real on/off state
-- (the AutoAttack / AutoHatch attributes); the button only asks it to change.
local spinners: { UIGradient } = {}
local function wireToggle(b: TextButton, icon: TextLabel, text: TextLabel, opts: { [string]: string }): (() -> (), () -> boolean?)
	local ring = b:FindFirstChildOfClass("UIStroke") :: UIStroke
	-- a white shine that spins around the ring while the toggle is ON
	local shine = new("UIGradient", { Enabled = false, Parent = ring, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.green), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, THEME.green) }) })
	table.insert(spinners, shine)
	local lock = new("Frame", { Name = "Lock", BackgroundColor3 = THEME.gold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.85, 0.15),
		Size = UDim2.fromOffset(28, 28), Parent = b }, { corner(14), stroke(2) })
	label({ Text = "🔒", Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.14), Parent = lock })
	local function show(owned: boolean, on: boolean)
		lock.Visible = not owned
		icon.TextTransparency = if owned then 0 else 0.4
		text.Text = if not owned then "LOCKED" elseif on then opts.onText else opts.offText
		text.TextColor3 = if on then THEME.green elseif owned then THEME.sub else THEME.gold
		ring.Color = if on then Color3.new(1, 1, 1) else THEME.orange
		shine.Enabled = on
	end
	local function refresh()
		local owned = player:GetAttribute(opts.passAttr) == true
		show(owned, owned and player:GetAttribute(opts.onAttr) == true)
	end
	-- A tap: no pass yet = open the Store; otherwise ask the server to switch it. Returns the
	-- state it asked for (nil when it opened the Store). The summon overlay's AUTO HATCH switch
	-- uses this too, so both behave exactly the same.
	local function press(): boolean?
		if player:GetAttribute(opts.passAttr) ~= true then
			toast("Unlock " .. opts.passName .. " in the Store!", THEME.gold)
			showPanel("Store")
			return nil
		end
		local want = player:GetAttribute(opts.onAttr) ~= true
		show(true, want) -- show the change straight away; the server's attribute confirms it
		if want then toast(opts.onToast, THEME.green) end
		if not fire("SetToggle", opts.key, want) and opts.key == "autoAttack" then fire("ToggleAuto", want) end
		task.delay(1.5, refresh) -- if the server said no, go back to the real state
		return want
	end
	b.Activated:Connect(function()
		bounce(b)
		press()
	end)
	return refresh, press
end
RunService.Heartbeat:Connect(function()
	local rot = (os.clock() * 160) % 360
	for _, g in spinners do if g.Enabled then g.Rotation = rot end end
end)
local refreshAutoAttack, pressAutoAttack = wireToggle(autoBtn, autoIcon, autoLabel, { passAttr = "PassAutoAttack", onAttr = "AutoAttack", key = "autoAttack",
	passName = "Auto Attack", onText = "AUTO ON", offText = "AUTO OFF", onToast = "Auto Attack ON: your champions fight by themselves!" })
local refreshAutoHatch, pressAutoHatch = wireToggle(hatchBtn, hatchIcon, hatchLabel, { passAttr = "PassAutoHatch", onAttr = "AutoHatch", key = "autoHatch",
	passName = "Auto Hatch", onText = "HATCH ON", offText = "HATCH OFF", onToast = "Auto Hatch ON: stand near a summon shrine!" })
for _, a in { "PassAutoAttack", "AutoAttack", "PassAutoHatch", "AutoHatch" } do
	player:GetAttributeChangedSignal(a):Connect(function() refreshAutoAttack(); refreshAutoHatch() end)
end
refreshAutoAttack()
refreshAutoHatch()
local bestBtn = new("TextButton", { Name = "BestButton", Text = "", AutoButtonColor = true, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 58, 1, -8),
	Size = UDim2.fromOffset(70, 70), BackgroundColor3 = THEME.panel, Parent = bottom }, { corner(35), stroke(4, THEME.gold) })
label({ Text = "⭐", Size = UDim2.fromScale(0.55, 0.55), Position = UDim2.fromScale(0.225, 0.1), Parent = bestBtn })
label({ Text = "BEST", Size = UDim2.new(1, 0, 0.24, 0), Position = UDim2.fromScale(0, 0.68), TextColor3 = THEME.gold, Parent = bestBtn })
for _, b in { autoBtn, hatchBtn, bestBtn } do feedback(b) end
bestBtn.Activated:Connect(function()
	bounce(bestBtn)
	Remotes.EquipBest:InvokeServer()
	toast("Equipped your strongest champions!", THEME.gold)
end)

----------------------------------------------------------------------------
-- controller bridge: the ControllerSupport LocalScript asks the HUD to open and close menus
-- through this (only the HUD knows how its menus work). Client-only, so nothing to exploit.
----------------------------------------------------------------------------
new("BindableFunction", { Name = "Command", Parent = gui }).OnInvoke = function(command: string, arg: any): any
	if command == "toggle" and type(arg) == "string" then
		togglePanel(arg)
	elseif command == "back" then
		-- B: the summon result screen first, then whatever menu is open (true = it closed something)
		if summonPhase == "results" then closeSummonResults(false) return true end
		if openPanel then showPanel(nil) return true end
		return false
	elseif command == "autoAttack" then
		pressAutoAttack()
	elseif command == "toast" and type(arg) == "string" then
		toast(arg, THEME.orange)
	end
	return nil
end

----------------------------------------------------------------------------
-- panel frame helper
----------------------------------------------------------------------------
local function makePanel(name: string, title: string, accent: Color3, size: Vector2): (Frame, Frame, TextLabel)
	local p = new("Frame", { Name = name, Visible = false, BackgroundColor3 = THEME.panel, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.52, 0.52), Size = UDim2.fromOffset(size.X, size.Y), Parent = canvas },
		{ corner(20), stroke(4, accent), new("UIScale", { Name = "OpenScale" }) })
	local header = new("Frame", { Name = "Header", BackgroundColor3 = accent, Size = UDim2.new(1, 0, 0, 56), Parent = p }, { corner(20), stroke(3) })
	-- a soft shine on the top half of every header (same on all panels, behind the title)
	new("Frame", { Name = "Shine", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 0,
		Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 0.4, 0), Parent = header }, { corner(14) })
	local titleLabel = label({ Text = title, Size = UDim2.new(1, -120, 0.75, 0), Position = UDim2.new(0, 20, 0.125, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = header })
	button({ Color = THEME.red, Text = "X", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(46, 46), Parent = header }, function()
		showPanel(nil)
	end)
	local body = new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 68), Size = UDim2.new(1, -32, 1, -84), Parent = p })
	panels[name] = p
	return p, body, titleLabel
end

----------------------------------------------------------------------------
-- full-screen panel helper (the Galaxy Map uses it, and the summon overlay)
----------------------------------------------------------------------------
-- makeFullscreen(name, opts) builds a panel that covers the WHOLE screen (any screen shape)
-- and plugs into the same panel system as makePanel: showPanel(name) or togglePanel(name)
-- opens it, showPanel(nil) (or opening another menu) closes it.
-- While it's open the rest of the HUD hides (menu grid, currencies, goal box, AUTO buttons,
-- the touch DASH button and, on phones, Roblox's thumbstick + jump button), so nothing
-- covers it or catches its taps. It all comes back the moment it closes. Toasts stay on top.
-- Opening: the background fades in while the content zooms in a little. Closing: a quick fade.
--   opts (all optional):
--     background              Color3 behind everything (default deep space #04050D)
--     backgroundTransparency  0..1 (default 0: the world is hidden behind the panel)
--     closeKeys   keys that close it while it's open (default Escape + gamepad B)
--     onOpen()    runs every time it opens, BEFORE refreshers[name] (reset a selection here)
--     onClose()   runs every time it starts closing
--     onLayout(size)  runs on open and when the screen size changes while it's open.
--                     size = the screen in design pixels (the canvas: 1280 x 720 or bigger)
--     onFrame(dt, t)  per-frame animation (t = os.clock()). It runs from ONE RenderStepped
--                     connection that only exists while the panel is on screen.
-- Returns panel, content, fs:
--   panel    the full-screen Frame named `name` (Active, so taps never reach what's under it)
--   content  a see-through full-screen Frame to build the layout in (it does the zoom-in)
--   fs       { backdrop = a full-screen Frame under `content` (stars, glows...),
--              isOpen = () -> boolean, canvasSize = () -> Vector2 }
local function makeFullscreen(name: string, opts: { [string]: any }?): (Frame, Frame, any)
	local o: { [string]: any } = opts or {}
	local solid = o.backgroundTransparency or 0
	local panel = new("Frame", { Name = name, Visible = false, Active = true, BorderSizePixel = 0, ZIndex = 8, Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = o.background or Color3.fromRGB(4, 5, 13), BackgroundTransparency = solid, Parent = canvas },
		{ new("UIScale", { Name = "OpenScale" }) }) -- (kept for code that looks for one; it stays at 1)
	local backdrop = new("Frame", { Name = "Backdrop", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = panel })
	-- (centred, so the open zoom grows from the middle of the screen: a UIScale scales toward
	-- the AnchorPoint)
	local content = new("Frame", { Name = "Content", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = panel })
	local zoom = new("UIScale", { Name = "ZoomScale", Parent = content })
	-- (consoles: the background also covers the TV safe-area margin around the canvas, while
	-- the content stays inside the safe area)
	local function fitSafe()
		panel.Position = UDim2.fromOffset(-canvasSafe.x, -canvasSafe.y)
		panel.Size = UDim2.new(1, canvasSafe.x * 2, 1, canvasSafe.y * 2)
		content.Size = UDim2.new(1, -canvasSafe.x * 2, 1, -canvasSafe.y * 2)
	end
	canvasSafe.changed.Event:Connect(fitSafe)
	fitSafe()
	local keys = o.closeKeys or { Enum.KeyCode.Escape, Enum.KeyCode.ButtonB }
	local action = "AetherwakeClose" .. name
	local isOpen = false
	local frameConn: RBXScriptConnection? = nil
	local escConn: RBXScriptConnection? = nil -- (watches the Escape key while it's open: see opening)
	local function canvasSize(): Vector2
		return Vector2.new(canvas.Size.X.Offset, canvas.Size.Y.Offset)
	end
	-- runs one of the opts callbacks: a mistake in it is reported instead of breaking the menus
	local function run(fn: any, ...: any)
		if type(fn) ~= "function" then return end
		local ok, err = pcall(fn, ...)
		if not ok then warn("[HUD] " .. name .. ": " .. tostring(err)) end
	end
	local fs: { [string]: any } = { backdrop = backdrop, canvasSize = canvasSize }
	fs.isOpen = function(): boolean return isOpen end
	-- (showPanel calls opening / closing / animateIn; nothing else needs to)
	fs.opening = function()
		isOpen = true
		-- one action per key, so a key Roblox keeps for itself can't stop the others working
		for _, key in keys do
			pcall(function()
				ContextActionService:BindActionAtPriority(action .. key.Name, function(_, state: Enum.UserInputState)
					if state == Enum.UserInputState.Begin and isOpen then showPanel(nil) end
					return Enum.ContextActionResult.Sink
				end, false, Enum.ContextActionPriority.High.Value, key)
			end)
		end
		-- Roblox keeps Escape for its own menu, so a bound action never hears it in a real game:
		-- watch the key itself. (Roblox's menu still opens as well; a game can't stop that.)
		if table.find(keys, Enum.KeyCode.Escape) and not escConn then
			escConn = UserInputService.InputBegan:Connect(function(input: InputObject)
				if input.KeyCode == Enum.KeyCode.Escape and isOpen then showPanel(nil) end
			end)
		end
		run(o.onOpen)
		run(o.onLayout, canvasSize())
		if type(o.onFrame) == "function" and not frameConn then
			frameConn = RunService.RenderStepped:Connect(function(dt: number)
				if not panel.Visible then
					-- hidden: stop (it starts again the next time the panel opens)
					if frameConn then frameConn:Disconnect() end
					frameConn = nil
					return
				end
				local ok, err = pcall(o.onFrame, dt, os.clock())
				if not ok then
					warn("[HUD] " .. name .. " animation stopped: " .. tostring(err))
					if frameConn then frameConn:Disconnect() end
					frameConn = nil
				end
			end)
		end
	end
	fs.closing = function(time: number)
		if isOpen then
			isOpen = false
			for _, key in keys do ContextActionService:UnbindAction(action .. key.Name) end
			if escConn then escConn:Disconnect() end
			escConn = nil
			run(o.onClose)
		end
		if time > 0 then
			local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(panel, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(zoom, info, { Scale = 0.96 }):Play()
		end
	end
	fs.animateIn = function()
		panel.BackgroundTransparency = 1
		zoom.Scale = 0.94
		TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = solid }):Play()
		TweenService:Create(zoom, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	canvas:GetPropertyChangedSignal("Size"):Connect(function()
		if isOpen then run(o.onLayout, canvasSize()) end
	end)
	panels[name] = panel
	fullscreen.panels[name] = fs
	return panel, content, fs
end

-- What a full-screen panel hides, put back exactly as it was when it closes. (The goal box
-- isn't in the list: applyGoalVisibility decides that one, and it knows about fullscreen.on.)
do
	local chrome: { GuiObject } = { left, worldPill, version, mults, bottom }
	local saved: { [Instance]: boolean } = {}
	local savedModal: boolean? = nil
	fullscreen.setChrome = function(on: boolean)
		if on == fullscreen.on then return end
		fullscreen.on = on
		if on then
			for _, g in chrome do
				saved[g] = g.Visible
				g.Visible = false
			end
			-- the touch DASH button lives in its own ScreenGui, drawn above the HUD
			local playerGui = player:FindFirstChildOfClass("PlayerGui")
			local movement = playerGui and playerGui:FindFirstChild("MovementUI")
			if movement and movement:IsA("ScreenGui") then
				saved[movement] = movement.Enabled
				movement.Enabled = false
			end
			if UserInputService.TouchEnabled then
				savedModal = UserInputService.ModalEnabled
				UserInputService.ModalEnabled = true -- (hides Roblox's thumbstick and jump button)
			end
		else
			for g, was in saved do
				if g:IsA("ScreenGui") then (g :: ScreenGui).Enabled = was else (g :: GuiObject).Visible = was end
			end
			table.clear(saved)
			if savedModal ~= nil then
				UserInputService.ModalEnabled = savedModal
				savedModal = nil
			end
		end
		applyGoalVisibility()
	end
end

local function viewport(championId: string, parent: Instance, size: UDim2, pos: UDim2?, silhouette: boolean?)
	local vf = new("ViewportFrame", { BackgroundTransparency = 1, Size = size, Position = pos or UDim2.new(), Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), Parent = parent })
	if silhouette then vf.ImageColor3 = Color3.new(0, 0, 0); vf.ImageTransparency = 0.2 end
	local template = Models:FindFirstChild(championId)
	if template then
		local m = template:Clone()
		m:PivotTo(CFrame.new(0, 0, 0))
		m.Parent = vf
		local cam = new("Camera", { FieldOfView = 30, Parent = vf })
		cam.CFrame = CFrame.lookAt(Vector3.new(0, -0.1, -12.5), Vector3.new(0, -0.35, 0))
		vf.CurrentCamera = cam
	end
	return vf
end

----------------------------------------------------------------------------
-- inventory state
----------------------------------------------------------------------------
-- one owned champion: its id, fusion stars and an optional (filtered) nickname
type Owned = { id: string, stars: number?, name: string? }
local champions: { [string]: Owned } = {}
local equipped: { string } = {}
local discovered: { [string]: boolean } = {}
local function rarityOf(id: string)
	local def = Config.ChampionById[id]
	return Config.RarityById[def and def.rarity or "Common"] or Config.Rarities[1]
end
-- True if `rarityId` is `threshold` or better, by NAME (never compare rank numbers: a new
-- tier would shift them). Uses Config.RarityAtLeast when it exists.
local function rarityAtLeast(rarityId: any, threshold: string): boolean
	if type(CFG.RarityAtLeast) == "function" then
		local ok, result = pcall(CFG.RarityAtLeast, rarityId, threshold)
		if ok then return result == true end
	end
	local r, limit = Config.RarityById[rarityId], Config.RarityById[threshold]
	return r ~= nil and limit ~= nil and (r :: any).rank >= (limit :: any).rank
end
-- "LEGENDARY!" / "MYTHIC!" toast for a great pull
local function bigPullToast(rarityId: string, name: string, color: Color3)
	if rarityAtLeast(rarityId, "Mythic") then
		toast("MYTHIC! " .. name, color)
	elseif rarityAtLeast(rarityId, "Legendary") then
		toast("LEGENDARY! " .. name, color)
	end
end
local function starsOf(owned: Owned): number
	return math.max(0, math.floor(tonumber(owned.stars) or 0))
end
local function starText(n: number): string
	return string.rep("★", n)
end
-- a number from Config.Fusion, or `fallback` if it's missing
local function fusionNumber(key: string, fallback: number): number
	local f = CFG.Fusion
	return if type(f) == "table" and type(f[key]) == "number" then f[key] else fallback
end
-- the nickname if it has one, otherwise the champion's normal name
local function displayName(owned: Owned): string
	if type(owned.name) == "string" and owned.name ~= "" then return owned.name end
	local def = Config.ChampionById[owned.id]
	return def and def.name or owned.id
end
-- damage per hit including fusion stars (same maths as the server's Stats.ChampionPower)
local function powerOf(owned: Owned): number
	local def = Config.ChampionById[owned.id]
	if not def then return 0 end
	return def.power * (1 + starsOf(owned) * fusionNumber("powerPerStar", 0.5))
end
-- what one champion really deals per second: power x your damage multiplier / attack speed
local function dpsOf(owned: Owned): number
	local interval = (CFG.Combat and tonumber(CFG.Combat.AttackInterval)) or 1
	return powerOf(owned) * attrNumber("DamageMult", 1) / math.max(interval, 0.1)
end
-- RichText is on for some labels, so player-made names must not be read as tags
local function escapeRich(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
local openFuse: (string?) -> () = function() end -- set by the Fuse panel below
local refreshFuseCost: () -> () = function() end -- set by the Fuse panel below

----------------------------------------------------------------------------
-- Champions panel
----------------------------------------------------------------------------
do
	local panel, body = makePanel("Champions", "Champions", Color3.fromRGB(255, 120, 90), Vector2.new(840, 580))
	local info = label({ Text = "", Size = UDim2.new(1, -370, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
	button({ Color = THEME.green, Text = "Equip Best", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -4), Size = UDim2.fromOffset(170, 42), Parent = body }, function()
		Remotes.EquipBest:InvokeServer()
	end)
	local cardGrid = new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 140), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder })
	local list = new("ScrollingFrame", { BackgroundColor3 = THEME.panel2, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -172),
		ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, {
		corner(14),
		cardGrid,
		new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
	})
	-- View More: a bigger panel with smaller cards, so about 4x as many champions fit on screen
	-- (quicker to find the ones to release). Only this panel has it; it stays on until turned off.
	local CARD_NORMAL = { panel = Vector2.new(840, 580), cell = Vector2.new(112, 140), gap = 10, pic = 92, name = 96, nameH = 20, power = 116, powerH = 20, starW = 70, starH = 18, tag = 30 }
	local CARD_DENSE = { panel = Vector2.new(1180, 650), cell = Vector2.new(84, 104), gap = 8, pic = 66, name = 70, nameH = 16, power = 86, powerH = 15, starW = 56, starH = 14, tag = 22 }
	local expanded = false
	local expandBtn
	expandBtn = button({ Name = "ExpandButton", Color = THEME.gem, Text = "View More", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -180, 0, -4),
		Size = UDim2.fromOffset(170, 42), Parent = body }, function()
		expanded = not expanded
		local L = if expanded then CARD_DENSE else CARD_NORMAL
		expandBtn.Text = if expanded then "View Less" else "View More"
		panel.Size = UDim2.fromOffset(L.panel.X, L.panel.Y)
		cardGrid.CellSize = UDim2.fromOffset(L.cell.X, L.cell.Y)
		cardGrid.CellPadding = UDim2.fromOffset(L.gap, L.gap)
		refreshers.Champions()
	end)
	local detail = new("Frame", { BackgroundColor3 = THEME.panel2, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 118), Parent = body }, { corner(14) })
	local detailPic = new("Frame", { BackgroundColor3 = THEME.panel, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(102, 102), Parent = detail }, { corner(12) })
	local function detailLine(y: number, h: number, color: Color3?): TextLabel
		return label({ Text = "", Size = UDim2.fromOffset(330, h), Position = UDim2.fromOffset(120, y), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or THEME.text, Parent = detail })
	end
	local detailName = detailLine(8, 30)
	detailName.RichText = true -- (the stars after the name are gold)
	local detailSub = detailLine(42, 20, THEME.sub)
	local detailStats = detailLine(66, 20, THEME.red)
	local detailAbility = detailLine(90, 20, THEME.gem)
	local selected: string? = nil

	-- rename prompt (a box on top of the Champions panel)
	local renameUid: string? = nil
	local renaming = false
	local prompt = new("TextButton", { Name = "RenamePrompt", Text = "", AutoButtonColor = false, Visible = false, BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Parent = panel }, { corner(20) })
	local box = new("Frame", { BackgroundColor3 = THEME.panel, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 250), Parent = prompt }, { corner(18), stroke(4, THEME.gem), new("UIScale", { Name = "Pop" }) })
	local promptTitle = label({ Text = "Rename", Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 34), Parent = box })
	local input = new("TextBox", { Name = "NameInput", Text = "", PlaceholderText = "New name (up to 16 letters)", PlaceholderColor3 = THEME.sub,
		ClearTextOnFocus = false, Font = THEME.font, TextSize = 26, TextColor3 = THEME.text, BackgroundColor3 = THEME.panel2,
		Position = UDim2.fromOffset(16, 56), Size = UDim2.new(1, -32, 0, 52), Parent = box }, { corner(12), stroke(3, THEME.gem) })
	local status = label({ Text = "", Position = UDim2.fromOffset(16, 118), Size = UDim2.new(1, -32, 0, 24), TextColor3 = THEME.sub, Parent = box })
	-- keep it to 16 letters while typing (the server checks again and runs Roblox's filter)
	input:GetPropertyChangedSignal("Text"):Connect(function()
		local text = input.Text
		local len = utf8.len(text)
		if len and len > 16 then
			local cut = utf8.offset(text, 17)
			if cut then input.Text = string.sub(text, 1, cut - 1) end
		end
	end)
	local function closeRename()
		prompt.Visible = false
		renameUid = nil
	end
	local function sendName(text: string)
		local uid = renameUid
		if renaming or not uid then return end
		renaming = true
		status.Text = "Checking the name..."
		status.TextColor3 = THEME.sub
		local ok, result = invoke("RenameChampion", uid, text)
		renaming = false
		if ok then
			closeRename()
			-- show what the filter let through (it may have turned words into ###)
			if type(result) == "string" and result ~= "" then
				toast("Renamed to " .. result .. "!", THEME.green)
			else
				toast("Name reset!", THEME.green)
			end
		else
			status.Text = tostring(result or "Couldn't rename. Try again!")
			status.TextColor3 = THEME.red
		end
	end
	local function openRename(uid: string)
		local owned = champions[uid]
		if not owned then return end
		renameUid = uid
		promptTitle.Text = "Rename " .. displayName(owned)
		input.Text = if type(owned.name) == "string" then owned.name else ""
		status.Text = "Names are checked by Roblox's text filter."
		status.TextColor3 = THEME.sub
		prompt.Visible = true
		local pop = box:FindFirstChild("Pop") :: UIScale
		pop.Scale = 0.7
		TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		input:CaptureFocus()
	end
	button({ Color = THEME.green, Text = "Save", Position = UDim2.fromOffset(16, 180), Size = UDim2.fromOffset(136, 52), Parent = box }, function() sendName(input.Text) end)
	button({ Color = THEME.panel2, Text = "Reset", Position = UDim2.new(0.5, -68, 0, 180), Size = UDim2.fromOffset(136, 52), Parent = box }, function() sendName("") end)
	button({ Color = THEME.red, Text = "Cancel", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 180), Size = UDim2.fromOffset(136, 52), Parent = box }, closeRename)
	input.FocusLost:Connect(function(enterPressed) if enterPressed and prompt.Visible then sendName(input.Text) end end)
	panel:GetPropertyChangedSignal("Visible"):Connect(function() if not panel.Visible then closeRename() end end)

	-- detail buttons (2 x 2)
	local equipBtn, renameBtn, fuseBtn, releaseBtn
	equipBtn = button({ Color = THEME.green, Text = "Equip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -178, 0, 12), Size = UDim2.fromOffset(160, 44), Parent = detail }, function()
		if not selected then return end
		local ok, msg = Remotes.EquipChampion:InvokeServer(selected, not table.find(equipped, selected))
		if not ok and msg then toast(msg, THEME.red) end
	end)
	renameBtn = button({ Name = "RenameButton", Color = THEME.gem, Text = "Rename", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12), Size = UDim2.fromOffset(160, 44), Parent = detail }, function()
		if selected then openRename(selected) end
	end)
	fuseBtn = button({ Name = "OpenFuseButton", Color = THEME.purple, Text = "Fuse", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -178, 0, 62), Size = UDim2.fromOffset(160, 44), Parent = detail }, function()
		if selected then openFuse(selected) end
	end)
	releaseBtn = button({ Color = THEME.red, Text = "Release", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 62), Size = UDim2.fromOffset(160, 44), Parent = detail }, function()
		if not selected then return end
		if releaseBtn.Text ~= "Sure?" then releaseBtn.Text = "Sure?" return end
		local ok, msg = Remotes.ReleaseChampion:InvokeServer(selected)
		if not ok and msg then toast(msg, THEME.red) end
		selected = nil
	end)
	local shownPic: string? = nil -- which champion the detail picture shows (rebuilt only when it changes)
	local function refreshDetail()
		local owned = selected and champions[selected]
		local def = owned and Config.ChampionById[owned.id]
		for _, b in { equipBtn, renameBtn, fuseBtn, releaseBtn } do b.Visible = def ~= nil end
		releaseBtn.Text = "Release"
		local picId = if def then def.id else nil
		if picId ~= shownPic then
			shownPic = picId
			for _, c in detailPic:GetChildren() do if c:IsA("ViewportFrame") then c:Destroy() end end
			if picId then viewport(picId, detailPic, UDim2.fromScale(1, 1)) end
		end
		if not owned or not def then
			detailName.Text = "Tap a champion"
			detailName.TextColor3 = THEME.text
			detailSub.Text = "See its DPS and ability, rename it or fuse copies."
			detailStats.Text = ""
			detailAbility.Text = ""
			return
		end
		local r = rarityOf(owned.id)
		local stars = starsOf(owned)
		local nicknamed = type(owned.name) == "string" and owned.name ~= ""
		detailName.Text = escapeRich(displayName(owned)) .. (if stars > 0 then '  <font color="#FFC832">' .. starText(stars) .. "</font>" else "")
		detailName.TextColor3 = r.color
		detailSub.Text = r.id .. (if nicknamed then "  •  " .. def.name else "") .. "  •  " .. (if stars > 0 then stars .. " star" .. (if stars == 1 then "" else "s") else "no stars yet")
		detailStats.Text = "DPS " .. Format.Short(dpsOf(owned)) .. "   •   Power " .. Format.Short(powerOf(owned)) .. " per hit"
		local ability = AbilityInfo[def.id]
		detailAbility.Text = "Ability: " .. (if ability and ability.name then ability.name else "-")
		local isOn = table.find(equipped, selected) ~= nil
		equipBtn.Text = isOn and "Unequip" or "Equip"
		equipBtn.BackgroundColor3 = isOn and THEME.panel or THEME.green
		local maxed = stars >= fusionNumber("maxStars", 5)
		fuseBtn.Text = if maxed then "Max Stars" else "Fuse ★"
		fuseBtn.BackgroundColor3 = if maxed then THEME.panel else THEME.purple
	end
	refreshers.Champions = function()
		if renameUid and not champions[renameUid] then closeRename() end
		if selected and not champions[selected] then selected = nil end
		for _, c in list:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local items = {}
		for uid, owned in champions do
			local def = Config.ChampionById[owned.id]
			if def then table.insert(items, { uid = uid, owned = owned, def = def, power = powerOf(owned) }) end
		end
		table.sort(items, function(a, b)
			local ea, eb = table.find(equipped, a.uid) ~= nil, table.find(equipped, b.uid) ~= nil
			if ea ~= eb then return ea end
			if a.power ~= b.power then return a.power > b.power end
			return a.uid < b.uid
		end)
		local L = if expanded then CARD_DENSE else CARD_NORMAL
		for i, item in items do
			local r = rarityOf(item.def.id)
			local isOn = table.find(equipped, item.uid) ~= nil
			local card = new("TextButton", { Text = "", AutoButtonColor = true, LayoutOrder = i, BackgroundColor3 = r.color:Lerp(THEME.panel, 0.55), Parent = list },
				{ corner(14), stroke(selected == item.uid and 5 or 3, selected == item.uid and Color3.new(1, 1, 1) or r.color) })
			viewport(item.def.id, card, UDim2.new(1, 0, 0, L.pic), UDim2.fromOffset(0, 4))
			label({ Text = displayName(item.owned), Size = UDim2.new(1, -8, 0, L.nameH), Position = UDim2.new(0, 4, 0, L.name), Parent = card })
			local stars = starsOf(item.owned)
			if stars > 0 then
				label({ Text = starText(stars), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 5), Size = UDim2.fromOffset(L.starW, L.starH),
					TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = THEME.gold, Parent = card })
			end
			label({ Text = "⚔ " .. Format.Short(item.power), Size = UDim2.new(1, -8, 0, L.powerH), Position = UDim2.new(0, 4, 0, L.power), TextColor3 = THEME.red, Parent = card })
			if isOn then
				local tag = new("Frame", { BackgroundColor3 = THEME.green, Size = UDim2.fromOffset(L.tag, L.tag), Position = UDim2.fromOffset(4, 4), Parent = card }, { corner(L.tag / 2), stroke(2) })
				label({ Text = "✓", Size = UDim2.fromScale(1, 1), Parent = tag })
			end
			card.Activated:Connect(function() playUiSound("click"); selected = item.uid; refreshers.Champions() end)
		end
		local slots = math.floor(attrNumber("EquipSlots", (CFG.Combat and CFG.Combat.BaseEquipSlots) or 3))
		local space = math.floor(attrNumber("InventorySize", CFG.InventoryBase or CFG.BackpackSize or 50))
		info.Text = string.format("Equipped %d/%d   •   Backpack %d/%d", #equipped, slots, #items, space)
		refreshDetail()
	end
end

----------------------------------------------------------------------------
-- Index panel (every champion; undiscovered ones are silhouettes)
----------------------------------------------------------------------------
do
	local _, body = makePanel("Index", "Champion Index", Color3.fromRGB(90, 200, 255), Vector2.new(820, 560))
	local info = label({ Text = "", Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, Parent = body })
	local scroll = new("ScrollingFrame", { BackgroundColor3 = THEME.panel2, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40),
		ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, {
		corner(14), new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
	})
	refreshers.Index = function()
		for _, c in scroll:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local found = 0
		local sections = { { id = 0, name = "Starter Champions", theme = Config.Hub.theme } }
		for _, w in Config.Worlds do table.insert(sections, w) end
		for _, w in sections do
			label({ Text = w.name, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = w.theme.accent, LayoutOrder = w.id * 10, Parent = scroll })
			local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 140), LayoutOrder = w.id * 10 + 1, Parent = scroll }, {
				new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }),
			})
			for _, c in Config.Champions do
				if c.world == w.id then
					local has = discovered[c.id] == true
					if has then found += 1 end
					local r = Config.RarityById[c.rarity]
					local card = new("Frame", { BackgroundColor3 = has and r.color:Lerp(THEME.panel, 0.55) or THEME.panel, Size = UDim2.fromOffset(112, 136), Parent = row },
						{ corner(14), stroke(3, has and r.color or Color3.fromRGB(70, 70, 90)) })
					viewport(c.id, card, UDim2.new(1, 0, 0, 92), UDim2.fromOffset(0, 4), not has)
					label({ Text = has and c.name or "???", Size = UDim2.new(1, -8, 0, 20), Position = UDim2.new(0, 4, 0, 96), Parent = card })
					label({ Text = c.rarity, Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 0, 116), TextColor3 = r.color, Parent = card })
				end
			end
		end
		info.Text = string.format("Discovered %d/%d   •   +%d%% damage from your Index", found, #Config.Champions, math.floor(found * Config.Upgrades.IndexDamagePerChampion * 100))
	end
end

----------------------------------------------------------------------------
-- SUMMONING: Orb panel, summon cinematic, result screen ("Reveal"), Auto Hatch cards
----------------------------------------------------------------------------
-- How one summon goes:
--  1. A shrine's OrbPrompt opens the summon overlay (the "Orb" panel). We remember WHICH shrine: the cinematic
--     plays at its altar.
--  2. SUMMON x1 / x3 asks the server (Remotes.OpenOrb). The buttons lock while we wait, so a
--     double click can never send two requests.
--  3. SummonCinematic.Play shows the summon at the altar. The rest of the HUD hides so nothing
--     covers the altar; only a slim currency pill and SKIP stay. Tap SKIP (or Space) = skip,
--     hold the screen (or Space) = fast-forward while held.
--  4. The result screen shows a card per champion (with EQUIP), SUMMON AGAIN and CLOSE. It
--     closes by itself after a few seconds without a tap, so AFK players never need to click.
-- If SummonCinematic is missing or errors, step 3 is skipped and the cards show straight away.
local currentOrbWorld = 1          -- which world's orb the panel sells (the shrine's WorldId)
local currentAltar: Model? = nil   -- the shrine whose OrbPrompt opened the panel
local refreshSummonButtons: () -> () = function() end -- repaints the summon buttons (set below)
local refreshSummonEquips: () -> () = function() end  -- repaints EQUIP on the result cards (set below)
local showAutoHatch: (any, any, boolean?) -> () = function() end -- Auto Hatch cards (set below)
-- The summon shrine (a Model with OrbShrine = true) that `inst` belongs to.
local function shrineOf(inst: Instance): Model?
	local node = inst.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("OrbShrine") == true then return node end
		node = node.Parent
	end
	return nil
end

-- (everything else lives inside this do-block: Luau allows only 200 locals per script level)
do
	-- The summon screens use the AETHERWAKE look: dark navy, violet/cyan accents, gold = coins.
	local SUMMON = {
		navy = Color3.fromRGB(12, 15, 34),
		navy2 = Color3.fromRGB(22, 27, 58),
		navy3 = Color3.fromRGB(36, 43, 84),
		line = Color3.fromRGB(64, 74, 140),
		violet = Color3.fromRGB(140, 92, 255),
		violetDark = Color3.fromRGB(76, 38, 168),
		cyan = Color3.fromRGB(64, 224, 255),
		gold = Color3.fromRGB(255, 200, 61),
		goldDark = Color3.fromRGB(190, 112, 18),
		text = Color3.fromRGB(245, 247, 255),
		sub = Color3.fromRGB(165, 176, 222),
		off = Color3.fromRGB(120, 126, 160), -- text on a button you can't use right now
		bad = Color3.fromRGB(255, 104, 120),
		good = Color3.fromRGB(80, 214, 130),
	}
	local TIMING = {
		hold = 0.25,        -- seconds: a press longer than this fast-forwards instead of skipping
		fastSpeed = 3,      -- cinematic speed while fast-forwarding
		results = 8,        -- the result screen closes after this many seconds without a tap
		quickAfter = 5,     -- after this many summons this session, Common/Uncommon play the short version
		maxCinematic = 30,  -- safety net: never wait on the cinematic longer than this
		maxHatchCards = 7,  -- Auto Hatch cards on screen at once
	}
	local SKIP_ACTION = "AetherwakeSummonSkip"

	local summonBusy = false       -- true while an OpenOrb request is on its way (no double requests)
	local summonsThisSession = 0
	local startSummon: (number) -> () = function() end   -- set below
	local refreshAgainButton: () -> () = function() end  -- set below
	-- the result screen's state
	local resultScreen = {
		token = 0,                         -- bumps every open/close, so old timers never touch a newer screen
		conn = nil :: RBXScriptConnection?, -- the countdown
		lastTap = 0,                       -- os.clock() of the last tap (restarts the countdown)
		cards = {} :: { () -> () },        -- one repaint function per card
		count = 1,                         -- how many orbs SUMMON AGAIN opens
	}

	-- OPTIONAL MODULES -------------------------------------------------------
	-- SummonCinematic is built separately and may be missing (or broken) while the game is
	-- being made. Everything goes through cine(), which never errors: no module = no cinematic.
	local cinematicModule: any = nil
	local cinematicWarned = false
	local function getCinematic(): any
		if cinematicModule then return cinematicModule end
		local mod = ReplicatedStorage.Shared:FindFirstChild("SummonCinematic")
		if not mod or not mod:IsA("ModuleScript") then return nil end
		local ok, result = pcall(require, mod)
		if ok and type(result) == "table" and type(result.Play) == "function" then
			cinematicModule = result
			return result
		end
		if not cinematicWarned then
			cinematicWarned = true
			warn("[HUD] SummonCinematic didn't load, using the simple reveal instead: " .. tostring(result))
		end
		return nil
	end
	-- Calls SummonCinematic.<name>(...) safely. Returns ok, result (ok = false when missing or errored).
	local function cine(name: string, ...: any): (boolean, any)
		local m = getCinematic()
		local fn = m and m[name]
		if type(fn) ~= "function" then return false, nil end
		local ok, result = pcall(fn, ...)
		if not ok then warn("[HUD] SummonCinematic." .. name .. " failed: " .. tostring(result)) end
		return ok, result
	end
	-- SummonTiers (optional) gives each rarity a darker shade for the card backgrounds.
	local summonTiers: any = nil
	do
		local mod = ReplicatedStorage.Shared:FindFirstChild("SummonTiers")
		if mod and mod:IsA("ModuleScript") then
			local ok, result = pcall(require, mod)
			if ok and type(result) == "table" then summonTiers = result end
		end
	end

	-- COLOURS + SMALL HELPERS -------------------------------------------------
	local function rarityColor(rarityId: string?): Color3
		local r = rarityId and Config.RarityById[rarityId]
		return if r then r.color else SUMMON.sub
	end
	local function rarityDark(rarityId: string?): Color3
		if summonTiers and type(summonTiers.get) == "function" then
			local ok, tier = pcall(summonTiers.get, rarityId)
			if ok and type(tier) == "table" and type(tier.palette) == "table" and typeof(tier.palette.dark) == "Color3" then
				return tier.palette.dark
			end
		end
		return rarityColor(rarityId):Lerp(Color3.new(0, 0, 0), 0.6)
	end
	-- dark text reads better on bright pills (silver, green, gold), white text on darker ones
	local function textOn(color: Color3): Color3
		local brightness = 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
		return if brightness > 0.5 then SUMMON.navy else SUMMON.text
	end
	-- a small rounded "EPIC" pill in the rarity's colour
	local function rarityPill(parent: Instance, rarityId: string, pos: UDim2, anchor: Vector2, size: UDim2): Frame
		local color = rarityColor(rarityId)
		local pill = new("Frame", { Name = "RarityPill", BackgroundColor3 = color, AnchorPoint = anchor, Position = pos, Size = size, Parent = parent },
			{ new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local textColor = textOn(color)
		local t = label({ Text = string.upper(rarityId), Position = UDim2.new(0, 8, 0, 2), Size = UDim2.new(1, -16, 1, -4), TextColor3 = textColor, Parent = pill })
		local outline = t:FindFirstChildOfClass("UIStroke")
		if outline then outline.Enabled = textColor ~= SUMMON.navy end -- (an outline only helps white text)
		return pill
	end
	-- The rarity id of one server result (newer servers send it; otherwise use the champion's).
	local function resultRarity(res: any): string
		if type(res.rarity) == "string" and Config.RarityById[res.rarity] then return res.rarity end
		local def = Config.ChampionById[res.id]
		return if def then def.rarity else "Common"
	end
	-- The best rarity in a list of results, compared by NAME (rarityAtLeast), never by rank numbers.
	local function bestRarity(results: { any }): string?
		local best: string? = nil
		for _, res in results do
			if type(res) == "table" and Config.ChampionById[res.id] then
				local id = resultRarity(res)
				if best == nil or (id ~= best and rarityAtLeast(id, best)) then best = id end
			end
		end
		return best
	end
	-- Keeps only results that make sense (right types, a champion we know), in one fixed shape.
	local function cleanResults(list: any): { any }
		local out = {}
		if type(list) ~= "table" then return out end
		for _, res in list do
			if type(res) == "table" and type(res.id) == "string" and Config.ChampionById[res.id] then
				table.insert(out, {
					uid = if res.uid ~= nil then tostring(res.uid) else nil,
					id = res.id,
					new = res.new == true,
					rarity = resultRarity(res),
					power = tonumber(res.power),
				})
			end
		end
		return out
	end
	local function myRoot(): BasePart?
		local char = player.Character
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	-- The closest shrine of `worldId` (nil = any world) within `range` studs of you.
	local function nearestShrine(worldId: number?, range: number): Model?
		local root = myRoot()
		local worlds = workspace:FindFirstChild("Worlds")
		if not root or not worlds then return nil end
		local best, bestDist = nil, range
		for _, folder in worlds:GetChildren() do
			for _, m in folder:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("OrbShrine") == true and (worldId == nil or m:GetAttribute("WorldId") == worldId) then
					local dist = (m:GetPivot().Position - root.Position).Magnitude
					if dist < bestDist then best, bestDist = m, dist end
				end
			end
		end
		return best
	end
	-- Where the cinematic plays: the shrine that opened the panel, or the nearest shrine of the
	-- same world if you walked over to another one.
	local function summonAltar(): Model?
		local root = myRoot()
		local altar = currentAltar
		if altar and altar.Parent and root and (altar:GetPivot().Position - root.Position).Magnitude <= 45 then return altar end
		return nearestShrine(currentOrbWorld, 45) or (if altar and altar.Parent then altar else nil)
	end
	local function orbWorld(): any
		for _, w in Config.Worlds do
			if w.id == currentOrbWorld then return w end
		end
		return Config.Worlds[1] -- (unknown shrine id: World 1's orb)
	end
	local function ownedCount(): number
		local n = 0
		for _ in champions do n += 1 end
		return n
	end
	local function backpackSpace(): number
		return math.floor(attrNumber("InventorySize", CFG.InventoryBase or CFG.BackpackSize or 50))
	end
	local function multiCount(): number
		return math.max(1, math.floor(attrNumber("OpenCount", 1)))
	end
	-- the Multi Open milestone (Config.Upgrades.MultiOpen): orbs needed, and the count it unlocks
	local function multiStep(): (number, number)
		local steps = Config.Upgrades and Config.Upgrades.MultiOpen
		local step = if type(steps) == "table" then steps[1] else nil
		return (step and tonumber(step.need)) or 100, 1 + ((step and tonumber(step.bonus)) or 2)
	end
	local function multiUnlockText(): string
		local need = multiStep()
		return string.format("Summon %d orbs to unlock (%d/%d)", need, math.min(math.floor(attrNumber("OrbsOpened", 0)), need), need)
	end
	-- Why `count` summons can't happen right now: (short text for a button, longer text for a
	-- toast). Both nil = it can. (The server checks all of this again; this is just for the UI.)
	local function summonBlocker(count: number): (string?, string?)
		if ownedCount() + count > backpackSpace() then
			return "Backpack full", "Your backpack is full! Release or fuse some champions."
		end
		local cost = orbWorld().orb.cost * count
		local coins = attrNumber("Coins", 0)
		if coins < cost then
			local short = "Need $" .. Format.Short(cost - coins) .. " more"
			return short, short .. " coins for that summon."
		end
		return nil, nil
	end
	-- Bad-luck protection from Config.Pity, lowest rarity first: { { id = "Legendary", limit = 75 }, ... }
	-- (The server counts it per world, but it doesn't send your counters to the client, so the
	-- summon overlay shows these limits, not "N to go".)
	local function pityList(): { any }
		local list = {}
		for _, r in Config.Rarities do
			local limit = if type(Config.Pity) == "table" then (Config.Pity :: any)[r.id] else nil
			if type(limit) == "number" then table.insert(list, { id = r.id, limit = limit }) end
		end
		return list
	end

	-- AUTO HATCH -------------------------------------------------------------
	-- Small cards above the AUTO buttons that fade away by themselves (they never block the
	-- screen or need a click: perfect for AFK), plus a quick flash on the shrine you stand at.
	local autoHatchRow = new("Frame", { Name = "AutoHatchRow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -128),
		Size = UDim2.fromOffset(660, 112), ZIndex = 4, Parent = canvas }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local autoHatchCount = 0
	local pendingHatch: { any } = {} -- Auto Hatch results that arrived while a manual summon was on screen
	showAutoHatch = function(results: any, worldId: any, noPulse: boolean?)
		if type(results) ~= "table" then return end
		if summonPhase ~= "idle" then
			-- a manual summon is on screen: show these afterwards (only the newest few)
			for _, res in results do table.insert(pendingHatch, res) end
			while #pendingHatch > TIMING.maxHatchCards do table.remove(pendingHatch, 1) end
			return
		end
		if not noPulse then
			-- a cheap flash on the altar in the best result's colour (no camera, no UI)
			local best = bestRarity(results)
			local shrine = nearestShrine(if type(worldId) == "number" then worldId else nil, 60)
			if best and shrine then cine("Pulse", shrine, best) end
		end
		for i, res in results do
			local def = type(res) == "table" and Config.ChampionById[res.id]
			if not def then continue end
			-- too many on screen? remove the oldest first
			local cards = {}
			for _, c in autoHatchRow:GetChildren() do if c:IsA("GuiObject") then table.insert(cards, c) end end
			table.sort(cards, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			for k = 1, #cards - TIMING.maxHatchCards + 1 do cards[k]:Destroy() end
			autoHatchCount += 1
			local rarityId = resultRarity(res)
			local color = rarityColor(rarityId)
			local card = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(84, 108), LayoutOrder = autoHatchCount, Parent = autoHatchRow },
				{ corner(14), stroke(3, color), gradient(rarityDark(rarityId):Lerp(SUMMON.navy2, 0.3), SUMMON.navy), new("UIScale", { Name = "Pop", Scale = 0 }) })
			viewport(def.id, card, UDim2.new(1, 0, 0, 70), UDim2.fromOffset(0, 2))
			label({ Text = def.name, Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0, 72), Parent = card })
			label({ Text = rarityId, Size = UDim2.new(1, -6, 0, 14), Position = UDim2.new(0, 3, 0, 90), TextColor3 = color, Parent = card })
			if res.new then
				local tag = new("Frame", { BackgroundColor3 = SUMMON.gold, Rotation = -12, Size = UDim2.fromOffset(44, 20), Position = UDim2.fromOffset(-6, -6), Parent = card }, { corner(6), stroke(2) })
				label({ Text = "NEW!", Size = UDim2.fromScale(1, 1), Parent = tag })
			end
			local pop = card:FindFirstChild("Pop") :: UIScale
			local delay = (i - 1) * 0.12
			task.delay(delay, function()
				TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				bigPullToast(rarityId, def.name, color) -- ("LEGENDARY!" / "MYTHIC!", by rarity name)
			end)
			task.delay(delay + 2.2, function()
				if not card.Parent then return end
				TweenService:Create(pop, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.6 }):Play()
				fadeAway(card, 0.3)
				task.wait(0.32)
				card:Destroy()
			end)
		end
	end
	local function flushPendingHatch()
		if #pendingHatch == 0 then return end
		local list = pendingHatch
		pendingHatch = {}
		showAutoHatch(list, nil, true) -- (no shrine flash: those orbs opened a while ago)
	end

	-- A big two-line summon button: main text on top, a smaller status line under it.
	local function summonButton(name: string, parent: Instance, pos: UDim2, size: UDim2, anchor: Vector2, top: Color3, bottom: Color3, onClick: () -> ()): any
		local b = new("TextButton", { Name = name, Text = "", AutoButtonColor = true, BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = anchor,
			Position = pos, Size = size, Parent = parent }, { corner(16), new("UIStroke", { Thickness = 3, Color = SUMMON.navy, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
		local grad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom), Parent = b })
		local main = label({ Name = "Main", Text = "", Position = UDim2.new(0, 12, 0, 8), Size = UDim2.new(1, -24, 0.5, -6), Parent = b })
		local status = label({ Name = "Status", Text = "", Position = UDim2.new(0, 12, 0.56, 0), Size = UDim2.new(1, -24, 0.3, 0), Parent = b })
		feedback(b)
		b.Activated:Connect(function() bounce(b); onClick() end)
		return { button = b, main = main, status = status, gradient = grad, top = top, bottom = bottom }
	end
	-- Paints a summon button: usable (its own colours) or not (grey, the reason in the status line).
	local function setSummonButton(sb: any, usable: boolean, mainText: string, statusText: string, statusColor: Color3)
		sb.main.Text = mainText
		sb.main.TextColor3 = if usable then SUMMON.text else SUMMON.off
		sb.status.Text = statusText
		sb.status.TextColor3 = statusColor
		sb.gradient.Color = if usable then ColorSequence.new(sb.top, sb.bottom) else ColorSequence.new(SUMMON.navy3, SUMMON.navy2)
		sb.button.AutoButtonColor = usable
	end

	-- ORB PANEL --------------------------------------------------------------
	-- The Orb panel is the full-screen SUMMON OVERLAY (built with makeFullscreen: the rest of the
	-- HUD hides and the world is hidden behind it), laid out like the AETHERWAKE design:
	--   top     AETHERWAKE + "SUMMON · <orb> · <place>", your coins and gems (+ = Store), X
	--   left    UNIT ODDS: every champion this orb can give and its base chance (the ODDS tab
	--           opens / closes it), with the bad-luck protection under it
	--   middle  the shrine's glass orb in that orb's colours, its name and your Luck, then the
	--           big SUMMON 1X (gold) and SUMMON multi (cyan) buttons
	--   right   AUTO HATCH (the same switch as the AUTO HATCH button), backpack, orbs opened
	-- Phones (a small real screen) get the phone design: odds behind the ODDS tab, the orb on the
	-- left, the buttons stacked on the right.
	-- Keys while it's open: E = summon 1, R = summon multi, T = Auto Hatch. They're ignored for
	-- 0.4 s after it opens, because E is also the shrine's key.
	-- The tutorial guide (QuestClient) finds "Orb", "OpenOne" and "OpenMulti" by name: keep those
	-- names and don't give them to anything else in the HUD.
	-- Sizes and positions are in DESIGN UNITS: pixels of the PC design (1600 x 900) or of the phone
	-- design (844 x 390). Each block has a UIScale named "Fit" that turns them into screen size.
	-- Built once; while it's hidden nothing animates (makeFullscreen stops the loop).
	-- (Built inside a function: Luau allows only 200 locals per script level.)
	local function buildSummonOverlay()
		local GuiService = game:GetService("GuiService")
		local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
		local hex = Color3.fromHex

		-- COLOURS (from the design) -----------------------------------------------------
		local S = {
			space = hex("#070914"), glass = hex("#101326"), pill = hex("#0E1122"), tab = hex("#1C203E"),
			cyan = hex("#5CF2FF"), violet = hex("#B06BFF"), gold = hex("#FFC83D"), red = hex("#FF4D6D"), bad = hex("#FF8FA3"),
			text = hex("#EEF1FF"), sub = hex("#A8B0D6"), soft = hex("#CBD1F0"), hint = hex("#8F98C2"), line = hex("#788CFF"), key = hex("#4A5280"),
		}
		-- the big buttons: gold = SUMMON 1X, cyan = SUMMON multi, off = can't be used right now
		local BIG: { [string]: any } = {
			gold = { top = hex("#FFE98F"), mid = S.gold, bottom = hex("#E58A00"), edge = hex("#FFF1B0"), text = hex("#2A1700"), glow = S.gold },
			cyan = { top = hex("#DDFCFF"), mid = S.cyan, bottom = hex("#1596C9"), edge = hex("#E4FDFF"), text = hex("#05202B"), glow = S.cyan },
			off = { top = hex("#2C325C"), mid = hex("#20264A"), bottom = hex("#161B3A"), edge = hex("#404A8C"), text = hex("#969CC4") },
		}
		-- each shrine's orb in the colours of its orb in the world: core, glass, glow and the 3 rings
		local ORBS: { [string]: any } = {
			Hub = { core = hex("#DDFBFF"), deep = hex("#6ECDEB"), shell = hex("#F0FAFF"), glow = hex("#78E1FF"), -- Starter Orb: white + cyan
				rings = { hex("#8FE8FF"), hex("#E6FCFF"), hex("#B79CFF") } },
			W1 = { core = hex("#EBFFF5"), deep = hex("#783CD7"), shell = hex("#8CFFC8"), glow = hex("#82FFC8"), -- Rift Orb: violet core + mint
				rings = { hex("#6EFFB9"), hex("#B79CFF"), hex("#82FFC8") } },
			W2 = { core = hex("#E6FFFF"), deep = hex("#28AABE"), shell = hex("#F0F8FF"), glow = hex("#78EBF0"), -- Tide Orb: aqua + pearl
				rings = { hex("#78DCFF"), hex("#FFB4CD"), hex("#CDF5FF") } },
			W3 = { core = hex("#FFF8E1"), deep = hex("#C87319"), shell = hex("#E6ECF6"), glow = hex("#FFD778"), -- Forge Orb: amber-gold + steel
				rings = { hex("#FFD778"), hex("#AFC8FF"), hex("#FFCD5A") } },
		}
		local function orbLookOf(home: any): any
			if ORBS[home.key] then return ORBS[home.key] end
			-- (a world added later gets an orb in its theme colour)
			local a = if type(home.theme) == "table" and typeof(home.theme.accent) == "Color3" then home.theme.accent else S.cyan
			return { core = a:Lerp(WHITE, 0.85), deep = a:Lerp(BLACK, 0.3), shell = a:Lerp(WHITE, 0.6), glow = a, rings = { a, a:Lerp(WHITE, 0.6), S.violet } }
		end
		-- The place whose shrine opened the overlay. The hub's shrine (in Workspace.Worlds.Hub) sells
		-- Verdant Rift's orbs (orbWorld), but in the world it's the Starter Orb, with its own look.
		local function shrineHome(): any
			local folder = currentAltar and currentAltar.Parent
			if folder and folder.Name == Config.Hub.key then return Config.Hub end
			return orbWorld()
		end

		-- STATE ------------------------------------------------------------------------------
		local compact = false      -- true = the phone layout (layout decides)
		local pcDrawer = true      -- the UNIT ODDS drawer is open on PC...
		local phoneDrawer = false  -- ...and on phones (there it covers the orb, so it starts closed)
		local openedAt = 0         -- os.clock() when the overlay opened (keys wait 0.4 s)
		local rowH = 54            -- the height of one odds row (smaller on phones)
		local oddsKey = ""         -- which odds rows are built ("world:row height")
		local lookKey = ""         -- which orb colours are painted (the shrine's place key)
		local knobOn: boolean? = nil
		local mutedPrompts: { ProximityPrompt } = {} -- the shrine's prompts, switched off while it's open
		-- the last layout: design-unit scale, screen size in design units, drawer / tab / column tops
		local fitNow = { u = 1, W = 1600, H = 900, drawerTop = 0, tabTop = 0, colTop = 72 }
		local orbSpot = { x = 0.5, y = 260, h = 600 } -- where the orb floats inside its block
		local layout: (Vector2) -> () = function() end
		local animate: (number) -> () = function() end
		local refreshOverlay: () -> () = function() end
		local bindKeys: () -> () = function() end
		local unbindKeys: () -> () = function() end

		local panel, content, fs = makeFullscreen("Orb", {
			background = S.space,
			onOpen = function()
				openedAt = os.clock()
				phoneDrawer = false
				-- E is also the shrine's key, and a prompt hears its key before the overlay's E binding
				-- does. So the shrine's prompt is switched off while the overlay is open (on this screen
				-- only: the server's prompt isn't touched), and E summons instead of reopening it.
				if currentAltar then
					for _, d in currentAltar:GetDescendants() do
						if d:IsA("ProximityPrompt") and d.Enabled then
							d.Enabled = false
							table.insert(mutedPrompts, d)
						end
					end
				end
				bindKeys()
			end,
			onClose = function()
				unbindKeys()
				for _, d in mutedPrompts do d.Enabled = true end -- (the shrine works again)
				table.clear(mutedPrompts)
			end,
			onLayout = function(size: Vector2) layout(size) end,
			onFrame = function(_dt: number, t: number) animate(t) end,
		})

		-- SMALL BUILDERS -------------------------------------------------------------------
		-- plain text, no outline (the overlay is dark, like the design); max = the biggest text size
		local function text(props: { [string]: any }, max: number?): TextLabel
			local base: { [string]: any } = { BackgroundTransparency = 1, Font = THEME.font, TextColor3 = S.text, TextScaled = true }
			for k, v in props do base[k] = v end
			local l = new("TextLabel", base)
			if max then new("UITextSizeConstraint", { MaxTextSize = max, Parent = l }) end
			return l
		end
		-- text at one fixed size that grows sideways to fit it (for rows made by a UIListLayout)
		local function fixedText(props: { [string]: any }, size: number): TextLabel
			props.TextScaled = false
			props.TextSize = size
			props.AutomaticSize = Enum.AutomaticSize.X
			return text(props)
		end
		-- a circle (a pill when it isn't square), centred on its Position, full size by default
		local function round(props: { [string]: any }): Frame
			local base: { [string]: any } = { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) }
			for k, v in props do base[k] = v end
			return new("Frame", base, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
		local function edge(parent: Instance, thickness: number, color: Color3, transparency: number): UIStroke
			return new("UIStroke", { Thickness = thickness, Color = color, Transparency = transparency, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
		end
		-- { time, value, time, value, ... } -> a sequence for a UIGradient
		local function fade(points: { number }): NumberSequence
			local keys = {}
			for i = 1, #points, 2 do table.insert(keys, NumberSequenceKeypoint.new(points[i], points[i + 1])) end
			return NumberSequence.new(keys)
		end
		local function colors(points: { any }): ColorSequence
			local keys = {}
			for i = 1, #points, 2 do table.insert(keys, ColorSequenceKeypoint.new(points[i], points[i + 1])) end
			return ColorSequence.new(keys)
		end
		-- one block of the layout: layout() positions it, its UIScale "Fit" sizes it for the screen
		local function block(name: string, z: number): Frame
			local f = new("Frame", { Name = name, BackgroundTransparency = 1, ZIndex = z, Parent = content })
			new("UIScale", { Name = "Fit", Parent = f })
			return f
		end
		-- a soft glow that fills `parent`: 5 see-through circles inside each other (the middle is
		-- brightest). Returns the circles so their colour can change.
		local function softGlow(parent: Instance, color: Color3, alpha: number): { Frame }
			local each = 1 - (1 - alpha) ^ (1 / 5) -- (5 layers on top of each other reach `alpha`)
			local layers = {}
			for i = 1, 5 do
				local s = 1 - (i - 1) * 0.18
				layers[i] = round({ BackgroundColor3 = color, BackgroundTransparency = 1 - each, Size = UDim2.fromScale(s, s), Parent = parent })
				-- (each layer fades out on two sides, alternating, so together they look round)
				new("UIGradient", { Rotation = if i % 2 == 0 then 90 else 0, Transparency = fade({ 0, 1, 0.3, 0, 0.7, 0, 1, 1 }), Parent = layers[i] })
			end
			return layers
		end
		-- An ellipse made of short straight pieces (a GUI frame can't be an ellipse) around the
		-- centre of a square `box` units wide. dash < 1 leaves gaps; keep(angle) can leave pieces
		-- out (a ring's far half goes behind the glass). Pieces are placed by Scale (no rounding).
		local function ellipse(parent: Instance, box: number, rx: number, ry: number, pieces: number, thickness: number,
			color: Color3, transparency: number, dash: number?, keep: ((number) -> boolean)?): { Frame }
			local list = {}
			for i = 0, pieces - 1 do
				local a0, a1 = i / pieces * math.pi * 2, (i + 1) / pieces * math.pi * 2
				if keep and not keep((a0 + a1) / 2) then continue end
				local p0 = Vector2.new(rx * math.cos(a0), ry * math.sin(a0))
				local p1 = Vector2.new(rx * math.cos(a1), ry * math.sin(a1))
				local d, mid = p1 - p0, (p0 + p1) / 2
				table.insert(list, new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color,
					BackgroundTransparency = transparency, Position = UDim2.fromScale(0.5 + mid.X / box, 0.5 + mid.Y / box),
					Size = UDim2.fromOffset(math.ceil(d.Magnitude * (dash or 1)) + 1, thickness), Rotation = math.deg(math.atan2(d.Y, d.X)), Parent = parent }))
			end
			return list
		end
		-- numbers as text: 1.25 (no extra zeros), 12.5% / 0.45%, 1,234
		local function short(x: number, digits: number?): string
			local s = string.format("%." .. (digits or 2) .. "f", x)
			s = s:gsub("0+$", ""):gsub("%.$", "")
			return s
		end
		local function percent(p: number): string
			return short(p, if p >= 1 then 1 else 2) .. "%"
		end
		local function commas(n: number): string
			local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
			return (s:gsub("^,", ""))
		end
		-- "Pip Sprout" -> "PS", "Gearling" -> "GE" (the coloured chip on each odds row)
		local function initials(name: string): string
			local words = {}
			for w in string.gmatch(name, "%S+") do table.insert(words, w) end
			if #words >= 2 then return string.upper(string.sub(words[1], 1, 1) .. string.sub(words[#words], 1, 1)) end
			return string.upper(string.sub(name, 1, 2))
		end

		-- BACKGROUND: a violet glow in the middle, a faint grid and darker edges ------------------
		local glowSpot = new("Frame", { Name = "Glow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromScale(0.85, 1.1), Parent = fs.backdrop })
		softGlow(new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.5, 1.3), Parent = glowSpot }), hex("#0D0F24"), 0.9)
		softGlow(glowSpot, hex("#1B1440"), 0.95)
		local gridBox = new("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = fs.backdrop })
		local gridLines: { Frame } = {}
		for i = 1, 100 do
			gridLines[i] = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = S.cyan, BackgroundTransparency = 0.975, Visible = false, Parent = gridBox })
		end
		for _, v in { { Vector2.new(0, 0), UDim2.fromScale(1, 0.22), 90 }, { Vector2.new(0, 1), UDim2.fromScale(1, 0.22), -90 },
			{ Vector2.new(0, 0), UDim2.fromScale(0.16, 1), 0 }, { Vector2.new(1, 0), UDim2.fromScale(0.16, 1), 180 } } do
			local f = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = hex("#03040A"), AnchorPoint = v[1], Position = UDim2.fromScale(v[1].X, v[1].Y),
				Size = v[2], Parent = fs.backdrop })
			new("UIGradient", { Rotation = v[3], Transparency = fade({ 0, 0.2, 1, 1 }), Parent = f })
		end

		-- HEADER: the title (left), coins + gems + close (right) ----------------------------------
		local band = new("Frame", { Name = "HeaderBand", BorderSizePixel = 0, BackgroundColor3 = S.space, Size = UDim2.new(1, 0, 0, 70), Parent = content })
		new("UIGradient", { Rotation = 90, Transparency = fade({ 0, 0.05, 1, 0.6 }), Parent = band })
		new("Frame", { BorderSizePixel = 0, BackgroundColor3 = S.line, BackgroundTransparency = 0.82, AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), Parent = band })
		local titleBlock = block("TitleBlock", 3)
		titleBlock.AnchorPoint = Vector2.new(0, 0.5)
		titleBlock.Size = UDim2.fromOffset(620, 60)
		-- (PC: AETHERWAKE in the game's title font; phones: the orb's name)
		local gameTitle = text({ Name = "GameTitle", Text = "AETHERWAKE", Font = Enum.Font.LuckiestGuy, TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 32), Parent = titleBlock }, 28)
		new("UIStroke", { Color = S.cyan, Transparency = 0.6, Thickness = 1.5, Parent = gameTitle }) -- (a soft cyan glow)
		local subTitle = text({ Name = "Where", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = S.sub,
			Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 16), Parent = titleBlock }, 14)
		local gameMax = gameTitle:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
		local subMax = subTitle:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
		local wallet = block("Wallet", 3)
		wallet.AnchorPoint = Vector2.new(1, 0.5)
		local walletList = new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wallet })
		local pills: { any } = {}
		-- one currency: a coloured coin, a caption (PC only) and the live value; `onPlus` adds a +
		local function currencyPill(order: number, caption: string, icon: string, color: Color3, iconColors: ColorSequence, ink: Color3,
			captionColor: Color3, onPlus: (() -> ())?): TextLabel
			local p = new("Frame", { Name = caption .. "Pill", BackgroundColor3 = S.pill, BackgroundTransparency = 0.15, AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 52), LayoutOrder = order, Parent = wallet }, { corner(26) })
			edge(p, 1, color, 0.5)
			local pad = new("UIPadding", { Parent = p })
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = p })
			local badge = round({ Name = "Icon", BackgroundColor3 = WHITE, AnchorPoint = Vector2.zero, Size = UDim2.fromOffset(36, 36), LayoutOrder = 1, Parent = p })
			new("UIGradient", { Rotation = 45, Color = iconColors, Parent = badge })
			text({ Text = icon, TextColor3 = ink, Position = UDim2.fromScale(0.18, 0.18), Size = UDim2.fromScale(0.64, 0.64), Parent = badge })
			local words = new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 52), LayoutOrder = 2, Parent = p })
			local cap = fixedText({ Text = caption, TextColor3 = captionColor, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(0, 6),
				Size = UDim2.fromOffset(0, 13), Parent = words }, 12)
			local value = fixedText({ Name = "Value", Text = "0", TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(0, 20),
				Size = UDim2.fromOffset(0, 24), Parent = words }, 22)
			local plus: TextButton? = nil
			if onPlus then
				local b = new("TextButton", { Name = "Plus", Text = "+", Font = THEME.font, TextSize = 20, TextColor3 = ink, AutoButtonColor = true,
					BackgroundColor3 = color, Size = UDim2.fromOffset(30, 30), LayoutOrder = 3, Parent = p }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
				feedback(b)
				b.Activated:Connect(function() bounce(b); onPlus() end)
				plus = b
			end
			table.insert(pills, { frame = p, pad = pad, badge = badge, words = words, cap = cap, value = value, plus = plus })
			return value
		end
		local coinsValue = currencyPill(1, "COINS", "$", S.gold, colors({ 0, hex("#FFE9A3"), 0.6, hex("#FFB627"), 1, hex("#B87400") }), hex("#2A1700"), hex("#FFDF8A"))
		local gemsValue = currencyPill(2, "GEMS", "◆", S.cyan, colors({ 0, hex("#E4FDFF"), 0.55, S.cyan, 1, hex("#1588B5") }), hex("#05202B"), hex("#A9F7FF"),
			function() showPanel("Store") end) -- (the + opens the Store, like the HUD's gem pill)
		local closeBtn = new("TextButton", { Name = "CloseSummon", Text = "", AutoButtonColor = true, BackgroundColor3 = S.red, BackgroundTransparency = 0.86,
			Size = UDim2.fromOffset(52, 52), LayoutOrder = 9, Parent = wallet }, { corner(16) })
		edge(closeBtn, 1, S.red, 0.4)
		for _, angle in { 45, -45 } do -- (the X: two crossed bars)
			new("Frame", { BorderSizePixel = 0, BackgroundColor3 = S.bad, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.44, 0, 0, 3), Rotation = angle, Parent = closeBtn }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
		feedback(closeBtn)
		closeBtn.Activated:Connect(function() bounce(closeBtn); showPanel(nil) end)

		-- UNIT ODDS DRAWER (left) and its ODDS tab ---------------------------------------------
		-- (its first 24 units sit off the left edge of the screen, so its left corners look square)
		local drawer = block("OddsDrawer", 5)
		local drawerGlass = new("Frame", { Name = "Glass", BackgroundColor3 = S.glass, BackgroundTransparency = 0.22, Size = UDim2.fromScale(1, 1), Parent = drawer }, { corner(24) })
		edge(drawerGlass, 1, S.line, 0.78)
		text({ Text = "UNIT ODDS", TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(52, 24), Size = UDim2.fromOffset(200, 26), Parent = drawerGlass }, 24)
		text({ Text = "base odds", TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = S.sub, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -22, 0, 31), Size = UDim2.fromOffset(120, 16), Parent = drawerGlass }, 14)
		local rowsBox = new("ScrollingFrame", { Name = "OddsRows", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(52, 64),
			Size = UDim2.fromOffset(322, 400), ScrollBarThickness = 4, ScrollBarImageColor3 = S.line, AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Parent = drawerGlass },
			{ new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
		local rowsList = rowsBox:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		-- bad-luck protection under the odds (the limits from Config.Pity: see pityList)
		local pityRows = pityList()
		local PITY_H = 14 + #pityRows * 28 + 34
		local pityBox = new("Frame", { Name = "Pity", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 52, 1, -20),
			Size = UDim2.new(1, -74, 0, PITY_H), Parent = drawerGlass })
		new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.92, Size = UDim2.new(1, 0, 0, 1), Parent = pityBox })
		for i, p in pityRows do
			local y = 14 + (i - 1) * 28
			text({ Text = p.id .. " guaranteed within", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = S.soft, Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(0.66, 0, 0, 18), Parent = pityBox }, 14)
			text({ Text = p.limit .. " summons", TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = rarityColor(p.id):Lerp(WHITE, 0.2),
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, y), Size = UDim2.new(0.34, 0, 0, 18), Parent = pityBox }, 14)
		end
		local pityNote = text({ TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = S.sub,
			Position = UDim2.fromOffset(0, 14 + #pityRows * 28), Size = UDim2.new(1, 0, 0, 30), Parent = pityBox }, 13)
		local tab = block("OddsTab", 6)
		tab.Size = UDim2.fromOffset(40, 112)
		-- (14 extra units on the left hide under the drawer / off the screen: square left corners)
		local tabButton = new("TextButton", { Name = "OddsTabButton", Text = "", AutoButtonColor = true, BackgroundColor3 = S.tab, BackgroundTransparency = 0.08,
			Position = UDim2.fromOffset(-14, 0), Size = UDim2.new(1, 14, 1, 0), Parent = tab }, { corner(14) })
		edge(tabButton, 1, S.line, 0.7)
		text({ Text = "ODDS", Rotation = 90, TextColor3 = S.soft, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 7, 0.5, 0),
			Size = UDim2.fromOffset(90, 22), Parent = tabButton }, 15)

		-- THE ORB (middle): glass ball, bright core, 3 tilted rings with a spark running round each --
		local ORB_BOX = 520 -- (the orb's square in the PC design; the rings reach a bit outside it)
		local orbBlock = block("OrbBlock", 2)
		local orbArt = new("Frame", { Name = "OrbArt", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(ORB_BOX, ORB_BOX), Parent = orbBlock })
		local orbArtScale = new("UIScale", { Parent = orbArt })
		-- a see-through square inside the orb (stacked by z), centred unless `at` is given
		local function layer(name: string, size: Vector2, z: number, at: Vector2?): Frame
			return new("Frame", { Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = if at then UDim2.fromScale(at.X / ORB_BOX, at.Y / ORB_BOX) else UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(size.X, size.Y), ZIndex = z, Parent = orbArt })
		end
		local floorLayers = softGlow(layer("Floor", Vector2.new(380, 70), 1, Vector2.new(260, 505)), S.cyan, 0.55)
		local halo = layer("Halo", Vector2.new(560, 560), 2)
		local haloScale = new("UIScale", { Parent = halo })
		local haloLayers = softGlow(halo, S.cyan, 0.45)
		-- the rings: radius across, radius up / down, tilt (degrees) and how fast the spark runs
		local RINGS = {
			{ rx = 290, ry = 99, tilt = 24, speed = 0.55 },
			{ rx = 250, ry = 75, tilt = -16, speed = -0.42 },
			{ rx = 220, ry = 57, tilt = 78, speed = 0.7 },
		}
		local rings: { any } = {}
		for k, r in RINGS do
			local ring: { [string]: any } = { pieces = {}, near = false }
			-- the far half (behind the glass) and the near half (in front of it)
			for _, near in { false, true } do
				local half = layer(if near then "RingFront" else "RingBack", Vector2.new(ORB_BOX, ORB_BOX), if near then 9 else 3)
				half.Rotation = r.tilt
				local function keep(angle: number): boolean return (math.sin(angle) >= 0) == near end
				for _, p in ellipse(half, ORB_BOX, r.rx, r.ry, 32, 9, S.cyan, 0.84, nil, keep) do table.insert(ring.pieces, p) end -- (glow)
				for _, p in ellipse(half, ORB_BOX, r.rx, r.ry, 56, 3, S.cyan, 0.05, nil, keep) do table.insert(ring.pieces, p) end -- (line)
				ring[if near then "front" else "back"] = half
			end
			ring.bead = layer("Spark", Vector2.new(26, 26), 3)
			ring.beadGlow = round({ BackgroundColor3 = S.cyan, BackgroundTransparency = 0.55, Parent = ring.bead })
			ring.beadDot = round({ BackgroundColor3 = WHITE, Size = UDim2.fromScale(0.4, 0.4), Parent = ring.bead })
			rings[k] = ring
		end
		-- the glass ball: tinted glass lit from the top left, a rim, an inner glow and a darker side
		local SPHERE = 360
		local ball = round({ Name = "Glass", BackgroundColor3 = WHITE, Size = UDim2.fromOffset(SPHERE, SPHERE), ZIndex = 4, Parent = orbArt })
		local ballColors = new("UIGradient", { Rotation = 45, Transparency = fade({ 0, 0.42, 0.35, 0.84, 0.72, 0.74, 1, 0.5 }), Parent = ball })
		edge(ball, 2, WHITE, 0.62)
		local innerRim = edge(round({ Name = "Rim", BackgroundTransparency = 1, Size = UDim2.fromOffset(SPHERE - 20, SPHERE - 20), ZIndex = 4, Parent = orbArt }), 10, S.cyan, 0.84)
		local shade = round({ Name = "Shade", BackgroundColor3 = BLACK, Size = UDim2.fromOffset(SPHERE, SPHERE), ZIndex = 5, Parent = orbArt })
		new("UIGradient", { Rotation = 45, Transparency = fade({ 0, 1, 0.55, 1, 1, 0.62 }), Parent = shade })
		-- the bright core (it breathes)
		local core = layer("Core", Vector2.new(210, 210), 6)
		local coreScale = new("UIScale", { Parent = core })
		local coreLayers = softGlow(core, S.cyan, 0.85)
		local coreMid = round({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, Size = UDim2.fromScale(0.4, 0.4), ZIndex = 2, Parent = core })
		round({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.05, Size = UDim2.fromScale(0.18, 0.18), ZIndex = 3, Parent = core })
		-- a dashed ring that spins round the core
		local dashed = layer("Dashes", Vector2.new(ORB_BOX, ORB_BOX), 7)
		local dashPieces = ellipse(dashed, ORB_BOX, 110, 110, 36, 2, WHITE, 0.45, 0.55)
		-- the shine on the glass (top left)
		round({ Name = "Shine", BackgroundColor3 = WHITE, BackgroundTransparency = 0.6, Position = UDim2.fromScale(178 / ORB_BOX, 135 / ORB_BOX),
			Size = UDim2.fromOffset(92, 46), Rotation = -28, ZIndex = 8, Parent = orbArt })
		round({ BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, Position = UDim2.fromScale(170 / ORB_BOX, 128 / ORB_BOX),
			Size = UDim2.fromOffset(36, 15), Rotation = -28, ZIndex = 8, Parent = orbArt })
		-- three little sparkles that twinkle
		local sparkles: { any } = {}
		for i, s in { { 100, 140, 8 }, { 433, 323, 10 }, { 383, 99, 6 } } do
			local holder = layer("Sparkle", Vector2.new(s[3] * 3, s[3] * 3), 10, Vector2.new(s[1], s[2]))
			sparkles[i] = { phase = i * 2.1, glow = round({ BackgroundColor3 = S.cyan, BackgroundTransparency = 0.7, Parent = holder }),
				dot = round({ BackgroundColor3 = WHITE, Size = UDim2.fromScale(0.34, 0.34), Parent = holder }) }
		end
		-- under the orb: its name (PC), your Luck + the first guarantee, and (phones) backpack + orbs
		local orbName = text({ Name = "OrbTitle", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(460, 44), Parent = orbBlock }, 34)
		local orbNameGlow = new("UIStroke", { Color = S.cyan, Transparency = 0.6, Thickness = 1.5, Parent = orbName })
		local luckLine = text({ Name = "LuckLine", RichText = true, AnchorPoint = Vector2.new(0.5, 0), TextColor3 = S.soft, Size = UDim2.fromOffset(560, 20), Parent = orbBlock }, 15)
		local luckMax = luckLine:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint
		local infoLine = text({ Name = "InfoLine", AnchorPoint = Vector2.new(0.5, 0), TextColor3 = S.sub, Size = UDim2.fromOffset(300, 16), Visible = false, Parent = orbBlock }, 12)

		-- THE SUMMON BUTTONS: OpenOne (gold) and OpenMulti (cyan), the key hints under them --------
		local buttons = block("SummonButtons", 3)
		local bigs: { any } = {}
		local function bigButton(name: string, onClick: () -> ()): any
			local holder = new("Frame", { Name = name .. "Spot", BackgroundTransparency = 1, Parent = buttons })
			-- its glow: a soft haze and a thin halo just outside it (hidden while it can't be used)
			local haze = new("Frame", { Name = "Haze", BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 36, 1, 36), BackgroundTransparency = 0.85, ZIndex = 1, Parent = holder }, { corner(36) })
			local halo2 = new("Frame", { Name = "Halo", BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 10, 1, 10), BackgroundTransparency = 0.82, ZIndex = 1, Parent = holder }, { corner(27) })
			local b = new("TextButton", { Name = name, Text = "", AutoButtonColor = true, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = holder }, { corner(22) })
			local bb: { [string]: any } = { holder = holder, button = b, haze = haze, halo = halo2 }
			bb.colors = new("UIGradient", { Rotation = 90, Parent = b })
			bb.rim = edge(b, 2, WHITE, 0)
			new("Frame", { Name = "Shine", BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, Position = UDim2.new(0, 10, 0, 5),
				Size = UDim2.new(1, -20, 0.34, 0), Parent = b }, { corner(16) })
			bb.main = text({ Name = "Main", Position = UDim2.new(0, 14, 0.16, 0), Size = UDim2.new(1, -28, 0.4, 0), Parent = b }, 34)
			bb.status = text({ Name = "Status", Position = UDim2.new(0, 14, 0.6, 0), Size = UDim2.new(1, -28, 0.19, 0), Parent = b }, 17)
			bb.mainMax = bb.main:FindFirstChildOfClass("UITextSizeConstraint")
			bb.statusMax = bb.status:FindFirstChildOfClass("UITextSizeConstraint")
			-- a small progress bar (the locked multi summon: orbs opened so far)
			bb.bar = new("Frame", { Name = "Progress", Visible = false, BorderSizePixel = 0, BackgroundColor3 = BLACK, BackgroundTransparency = 0.6,
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -9), Size = UDim2.new(0.62, 0, 0, 6), Parent = b }, { corner(3) })
			bb.fill = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = S.gold, Size = UDim2.fromScale(0, 1), Parent = bb.bar }, { corner(3) })
			feedback(b)
			b.Activated:Connect(function() bounce(b); onClick() end)
			table.insert(bigs, bb)
			return bb
		end
		-- (the same calls as the old panel's buttons: startSummon has the request guard)
		local function summonOne() startSummon(1) end
		local function summonMulti()
			local n = multiCount()
			if n <= 1 then toast(multiUnlockText(), SUMMON.gold) return end
			startSummon(n)
		end
		local one = bigButton("OpenOne", summonOne)
		local multi = bigButton("OpenMulti", summonMulti)
		local hints = new("Frame", { Name = "KeyHints", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(660, 20), Parent = buttons },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }) })
		local function keyHint(order: number, key: string, words: string): TextLabel
			local f = new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), LayoutOrder = order, Parent = hints },
				{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }) })
			local cap = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 20), LayoutOrder = 1, Parent = f }, { corner(5) })
			edge(cap, 1, S.key, 0)
			text({ Text = key, TextScaled = false, TextSize = 13, TextColor3 = S.soft, Size = UDim2.fromScale(1, 1), Parent = cap })
			return fixedText({ Text = words, TextColor3 = S.hint, Size = UDim2.fromOffset(0, 20), LayoutOrder = 2, Parent = f }, 13)
		end
		keyHint(1, "E", "Summon 1x")
		local multiHint = keyHint(2, "R", "Summon 3x")
		keyHint(3, "T", "Auto Hatch")

		-- RIGHT: AUTO HATCH, backpack, orbs opened ----------------------------------------------
		local side = block("SummonSide", 3)
		side.AnchorPoint = Vector2.new(1, 0)
		local sideGlass = new("Frame", { Name = "Glass", BackgroundColor3 = S.glass, BackgroundTransparency = 0.22, Size = UDim2.fromScale(1, 1), Parent = side }, { corner(24) })
		edge(sideGlass, 1, S.line, 0.78)
		local autoCard = new("Frame", { Name = "AutoHatchCard", BackgroundColor3 = S.cyan, BackgroundTransparency = 0.92, Parent = side }, { corner(16) })
		local autoEdge = edge(autoCard, 1, S.cyan, 0.65)
		local autoTitle = text({ Text = "AUTO HATCH", TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(200, 22), Parent = autoCard }, 20)
		local autoSub = text({ TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = S.sub,
			Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -124, 0, 30), Parent = autoCard }, 13)
		-- the switch (you own Auto Hatch) or a gold GET button (you don't: it opens the Store)
		local switchGlow = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = S.cyan, BackgroundTransparency = 0.8, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(76, 48), Parent = autoCard }, { corner(24) })
		local switch = new("TextButton", { Name = "AutoHatchSwitch", Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(64, 36), ZIndex = 2, Parent = autoCard }, { corner(18) })
		local switchColors = new("UIGradient", { Parent = switch })
		local switchEdge = edge(switch, 1, WHITE, 0.8)
		local knob = round({ Name = "Knob", BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(28, 28), Parent = switch })
		local getAuto = new("TextButton", { Name = "GetAutoHatch", Text = "🔒 GET", Font = THEME.font, TextScaled = true, TextColor3 = hex("#2A1700"),
			AutoButtonColor = true, BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(96, 36), ZIndex = 2, Parent = autoCard }, {
			corner(18), new("UIGradient", { Rotation = 90, Color = colors({ 0, hex("#FFE98F"), 0.5, S.gold, 1, hex("#E58A00") }) }),
			new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		})
		-- a stat row: name, value, a bar and a small note under it
		local function statRow(name: string, y: number): (Frame, TextLabel, Frame, UIGradient, TextLabel)
			local row = new("Frame", { Name = name, BackgroundTransparency = 1, Position = UDim2.fromOffset(24, y), Size = UDim2.new(1, -48, 0, 56), Parent = side })
			text({ Text = name, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = S.soft, Size = UDim2.new(0.6, 0, 0, 18), Parent = row }, 14)
			local value = text({ TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0.4, 0, 0, 18), Parent = row }, 14)
			local back = new("Frame", { Name = "Bar", BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.92, Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, 0, 0, 8), Parent = row }, { corner(4) })
			local fill = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = WHITE, Size = UDim2.fromScale(0, 1), Parent = back }, { corner(4) })
			local grad = new("UIGradient", { Parent = fill })
			local note = text({ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = S.sub, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 14), Parent = row }, 13)
			return row, value, fill, grad, note
		end
		local packRow, packValue, packFill, packColors, packNote = statRow("Backpack", 126)
		local orbsRow, orbsValue, orbsFill, orbsColors, orbsNote = statRow("Orbs opened", 196)
		orbsColors.Color = ColorSequence.new(hex("#FFB627"), hex("#FFE27A"))
		local orbsBar = orbsFill.Parent :: Frame

		-- PAINTING -----------------------------------------------------------------------------
		local function paintBig(bb: any, style: string, mainText: string, statusText: string, statusColor: Color3?, progress: number?)
			local st = BIG[style]
			bb.colors.Color = colors({ 0, st.top, 0.47, st.mid, 1, st.bottom })
			bb.rim.Color = st.edge
			bb.main.Text = mainText
			bb.main.TextColor3 = st.text
			bb.status.Text = statusText
			bb.status.TextColor3 = statusColor or st.text
			bb.button.AutoButtonColor = style ~= "off"
			bb.haze.Visible = st.glow ~= nil
			bb.halo.Visible = st.glow ~= nil
			if st.glow then
				bb.haze.BackgroundColor3 = st.glow
				bb.halo.BackgroundColor3 = st.glow
			end
			bb.bar.Visible = progress ~= nil
			if progress then bb.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) end
		end
		-- the orb in the colours of the shrine's orb
		local function paintOrb(look: any)
			for _, l in haloLayers do l.BackgroundColor3 = look.glow end
			for _, l in floorLayers do l.BackgroundColor3 = look.glow end
			for _, l in coreLayers do l.BackgroundColor3 = look.deep:Lerp(look.glow, 0.35) end
			coreMid.BackgroundColor3 = look.core
			ballColors.Color = colors({ 0, WHITE, 0.35, look.shell, 0.72, look.deep, 1, look.rings[1] })
			innerRim.Color = look.glow
			for _, p in dashPieces do p.BackgroundColor3 = look.shell end
			for k, ring in rings do
				local c = look.rings[k] or look.glow
				for _, p in ring.pieces do p.BackgroundColor3 = c end
				ring.beadGlow.BackgroundColor3 = c
				ring.beadDot.BackgroundColor3 = c:Lerp(WHITE, 0.6)
			end
			for i, sp in sparkles do
				local c = look.rings[i] or look.glow
				sp.glow.BackgroundColor3 = c
				sp.dot.BackgroundColor3 = c:Lerp(WHITE, 0.5)
			end
			orbNameGlow.Color = look.glow
		end
		-- AUTO HATCH: `want` = the state just asked for (shown straight away), else the real one
		local function paintAuto(want: boolean?)
			local owned = player:GetAttribute("PassAutoHatch") == true
			local on = owned and (if want ~= nil then want else player:GetAttribute("AutoHatch") == true)
			switch.Visible = owned
			switchGlow.Visible = on
			getAuto.Visible = not owned
			switchColors.Color = if on then ColorSequence.new(hex("#1596C9"), S.cyan) else ColorSequence.new(hex("#2B2F52"))
			switchEdge.Transparency = if on then 1 else 0.8
			knob.BackgroundColor3 = if on then WHITE else S.soft
			if knobOn ~= on then
				knobOn = on
				TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Position = if on then UDim2.new(1, -32, 0.5, 0) else UDim2.new(0, 4, 0.5, 0) }):Play()
			end
			autoCard.BackgroundColor3 = if owned then S.cyan else S.gold
			autoEdge.Color = if not owned then S.gold elseif on then S.cyan else WHITE
			autoEdge.Transparency = if on then 0.5 else 0.75
			local pass = CFG.Passes and CFG.Passes.AutoHatch
			autoSub.Text = if not owned then "Get Auto Hatch" .. (if pass and pass.gems then " (◆" .. pass.gems .. ")" else "") .. " in the Store: orbs open by themselves"
				elseif on then "ON: orbs open by themselves while you stand at a shrine"
				else "OFF: switch it on and orbs open by themselves"
		end
		local function pressAuto()
			local want = pressAutoHatch() -- (the AUTO HATCH button's own code: same rules, same messages)
			if want == nil then return end -- (no pass yet: it opened the Store)
			paintAuto(want)
			task.delay(1.6, function() if panel.Visible then paintAuto() end end)
		end
		feedback(switch)
		switch.Activated:Connect(function() bounce(switch); pressAuto() end)
		feedback(getAuto)
		getAuto.Activated:Connect(function() bounce(getAuto); pressAuto() end)
		for _, a in { "AutoHatch", "PassAutoHatch" } do
			player:GetAttributeChangedSignal(a):Connect(function() if panel.Visible then paintAuto() end end)
		end
		-- one odds row per champion of that orb's world, lowest rarity first. Per champion = the
		-- world's odds for its rarity / how many champions share that rarity ("base odds": Luck
		-- raises Epic and better on the real roll)
		local rarityPlace = {}
		for i, r in Config.Rarities do rarityPlace[r.id] = i end
		local function buildOdds(w: any)
			for _, c in rowsBox:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
			local odds = if type(w.odds) == "table" then w.odds else nil
			local function chanceOf(r: any): number return (odds and tonumber(odds[r.id])) or tonumber(r.chance) or 0 end
			local total = 0
			for _, r in Config.Rarities do total += chanceOf(r) end
			local list, sameRarity = {}, {}
			for _, c in Config.Champions do
				if c.world == w.id and Config.RarityById[c.rarity] then
					table.insert(list, c)
					sameRarity[c.rarity] = (sameRarity[c.rarity] or 0) + 1
				end
			end
			table.sort(list, function(a, b)
				if rarityPlace[a.rarity] ~= rarityPlace[b.rarity] then return rarityPlace[a.rarity] < rarityPlace[b.rarity] end
				return a.name < b.name
			end)
			local chip = rowH - 16
			for i, c in list do
				local color = rarityColor(c.rarity)
				local pct = chanceOf(Config.RarityById[c.rarity]) / math.max(total, 0.001) * 100 / sameRarity[c.rarity]
				local row = new("Frame", { Name = "OddsRow", BackgroundColor3 = WHITE, BackgroundTransparency = 0.96, Size = UDim2.new(1, -8, 0, rowH),
					LayoutOrder = i, Parent = rowsBox }, { corner(14) })
				edge(row, 1, WHITE, 0.94)
				local badge = new("Frame", { BackgroundColor3 = color, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0),
					Size = UDim2.fromOffset(chip, chip), Parent = row }, { corner(12) })
				text({ Text = initials(c.name), TextColor3 = textOn(color), Position = UDim2.fromScale(0.14, 0.22), Size = UDim2.fromScale(0.72, 0.56), Parent = badge }, 15)
				local x = chip + 20
				text({ Text = c.name, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, x, 0.13, 0), Size = UDim2.new(1, -(x + 84), 0.34, 0), Parent = row }, 16)
				local tag = fixedText({ Text = string.upper(c.rarity), TextColor3 = textOn(color), BackgroundColor3 = color, BackgroundTransparency = 0,
					Position = UDim2.new(0, x, 0.55, 0), Size = UDim2.new(0, 0, 0.3, 0), Parent = row }, 12)
				corner(10).Parent = tag
				new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = tag })
				text({ Text = percent(pct), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = color:Lerp(WHITE, 0.35), AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0, 76, 0.36, 0), Parent = row }, 18)
			end
		end
		-- a value that changes while you watch gets a little pop
		local function setValue(l: TextLabel, value: string)
			if l.Text == value then return end
			l.Text = value
			if not panel.Visible then return end
			local pop = l:FindFirstChild("Pop") or new("UIScale", { Name = "Pop", Parent = l })
			pop.Scale = 1.15
			TweenService:Create(pop, TweenInfo.new(0.2), { Scale = 1 }):Play()
		end

		-- LIVE VALUES: coins, gems, backpack, orbs opened and the two buttons. (Called on every
		-- coin / backpack / multi-open change and while waiting for the server, so it only sets text
		-- and colours.) Same states as before: busy, can't afford, backpack full, multi locked.
		refreshSummonButtons = function()
			local w = orbWorld()
			setValue(coinsValue, Format.Short(attrNumber("Coins", 0)))
			setValue(gemsValue, Format.Short(attrNumber("Gems", 0)))
			local have, space = ownedCount(), backpackSpace()
			local opened = math.floor(attrNumber("OrbsOpened", 0))
			local need, unlockCount = multiStep()
			local n = multiCount()
			packValue.Text = have .. " / " .. space
			packFill.Size = UDim2.fromScale(math.clamp(have / math.max(space, 1), 0, 1), 1)
			packColors.Color = if have >= space * 0.9 then ColorSequence.new(S.red, hex("#FF9AAE")) else ColorSequence.new(hex("#2EC5FF"), S.cyan)
			packNote.Text = if have >= space then "Full! Release or fuse some champions" else "Room for " .. (space - have) .. " more"
			packNote.TextColor3 = if have >= space then S.bad else S.sub
			orbsValue.Text = commas(opened)
			orbsBar.Visible = n <= 1
			orbsFill.Size = UDim2.fromScale(math.clamp(opened / math.max(need, 1), 0, 1), 1)
			orbsNote.Text = if n <= 1 then "SUMMON " .. unlockCount .. "X unlocks at " .. need .. " orbs" else "Multi summon: " .. n .. " orbs at a time"
			infoLine.Text = "Backpack " .. have .. "/" .. space .. "   ·   " .. commas(opened) .. " orbs opened"
			multiHint.Text = "Summon " .. (if n > 1 then n else unlockCount) .. "x"
			if summonBusy then
				paintBig(one, "off", "SUMMONING...", "Hold on!", S.sub)
				paintBig(multi, "off", "SUMMONING...", "Hold on!", S.sub)
			else
				local block1 = summonBlocker(1)
				paintBig(one, if block1 then "off" else "gold", "SUMMON 1X", block1 or ("$" .. Format.Short(w.orb.cost)), if block1 then S.bad else nil)
				if n <= 1 then
					paintBig(multi, "off", "🔒 SUMMON " .. unlockCount .. "X", multiUnlockText(), S.sub, math.min(opened, need) / math.max(need, 1))
				else
					local blockN = summonBlocker(n)
					paintBig(multi, if blockN then "off" else "cyan", "SUMMON " .. n .. "X", blockN or ("$" .. Format.Short(w.orb.cost * n)), if blockN then S.bad else nil)
				end
			end
			refreshAgainButton()
		end
		-- EVERYTHING ELSE that depends on the shrine and your stats (on open and on stat changes)
		refreshOverlay = function()
			local home = shrineHome()
			local w = orbWorld()
			local orbTitle = string.upper(tostring(((home :: any).orb or w.orb).name))
			if compact then
				gameTitle.Text = orbTitle
				gameTitle.Font = THEME.font
				subTitle.Text = tostring(home.name)
			else
				gameTitle.Text = "AETHERWAKE"
				gameTitle.Font = Enum.Font.LuckiestGuy
				subTitle.Text = "SUMMON  ·  " .. orbTitle .. "  ·  " .. string.upper(tostring(home.name))
			end
			orbName.Text = orbTitle
			if lookKey ~= home.key then
				lookKey = home.key
				paintOrb(orbLookOf(home))
			end
			-- (the rows only change with the world or the row height)
			local key = w.id .. ":" .. rowH
			if oddsKey ~= key then
				oddsKey = key
				buildOdds(w)
			end
			-- your Luck and the first guarantee (Luck boosts Config.LuckBoostFrom and better)
			local luck = short(attrNumber("Luck", 1))
			local first = pityRows[1]
			luckLine.Text = 'Luck <font color="#8CFFB0">×' .. luck .. "</font>"
				.. (if first then "   ·   " .. first.id .. ' within <font color="#FFC83D">' .. first.limit .. "</font>" else "")
			pityNote.Text = "Counted per world. Your Luck ×" .. luck .. " boosts " .. tostring(CFG.LuckBoostFrom or "Epic") .. " and better."
			refreshSummonButtons()
			paintAuto()
		end
		refreshers.Orb = function() refreshOverlay() end

		-- LAYOUT (on open and when the screen changes) -------------------------------------------
		local function fit(g: Frame, scale: number)
			local fitScale = g:FindFirstChild("Fit") :: UIScale
			fitScale.Scale = scale
		end
		local function place(g: Frame, x: number, y: number) g.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5)) end
		-- the drawer and its tab (also when the ODDS tab is tapped)
		local function placeDrawer(animated: boolean)
			local open = if compact then phoneDrawer else pcDrawer
			local dScale = fitNow.u
			local drawerPos = UDim2.fromOffset(math.floor((if open then -24 else -400) * dScale), math.floor(fitNow.drawerTop))
			local tabPos = UDim2.fromOffset(if open then math.floor(372 * dScale) else 0, math.floor(fitNow.tabTop))
			if animated then
				local info = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
				TweenService:Create(drawer, info, { Position = drawerPos }):Play()
				TweenService:Create(tab, info, { Position = tabPos }):Play()
			else
				drawer.Position = drawerPos
				tab.Position = tabPos
			end
		end
		tabButton.Activated:Connect(function()
			playUiSound("click")
			if compact then phoneDrawer = not phoneDrawer else pcDrawer = not pcDrawer end
			placeDrawer(true)
		end)
		layout = function(size: Vector2)
			compact = uiScale.Scale < 0.78 -- (a small real screen: a phone; PCs always get the big layout)
			local u = if compact then math.min(size.X / 844, size.Y / 390) else math.min(size.X / 1600, size.Y / 900)
			local W, H = size.X / u, size.Y / u -- the screen in design units
			local dy = if compact then 0 else (H - 900) / 2 -- (taller screens: the middle moves down)
			fitNow.u, fitNow.W, fitNow.H = u, W, H
			-- QuestUI's tutorial card covers the top right (canvas pixels 64..204) while it's up
			local cardBottom = if player:GetAttribute("TutorialTracker") == true then 214 else 0
			-- Roblox's own buttons along the top (menu, chat...): keep the header clear of them
			local leftClear, rightClear = 0, 0
			pcall(function()
				local inset = GuiService.TopbarInset
				if inset.Width > 0 then
					local k = math.max(uiScale.Scale, 0.01) * u
					leftClear = inset.Min.X / k
					rightClear = math.max(0, workspace.CurrentCamera.ViewportSize.X - inset.Max.X) / k
				end
			end)

			-- header: the band, the title (left), the wallet (right)
			local headH = if compact then 56 else 88
			band.Size = UDim2.new(1, 0, 0, math.floor(headH * u + 0.5))
			fit(titleBlock, u)
			place(titleBlock, math.max(if compact then 16 else 32, leftClear + 14) * u, headH / 2 * u)
			gameTitle.Position = UDim2.fromOffset(0, if compact then 12 else 2)
			gameTitle.Size = UDim2.new(1, 0, 0, if compact then 20 else 32)
			gameMax.MaxTextSize = if compact then 16 else 28
			subTitle.Position = UDim2.fromOffset(0, if compact then 34 else 40)
			subTitle.Size = UDim2.new(1, 0, 0, if compact then 14 else 16)
			subMax.MaxTextSize = if compact then 11 else 14
			local pillH = if compact then 34 else 52
			for _, p in pills do
				p.frame.Size = UDim2.fromOffset(0, pillH)
				local pillCorner = p.frame:FindFirstChildOfClass("UICorner") :: UICorner
				pillCorner.CornerRadius = UDim.new(0, pillH / 2)
				p.badge.Size = if compact then UDim2.fromOffset(26, 26) else UDim2.fromOffset(36, 36)
				p.pad.PaddingLeft = UDim.new(0, if compact then 4 else 8)
				p.pad.PaddingRight = UDim.new(0, if p.plus then (if compact then 5 else 8) else (if compact then 12 else 18))
				p.words.Size = UDim2.fromOffset(0, pillH)
				p.cap.Visible = not compact
				p.value.TextSize = if compact then 15 else 22
				p.value.Position = UDim2.fromOffset(0, if compact then 8 else 20)
				p.value.Size = UDim2.fromOffset(0, if compact then 18 else 24)
				if p.plus then
					p.plus.Size = if compact then UDim2.fromOffset(24, 24) else UDim2.fromOffset(30, 30)
					p.plus.TextSize = if compact then 17 else 20
				end
			end
			local wallH = if compact then 44 else 52
			closeBtn.Size = UDim2.fromOffset(wallH, wallH)
			local closeCorner = closeBtn:FindFirstChildOfClass("UICorner") :: UICorner
			closeCorner.CornerRadius = UDim.new(0, if compact then 14 else 16)
			walletList.Padding = UDim.new(0, if compact then 8 else 14)
			wallet.Size = UDim2.fromOffset(700, wallH)
			local wScale, wY = u, headH / 2 * u
			if cardBottom > 0 and wY + wallH / 2 * wScale > 60 then
				-- (phones during the tutorial: a bit smaller and higher, above the tutorial card)
				wScale, wY = math.min(u, 56 / wallH), 31
			end
			fit(wallet, wScale)
			place(wallet, size.X - math.max(if compact then 16 else 32, rightClear + 14) * u, wY)

			-- the odds drawer (left) and its tab; phones: rows only (the guarantee is under the orb)
			fit(drawer, u)
			local dH = if compact then H - 56 - 6 else 640
			drawer.Size = UDim2.fromOffset(396, dH)
			pityBox.Visible = not compact
			local rowsH = dH - 64 - (if compact then 14 else PITY_H + 34)
			rowsBox.Size = UDim2.fromOffset(322, rowsH)
			local gap = if compact then 6 else 8
			rowsList.Padding = UDim.new(0, gap)
			local count = 0
			local worldId = orbWorld().id
			for _, c in Config.Champions do if c.world == worldId then count += 1 end end
			-- (phones: rows get shorter to fit, down to 38; any more scroll)
			rowH = if compact then math.clamp(math.floor((rowsH - math.max(count - 1, 0) * gap) / math.max(count, 1)), 38, 54) else 54
			fitNow.drawerTop = (if compact then 56 else 116 + dy) * u
			fit(tab, if compact then u * 1.1 else u)
			fitNow.tabTop = (if compact then 120 else 380 + dy) * u
			placeDrawer(false)

			-- the orb block; the right column (phones: Auto Hatch on top, the buttons under it)
			fit(orbBlock, u)
			orbBlock.AnchorPoint = Vector2.new(0.5, 0)
			fitNow.colTop = math.max(72, cardBottom / u + 6)
			if compact then
				local cx = (44 + (W - 24 - 300)) / 2 -- (between the ODDS tab and the buttons)
				orbBlock.Size = UDim2.fromOffset(300, 320)
				place(orbBlock, cx * u, 70 * u)
				orbArtScale.Scale = 190 / 360
				orbSpot.x, orbSpot.y, orbSpot.h = 0.5, 135, 320
				orbName.Visible = false
				luckLine.Position = UDim2.new(0.5, 0, 0, 260)
				luckLine.Size = UDim2.fromOffset(300, 18)
				luckMax.MaxTextSize = 13
				infoLine.Visible = true
				infoLine.Position = UDim2.new(0.5, 0, 0, 282)
				glowSpot.Position = UDim2.fromScale(cx * u / size.X, 205 * u / size.Y)
				glowSpot.Size = UDim2.fromScale(0.7, 1.2)
			else
				orbBlock.Size = UDim2.fromOffset(560, 600)
				place(orbBlock, size.X / 2, (150 + dy) * u)
				orbArtScale.Scale = 1
				orbSpot.x, orbSpot.y, orbSpot.h = 0.5, 260, 600
				orbName.Visible = true
				orbName.Position = UDim2.new(0.5, 0, 0, 490)
				luckLine.Position = UDim2.new(0.5, 0, 0, 538)
				luckLine.Size = UDim2.fromOffset(560, 20)
				luckMax.MaxTextSize = 15
				infoLine.Visible = false
				glowSpot.Position = UDim2.fromScale(0.5, 0.48)
				glowSpot.Size = UDim2.fromScale(0.85, 1.1)
			end
			orbArt.Position = UDim2.fromScale(orbSpot.x, orbSpot.y / orbSpot.h)

			-- the summon buttons
			fit(buttons, u)
			if compact then
				local top = fitNow.colTop + 56 + 12
				local btnH = math.floor(math.clamp((H - 8 - top - 12) / 2, 64, 96))
				buttons.AnchorPoint = Vector2.new(1, 0)
				buttons.Size = UDim2.fromOffset(300, btnH * 2 + 12)
				place(buttons, (W - 24) * u, top * u)
				one.holder.Position = UDim2.fromOffset(0, 0)
				multi.holder.Position = UDim2.fromOffset(0, btnH + 12)
				for _, bb in bigs do
					bb.holder.Size = UDim2.fromOffset(300, btnH)
					bb.mainMax.MaxTextSize = math.floor(28 * btnH / 96)
					bb.statusMax.MaxTextSize = 15
				end
				hints.Visible = false
			else
				buttons.AnchorPoint = Vector2.new(0.5, 0)
				buttons.Size = UDim2.fromOffset(660, 150)
				place(buttons, size.X / 2, (724 + dy) * u)
				one.holder.Position = UDim2.fromOffset(19, 0)
				multi.holder.Position = UDim2.fromOffset(341, 0)
				for _, bb in bigs do
					bb.holder.Size = UDim2.fromOffset(300, 112)
					bb.mainMax.MaxTextSize = 34
					bb.statusMax.MaxTextSize = 17
				end
				hints.Position = UDim2.new(0.5, 0, 0, 128)
				-- (the E / R / T keys: not shown to someone playing with a controller)
				hints.Visible = UserInputService.KeyboardEnabled and player:GetAttribute("InputMode") ~= "Gamepad"
			end

			-- the right panel (phones: only the AUTO HATCH card, above the buttons)
			if compact then
				fit(side, u * 300 / 372)
				side.Size = UDim2.fromOffset(372, 69)
				place(side, (W - 24) * u, fitNow.colTop * u)
				autoCard.Position = UDim2.fromOffset(0, 0)
				autoCard.Size = UDim2.fromOffset(372, 69)
				autoTitle.Position = UDim2.fromOffset(18, 23)
			else
				fit(side, u)
				side.Size = UDim2.fromOffset(372, 276)
				place(side, (W - 24) * u, math.max((116 + dy) * u, cardBottom))
				autoCard.Position = UDim2.fromOffset(24, 24)
				autoCard.Size = UDim2.fromOffset(324, 84)
				autoTitle.Position = UDim2.fromOffset(16, 14)
			end
			for _, g in { sideGlass, autoSub, packRow, orbsRow } do g.Visible = not compact end

			-- the background grid (48 design units apart)
			local step = 48 * u
			local nx, ny = math.floor(size.X / step), math.floor(size.Y / step)
			for i, line in gridLines do
				line.Visible = i <= nx + ny
				if i <= nx then
					line.Position = UDim2.fromOffset(math.floor(i * step), 0)
					line.Size = UDim2.new(0, 1, 1, 0)
				elseif i <= nx + ny then
					line.Position = UDim2.fromOffset(0, math.floor((i - nx) * step))
					line.Size = UDim2.new(1, 0, 0, 1)
				end
			end
			refreshOverlay() -- (the titles and the odds rows depend on the layout)
		end
		player:GetAttributeChangedSignal("TutorialTracker"):Connect(function()
			if fs.isOpen() then layout(fs.canvasSize()) end
		end)

		-- ANIMATION (only while the overlay is on screen: see makeFullscreen) ---------------------
		animate = function(t: number)
			-- the orb floats (placed by Scale: offsets are whole pixels and would jitter)
			orbArt.Position = UDim2.fromScale(orbSpot.x, (orbSpot.y + math.sin(t * 1.1) * 5) / orbSpot.h)
			-- the rings rock a little and a spark runs round each one, in front of or behind the glass
			for k, ring in rings do
				local r = RINGS[k]
				local tilt = r.tilt + math.sin(t * 0.35 + k * 2.1) * 5
				ring.back.Rotation = tilt
				ring.front.Rotation = tilt
				local a = t * r.speed + k * 2
				local x, y = r.rx * math.cos(a), r.ry * math.sin(a)
				local c, s = math.cos(math.rad(tilt)), math.sin(math.rad(tilt))
				ring.bead.Position = UDim2.fromScale(0.5 + (x * c - y * s) / ORB_BOX, 0.5 + (x * s + y * c) / ORB_BOX)
				local near = math.sin(a) >= 0
				if near ~= ring.near then
					ring.near = near
					ring.bead.ZIndex = if near then 9 else 3
				end
			end
			dashed.Rotation = (18 + t * 14) % 360
			-- the core breathes, the glow round the glass swells a little, the sparkles twinkle
			coreScale.Scale = 1 + 0.07 * math.sin(t * 2.4)
			haloScale.Scale = 1 + 0.035 * math.sin(t * 1.3)
			for _, sp in sparkles do
				local k = 0.5 + 0.5 * math.sin(t * 2.6 + sp.phase)
				sp.dot.BackgroundTransparency = 0.1 + 0.55 * (1 - k)
				sp.glow.BackgroundTransparency = 0.6 + 0.35 * (1 - k)
			end
			-- the buttons you can use glow softly
			local pulse = 0.85 + 0.05 * math.sin(t * 2.5)
			for _, bb in bigs do
				if bb.haze.Visible then bb.haze.BackgroundTransparency = pulse end
			end
		end

		-- KEYS: E = summon 1, R = summon multi, T = Auto Hatch (bound only while it's open) ----------
		local KEYS = { AetherwakeSummonOne = Enum.KeyCode.E, AetherwakeSummonMulti = Enum.KeyCode.R, AetherwakeSummonAuto = Enum.KeyCode.T }
		local function onKey(action: string, state: Enum.UserInputState): Enum.ContextActionResult
			-- (the keys are swallowed while it's open, so E can't trigger the shrine again; for 0.4 s
			-- after opening they do nothing, because E is also what opened it)
			if state ~= Enum.UserInputState.Begin or not fs.isOpen() or os.clock() - openedAt < 0.4 then
				return Enum.ContextActionResult.Sink
			end
			if action == "AetherwakeSummonOne" then
				bounce(one.button)
				task.spawn(summonOne)
			elseif action == "AetherwakeSummonMulti" then
				bounce(multi.button)
				task.spawn(summonMulti)
			else
				task.spawn(pressAuto)
			end
			return Enum.ContextActionResult.Sink
		end
		bindKeys = function()
			for action, key in KEYS do
				ContextActionService:BindActionAtPriority(action, onKey, false, Enum.ContextActionPriority.High.Value, key)
			end
		end
		unbindKeys = function()
			for action in KEYS do ContextActionService:UnbindAction(action) end
		end
	end
	buildSummonOverlay()

	-- SUMMON OVERLAY ---------------------------------------------------------
	-- One full-screen layer for the whole summon. It's named "Reveal" because the tutorial
	-- guide (QuestClient) waits while it's visible. During the cinematic it's see-through (only
	-- SKIP shows), afterwards it becomes the result screen.
	local ui: { [string]: any } = {}
	-- (Selectable = false: it's a full-screen tap catcher, a controller should never land on it)
	ui.reveal = new("TextButton", { Name = "Reveal", Text = "", AutoButtonColor = false, Selectable = false, Visible = false, BackgroundColor3 = SUMMON.navy,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = canvas })
	ui.cinematicLayer = new("Frame", { Name = "CinematicLayer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = ui.reveal })
	ui.resultsLayer = new("Frame", { Name = "ResultsLayer", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = ui.reveal })

	-- slim currency pill (top left): the only stats left on screen during a summon.
	-- (SKIP and this pill are placed by screen scale, 0.07 / 0.93, so the cinematic's black
	-- letterbox bars, up to ~6.5% of the screen at the top and bottom, never cover them)
	ui.pill = new("Frame", { Name = "SummonCurrency", Visible = false, BackgroundColor3 = SUMMON.navy, BackgroundTransparency = 0.15,
		Position = UDim2.new(0, 16, 0.07, 6), Size = UDim2.fromOffset(220, 40), ZIndex = 6, Parent = canvas },
		{ corner(20), new("UIStroke", { Thickness = 2, Color = SUMMON.violet, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	ui.pillCoins = label({ Text = "", Position = UDim2.fromOffset(16, 7), Size = UDim2.new(0.58, -16, 1, -14), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = SUMMON.gold, Parent = ui.pill })
	ui.pillGems = label({ Text = "", Position = UDim2.new(0.58, 0, 0, 7), Size = UDim2.new(0.42, -16, 1, -14), TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = THEME.gem, Parent = ui.pill })

	-- SKIP (bottom right, big enough for a thumb). A tap skips; holding anywhere fast-forwards.
	ui.skip = new("TextButton", { Name = "SkipButton", Text = "", Visible = false, AutoButtonColor = true, BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 0.93, -8), Size = UDim2.fromOffset(210, 80), Parent = ui.cinematicLayer },
		{ corner(40), new("UIStroke", { Thickness = 3, Color = SUMMON.cyan, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }), gradient(SUMMON.navy3, SUMMON.navy) })
	label({ Text = "SKIP  ▶", Position = UDim2.new(0, 18, 0, 14), Size = UDim2.new(1, -36, 1, -28), Parent = ui.skip })
	ui.skipHint = label({ Name = "SkipHint", Visible = false,
		Text = "", -- (set by skipHintText below: it follows the last device used)
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -30, 0.93, -96), Size = UDim2.fromOffset(320, 22),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = SUMMON.sub, Parent = ui.cinematicLayer })
	-- the hint follows the device you're using (InputMode is set by ControllerSupport)
	local function skipHintText()
		local mode = player:GetAttribute("InputMode")
		ui.skipHint.Text = if mode == "Gamepad" then "Hold to fast-forward, tap to skip"
			elseif mode == "Touch" or (mode == nil and UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then "Hold the screen to fast-forward"
			else "Hold mouse or Space to fast-forward"
	end
	player:GetAttributeChangedSignal("InputMode"):Connect(skipHintText)
	skipHintText()
	-- the small "▶▶" chip while fast-forwarding
	ui.fastChip = new("Frame", { Name = "FastForward", Visible = false, BackgroundColor3 = SUMMON.cyan, AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -30, 0.93, -126), Size = UDim2.fromOffset(100, 36), Parent = ui.cinematicLayer }, { corner(18), stroke(2, SUMMON.navy) })
	do
		local chipText = label({ Text = "▶▶  x" .. TIMING.fastSpeed, Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 1, -10), TextColor3 = SUMMON.navy, Parent = ui.fastChip })
		local outline = chipText:FindFirstChildOfClass("UIStroke")
		if outline then outline.Enabled = false end
	end

	-- the result screen: title, a row of cards, SUMMON AGAIN + CLOSE, the countdown
	-- (laid out around the screen centre; the whole column fits a 640-high canvas, the smallest phones)
	ui.title = label({ Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, -270), Size = UDim2.fromOffset(600, 44),
		TextColor3 = SUMMON.gold, Parent = ui.resultsLayer })
	ui.cards = new("Frame", { Name = "Cards", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, -208),
		Size = UDim2.fromOffset(1180, 370), Parent = ui.resultsLayer }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 20), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	ui.again = summonButton("SummonAgain", ui.resultsLayer, UDim2.new(0.5, -10, 0.5, 180), UDim2.fromOffset(340, 70), Vector2.new(1, 0),
		SUMMON.violet, SUMMON.violetDark, function()
			if summonBusy or summonBlocker(resultScreen.count) then return end -- (the button already says why)
			startSummon(resultScreen.count)
		end)
	ui.close = button({ Name = "CloseResults", Color = SUMMON.navy3, Text = "CLOSE", Position = UDim2.new(0.5, 10, 0.5, 180),
		Size = UDim2.fromOffset(200, 70), Parent = ui.resultsLayer }, function() closeSummonResults(false) end)
	ui.timerBack = new("Frame", { BackgroundColor3 = SUMMON.navy, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 264),
		Size = UDim2.fromOffset(320, 10), Parent = ui.resultsLayer }, { corner(5), new("UIStroke", { Thickness = 1, Color = SUMMON.line, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	ui.timerFill = new("Frame", { BackgroundColor3 = SUMMON.cyan, Size = UDim2.fromScale(1, 1), Parent = ui.timerBack }, { corner(5) })
	ui.timerText = label({ Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 280), Size = UDim2.fromOffset(440, 20),
		TextColor3 = SUMMON.sub, Parent = ui.resultsLayer })

	-- FAST-FORWARD + SKIP INPUT ----------------------------------------------
	local hold = {
		pointers = {} :: { [any]: boolean }, -- mouse button / fingers held down right now
		pointerFast = false, pointerToken = 0,
		spaceDownAt = nil :: number?, spaceFast = false, spaceToken = 0,
		becameHold = false, -- this press turned into fast-forward, so letting go must not skip
		speed = 1,          -- the speed we last gave SummonCinematic
		startedAt = 0,      -- os.clock() when the cinematic started
	}
	local function canSkipNow(): boolean
		local m = getCinematic()
		if not m then return false end
		if type(m.CanSkip) ~= "function" then return os.clock() - hold.startedAt > 0.4 end
		local ok, can = pcall(m.CanSkip)
		return ok and can == true
	end
	-- Tells SummonCinematic the speed: x3 while the screen or Space is held, otherwise normal.
	local function applySpeed()
		local want = if summonPhase == "cinematic" and (hold.pointerFast or hold.spaceFast) then TIMING.fastSpeed else 1
		if want ~= hold.speed then
			hold.speed = want
			cine("SetSpeed", want)
		end
		ui.fastChip.Visible = want > 1
	end
	local function resetHold()
		table.clear(hold.pointers)
		hold.pointerFast, hold.spaceFast, hold.spaceDownAt, hold.becameHold = false, false, nil, false
		hold.pointerToken += 1
		hold.spaceToken += 1
		hold.speed = 1
		cine("SetSpeed", 1) -- (every summon starts at normal speed)
		ui.fastChip.Visible = false
	end
	local function trySkip()
		if summonPhase ~= "cinematic" or not canSkipNow() then return end
		cine("Skip")
		ui.skip.Visible = false
		ui.skipHint.Visible = false
	end
	-- Space (and gamepad A): a quick tap skips, holding it fast-forwards. Sinking the key also
	-- stops the character jumping while the cinematic plays.
	local function onSkipKey(_action: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
		if summonPhase ~= "cinematic" then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then
			hold.spaceDownAt = os.clock()
			hold.spaceToken += 1
			local token = hold.spaceToken
			task.delay(TIMING.hold, function()
				if token == hold.spaceToken and hold.spaceDownAt then
					hold.spaceFast = true
					applySpeed()
				end
			end)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			local downAt = hold.spaceDownAt
			local tapped = downAt ~= nil and not hold.spaceFast and os.clock() - downAt < TIMING.hold
			hold.spaceDownAt, hold.spaceFast = nil, false
			hold.spaceToken += 1
			applySpeed()
			if tapped and state == Enum.UserInputState.End then trySkip() end
		end
		return Enum.ContextActionResult.Sink
	end
	feedback(ui.skip)
	ui.skip.Activated:Connect(function()
		if hold.becameHold then return end -- (that press was a fast-forward hold, not a tap)
		bounce(ui.skip)
		trySkip()
	end)
	-- Mouse / touch anywhere: during the cinematic a long press fast-forwards; on the result
	-- screen any tap counts as "I'm still here" and restarts the countdown.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		-- (a controller press on the result screen also means "I'm still here")
		if summonPhase == "results" and string.find(kind.Name, "Gamepad") then resultScreen.lastTap = os.clock() return end
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
		if summonPhase == "results" then resultScreen.lastTap = os.clock() return end
		if summonPhase ~= "cinematic" then return end
		local key = if kind == Enum.UserInputType.Touch then input else "mouse"
		hold.pointers[key] = true
		hold.becameHold = false
		hold.pointerToken += 1
		local token = hold.pointerToken
		task.delay(TIMING.hold, function()
			if token == hold.pointerToken and hold.pointers[key] and summonPhase == "cinematic" then
				hold.pointerFast = true
				hold.becameHold = true
				applySpeed()
			end
		end)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		local key = if kind == Enum.UserInputType.Touch then input elseif kind == Enum.UserInputType.MouseButton1 then "mouse" else nil
		if key == nil or not hold.pointers[key] then return end
		hold.pointers[key] = nil
		if next(hold.pointers) == nil then
			hold.pointerFast = false
			hold.pointerToken += 1
			applySpeed()
		end
	end)

	-- SCREEN MODES -----------------------------------------------------------
	-- Everything that would cover the altar during a summon (put back afterwards).
	local hudFrames: { GuiObject } = { left, worldPill, version, goal, mults, bottom, autoHatchRow }
	-- other scripts' screens (dash button, tutorial hand): switched off only while the cinematic plays
	local OTHER_GUIS = { "MovementUI", "QuestUI" }
	local savedVisible: { [Instance]: boolean } = {}
	local function refreshPill()
		ui.pillCoins.Text = "$ " .. Format.Short(attrNumber("Coins", 0))
		ui.pillGems.Text = "◆ " .. Format.Short(attrNumber("Gems", 0))
	end
	-- "cinematic": only SKIP + the currency pill. "results": the result screen (+ pill).
	-- "idle": the normal HUD. Every change goes through here, so nothing is ever left hidden.
	local function setSummonMode(mode: string)
		summonPhase = mode
		gui:SetAttribute("SummonPhase", mode) -- (ControllerSupport reads it to move the controller focus)
		local busy = mode ~= "idle"
		for _, g in hudFrames do
			if busy then
				if savedVisible[g] == nil then savedVisible[g] = g.Visible end
				g.Visible = false
			elseif savedVisible[g] ~= nil then
				g.Visible = savedVisible[g]
			end
		end
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		for _, name in OTHER_GUIS do
			local g = playerGui and playerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				if mode == "cinematic" then
					if savedVisible[g] == nil then savedVisible[g] = g.Enabled end
					g.Enabled = false
				elseif savedVisible[g] ~= nil then
					g.Enabled = savedVisible[g]
					savedVisible[g] = nil
				end
			end
		end
		if not busy then table.clear(savedVisible) end
		if not busy then applyGoalVisibility() end -- (the training card may have come or gone meanwhile)
		toastHolder.Visible = mode ~= "cinematic"
		ui.pill.Visible = busy
		ui.reveal.Visible = busy
		ui.reveal.BackgroundTransparency = if mode == "results" then 0.4 else 1
		ui.cinematicLayer.Visible = mode == "cinematic"
		ui.resultsLayer.Visible = mode == "results"
		ui.skip.Visible = false
		ui.skipHint.Visible = false
		if busy then refreshPill() end
		-- (The proximity prompts over the altar are hidden by SummonCinematic itself while it plays
		-- and put back when it ends. The HUD doesn't touch them: two scripts saving and restoring the
		-- same setting could leave the shrine prompts switched off for good.)
		if mode == "cinematic" then
			ContextActionService:BindActionAtPriority(SKIP_ACTION, onSkipKey, false, Enum.ContextActionPriority.High.Value + 10,
				Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
		else
			ContextActionService:UnbindAction(SKIP_ACTION)
		end
		if mode == "idle" then
			-- safety net: with no summon on screen any more, the shrine prompts must work again
			local _, playing = cine("IsPlaying")
			local _, holding = cine("IsHolding")
			if playing ~= true and holding ~= true then
				pcall(function()
					if not ProximityPromptService.Enabled then ProximityPromptService.Enabled = true end
				end)
			end
		end
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refreshPill)
	player:GetAttributeChangedSignal("Gems"):Connect(refreshPill)

	-- RESULT SCREEN ----------------------------------------------------------
	-- The summoned champions stand on the altar until the result screen closes.
	-- SummonCinematic keeps them posed (its "hold") until Release() is called; that also gives the
	-- camera and controls back. (It lets go by itself too once "Reveal" hides, this is just quicker.)
	local function clearLineup()
		local m = getCinematic()
		if not m then return end
		for _, name in { "Release", "ClearLineup", "Clear", "Cleanup" } do
			if type(m[name]) == "function" then cine(name) return end
		end
	end
	-- Copies of champion `id` you own now (3 fuse into a star). The inventory update can land a
	-- moment after the summon result, so the summoned one counts even if it isn't in yet.
	local function copiesOwned(id: string, uid: string?): number
		local n, hasIt = 0, false
		for u, owned in champions do
			if owned.id == id then n += 1 end
			if u == uid then hasIt = true end
		end
		return if hasIt or uid == nil then n else n + 1
	end
	-- One result card: 3D picture, name, rarity pill, power, NEW / duplicate line, EQUIP.
	local function buildResultCard(index: number, res: any, width: number, token: number, simple: boolean)
		local def = Config.ChampionById[res.id]
		local rarityId = res.rarity
		local color = rarityColor(rarityId)
		local card = new("Frame", { Name = "ResultCard", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(width, 370), LayoutOrder = index, Parent = ui.cards }, {
			corner(18), new("UIStroke", { Thickness = 4, Color = color, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			gradient(rarityDark(rarityId):Lerp(SUMMON.navy2, 0.3), SUMMON.navy), new("UIScale", { Name = "Pop", Scale = 0 }),
		})
		local pic = new("Frame", { BackgroundColor3 = SUMMON.navy, BackgroundTransparency = 0.35, Position = UDim2.fromOffset(10, 10),
			Size = UDim2.new(1, -20, 0, 144), Parent = card }, { corner(14) })
		if Models:FindFirstChild(def.id) then
			viewport(def.id, pic, UDim2.fromScale(1, 1))
		else
			label({ Text = "?", TextColor3 = color, Position = UDim2.fromScale(0.3, 0.2), Size = UDim2.fromScale(0.4, 0.6), Parent = pic }) -- (no 3D model yet)
		end
		label({ Text = def.name, Position = UDim2.fromOffset(10, 160), Size = UDim2.new(1, -20, 0, 28), Parent = card })
		rarityPill(card, rarityId, UDim2.new(0.5, 0, 0, 192), Vector2.new(0.5, 0), UDim2.fromOffset(124, 22))
		label({ Text = "⚔ " .. Format.Short(res.power or def.power) .. " power", Position = UDim2.fromOffset(10, 220), Size = UDim2.new(1, -20, 0, 20),
			TextColor3 = Color3.fromRGB(255, 150, 150), Parent = card })
		-- (two lines tall so "NEW! Added to your collection" stays readable on phones)
		local status = label({ Text = "", TextWrapped = true, Position = UDim2.fromOffset(8, 246), Size = UDim2.new(1, -16, 0, 40), Parent = card })
		-- fusion pips: one per copy a fusion needs (3); lit = copies you own
		local need = math.clamp(math.floor(fusionNumber("copies", 3)), 2, 5)
		local pipRow = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 292),
			Size = UDim2.fromOffset(need * 22, 12), Visible = not res.new, Parent = card }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local pips = {}
		for k = 1, need do
			local glow = new("UIStroke", { Thickness = 2, Color = SUMMON.gold, Transparency = 0.2, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
			local dot = new("Frame", { BackgroundColor3 = SUMMON.navy3, Size = UDim2.fromOffset(14, 12), LayoutOrder = k, Parent = pipRow },
				{ new("UICorner", { CornerRadius = UDim.new(0.5, 0) }), glow })
			pips[k] = { dot = dot, glow = glow }
		end
		if res.new then
			local tag = new("Frame", { BackgroundColor3 = SUMMON.gold, Rotation = -12, Size = UDim2.fromOffset(84, 34), Position = UDim2.fromOffset(-10, -10),
				ZIndex = 2, Parent = card }, { corner(10), stroke(2) })
			label({ Text = "NEW!", Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), ZIndex = 2, Parent = tag })
		end
		local equipBtn = new("TextButton", { Name = "EquipButton", Text = "EQUIP", Font = THEME.font, TextScaled = true, TextColor3 = SUMMON.text,
			BackgroundColor3 = SUMMON.good, AutoButtonColor = true, Position = UDim2.new(0, 10, 1, -52), Size = UDim2.new(1, -20, 0, 42), Parent = card }, {
			corner(12), new("UIStroke", { Thickness = 2, Color = SUMMON.navy, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			new("UIStroke", { Thickness = 1.5, Color = THEME.stroke }), -- (outline on the text)
			new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})
		local equipping, equippedHere = false, false
		local messageUntil = 0 -- while os.clock() is below this, EQUIP shows the server's message
		local function update()
			if not card.Parent then return end
			if res.new then
				status.Text = "NEW! Added to your collection ✓"
				status.TextColor3 = SUMMON.gold
			else
				local have = math.min(copiesOwned(res.id, res.uid), need)
				local ready = have >= need
				status.Text = if ready then "DUPLICATE • Ready to fuse!" else string.format("DUPLICATE • fusion %d/%d", have, need)
				status.TextColor3 = if ready then SUMMON.gold else SUMMON.cyan
				for k, pip in pips do
					local lit = k <= have
					pip.dot.BackgroundColor3 = if not lit then SUMMON.navy3 elseif ready then SUMMON.gold else SUMMON.cyan
					pip.glow.Enabled = ready and lit -- (full pips glow)
				end
			end
			if equipping or os.clock() < messageUntil then return end
			if res.uid == nil then
				equipBtn.Visible = false
			elseif equippedHere or table.find(equipped, res.uid) then
				equipBtn.Text = "EQUIPPED ✓"
				equipBtn.BackgroundColor3 = SUMMON.navy3
				equipBtn.TextColor3 = SUMMON.good
				equipBtn.AutoButtonColor = false
			else
				equipBtn.Text = "EQUIP"
				equipBtn.BackgroundColor3 = SUMMON.good
				equipBtn.TextColor3 = SUMMON.text
				equipBtn.AutoButtonColor = true
			end
		end
		feedback(equipBtn)
		equipBtn.Activated:Connect(function()
			resultScreen.lastTap = os.clock()
			if equipping or equippedHere or not res.uid or table.find(equipped, res.uid) then return end
			bounce(equipBtn)
			equipping = true
			equipBtn.Text = "..."
			local ok, msg = invoke("EquipChampion", res.uid, true)
			equipping = false
			if token ~= resultScreen.token then return end -- (the result screen closed meanwhile)
			if ok then
				equippedHere = true
			else
				-- show the server's reason (e.g. "All equip slots are full.") on the button for a moment
				messageUntil = os.clock() + 2.5
				equipBtn.Text = tostring(msg or "Can't equip that")
				equipBtn.BackgroundColor3 = SUMMON.navy3
				equipBtn.TextColor3 = SUMMON.bad
				task.delay(2.6, update)
			end
			update()
		end)
		table.insert(resultScreen.cards, update)
		update()
		-- pop in one after another (slower when there was no cinematic, like the old reveal)
		local delay = if simple then 0.2 + (index - 1) * 0.35 else 0.05 + (index - 1) * 0.1
		task.delay(delay, function()
			if token ~= resultScreen.token then return end
			TweenService:Create(card:FindFirstChild("Pop") :: UIScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			if simple then bigPullToast(rarityId, def.name, color) end -- (the cinematic shows its own banner)
		end)
	end

	refreshAgainButton = function()
		local count = resultScreen.count
		if summonBusy then
			setSummonButton(ui.again, false, "SUMMONING...", "Hold on!", SUMMON.sub)
			return
		end
		local block = summonBlocker(count)
		setSummonButton(ui.again, block == nil, "SUMMON AGAIN x" .. count .. "  •  $" .. Format.Short(orbWorld().orb.cost * count),
			block or ("You have $" .. Format.Short(attrNumber("Coins", 0))), if block then SUMMON.bad else SUMMON.gold)
	end
	refreshSummonEquips = function()
		for _, update in resultScreen.cards do update() end
	end

	local function showResults(list: { any }, count: number, simple: boolean)
		setSummonMode("results")
		resultScreen.token += 1
		local token = resultScreen.token
		resultScreen.count = count
		pcall(function() player:SetAttribute("SummonResultsOpen", true) end) -- (a local hint for other client scripts)
		for _, c in ui.cards:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		table.clear(resultScreen.cards)
		local n = #list
		ui.title.Text = if n > 1 then "YOU SUMMONED " .. n .. " CHAMPIONS!" else "YOU SUMMONED!"
		-- cards are 230 wide; if they don't fit the screen (lots of results, small phones) they get
		-- narrower and closer together. (canvas.Size = the screen size in design pixels)
		local room = math.min(1180, canvas.Size.X.Offset - 40)
		local gap = if n > 5 then 10 else 20
		local width = math.clamp(math.floor((room - gap * (n - 1)) / n), 96, 230)
		local row = ui.cards:FindFirstChildOfClass("UIListLayout")
		if row then row.Padding = UDim.new(0, gap) end
		for i, res in list do buildResultCard(i, res, width, token, simple) end
		refreshAgainButton()
		-- the countdown: it closes by itself after TIMING.results seconds without a tap
		resultScreen.lastTap = os.clock()
		local shownSeconds = -1
		if resultScreen.conn then resultScreen.conn:Disconnect() end
		resultScreen.conn = RunService.Heartbeat:Connect(function()
			local left = TIMING.results - (os.clock() - resultScreen.lastTap)
			ui.timerFill.Size = UDim2.fromScale(math.clamp(left / TIMING.results, 0, 1), 1)
			local whole = math.max(0, math.ceil(left))
			if whole ~= shownSeconds then
				shownSeconds = whole
				ui.timerText.Text = "Closes in " .. whole .. "s  •  " .. (if player:GetAttribute("InputMode") == "Gamepad" then "press any button" else "tap") .. " to keep it open"
			end
			if left <= 0 then closeSummonResults(false) end
		end)
	end
	-- keepPending = true: leave buffered Auto Hatch cards for later (SUMMON AGAIN is starting)
	closeSummonResults = function(instant: boolean?, keepPending: boolean?)
		if summonPhase ~= "results" then return end
		resultScreen.token += 1
		local token = resultScreen.token
		if resultScreen.conn then resultScreen.conn:Disconnect(); resultScreen.conn = nil end
		table.clear(resultScreen.cards)
		clearLineup()
		pcall(function() player:SetAttribute("SummonResultsOpen", false) end)
		local function finish()
			if token ~= resultScreen.token then return end
			for _, c in ui.cards:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
			setSummonMode("idle")
			if not keepPending then flushPendingHatch() end
		end
		if instant then finish() return end
		-- shrink the cards away, then hide everything
		for _, c in ui.cards:GetChildren() do
			local p = c:FindFirstChild("Pop")
			if p then TweenService:Create(p, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play() end
		end
		task.delay(0.2, finish)
	end

	-- THE SUMMON FLOW --------------------------------------------------------
	-- Plays SummonCinematic at the altar and waits until it's over (finished or skipped).
	-- Returns false if the player didn't get to see it (errored, aborted), so the caller shows
	-- the cards the simple way.
	local function runCinematic(list: { any }, quick: boolean): boolean
		setSummonMode("cinematic")
		resetHold()
		hold.startedAt = os.clock()
		local finished, playedOk = false, false
		local altar = summonAltar()
		task.spawn(function()
			-- Play says how it ended. "finished" / "skipped": the player saw the summon. "aborted"
			-- (teleported, died), "error" or "empty": they didn't, so the cards pop in the slow way.
			local ok, how = cine("Play", list, altar, { quick = quick })
			playedOk = ok and (how == nil or how == "finished" or how == "skipped" or how == "released")
			finished = true
		end)
		-- SKIP shows up once the cinematic says it can be skipped (about 0.4 s in)
		local skipWatch = RunService.Heartbeat:Connect(function()
			local can = summonPhase == "cinematic" and canSkipNow()
			ui.skip.Visible = can
			ui.skipHint.Visible = can
		end)
		while not finished and os.clock() - hold.startedAt < TIMING.maxCinematic do task.wait() end
		skipWatch:Disconnect()
		if not finished then
			warn("[HUD] The summon cinematic ran too long, skipping it.")
			cine("Skip")
		elseif not playedOk then
			cine("Skip") -- (it errored: make sure the camera, controls and lighting are handed back)
		end
		resetHold()
		return finished and playedOk
	end
	local function playSummon(list: { any }, count: number)
		if summonPhase == "results" then closeSummonResults(true, true) end
		showPanel(nil)
		-- after a few summons this session, Common/Uncommon singles play the short version
		local quick = summonsThisSession >= TIMING.quickAfter
		summonsThisSession += 1
		local played = false
		if getCinematic() then played = runCinematic(list, quick) end
		showResults(list, count, not played)
	end
	startSummon = function(count: number)
		if summonBusy or summonPhase == "cinematic" then return end
		if type(count) ~= "number" or count < 1 then return end
		local _, why = summonBlocker(count)
		if why then toast(why, SUMMON.bad) return end
		summonBusy = true -- (locks every summon button until the server answers)
		refreshSummonButtons()
		local ok, reply = invoke("OpenOrb", currentOrbWorld, count)
		summonBusy = false
		local list = if ok then cleanResults(reply) else {}
		if #list == 0 then
			refreshSummonButtons()
			toast(if not ok and type(reply) == "string" then reply else "Couldn't summon. Try again!", SUMMON.bad)
			return
		end
		playSummon(list, count)
		refreshSummonButtons()
	end

	-- the buttons react live to coins, backpack space and the multi-open unlock
	for _, a in { "Coins", "InventorySize", "OpenCount", "OrbsOpened" } do
		player:GetAttributeChangedSignal(a):Connect(function() refreshSummonButtons() end)
	end
end

----------------------------------------------------------------------------
-- Worlds panel = the GALAXY MAP (full screen: TELEPORT, the Teleporter and the gates open it)
----------------------------------------------------------------------------
-- Champion City (the hub) and every world in Config.Worlds are planets on one path. Tap a
-- planet to see it in the panel on the right; tap it again (or the big button) to travel
-- there, or to unlock it. The tutorial guide (QuestClient) looks for these names: the panel
-- "Worlds", the planet buttons "Travel<id>" (Travel0 = the hub) and the big button
-- "FastTravel". The selected planet's id is kept in the panel's SelectedWorld attribute, so
-- the guide knows when to stop pointing at the planet and point at FastTravel instead.
-- Everything is built once; while the map is hidden nothing in it animates.
-- (It's built inside a function: Luau allows only 200 locals per script level.)
do
	local GuiService = game:GetService("GuiService")
	local function buildGalaxyMap()
		-- COLOURS (from the design) ---------------------------------------------------
		local G = {
			cyan = Color3.fromRGB(92, 242, 255), violet = Color3.fromRGB(176, 107, 255), lilac = Color3.fromRGB(205, 163, 255),
			pink = Color3.fromRGB(255, 61, 203), gold = Color3.fromRGB(255, 200, 61), green = Color3.fromRGB(140, 255, 176),
			red = Color3.fromRGB(255, 77, 109), text = Color3.fromRGB(238, 241, 255), sub = Color3.fromRGB(168, 176, 214),
			dim = Color3.fromRGB(74, 82, 128), panel = Color3.fromRGB(14, 12, 32), card = Color3.fromRGB(12, 14, 30),
			glass = Color3.fromRGB(16, 19, 38),
		}
		-- the tag under each planet's name
		local TAGS = {
			CURRENT = { bg = G.lilac, text = Color3.fromRGB(26, 5, 51) },
			UNLOCKED = { bg = G.green, text = Color3.fromRGB(6, 48, 26) },
			LOCKED = { bg = Color3.fromRGB(43, 47, 82), text = Color3.fromRGB(203, 209, 240) },
		}
		-- the big button: travel (violet), unlock (gold), off (it can't be used right now)
		local BUTTONS = {
			travel = { top = Color3.fromRGB(209, 107, 255), mid = Color3.fromRGB(155, 61, 255), bottom = Color3.fromRGB(90, 20, 181),
				edge = Color3.fromRGB(240, 210, 255), text = Color3.new(1, 1, 1), glow = G.violet },
			unlock = { top = Color3.fromRGB(255, 226, 122), mid = G.gold, bottom = Color3.fromRGB(201, 138, 18),
				edge = Color3.fromRGB(255, 240, 190), text = Color3.fromRGB(46, 28, 0), glow = G.gold },
			off = { top = Color3.fromRGB(36, 43, 84), mid = Color3.fromRGB(28, 34, 68), bottom = Color3.fromRGB(22, 27, 58),
				edge = Color3.fromRGB(64, 74, 140), text = Color3.fromRGB(150, 156, 196) },
		}
		-- each planet: its colours lit from the top left (highlight, middle, deep, night side),
		-- its glow and its orbit ring
		local PLANETS: { [number]: any } = {
			[0] = { -- Champion City: warm pink + cyan
				colors = { Color3.fromRGB(255, 228, 244), Color3.fromRGB(255, 125, 196), Color3.fromRGB(70, 200, 235), Color3.fromRGB(20, 30, 74) },
				glow = Color3.fromRGB(255, 120, 200), orbit = Color3.fromRGB(255, 175, 225) },
			[1] = { -- Verdant Rift: green + violet crystal
				colors = { Color3.fromRGB(216, 255, 226), Color3.fromRGB(80, 224, 150), Color3.fromRGB(122, 72, 220), Color3.fromRGB(28, 12, 66) },
				glow = Color3.fromRGB(110, 255, 190), orbit = G.green },
			[2] = { -- Coral Harbor: aqua + blue sea
				colors = { Color3.fromRGB(220, 255, 255), Color3.fromRGB(70, 230, 230), Color3.fromRGB(30, 120, 210), Color3.fromRGB(10, 40, 90) },
				glow = Color3.fromRGB(70, 210, 255), orbit = Color3.fromRGB(127, 220, 255) },
			[3] = { -- Skyforge Academy: white + royal blue
				colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 225, 255), Color3.fromRGB(60, 100, 230), Color3.fromRGB(16, 28, 90) },
				glow = Color3.fromRGB(120, 170, 255), orbit = Color3.fromRGB(185, 210, 255) },
		}
		local function accentOf(w: any): Color3
			return if type(w.theme) == "table" and typeof(w.theme.accent) == "Color3" then w.theme.accent else G.cyan
		end
		local function lookOf(w: any): any
			if PLANETS[w.id] then return PLANETS[w.id] end
			-- (a world added later without its own colours gets them from its theme accent)
			local a = accentOf(w)
			return { colors = { a:Lerp(Color3.new(1, 1, 1), 0.7), a, a:Lerp(Color3.new(0, 0, 0), 0.45), a:Lerp(Color3.new(0, 0, 0), 0.85) },
				glow = a, orbit = a:Lerp(Color3.new(1, 1, 1), 0.3) }
		end
		local function planetColors(look: any): ColorSequence
			local c = look.colors
			return ColorSequence.new({ ColorSequenceKeypoint.new(0, c[1]), ColorSequenceKeypoint.new(0.4, c[2]),
				ColorSequenceKeypoint.new(0.72, c[3]), ColorSequenceKeypoint.new(1, c[4]) })
		end
		-- { time, value, time, value, ... } -> a transparency sequence for a UIGradient
		local function fade(points: { number }): NumberSequence
			local keys = {}
			for i = 1, #points, 2 do table.insert(keys, NumberSequenceKeypoint.new(points[i], points[i + 1])) end
			return NumberSequence.new(keys)
		end

		-- SMALL BUILDERS ------------------------------------------------------------
		-- plain text, no outline (the map is dark, like the design). max = the biggest text size.
		local function text(props: { [string]: any }, max: number?): TextLabel
			local base: { [string]: any } = { BackgroundTransparency = 1, Font = THEME.font, TextColor3 = G.text, TextScaled = true }
			for k, v in props do base[k] = v end
			local l = new("TextLabel", base)
			if max then new("UITextSizeConstraint", { MaxTextSize = max, Parent = l }) end
			return l
		end
		-- a small rounded tag ("CURRENT", "LOCKED") exactly as wide as its text
		local function tagPill(props: { [string]: any }): TextLabel
			local base: { [string]: any } = { Text = "", Font = THEME.font, TextSize = 11, BorderSizePixel = 0,
				AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 17) }
			for k, v in props do base[k] = v end
			return new("TextLabel", base, { new("UICorner", { CornerRadius = UDim.new(0, 8) }),
				new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }) })
		end
		-- a circle (a pill when it isn't square), centred on its Position, full size by default
		local function round(props: { [string]: any }): Frame
			local base: { [string]: any } = { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1) }
			for k, v in props do base[k] = v end
			return new("Frame", base, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
		local function edge(parent: Instance, thickness: number, color: Color3, transparency: number): UIStroke
			return new("UIStroke", { Thickness = thickness, Color = color, Transparency = transparency, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
		end
		-- An ellipse made of short straight pieces (a GUI frame can't be an ellipse).
		-- dash < 1 leaves gaps between the pieces; keep(angle) can leave some pieces out.
		local function ellipse(parent: Instance, c: Vector2, rx: number, ry: number, tiltDeg: number, pieces: number,
			thickness: number, color: Color3, transparency: number, dash: number?, keep: ((number) -> boolean)?)
			local tilt = math.rad(tiltDeg)
			local ct, st = math.cos(tilt), math.sin(tilt)
			local function at(angle: number): Vector2
				local x, y = rx * math.cos(angle), ry * math.sin(angle)
				return Vector2.new(c.X + x * ct - y * st, c.Y + x * st + y * ct)
			end
			for i = 0, pieces - 1 do
				local a0, a1 = i / pieces * math.pi * 2, (i + 1) / pieces * math.pi * 2
				if keep and not keep((a0 + a1) / 2) then continue end
				local p0, p1 = at(a0), at(a1)
				local d = p1 - p0
				new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BackgroundTransparency = transparency,
					Position = UDim2.fromOffset((p0.X + p1.X) / 2, (p0.Y + p1.Y) / 2), Size = UDim2.fromOffset(d.Magnitude * (dash or 1) + 0.5, thickness),
					Rotation = math.deg(math.atan2(d.Y, d.X)), Parent = parent })
			end
		end

		-- STATE -------------------------------------------------------------------
		local order = { Config.Hub }          -- the path: the hub first, then the worlds in order
		for _, w in Config.Worlds do table.insert(order, w) end
		local nodes: { [number]: any } = {}  -- one per planet, by world id
		local lanes: { any } = {}
		local twinkles: { any } = {}
		local selected = -1                   -- the planet shown on the right (-1 = choose one)
		local travelling = false              -- a TravelToWorld request is on its way (no double taps)
		local chipsKey = ""                   -- which champion chips are built (world:found)
		-- (filled in further down)
		local layout: (Vector2) -> () = function() end
		local refreshMap: () -> () = function() end
		local animate: (number) -> () = function() end
		local tapPlanet: (number) -> () = function() end
		local pressMain: () -> () = function() end

		local panel, content, fs = makeFullscreen("Worlds", {
			onOpen = function() selected = -1 end, -- (refreshMap then picks the right planet)
			onLayout = function(size: Vector2) layout(size) end,
			onFrame = function(_dt: number, t: number) animate(t) end,
		})

		-- BACKGROUND: soft nebula glows + stars -----------------------------------------
		-- (a soft glow = 5 see-through pills inside each other, so the middle is brightest)
		local function nebula(pos: Vector2, size: Vector2, color: Color3, alpha: number)
			local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(pos.X, pos.Y),
				Size = UDim2.fromScale(size.X, size.Y), Parent = fs.backdrop })
			local each = 1 - (1 - alpha) ^ (1 / 5) -- (5 layers on top of each other reach `alpha`)
			for i = 1, 5 do
				local s = 1 - (i - 1) * 0.18
				local layer = round({ BackgroundColor3 = color, BackgroundTransparency = 1 - each, Size = UDim2.fromScale(s, s), Parent = holder })
				new("UIGradient", { Transparency = fade({ 0, 1, 0.3, 0, 0.7, 0, 1, 1 }), Parent = layer })
			end
		end
		nebula(Vector2.new(0.72, 0.22), Vector2.new(0.62, 0.66), Color3.fromRGB(30, 190, 150), 0.35)
		nebula(Vector2.new(0.4, 0.78), Vector2.new(0.66, 0.8), Color3.fromRGB(120, 40, 200), 0.38)
		nebula(Vector2.new(0.12, 0.18), Vector2.new(0.44, 0.56), Color3.fromRGB(46, 120, 255), 0.25)
		-- 80 small stars, the same pattern every time; every 8th one twinkles while the map is open
		local seed = 11
		local function rnd(): number
			seed = (seed * 9301 + 49297) % 233280
			return seed / 233280
		end
		for i = 1, 80 do
			local x, y = rnd(), rnd()
			local size = if rnd() < 0.12 then 3 else 2
			local base = 0.1 + rnd() * 0.7 -- (how see-through it is)
			local star = round({ BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = base, AnchorPoint = Vector2.zero,
				Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(size, size), Parent = fs.backdrop })
			if i % 8 == 0 then table.insert(twinkles, { star = star, base = base, phase = rnd() * 6.28 }) end
		end

		-- HEADER: back button, GALAXY 1, how many worlds you've unlocked ---------------
		local back = new("TextButton", { Name = "BackButton", Text = "", AutoButtonColor = true, BackgroundColor3 = G.glass, BackgroundTransparency = 0.25,
			Position = UDim2.fromOffset(26, 18), Size = UDim2.fromOffset(124, 42), ZIndex = 5, Parent = content }, { new("UICorner", { CornerRadius = UDim.new(0, 13) }) })
		edge(back, 1, Color3.fromRGB(120, 140, 255), 0.7)
		text({ Text = "‹  BACK", Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 1, -20), Parent = back }, 18)
		feedback(back)
		back.Activated:Connect(function()
			bounce(back)
			showPanel(nil)
		end)
		-- (one galaxy for now, so no previous / next arrows)
		new("Frame", { BorderSizePixel = 0, BackgroundColor3 = G.cyan, BackgroundTransparency = 0.9, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 9), Size = UDim2.fromOffset(272, 60), ZIndex = 4, Parent = content }, { new("UICorner", { CornerRadius = UDim.new(0, 20) }) })
		local title = new("Frame", { Name = "Title", BackgroundColor3 = Color3.fromRGB(8, 10, 22), BackgroundTransparency = 0.1, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(256, 46), ZIndex = 5, Parent = content }, { new("UICorner", { CornerRadius = UDim.new(0, 13) }) })
		edge(title, 2, G.text, 0.45)
		text({ Text = "GALAXY 1", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16), Parent = title }, 26)
		local countLabel = text({ TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = G.sub, AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -26, 0, 39), Size = UDim2.fromOffset(230, 18), ZIndex = 5, Parent = content }, 14)

		-- THE PATH: planets joined by lanes, in an 820 x 560 box that scales to fit ---------
		local PATH = Vector2.new(820, 560) -- (the design's planet area, in design pixels)
		local PLANET = 136                 -- planet size
		local SPOTS = { Vector2.new(108, 392), Vector2.new(316, 144), Vector2.new(556, 360), Vector2.new(708, 112) }
		local function spotOf(i: number): Vector2
			-- (a 5th world would need its own spot in SPOTS: until then it goes after the last one)
			return SPOTS[i] or SPOTS[#SPOTS] + Vector2.new((i - #SPOTS) * 150, if (i - #SPOTS) % 2 == 1 then 250 else 0)
		end
		local mapArea = new("Frame", { Name = "Map", BackgroundTransparency = 1, ZIndex = 1, Parent = content })
		local path = new("Frame", { Name = "Path", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(PATH.X, PATH.Y), Parent = mapArea })
		local pathScale = new("UIScale", { Parent = path })
		-- two faint orbits behind the planets
		ellipse(path, Vector2.new(372, 280), 424, 280, -12, 96, 1.2, G.cyan, 0.8)
		ellipse(path, Vector2.new(372, 280), 360, 216, -12, 64, 1.2, G.violet, 0.72, 0.55)
		-- the lanes between planets, with chevrons that scroll toward the next one
		for i = 1, #order - 1 do
			local a, b = spotOf(i), spotOf(i + 1)
			local dir = (b - a).Unit
			local from, to = a + dir * 76, b - dir * 76
			local len = (to - from).Magnitude
			local mid = (from + to) / 2 - Vector2.new(0, 6)
			local frame = new("Frame", { Name = "Lane", BorderSizePixel = 0, BackgroundColor3 = G.text, BackgroundTransparency = 0.92, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(mid.X, mid.Y), Size = UDim2.fromOffset(len, 13), Rotation = math.deg(math.atan2(dir.Y, dir.X)), ZIndex = 2,
				Parent = path }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			local lane = { to = order[i + 1].id, len = len, base = 0.25, edge = edge(frame, 1, G.text, 0.55), chevrons = {} }
			for k = 1, math.floor(len / 26) + 1 do
				lane.chevrons[k] = text({ Text = ">", TextScaled = false, TextSize = 13, AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset((k - 1) * 26 + 13, 6.5), Size = UDim2.fromOffset(12, 13), TextTransparency = 0.25, Parent = frame })
			end
			table.insert(lanes, lane)
		end
		-- the planets
		for i, w in order do
			local spot = spotOf(i)
			local look = lookOf(w)
			local n: { [string]: any } = { spot = spot, look = look, phase = i * 1.7, aura = {} }
			nodes[w.id] = n
			-- everything in `holder` bobs gently together
			local holder = new("Frame", { Name = "Planet" .. w.id, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(spot.X, spot.Y), Size = UDim2.fromOffset(PLANET, PLANET), ZIndex = 3, Parent = path })
			n.holder = holder
			-- its glow (violet and breathing on the planet you're on, pink when it's locked)
			local aura = new("Frame", { Name = "Aura", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = holder })
			n.auraScale = new("UIScale", { Parent = aura })
			for k, size in { 1.62, 1.38, 1.18 } do
				n.aura[k] = round({ BackgroundColor3 = look.glow, BackgroundTransparency = 0.9, Size = UDim2.fromScale(size, size), Parent = aura })
			end
			-- its orbit ring in two halves: the far half behind the planet, the near half in front
			local function ringHalf(z: number, near: boolean): Frame
				local f = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = holder })
				ellipse(f, Vector2.new(PLANET / 2, PLANET / 2 + 2), 89, 14, -14, 40, 2, look.orbit, 0.45, nil, function(angle: number)
					return (math.sin(angle) >= 0) == near
				end)
				return f
			end
			n.ringBack = ringHalf(2, false)
			-- the planet: its colours, a faint band sliding across (so it seems to turn), its
			-- night side and a shine
			local body = round({ Name = "Body", BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Parent = holder })
			new("UIGradient", { Rotation = 45, Color = planetColors(look), Parent = body })
			local surface = round({ Name = "Surface", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2, ZIndex = 4, Parent = holder })
			n.surface = new("UIGradient", { Rotation = 75, Parent = surface,
				Transparency = fade({ 0, 1, 0.18, 1, 0.26, 0.8, 0.34, 1, 0.52, 1, 0.6, 0.84, 0.7, 1, 1, 1 }) })
			local shade = round({ Name = "Shade", BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5, Parent = holder })
			new("UIGradient", { Rotation = 45, Transparency = fade({ 0, 1, 0.5, 1, 1, 0.35 }), Parent = shade })
			round({ Name = "Shine", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.62, Position = UDim2.fromScale(0.34, 0.27),
				Size = UDim2.fromScale(0.22, 0.13), Rotation = -35, ZIndex = 6, Parent = holder })
			n.dim = round({ Name = "Dim", BackgroundColor3 = Color3.fromRGB(8, 10, 24), BackgroundTransparency = 0.45, Visible = false, ZIndex = 7, Parent = holder })
			n.ringFront = ringHalf(8, true)
			n.currentRing = round({ Name = "CurrentRing", BackgroundTransparency = 1, Size = UDim2.new(1, 8, 1, 8), Visible = false, ZIndex = 9, Parent = holder })
			edge(n.currentRing, 4, G.lilac, 0.15)
			n.selRing = round({ Name = "SelectedRing", BackgroundTransparency = 1, Size = UDim2.new(1, 26, 1, 26), Visible = false, ZIndex = 9, Parent = holder })
			n.selEdge = edge(n.selRing, 2.5, G.cyan, 0.2)
			n.lock = new("Frame", { Name = "Lock", BackgroundColor3 = Color3.fromRGB(8, 10, 22), BackgroundTransparency = 0.2, AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 50), Visible = false, ZIndex = 10, Parent = holder },
				{ new("UICorner", { CornerRadius = UDim.new(0, 13) }) })
			edge(n.lock, 2, G.pink, 0)
			text({ Text = "🔒", Position = UDim2.fromScale(0.15, 0.15), Size = UDim2.fromScale(0.7, 0.7), Parent = n.lock }, 26)
			-- the planet's button (round, so the tutorial's highlight is round too)
			local hit = new("TextButton", { Name = "Travel" .. w.id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1), ZIndex = 11, Parent = holder }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			hit.MouseEnter:Connect(function()
				if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
				hoveredButtons[holder] = true
				TweenService:Create(clickScaleOf(holder), TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.05 }):Play()
			end)
			hit.MouseLeave:Connect(function()
				hoveredButtons[holder] = nil
				TweenService:Create(clickScaleOf(holder), TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			end)
			hit.Activated:Connect(function()
				bounce(holder)
				playUiSound("click")
				tapPlanet(w.id)
			end)
			-- its name card
			local card = new("TextButton", { Name = "Card", Text = "", AutoButtonColor = false, BackgroundColor3 = G.card, BackgroundTransparency = 0.18,
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(spot.X, spot.Y + PLANET / 2 + 16), Size = UDim2.fromOffset(170, 72),
				ZIndex = 3, Parent = path }, { new("UICorner", { CornerRadius = UDim.new(0, 13) }) })
			n.cardEdge = edge(card, 1, Color3.new(1, 1, 1), 0.88)
			n.name = text({ Text = string.upper(w.name), Position = UDim2.fromOffset(8, 7), Size = UDim2.new(1, -16, 0, 20), Parent = card }, 17)
			n.tag = tagPill({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Parent = card })
			n.sub = text({ Text = "", TextColor3 = G.sub, Position = UDim2.fromOffset(8, 51), Size = UDim2.new(1, -16, 0, 15), Parent = card }, 13)
			-- (the words sit in `inner`, which has its own UIScale: on small screens layout draws the
			-- card bigger than the planets so its words stay readable; the card's own UIScale is
			-- the hover/press one)
			n.card = card
			n.cardInner = new("Frame", { Name = "Inner", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = card })
			n.cardFit = new("UIScale", { Parent = n.cardInner })
			for _, word in { n.name, n.tag, n.sub } do word.Parent = n.cardInner end
			feedback(card)
			card.Activated:Connect(function()
				bounce(card)
				tapPlanet(w.id)
			end)
		end

		-- DETAIL PANEL (right): the selected planet -----------------------------------
		local DETAIL_W, PAD = 320, 18
		local detailGlow = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(120, 40, 200), BackgroundTransparency = 0.86,
			AnchorPoint = Vector2.new(1, 0), ZIndex = 3, Parent = content }, { new("UICorner", { CornerRadius = UDim.new(0, 28) }) })
		local detail = new("Frame", { Name = "Detail", BackgroundColor3 = G.panel, BackgroundTransparency = 0.18, AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(DETAIL_W, 600), ZIndex = 4, Parent = content }, { new("UICorner", { CornerRadius = UDim.new(0, 21) }) })
		edge(detail, 1, G.violet, 0.55)
		local function row(height: number): Frame
			return new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -PAD * 2, 0, height), Parent = detail })
		end
		-- planet icon, tag, name and "World n"
		local head = row(62)
		local icon = round({ BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(60, 60), Parent = head })
		local iconColors = new("UIGradient", { Rotation = 45, Parent = icon })
		local iconEdge = edge(icon, 2, G.violet, 0.35)
		new("UIGradient", { Rotation = 45, Transparency = fade({ 0, 1, 0.5, 1, 1, 0.35 }), Parent = round({ BackgroundColor3 = Color3.new(0, 0, 0), Parent = icon }) })
		local dTag = tagPill({ Position = UDim2.fromOffset(72, 1), Parent = head })
		local dName = text({ Position = UDim2.fromOffset(72, 20), Size = UDim2.new(1, -72, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, Parent = head }, 26)
		local dWorld = text({ Position = UDim2.fromOffset(72, 47), Size = UDim2.new(1, -72, 0, 15), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = G.sub, Parent = head }, 13)
		-- a line about the world (only when there's room for it)
		local blurb = text({ TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = G.sub,
			Size = UDim2.new(1, -PAD * 2, 0, 34), Parent = detail }, 13)
		-- two stat tiles
		local tiles = row(58)
		local function tile(right: boolean, caption: string, valueColor: Color3): (TextLabel, TextLabel)
			local f = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, Position = UDim2.new(if right then 0.5 else 0, if right then 5 else 0, 0, 0),
				Size = UDim2.new(0.5, -5, 1, 0), Parent = tiles }, { new("UICorner", { CornerRadius = UDim.new(0, 13) }) })
			edge(f, 1, Color3.new(1, 1, 1), 0.92)
			text({ Text = caption, Position = UDim2.fromOffset(11, 6), Size = UDim2.new(1, -22, 0, 12), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = G.sub, Parent = f }, 11)
			local value = text({ Position = UDim2.fromOffset(11, 19), Size = UDim2.new(1, -22, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = valueColor, Parent = f }, 22)
			local small = text({ Position = UDim2.fromOffset(11, 41), Size = UDim2.new(1, -22, 0, 12), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = G.sub, Parent = f }, 11)
			return value, small
		end
		local powerValue, powerSmall = tile(false, "YOUR POWER", G.green)
		powerSmall.Text = "your team's DPS"
		local orbValue, orbSmall = tile(true, "ORB", G.gold)
		-- this world's champions: one chip each, in its rarity colour
		local champs = row(80)
		text({ Text = "CHAMPIONS", Size = UDim2.new(0.6, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, Parent = champs }, 15)
		local champCount = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = G.sub, Parent = champs }, 12)
		local chipRow = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 23), Size = UDim2.new(1, 0, 0, 38), Parent = champs }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local champLine = text({ Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = G.sub, Parent = champs }, 12)
		-- the boss (the hub has none: a few words about it instead)
		local bossBox = row(74)
		local bossTitle = text({ Text = "BOSS", Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, Parent = bossBox }, 15)
		local bossPanel = new("Frame", { BackgroundColor3 = G.red, BackgroundTransparency = 0.9, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 50),
			Parent = bossBox }, { new("UICorner", { CornerRadius = UDim.new(0, 13) }) })
		edge(bossPanel, 1, G.red, 0.55)
		local bossName = text({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -100, 0, 19), TextXAlignment = Enum.TextXAlignment.Left, Parent = bossPanel }, 17)
		local bossSub = text({ Position = UDim2.fromOffset(12, 29), Size = UDim2.new(1, -100, 0, 13), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(255, 179, 193), Parent = bossPanel }, 12)
		local bossBeaten = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 5), Size = UDim2.fromOffset(80, 25),
			TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 143, 163), Parent = bossPanel }, 22)
		text({ Text = "BEATEN", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 31), Size = UDim2.fromOffset(80, 11),
			TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 179, 193), Parent = bossPanel }, 10)
		local about = text({ TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = G.sub,
			Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 50), Visible = false, Parent = bossBox }, 13)
		-- how many of this world's champions you've found (the same count as the Index)
		local disc = row(28)
		text({ Text = "Champions discovered", Size = UDim2.new(0.75, 0, 0, 15), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(203, 209, 240), Parent = disc }, 13)
		local discCount = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.25, 0, 0, 15),
			TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = G.lilac, Parent = disc }, 13)
		local discBar = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.92, Position = UDim2.fromOffset(0, 21),
			Size = UDim2.new(1, 0, 0, 7), Parent = disc }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local discFill = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0, 1), Parent = discBar }, {
			new("UICorner", { CornerRadius = UDim.new(1, 0) }), new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(155, 61, 255), G.pink) }),
		})
		-- the big button (named FastTravel: the tutorial guide points at it)
		local mainGlow = new("Frame", { BorderSizePixel = 0, BackgroundColor3 = G.violet, BackgroundTransparency = 0.78, AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -PAD + 5), Size = UDim2.new(1, -PAD * 2 + 10, 0, 68), ZIndex = 1, Parent = detail },
			{ new("UICorner", { CornerRadius = UDim.new(0, 20) }) })
		local main = new("TextButton", { Name = "FastTravel", Text = "", AutoButtonColor = true, BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -PAD), Size = UDim2.new(1, -PAD * 2, 0, 58), ZIndex = 2, Parent = detail }, { new("UICorner", { CornerRadius = UDim.new(0, 16) }) })
		local mainColors = new("UIGradient", { Rotation = 90, Parent = main })
		local mainEdge = edge(main, 2, Color3.new(1, 1, 1), 0)
		local mainText = text({ Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -28), Parent = main }, 22)
		feedback(main)
		main.Activated:Connect(function()
			bounce(main)
			pressMain()
		end)

		-- LEGEND (bottom left) ----------------------------------------------------------
		local legend = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 26, 1, -20), Size = UDim2.fromOffset(330, 18),
			ZIndex = 2, Parent = content }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, item in { { "Unlocked", G.green }, { "Current", G.lilac }, { "Locked", G.dim } } do
			local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(92, 18), LayoutOrder = i, Parent = legend })
			local dot = round({ BackgroundColor3 = item[2], AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(11, 11), Parent = f })
			if i == 2 then edge(dot, 2, G.violet, 0.45) end
			text({ Text = item[1], Position = UDim2.fromOffset(18, 1), Size = UDim2.new(1, -18, 1, -2), TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = G.sub, Parent = f }, 13)
		end

		-- WHAT EACH WORLD SHOWS ------------------------------------------------------------
		-- Your progress, read from the attributes the server publishes.
		local function readProgress(): any
			return {
				unlocked = string.split(player:GetAttribute("Unlocked") or "W1", ","),
				current = player:GetAttribute("World") or 0,
				-- "W1=3,W2=0": how often you helped beat each world's boss (the next world needs 1)
				bossKills = parsePairs(player:GetAttribute("BossKills")),
				bossKillsKnown = player:GetAttribute("BossKills") ~= nil,
			}
		end
		local function isUnlocked(p: any, w: any): boolean
			return w.id == 0 or table.find(p.unlocked, w.key) ~= nil
		end
		-- One world's tag, the line under its name, its big button and (for a button you can't
		-- use yet) the toast that explains why. Same rules as the server (WorldService): a world
		-- unlocks once the one before it is unlocked and its boss was beaten, and you pay for it.
		local function stateOf(p: any, w: any): any
			local s: { [string]: any } = { current = w.id == p.current, unlocked = isUnlocked(p, w) }
			s.locked = not s.unlocked
			local prev = if w.id > 1 then Config.Worlds[w.id - 1] else nil
			local prevUnlocked = w.id <= 1 or (prev ~= nil and isUnlocked(p, prev))
			local needKey = (w :: any).requiresBoss
			local bossWorld = if type(needKey) == "string" and type(CFG.WorldByKey) == "function" then CFG.WorldByKey(needKey) else nil
			local bossDef = bossWorld and bossWorld.boss and CFG.Enemies and CFG.Enemies[bossWorld.boss]
			local bossName = if bossDef then tostring(bossDef.name) else "the boss"
			local needBoss = p.bossKillsKnown and type(needKey) == "string" and (p.bossKills[needKey] or 0) < 1
			local cost = tonumber(w.unlockCost) or 0
			if s.current then
				s.tag, s.sub, s.subColor = "CURRENT", "You are here", G.lilac
				s.button, s.style, s.enabled = "YOU'RE HERE", "off", false
			elseif s.unlocked then
				local kills = p.bossKills[w.key] or 0
				s.tag, s.subColor = "UNLOCKED", G.sub
				s.sub = if w.id == 0 then "Training & stations" elseif kills > 0 then "Boss beaten ×" .. kills else "Boss not beaten yet"
				s.button, s.style, s.enabled = "FAST TRAVEL  ▶", "travel", true
			elseif prevUnlocked and needBoss then
				s.tag, s.sub, s.subColor = "LOCKED", "Beat " .. bossName, Color3.fromRGB(255, 150, 210)
				s.button, s.style, s.enabled = "BEAT " .. string.upper(bossName) .. " FIRST", "off", false
				s.lockedMsg = "Defeat " .. bossName .. " in " .. (if bossWorld then bossWorld.name else "the last world")
					.. " first! (then it costs $" .. Format.Short(cost) .. ")"
			elseif prevUnlocked then
				s.tag, s.sub, s.subColor = "LOCKED", if cost > 0 then "Unlock for $" .. Format.Short(cost) else "Free to unlock", G.gold
				s.button, s.style, s.enabled = if cost > 0 then "UNLOCK  $" .. Format.Short(cost) else "UNLOCK", "unlock", true
			else
				local prevName = if prev then tostring(prev.name) else "the world before"
				s.tag, s.sub, s.subColor = "LOCKED", "Unlock " .. prevName .. " first", G.sub
				s.button, s.style, s.enabled = "LOCKED", "off", false
				s.lockedMsg = "Unlock " .. prevName .. " first!"
			end
			return s
		end
		-- Which planet is selected when the map opens.
		local function defaultSelection(p: any): number
			-- 1. a travel / unlock quest is active (the tutorial's last step is one): its world
			local q = Quests.Get(player:GetAttribute("QuestIndex") or 1)
			local qs = player:GetAttribute("QuestState") or "offer"
			if q and qs ~= "offer" and qs ~= "ready" and qs ~= "finished" and (q.kind == "travel" or q.kind == "unlock") then
				local id = if q.kind == "travel" then tonumber(q.key) else tonumber(string.sub(tostring(q.key), 2))
				if id and nodes[id] and id ~= p.current then return id end
			end
			-- 2. in the hub: the next world you haven't unlocked (the last one once you have them all)
			if p.current == 0 then
				for _, w in Config.Worlds do
					if not isUnlocked(p, w) then return w.id end
				end
				local last = Config.Worlds[#Config.Worlds]
				return if last then last.id else 0
			end
			-- 3. anywhere else: the world you're in
			return if nodes[p.current] then p.current else 0
		end
		-- the champion chips (lowest rarity first, like the summon odds)
		local rarityPlace = {}
		for i, r in Config.Rarities do rarityPlace[r.id] = i end
		local function buildChips(w: any)
			for _, c in chipRow:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
			local list = {}
			for _, c in Config.Champions do
				if c.world == w.id and Config.RarityById[c.rarity] then table.insert(list, c) end
			end
			table.sort(list, function(a, b)
				if rarityPlace[a.rarity] ~= rarityPlace[b.rarity] then return rarityPlace[a.rarity] < rarityPlace[b.rarity] end
				return a.name < b.name
			end)
			champCount.Text = #list .. (if w.id == 0 then " starters" else " in this world")
			champLine.Text = if #list > 0 then "Tap a champion to see who it is" else "No champions here yet"
			champLine.TextColor3 = G.sub
			for i, c in list do
				local color = Config.RarityById[c.rarity].color
				local chip = new("TextButton", { Name = "Chip", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(25, 22, 53),
					ClipsDescendants = true, Size = UDim2.fromOffset(38, 38), LayoutOrder = i, Parent = chipRow }, { new("UICorner", { CornerRadius = UDim.new(0, 11) }) })
				edge(chip, 2, color, 0)
				-- a little head-and-shoulders figure in the rarity colour (like the design)
				new("Frame", { BorderSizePixel = 0, BackgroundColor3 = color, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
					Size = UDim2.fromOffset(15, 15), Parent = chip }, { new("UICorner", { CornerRadius = UDim.new(0, 5) }) })
				new("Frame", { BorderSizePixel = 0, BackgroundColor3 = color, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26),
					Size = UDim2.fromOffset(26, 16), Parent = chip }, { new("UICorner", { CornerRadius = UDim.new(0, 7) }) })
				-- hover or tap: its name (??? until you've found it, like the Index) and rarity
				local function show()
					champLine.Text = (if discovered[c.id] == true then c.name else "???") .. "  ·  " .. c.rarity
					champLine.TextColor3 = color
				end
				chip.MouseEnter:Connect(show)
				chip.Activated:Connect(function()
					playUiSound("click")
					show()
				end)
			end
		end
		local function paintMain(s: any)
			local style = BUTTONS[s.style] or BUTTONS.off
			mainColors.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, style.top), ColorSequenceKeypoint.new(0.5, style.mid),
				ColorSequenceKeypoint.new(1, style.bottom) })
			mainEdge.Color = style.edge
			mainText.Text = s.button
			mainText.TextColor3 = style.text
			main.AutoButtonColor = s.enabled
			mainGlow.Visible = style.glow ~= nil
			if style.glow then mainGlow.BackgroundColor3 = style.glow end
		end
		-- Stacks the detail rows from the top. On short screens (or under the tutorial card)
		-- the world's description goes first, then the discovered bar, and the gaps shrink.
		local ROWS = { { head, 62 }, { blurb, 34 }, { tiles, 58 }, { champs, 80 }, { bossBox, 74 }, { disc, 28 } }
		local function placeRows()
			local room = detail.Size.Y.Offset - PAD * 2 - 58 -- (minus the padding and the big button)
			local hide: { [Instance]: boolean } = {}
			local function used(): (number, number)
				local total, count = 0, 0
				for _, r in ROWS do
					if not hide[r[1]] then total += r[2]; count += 1 end
				end
				return total, count
			end
			if selected == 0 then hide[blurb] = true end -- (the hub's description is under ABOUT)
			for _, extra in { blurb, disc } do
				local total, count = used()
				if total + count * 10 > room then hide[extra] = true end
			end
			local total, count = used()
			local gap = math.clamp((room - total) / count, 6, 14)
			local y = PAD
			for _, r in ROWS do
				r[1].Visible = not hide[r[1]]
				if not hide[r[1]] then
					r[1].Position = UDim2.fromOffset(PAD, y)
					y += r[2] + gap
				end
			end
		end

		-- REFRESH (on open, and when your stats change while it's open) ------------------
		refreshMap = function()
			local p = readProgress()
			if not nodes[selected] then selected = defaultSelection(p) end
			panel:SetAttribute("SelectedWorld", selected)
			local unlockedCount = 0
			for _, w in order do
				local n = nodes[w.id]
				local s = stateOf(p, w)
				n.state = s
				if s.unlocked then unlockedCount += 1 end
				local tag = TAGS[s.tag]
				n.tag.Text = s.tag
				n.tag.BackgroundColor3 = tag.bg
				n.tag.TextColor3 = tag.text
				n.sub.Text = s.sub
				n.sub.TextColor3 = s.subColor
				n.name.TextColor3 = if s.current then Color3.fromRGB(231, 198, 255) elseif s.locked then G.sub else G.text
				local isSelected = w.id == selected
				n.cardEdge.Color = if isSelected then G.cyan elseif s.current then G.lilac elseif s.locked then G.pink else Color3.new(1, 1, 1)
				n.cardEdge.Transparency = if isSelected then 0.1 elseif s.current then 0.2 elseif s.locked then 0.45 else 0.88
				n.cardEdge.Thickness = if isSelected then 2 else 1
				n.dim.Visible = s.locked
				n.lock.Visible = s.locked
				n.currentRing.Visible = s.current
				n.selRing.Visible = isSelected
				local glow = if s.current then G.violet elseif s.locked then G.pink else n.look.glow
				local alphas = if s.current then { 0.86, 0.78, 0.66 } elseif s.locked then { 0.96, 0.94, 0.9 } else { 0.93, 0.89, 0.83 }
				for k, layer in n.aura do
					layer.BackgroundColor3 = glow
					layer.BackgroundTransparency = alphas[k]
				end
			end
			-- lanes into a locked planet are pink
			for _, lane in lanes do
				local locked = nodes[lane.to].state.locked
				lane.edge.Color = if locked then G.pink else G.text
				lane.edge.Transparency = if locked then 0.65 else 0.55
				lane.base = if locked then 0.55 else 0.25
				for _, c in lane.chevrons do c.TextColor3 = if locked then G.pink else G.text end
			end
			countLabel.Text = unlockedCount .. " of " .. #order .. " worlds unlocked"
			-- the detail panel
			local w = Config.WorldById(selected)
			local n = nodes[selected]
			local s = n.state
			iconColors.Color = planetColors(n.look)
			iconEdge.Color = n.look.glow
			local tag = TAGS[s.tag]
			dTag.Text = s.tag
			dTag.BackgroundColor3 = tag.bg
			dTag.TextColor3 = tag.text
			dName.Text = string.upper(w.name)
			dWorld.Text = if w.id == 0 then w.name .. "  ·  Hub" else "World " .. w.id
			dWorld.TextColor3 = accentOf(w)
			blurb.Text = tostring(w.blurb or "")
			powerValue.Text = Format.Short(attrNumber("TeamPower", 0))
			local orb = (w :: any).orb
			orbValue.Text = if orb then tostring(orb.name) else "-"
			orbSmall.Text = if orb then "$" .. Format.Short(orb.cost) .. " per summon" else ""
			-- champions (the chips are rebuilt only when the world or what you've found changes)
			local found, total = 0, 0
			for _, c in Config.Champions do
				if c.world == w.id then
					total += 1
					if discovered[c.id] == true then found += 1 end
				end
			end
			if chipsKey ~= w.id .. ":" .. found then
				chipsKey = w.id .. ":" .. found
				buildChips(w)
			end
			discCount.Text = found .. "/" .. total
			discFill.Size = UDim2.fromScale(if total > 0 then found / total else 0, 1)
			-- the boss (the hub has none: its description instead)
			local bossDef = (w :: any).boss and CFG.Enemies and CFG.Enemies[(w :: any).boss]
			bossTitle.Text = if bossDef then "BOSS" else "ABOUT"
			bossPanel.Visible = bossDef ~= nil
			about.Visible = bossDef == nil
			if bossDef then
				bossName.Text = tostring(bossDef.name)
				bossSub.Text = if bossDef.respawn then "Respawns every " .. bossDef.respawn .. " s" else "World boss"
				bossBeaten.Text = "×" .. (p.bossKills[w.key] or 0)
			else
				about.Text = tostring(w.blurb or "")
			end
			paintMain(s)
			if travelling then mainText.Text = "TRAVELLING..." end
			placeRows()
		end
		refreshers.Worlds = function() refreshMap() end

		-- TAPS -----------------------------------------------------------------------
		-- the big button: travel (or unlock and travel) with the same call and messages as before
		pressMain = function()
			local w = Config.WorldById(selected)
			if not w or travelling then return end
			local s = stateOf(readProgress(), w)
			if not s.enabled then
				if s.lockedMsg then toast(s.lockedMsg, THEME.orange) end
				return
			end
			travelling = true
			mainText.Text = "TRAVELLING..."
			local called, ok, msg = pcall(function() return Remotes.TravelToWorld:InvokeServer(w.id) end)
			travelling = false
			if called and ok then
				showPanel(nil)
				-- (TravelFx shows a big world name card; the toast is only a fallback without it)
				if not script.Parent:FindFirstChild("TravelFx") then toast("Welcome to " .. w.name .. "!", accentOf(w)) end
			else
				toast(if called and msg then tostring(msg) else "Can't travel.", THEME.red)
			end
			refreshMap()
		end
		-- a planet: the first tap selects it, tapping the selected one = the big button
		tapPlanet = function(id: number)
			if not nodes[id] then return end
			if id == selected then
				pressMain()
			else
				selected = id
				refreshMap()
			end
		end

		-- PHONES: the map is laid out for a big screen, so on a small one (the HUD's canvas scale
		-- under 0.78) everything in it is drawn bigger, as if the screen were PHONE_LOOK of the
		-- 1280 x 720 design, and laid out in fewer, bigger units. Without this its words came out
		-- at 5-8 px on a phone.
		local PHONE_LOOK = 0.88
		local phoneFit = new("Frame", { Name = "PhoneFit", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
		for _, c in content:GetChildren() do
			if c:IsA("GuiObject") then c.Parent = phoneFit end
		end
		phoneFit.Parent = content
		local phoneScale = new("UIScale", { Parent = phoneFit })

		-- LAYOUT (on open and when the screen changes) -----------------------------------
		layout = function(canvasSize: Vector2)
			local k = if uiScale.Scale < 0.78 then PHONE_LOOK / math.max(uiScale.Scale, 0.01) else 1
			phoneScale.Scale = k
			phoneFit.Size = UDim2.fromScale(1 / k, 1 / k) -- (scaled by k it fills the screen exactly)
			local size = canvasSize / k -- (the screen in phoneFit's units)
			-- the back button sits below Roblox's own buttons in the top left corner
			local topBar = GuiService:GetGuiInset().Y / math.max(uiScale.Scale * k, 0.01)
			back.Position = UDim2.fromOffset(26, math.max(18, topBar + 8))
			-- the detail panel: top right, lower while the tutorial card (QuestClient) is up there
			-- (214 is in the HUD canvas's units; / k turns it into phoneFit's)
			local top = if player:GetAttribute("TutorialTracker") == true then 214 / k else 90
			-- (at most 540 tall: on tall screens a longer panel would only add an empty gap above the button)
			local height = math.clamp(size.Y - top - 22, 300, 540)
			detail.Position = UDim2.new(1, -20, 0, top)
			detail.Size = UDim2.fromOffset(DETAIL_W, height)
			detailGlow.Position = UDim2.new(1, -12, 0, top - 8)
			detailGlow.Size = UDim2.fromOffset(DETAIL_W + 16, height + 16)
			-- the planets get the space left of the panel, scaled to fit it
			local areaW, areaH = size.X - DETAIL_W - 36, size.Y - 80 - 40
			mapArea.Position = UDim2.fromOffset(0, 80)
			mapArea.Size = UDim2.fromOffset(areaW, areaH)
			pathScale.Scale = math.clamp(math.min(areaW / PATH.X, areaH / PATH.Y), 0.4, 1.12)
			-- the planets shrink to fit, but their name cards stay at least 0.9 of their design size
			local cardScale = math.clamp(0.9 / pathScale.Scale, 1, 1.55)
			-- phones: the card shows the name and tag only (the line under them is also in the panel),
			-- so the bigger cards stay clear of the planet below them
			local cardH = if k > 1 then 50 else 72
			-- the part of the path you can see (the path is centred in the map area), in path units
			local halfW = areaW / pathScale.Scale / 2
			local minX, maxX = PATH.X / 2 - halfW, PATH.X / 2 + halfW
			for _, n in nodes do
				local cardW = math.floor(170 * cardScale + 0.5)
				-- (kept inside the visible map: never off the screen's edge or under the panel)
				local lo = minX + cardW / 2 + 4
				local x = math.clamp(n.spot.X, lo, math.max(lo, maxX - cardW / 2 - 4))
				n.card.Position = UDim2.fromOffset(x, n.spot.Y + PLANET / 2 + 16)
				n.card.Size = UDim2.fromOffset(cardW, math.floor(cardH * cardScale + 0.5))
				n.sub.Visible = k <= 1
				n.cardInner.Size = UDim2.fromScale(1 / cardScale, 1 / cardScale)
				n.cardFit.Scale = cardScale
				-- the tag is the smallest text on the map: it grows (up to 14) to stay about 9.5 real px
				local tagScale = uiScale.Scale * k * pathScale.Scale * cardScale
				n.tag.TextSize = math.clamp(math.ceil(9.5 / math.max(tagScale, 0.01)), 11, 14)
			end
			placeRows()
		end
		player:GetAttributeChangedSignal("TutorialTracker"):Connect(function()
			if fs.isOpen() then layout(fs.canvasSize()) end
		end)

		-- ANIMATION (only while the map is on screen: see makeFullscreen) ----------------
		animate = function(t: number)
			for _, n in nodes do
				-- planets bob, their surface band slides, their rings rock a little
				-- (placed by Scale, not Offset: offsets are whole pixels, so a 4 px bob would jitter)
				n.holder.Position = UDim2.fromScale(n.spot.X / PATH.X, (n.spot.Y + math.sin(t * 1.1 + n.phase) * 4) / PATH.Y)
				n.surface.Offset = Vector2.new(((t * 0.035 + n.phase) % 1.6) - 0.8, 0)
				local tilt = math.sin(t * 0.45 + n.phase) * 3
				n.ringBack.Rotation = tilt
				n.ringFront.Rotation = tilt
				-- the planet you're on breathes; the selected one's ring pulses
				n.auraScale.Scale = if n.state and n.state.current then 1 + 0.07 * math.sin(t * 2.2) else 1
				if n.selRing.Visible then n.selEdge.Transparency = 0.15 + 0.3 * (0.5 + 0.5 * math.sin(t * 4)) end
			end
			-- chevrons scroll along the lanes and fade in / out at the ends
			local offset = (t * 22) % 26
			for _, lane in lanes do
				for k, c in lane.chevrons do
					local x = (k - 1) * 26 + offset
					local ends = math.clamp(math.min(x, lane.len - x) / 16, 0, 1)
					c.Position = UDim2.fromOffset(x, 6.5)
					c.TextTransparency = 1 - ends * (1 - lane.base)
				end
			end
			for _, s in twinkles do
				s.star.BackgroundTransparency = s.base + (1 - s.base) * 0.8 * (0.5 + 0.5 * math.sin(t * 2.3 + s.phase))
			end
		end
	end
	buildGalaxyMap()
end

----------------------------------------------------------------------------
-- Upgrades panel
----------------------------------------------------------------------------
do
	local ACCENT = Color3.fromRGB(90, 210, 120)
	local _, body = makePanel("Upgrades", "Upgrades", ACCENT, Vector2.new(760, 560))
	local scroll = new("ScrollingFrame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, {
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- GEM SHOP: rows are built once and only their text changes (so BUY can bounce)
	local shopHeader = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 30), LayoutOrder = 0, Parent = scroll })
	label({ Text = "Gem Shop", Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.gem, Parent = shopHeader })
	local gemsHave = label({ Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = THEME.gem, Parent = shopHeader })
	local SHOP_ORDER = if type(CFG.ShopOrder) == "table" then CFG.ShopOrder else { "Equip", "Inventory", "Range", "Dash", "Jump" }
	local function plural(n: number, one: string, many: string) return tostring(n) .. " " .. (if n == 1 then one else many) end
	-- how each upgrade shows its value, and which attribute holds the current value
	local SHOP_LOOK = {
		Equip = { icon = "👥", attr = "EquipSlots", base = 3, fmt = function(v) return plural(v, "slot", "slots") end },
		Inventory = { icon = "🎒", attr = "InventorySize", base = CFG.InventoryBase or 200, fmt = function(v) return plural(v, "space", "spaces") end },
		Range = { icon = "🎯", attr = "AttackRange", base = 40, fmt = function(v) return plural(v, "stud", "studs") end },
		Dash = { icon = "💨", attr = "DashCharges", base = 1, fmt = function(v) return plural(v, "dash", "dashes") end },
		Jump = { icon = "🐇", attr = "JumpCount", base = 2, fmt = function(v)
			return if v == 2 then "Double jump" elseif v == 3 then "Triple jump" else plural(v, "jump", "jumps") end },
	}
	local function shopLevels(kind: string): { any }
		local shop = CFG.Shop
		return if type(shop) == "table" and type(shop[kind]) == "table" then shop[kind] else {}
	end
	local shopRows = {}
	local buyingUpgrade = false
	local function buyUpgrade(kind: string)
		local levels = parsePairs(player:GetAttribute("UpgradeLevels"))
		if not shopLevels(kind)[(levels[string.lower(kind)] or 0) + 1] then toast("Already maxed out!", THEME.gold) return end
		if buyingUpgrade then return end
		buyingUpgrade = true
		local ok, msg = invoke("PurchaseUpgrade", kind)
		buyingUpgrade = false
		toast(tostring(msg or (if ok then "Upgraded!" else "Couldn't buy that.")), if ok then THEME.green else THEME.red)
		if ok and shopRows[kind] then bounce(shopRows[kind].row) end
		if refreshers.Upgrades then refreshers.Upgrades() end
	end
	for i, kind in SHOP_ORDER do
		local look = SHOP_LOOK[kind] or { icon = "⭐", attr = "", base = 0, fmt = tostring }
		local info = if type(CFG.ShopInfo) == "table" and type(CFG.ShopInfo[kind]) == "table" then CFG.ShopInfo[kind] else {}
		local row = new("Frame", { BackgroundColor3 = THEME.panel2, Size = UDim2.new(1, -12, 0, 84), LayoutOrder = i, Parent = scroll },
			{ corner(14), stroke(3, Color3.fromRGB(70, 74, 110)) })
		local iconBg = new("Frame", { BackgroundColor3 = ACCENT:Lerp(THEME.panel, 0.45), Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(64, 64), Parent = row },
			{ corner(16), stroke(2) })
		label({ Text = look.icon, Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.14), Parent = iconBg })
		label({ Text = tostring(info.name or kind), Position = UDim2.fromOffset(86, 10), Size = UDim2.fromOffset(290, 28), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		label({ Text = tostring(info.blurb or ""), Position = UDim2.fromOffset(86, 44), Size = UDim2.fromOffset(290, 20), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = THEME.sub, Parent = row })
		local valueText = label({ Text = "", Position = UDim2.fromOffset(388, 12), Size = UDim2.fromOffset(160, 28), TextColor3 = THEME.green, Parent = row })
		local levelText = label({ Text = "", Position = UDim2.fromOffset(388, 46), Size = UDim2.fromOffset(160, 20), TextColor3 = THEME.sub, Parent = row })
		local buy = button({ Name = "Buy" .. kind, Color = THEME.green, Text = "BUY", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, 56), Parent = row }, function() buyUpgrade(kind) end)
		shopRows[kind] = { row = row, look = look, valueText = valueText, levelText = levelText, buy = buy }
	end
	local function refreshShop()
		local levels = parsePairs(player:GetAttribute("UpgradeLevels"))
		local gems = attrNumber("Gems", 0)
		gemsHave.Text = "You have ◆ " .. Format.Short(gems)
		for kind, r in shopRows do
			local list = shopLevels(kind)
			-- (capped: saves from before a shop got fewer levels can hold a higher number)
			local level = math.min(levels[string.lower(kind)] or 0, #list)
			local current = attrNumber(r.look.attr, r.look.base)
			local nextLevel = list[level + 1]
			if nextLevel then
				local cost = tonumber(nextLevel.cost) or 0
				-- (▶ because FredokaOne has no ➜ glyph: it showed up as an empty gap)
				r.valueText.Text = r.look.fmt(current) .. " ▶ " .. r.look.fmt(current + (tonumber(nextLevel.value) or 0))
				r.levelText.Text = "Level " .. level .. " / " .. #list
				r.buy.Text = "BUY  ◆ " .. Format.Short(cost)
				r.buy.BackgroundColor3 = if gems >= cost then THEME.green else THEME.green:Lerp(THEME.panel, 0.6)
			else
				r.valueText.Text = r.look.fmt(current)
				r.levelText.Text = if #list > 0 then "Level " .. level .. " / " .. #list else "Coming soon"
				r.buy.Text = if #list > 0 then "MAXED" else "SOON"
				r.buy.BackgroundColor3 = THEME.gold:Lerp(THEME.panel, 0.45)
			end
		end
	end

	-- MILESTONES: earned just by playing (rebuilt on refresh; they're tagged "Track")
	label({ Text = "Milestones (earned just by playing)", Size = UDim2.new(1, -12, 0, 30), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = ACCENT, LayoutOrder = 20, Parent = scroll })
	local function track(order: number, title: string, current: number, steps: { any }, valueText: string, fmt: (number) -> string)
		local nextStep
		for _, st in steps do if current < st.need then nextStep = st break end end
		local row = new("Frame", { Name = "Track", BackgroundColor3 = THEME.panel2, Size = UDim2.new(1, -12, 0, 92), LayoutOrder = 20 + order, Parent = scroll }, { corner(14) })
		label({ Text = title, Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(14, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		label({ Text = valueText, AnchorPoint = Vector2.new(1, 0), Size = UDim2.new(0.45, 0, 0, 30), Position = UDim2.new(1, -14, 0, 8), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = THEME.green, Parent = row })
		local back = new("Frame", { BackgroundColor3 = THEME.stroke, Position = UDim2.fromOffset(14, 46), Size = UDim2.new(1, -28, 0, 20), Parent = row }, { corner(10) })
		new("Frame", { BackgroundColor3 = THEME.green, Size = UDim2.fromScale(nextStep and math.clamp(current / nextStep.need, 0, 1) or 1, 1), Parent = back }, { corner(10) })
		label({ Text = nextStep and ("Next: " .. nextStep.label .. "  (" .. fmt(current) .. " / " .. fmt(nextStep.need) .. ")") or "MAXED!",
			Size = UDim2.new(1, -28, 0, 20), Position = UDim2.fromOffset(14, 68), TextColor3 = THEME.sub, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	end
	local function hours(sec: number) return string.format("%.1fh", sec / 3600) end
	refreshers.Upgrades = function()
		refreshShop()
		for _, c in scroll:GetChildren() do if c.Name == "Track" then c:Destroy() end end
		track(1, "Damage (defeat enemies)", player:GetAttribute("Kills") or 0, Config.Upgrades.Damage, string.format("x%.2f damage", player:GetAttribute("DamageMult") or 1), Format.Short)
		track(2, "Luck (play time)", player:GetAttribute("PlaySeconds") or 0, Config.Upgrades.Luck, string.format("x%.2f luck", player:GetAttribute("Luck") or 1), hours)
		track(3, "Multi Open (open orbs)", player:GetAttribute("OrbsOpened") or 0, Config.Upgrades.MultiOpen, "Open x" .. (player:GetAttribute("OpenCount") or 1), Format.Short)
		local idx = player:GetAttribute("IndexCount") or 0
		track(4, "Champion Index (+2% damage each)", idx, { { need = #Config.Champions, label = "Discover all " .. #Config.Champions } }, idx .. "/" .. #Config.Champions .. " found", tostring)
	end
end

----------------------------------------------------------------------------
-- Quests + Help panels
----------------------------------------------------------------------------
do
	local _, body = makePanel("Quests", "Quests", THEME.gold, Vector2.new(660, 500))
	local info = label({ Text = "", Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.sub, Parent = body })
	local list = new("ScrollingFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36), ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body },
		{ new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	refreshers.Quests = function()
		for _, c in list:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local cur = player:GetAttribute("QuestIndex") or 1
		local state = player:GetAttribute("QuestState") or "offer"
		local prog = player:GetAttribute("QuestProgress") or 0
		local shown = 0
		for i, q in Quests.List do
			local done = i < cur or state == "finished"
			local isCur = i == cur and state ~= "finished"
			if done or isCur or shown < 3 then
				if not done and not isCur then shown += 1 end
				local color = if done then THEME.green:Lerp(THEME.panel, 0.6) elseif isCur then THEME.gold:Lerp(THEME.panel, 0.55) else THEME.panel2
				local row = new("Frame", { BackgroundColor3 = color, Size = UDim2.new(1, -12, 0, 58), LayoutOrder = if isCur then -1 else i, Parent = list },
					{ corner(12), stroke(isCur and 3 or 0, THEME.gold) })
				local icon = if done then "✅" elseif isCur then "▶" else "🔒"
				local tag = if Quests.IsTutorial(i) then "Tutorial" else (Config.WorldById(q.world) or Config.Hub).name
				label({ Text = icon .. " " .. q.title, Size = UDim2.new(0.68, -12, 0, 30), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
				label({ Text = tag, Size = UDim2.new(0.68, -12, 0, 18), Position = UDim2.fromOffset(38, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.sub, Parent = row })
				local right = ""
				if isCur then
					right = if state == "ready" then "Claim at Sensei!" elseif state == "offer" then "Talk to Sensei" elseif q.need > 1 then (prog .. " / " .. q.need) else "In progress"
				elseif not done then
					local r = q.reward or {}
					right = (r.coins and ("$" .. Format.Short(r.coins) .. " ") or "") .. (r.gems and ("◆" .. r.gems) or "")
				end
				label({ Text = right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.new(0.3, 0, 0, 26),
					TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = isCur and THEME.gold or THEME.sub, Parent = row })
			end
		end
		info.Text = string.format("Quest line: %d / %d complete", math.min(cur - 1, #Quests.List), #Quests.List)
	end
	local _, hbody = makePanel("Help", "How to play", Color3.fromRGB(120, 180, 255), Vector2.new(680, 520))
	label({ Size = UDim2.fromScale(1, 1), TextScaled = false, TextSize = 21, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = hbody,
		Text = "• Tap an enemy to send your champions after it. Only champions deal damage, so collect strong ones!\n\n• Enemies drop coins (bosses also drop ◆ Gems). Spend coins at summon shrines for new champions.\n\n• Press ⭐ BEST to equip your strongest team. Fuse 3 copies of a champion at the Fusion Machine to give it a star.\n\n• Q (or the DASH button) dashes. Jump again in mid-air to double jump.\n\n• Defeat a world's boss to unlock the next world (Teleport menu).\n\n• Spend Gems in Upgrades and the Store: Auto Attack, Auto Hatch and +1 Equip." })
end

----------------------------------------------------------------------------
-- Store panel: the 3 passes. Each is bought ONCE, with Gems or with Robux.
----------------------------------------------------------------------------
do
	local _, body = makePanel("Store", "Store", Color3.fromRGB(255, 170, 40), Vector2.new(880, 560))
	label({ Text = "Passes are forever! Earn ◆ Gems from bosses and quests, or use Robux.", Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.sub, Parent = body })
	local row = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Parent = body }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local LOOK = {
		AutoAttack = { icon = "⚔️", tag = "POPULAR", top = Color3.fromRGB(255, 110, 80), bottom = Color3.fromRGB(110, 20, 45),
			hint = "Switch it on with the AUTO button" },
		AutoHatch = { icon = "🥚", tag = "AFK!", top = Color3.fromRGB(185, 120, 255), bottom = Color3.fromRGB(55, 25, 120),
			hint = "Switch it on with AUTO HATCH" },
		ExtraEquip = { icon = "👥", tag = "+DAMAGE", top = Color3.fromRGB(70, 215, 130), bottom = Color3.fromRGB(15, 85, 60),
			hint = "Your extra slot is ready!" },
	}
	local order = if type(CFG.PassOrder) == "table" then CFG.PassOrder else { "AutoAttack", "AutoHatch", "ExtraEquip" }
	local passes = if type(CFG.Passes) == "table" then CFG.Passes else {}
	local cards = {}
	local buying = false
	local function buy(key: string, method: string)
		if buying then return end
		buying = true
		local ok, msg = invoke("PurchasePass", key, method)
		buying = false
		toast(tostring(msg or (if ok then "Unlocked!" else "Couldn't buy that.")), if ok then THEME.green else THEME.red)
		if refreshers.Store then refreshers.Store() end
	end
	for i, key in order do
		local pass = if type(passes[key]) == "table" then passes[key] else {}
		local look = LOOK[key] or { icon = "⭐", tag = "", top = THEME.purple, bottom = THEME.panel, hint = "" }
		local card = new("Frame", { Name = key .. "Card", BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 262, 1, -6), LayoutOrder = i, Parent = row },
			{ corner(20), stroke(4, look.top:Lerp(Color3.new(1, 1, 1), 0.35)), gradient(look.top, look.bottom), new("UIScale", { Name = "Pop" }) })
		-- big round icon
		local bubble = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(120, 120), Parent = card }, { corner(60), stroke(3, Color3.new(1, 1, 1)) })
		label({ Text = look.icon, Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.19, 0.19), Parent = bubble })
		if look.tag ~= "" then
			local tag = new("Frame", { BackgroundColor3 = THEME.gold, Rotation = -8, Position = UDim2.fromOffset(-10, 8), Size = UDim2.fromOffset(104, 30), Parent = card },
				{ corner(10), stroke(2) })
			label({ Text = look.tag, Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Parent = tag })
		end
		label({ Text = tostring(pass.name or key), Position = UDim2.fromOffset(12, 146), Size = UDim2.new(1, -24, 0, 34), Parent = card })
		label({ Text = tostring(pass.blurb or ""), TextScaled = false, TextSize = 19, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(14, 186), Size = UDim2.new(1, -28, 0, 74), TextColor3 = Color3.fromRGB(235, 235, 250), Parent = card })
		local gemPrice = tonumber(pass.gems)
		local robuxPrice = tonumber(pass.robux)
		-- gamePassId 0 = the Robux pass isn't set up yet (Gems still work)
		local robuxReady = (tonumber(pass.gamePassId) or 0) > 0
		local gemBtn = button({ Name = "Buy" .. key .. "Gems", Color = THEME.gem, Text = if gemPrice then "◆ " .. Format.Short(gemPrice) else "Gems soon",
			Position = UDim2.fromOffset(14, 268), Size = UDim2.new(1, -28, 0, 54), Parent = card }, function()
			if gemPrice then buy(key, "gems") else toast("Coming soon!", THEME.orange) end
		end)
		local robuxBtn = button({ Name = "Buy" .. key .. "Robux", Color = if robuxReady then THEME.green else THEME.panel2,
			Text = if robuxReady and robuxPrice then "R$ " .. robuxPrice else "Robux soon",
			Position = UDim2.fromOffset(14, 330), Size = UDim2.new(1, -28, 0, 54), Parent = card }, function()
			if robuxReady then buy(key, "robux") else toast("Robux purchases are coming soon. Gems work right now!", THEME.orange) end
		end)
		local ownedBadge = new("Frame", { Visible = false, BackgroundColor3 = THEME.green, Position = UDim2.fromOffset(14, 268), Size = UDim2.new(1, -28, 0, 116),
			Parent = card }, { corner(16), stroke(3) })
		label({ Text = "OWNED ✓", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 52), Parent = ownedBadge })
		label({ Text = look.hint, Position = UDim2.fromOffset(10, 68), Size = UDim2.new(1, -20, 0, 32), TextColor3 = Color3.fromRGB(230, 255, 235), Parent = ownedBadge })
		cards[key] = { card = card, gemBtn = gemBtn, robuxBtn = robuxBtn, owned = ownedBadge, gemPrice = gemPrice, wasOwned = nil :: boolean? }
	end
	refreshers.Store = function()
		local gems = attrNumber("Gems", 0)
		for key, c in cards do
			local owned = player:GetAttribute("Pass" .. key) == true
			c.gemBtn.Visible = not owned
			c.robuxBtn.Visible = not owned
			c.owned.Visible = owned
			if c.gemPrice then
				c.gemBtn.BackgroundColor3 = if gems >= c.gemPrice then THEME.gem else THEME.gem:Lerp(THEME.panel, 0.55)
			end
			if owned and c.wasOwned == false then
				-- just bought it: a happy bounce
				local pop = c.card:FindFirstChild("Pop") :: UIScale
				pop.Scale = 1.12
				TweenService:Create(pop, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
			c.wasOwned = owned
		end
	end
end

----------------------------------------------------------------------------
-- Updates panel: Config.UpdateLog, newest first
----------------------------------------------------------------------------
do
	local ACCENT = Color3.fromRGB(255, 110, 180)
	local _, body = makePanel("Updates", "What's New", ACCENT, Vector2.new(720, 560))
	local scroll = new("ScrollingFrame", { BackgroundColor3 = THEME.panel2, Size = UDim2.fromScale(1, 1), ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, {
		corner(14), new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 12) }),
	})
	local entries = updateLog()
	if #entries == 0 then
		label({ Text = "No updates yet. Check back soon!", Size = UDim2.new(1, 0, 0, 34), TextColor3 = THEME.sub, Parent = scroll })
	end
	for i, entry in entries do
		local newest = i == 1
		local card = new("Frame", { BackgroundColor3 = THEME.panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = scroll }, {
			corner(14), stroke(3, if newest then ACCENT else Color3.fromRGB(70, 74, 110)),
			new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }),
		})
		-- header: version badge, date, and NEW! on the newest one
		local head = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 0, Parent = card })
		local badge = new("Frame", { BackgroundColor3 = if newest then ACCENT else THEME.panel2, Size = UDim2.fromOffset(120, 36), Parent = head }, { corner(10), stroke(2) })
		label({ Text = "v" .. tostring(entry.version or "?"), Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Parent = badge })
		label({ Text = tostring(entry.date or ""), Position = UDim2.fromOffset(134, 6), Size = UDim2.new(1, -240, 1, -12), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = THEME.sub, Parent = head })
		if newest then
			local tag = new("Frame", { BackgroundColor3 = THEME.gold, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(90, 30),
				Rotation = 4, Parent = head }, { corner(10), stroke(2) })
			label({ Text = "NEW!", Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Parent = tag })
		end
		local notes = if type(entry.notes) == "table" then entry.notes else {}
		for n, note in notes do
			local l = label({ Text = "•  " .. tostring(note), TextScaled = false, TextSize = 20, TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = n, Parent = card })
			l:FindFirstChildOfClass("UIStroke").Thickness = 1.5 -- (thinner outline reads better on small text)
		end
	end
end

----------------------------------------------------------------------------
-- Fuse panel (Fusion Machine): a champion + spare copies of the SAME champion -> +1 star
----------------------------------------------------------------------------
do
	local ACCENT = Color3.fromRGB(190, 100, 255)
	local _, body = makePanel("Fuse", "Fusion Machine", ACCENT, Vector2.new(880, 580))
	label({ Text = "Pick a champion, then fuse it with spare copies of the SAME champion.", Size = UDim2.new(0.56, -8, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.sub, Parent = body })
	local list = new("ScrollingFrame", { BackgroundColor3 = THEME.panel2, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(0.56, -8, 1, -34),
		ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = body }, {
		corner(14),
		new("UIGridLayout", { CellSize = UDim2.fromOffset(100, 128), CellPadding = UDim2.fromOffset(9, 9), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
	})
	local side = new("Frame", { BackgroundColor3 = THEME.panel2, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.44, 0, 1, 0), Parent = body }, { corner(14), stroke(3, ACCENT) })
	local preview = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = side })
	local fxLayer = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = side }) -- success animation (survives refreshes)

	local target: string? = nil
	local fusing = false
	local costLabel: TextLabel? = nil
	local currentCost: number? = nil

	local function copiesNeeded(): number -- spare copies used up (Config.Fusion.copies counts the target too)
		return math.max(1, math.floor(fusionNumber("copies", 3)) - 1)
	end
	local function maxStars(): number
		return math.floor(fusionNumber("maxStars", 5))
	end
	local function costFor(owned: Owned): number?
		local fn = type(CFG.Fusion) == "table" and CFG.Fusion.cost
		if type(fn) ~= "function" then return nil end
		-- by rarity NAME, exactly like the server (so adding a tier never shifts a price)
		local ok, v = pcall(fn, starsOf(owned), rarityOf(owned.id).id)
		return if ok and type(v) == "number" then v else nil
	end
	-- Spare copies: same champion, not the target, not equipped. Lowest stars first,
	-- so the fusion never eats your best copies when worse ones are there.
	local function spareCopies(targetUid: string): ({ string }, number)
		local t = champions[targetUid]
		local spare, equippedCount = {}, 0
		if not t then return spare, 0 end
		for uid, owned in champions do
			if uid ~= targetUid and owned.id == t.id then
				if table.find(equipped, uid) then equippedCount += 1 else table.insert(spare, uid) end
			end
		end
		table.sort(spare, function(a, b)
			local sa, sb = starsOf(champions[a]), starsOf(champions[b])
			if sa ~= sb then return sa < sb end
			local na, nb = tonumber(a), tonumber(b)
			if na and nb then return na < nb end
			return a < b
		end)
		return spare, equippedCount
	end

	-- the "stars pop" celebration after a successful fusion
	local function celebrate(stars: number)
		local flash = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15, Size = UDim2.fromScale(1, 1), Parent = fxLayer }, { corner(14) })
		TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		local starRow = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
			Size = UDim2.fromOffset(340, 80), Parent = fxLayer }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i = 1, stars do
			local isNew = i == stars
			local size = if isNew then 76 else 56
			local s = label({ Text = "★", TextColor3 = THEME.gold, Size = UDim2.fromOffset(size, size), LayoutOrder = i, Parent = starRow })
			s:FindFirstChildOfClass("UIStroke").Thickness = 3
			local sc = new("UIScale", { Scale = 0, Parent = s })
			task.delay(0.1 + (i - 1) * 0.12, function()
				TweenService:Create(sc, TweenInfo.new(if isNew then 0.5 else 0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				if isNew then
					s.Rotation = -45
					TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
				end
			end)
		end
		local text = label({ Text = stars .. " STAR" .. (if stars == 1 then "" else "S") .. "!", TextColor3 = THEME.gold, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(300, 52), Rotation = -4, Parent = fxLayer })
		text:FindFirstChildOfClass("UIStroke").Thickness = 4
		local textScale = new("UIScale", { Scale = 0, Parent = text })
		task.delay(0.15 + stars * 0.12, function()
			TweenService:Create(textScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
		-- sparkles flying out
		for k = 1, 10 do
			local angle = k / 10 * math.pi * 2
			-- (★, not ✦: FredokaOne can't draw ✦, so those sparkles were invisible)
			local sp = label({ Text = "★", TextColor3 = if k % 2 == 0 then THEME.gold else Color3.fromRGB(230, 200, 255), AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(26, 26), Parent = fxLayer })
			TweenService:Create(sp, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.5, math.cos(angle) * 150, 0.3, math.sin(angle) * 110), TextTransparency = 1, Rotation = 180 }):Play()
			task.delay(0.85, function() sp:Destroy() end)
		end
		task.delay(1.9, function()
			fadeAway(starRow, 0.3)
			fadeAway(text, 0.3)
			task.wait(0.32)
			flash:Destroy()
			starRow:Destroy()
			text:Destroy()
		end)
	end

	local buildList: () -> () = function() end
	local function buildPreview()
		for _, c in preview:GetChildren() do c:Destroy() end
		costLabel, currentCost = nil, nil
		local targetUid = target
		local owned = targetUid and champions[targetUid]
		local def = owned and Config.ChampionById[owned.id]
		if not targetUid or not owned or not def then
			label({ Text = "Pick a champion on the left", Position = UDim2.fromOffset(16, 200), Size = UDim2.new(1, -32, 0, 34), TextColor3 = THEME.sub, Parent = preview })
			return
		end
		local r = rarityOf(def.id)
		local stars = starsOf(owned)
		local maxS = maxStars()
		local need = copiesNeeded()
		local spare, equippedCopies = spareCopies(targetUid)
		local fodder = {}
		for i = 1, math.min(need, #spare) do fodder[i] = spare[i] end

		local pic = new("Frame", { BackgroundColor3 = r.color:Lerp(THEME.panel, 0.5), Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 160), Parent = preview },
			{ corner(14), stroke(3, r.color) })
		viewport(def.id, pic, UDim2.fromScale(1, 1))
		label({ Text = displayName(owned), Position = UDim2.fromOffset(12, 178), Size = UDim2.new(1, -24, 0, 30), TextColor3 = r.color, Parent = preview })
		local maxed = stars >= maxS
		label({ Text = if maxed then starText(stars) .. "  MAX!" else (if stars > 0 then starText(stars) else "☆") .. "  ▶  " .. starText(stars + 1),
			Position = UDim2.fromOffset(12, 210), Size = UDim2.new(1, -24, 0, 28), TextColor3 = THEME.gold, Parent = preview })
		local after = def.power * (1 + (stars + 1) * fusionNumber("powerPerStar", 0.5))
		label({ Text = if maxed then "Power " .. Format.Short(powerOf(owned)) else "Power " .. Format.Short(powerOf(owned)) .. "  ▶  " .. Format.Short(after),
			Position = UDim2.fromOffset(12, 240), Size = UDim2.new(1, -24, 0, 22), TextColor3 = THEME.green, Parent = preview })
		-- which copies get used up
		local copyWord = if need == 1 then "copy" else "copies"
		local copiesText = if #spare >= need then string.format("Uses %d spare %s of %s", need, copyWord, def.name)
			else string.format("Needs %d spare %s of %s (you have %d)", need, copyWord, def.name, #spare)
		for _, uid in fodder do
			if starsOf(champions[uid]) > 0 then copiesText ..= "  (one has stars!)" break end
		end
		label({ Text = copiesText, Position = UDim2.fromOffset(12, 266), Size = UDim2.new(1, -24, 0, 20), TextColor3 = THEME.sub, Parent = preview })
		local chips = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 292), Size = UDim2.new(1, -24, 0, 70), Parent = preview }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i = 1, math.min(need, 4) do
			local uid = fodder[i]
			local chip = new("Frame", { BackgroundColor3 = if uid then r.color:Lerp(THEME.panel, 0.5) else THEME.panel, Size = UDim2.fromOffset(70, 70), LayoutOrder = i,
				Parent = chips }, { corner(12), stroke(2, if uid then r.color else Color3.fromRGB(80, 84, 120)) })
			if uid then
				viewport(def.id, chip, UDim2.fromScale(1, 1))
				local s = starsOf(champions[uid])
				if s > 0 then
					label({ Text = starText(s), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -6, 0, 14), TextColor3 = THEME.gold, Parent = chip })
				end
			else
				label({ Text = "?", Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), TextColor3 = THEME.sub, Parent = chip })
			end
		end
		local cost = if maxed then nil else costFor(owned)
		currentCost = cost
		costLabel = label({ Text = if cost then "Cost: $" .. Format.Short(cost) else "", Position = UDim2.fromOffset(12, 368), Size = UDim2.new(1, -24, 0, 26),
			TextColor3 = THEME.gold, Parent = preview })
		refreshFuseCost()
		-- why FUSE can't be pressed yet (nil = it can)
		local reason: string? = nil
		local reasonToast = ""
		if maxed then
			reason, reasonToast = "MAX STARS", displayName(owned) .. " already has max stars!"
		elseif #spare < need then
			if #spare + equippedCopies >= need then
				reason, reasonToast = "Unequip copies", "Unequip the spare copies of " .. def.name .. " to fuse them."
			else
				reason, reasonToast = "Need " .. (need - #spare) .. " more", "Open orbs to find more copies of " .. def.name .. "!"
			end
		end
		button({ Name = "FuseButton", Color = if reason then THEME.panel else ACCENT, Text = reason or "FUSE!", AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -24, 0, 64), Parent = preview }, function()
			if reason then toast(reasonToast, THEME.orange) return end
			if fusing then return end
			fusing = true
			local ok, msg = invoke("FuseChampions", targetUid, fodder)
			fusing = false
			if ok then
				celebrate(stars + 1)
				toast(tostring(msg or "Fusion complete!"), THEME.gold)
			else
				toast(tostring(msg or "Couldn't fuse."), THEME.red)
			end
		end)
	end

	buildList = function()
		for _, c in list:GetChildren() do if c:IsA("GuiObject") then c:Destroy() end end
		local count: { [string]: number } = {} -- how many of each champion you own
		for _, owned in champions do count[owned.id] = (count[owned.id] or 0) + 1 end
		local need = copiesNeeded()
		local maxS = maxStars()
		local items = {}
		for uid, owned in champions do
			local def = Config.ChampionById[owned.id]
			if def then
				local ready = starsOf(owned) < maxS and (count[owned.id] or 0) > need
				table.insert(items, { uid = uid, owned = owned, def = def, ready = ready, power = powerOf(owned) })
			end
		end
		-- ready-to-fuse champions first, then the strongest
		table.sort(items, function(a, b)
			if a.ready ~= b.ready then return a.ready end
			if a.power ~= b.power then return a.power > b.power end
			return a.uid < b.uid
		end)
		if #items == 0 then
			label({ Text = "No champions yet!", Size = UDim2.fromOffset(100, 40), TextColor3 = THEME.sub, Parent = list })
		end
		for i, item in items do
			local r = rarityOf(item.def.id)
			local isTarget = item.uid == target
			local card = new("TextButton", { Text = "", AutoButtonColor = true, LayoutOrder = i, BackgroundColor3 = r.color:Lerp(THEME.panel, if item.ready then 0.5 else 0.78),
				Parent = list }, { corner(14), stroke(if isTarget then 5 else 3, if isTarget then Color3.new(1, 1, 1) else r.color) })
			viewport(item.def.id, card, UDim2.new(1, 0, 0, 82), UDim2.fromOffset(0, 4))
			label({ Text = displayName(item.owned), Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 0, 86), Parent = card })
			local stars = starsOf(item.owned)
			label({ Text = if stars > 0 then starText(stars) else "☆", Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 0, 106), TextColor3 = THEME.gold, Parent = card })
			-- "x3" = you own three of this champion (green = enough to fuse)
			local badge = new("Frame", { BackgroundColor3 = if item.ready then THEME.green else THEME.panel, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(38, 22), Parent = card }, { corner(11), stroke(2) })
			label({ Text = "x" .. (count[item.owned.id] or 1), Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2), Parent = badge })
			if table.find(equipped, item.uid) then
				local tag = new("Frame", { BackgroundColor3 = THEME.green, Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(4, 4), Parent = card }, { corner(12), stroke(2) })
				label({ Text = "✓", Size = UDim2.fromScale(1, 1), Parent = tag })
			end
			card.Activated:Connect(function()
				playUiSound("click")
				target = item.uid
				buildList()
				buildPreview()
			end)
		end
	end

	refreshFuseCost = function()
		if costLabel and currentCost then
			costLabel.TextColor3 = if attrNumber("Coins", 0) >= currentCost then THEME.gold else THEME.red
		end
	end
	refreshers.Fuse = function()
		if not target or not champions[target] then
			-- nothing picked yet: start with the strongest champion that can be fused right now
			target = nil
			local count: { [string]: number } = {}
			for _, owned in champions do count[owned.id] = (count[owned.id] or 0) + 1 end
			local bestReady, bestPower = false, -1
			for uid, owned in champions do
				local ready = starsOf(owned) < maxStars() and (count[owned.id] or 0) > copiesNeeded()
				local power = powerOf(owned)
				if (ready and not bestReady) or (ready == bestReady and power > bestPower) then
					target, bestReady, bestPower = uid, ready, power
				end
			end
		end
		buildList()
		buildPreview()
	end
	openFuse = function(uid: string?)
		target = uid
		showPanel("Fuse")
	end
end

----------------------------------------------------------------------------
-- live stat updates
----------------------------------------------------------------------------
local function pop(l: TextLabel)
	local sc = l:FindFirstChild("PopScale") or new("UIScale", { Name = "PopScale", Parent = l })
	sc.Scale = 1.2
	TweenService:Create(sc, TweenInfo.new(0.2), { Scale = 1 }):Play()
end

-- Goal tracker (top right) follows Sensei Hikari's quest line.
-- (The trail / arrow / tapping hand that show the way live in QuestClient.)
local function refreshGoal()
	local i = player:GetAttribute("QuestIndex") or 1
	local state = player:GetAttribute("QuestState") or "offer"
	local prog = player:GetAttribute("QuestProgress") or 0
	local q = Quests.Get(i)
	local text, pct
	if q and state ~= "finished" then
		goalTitle.Text = if Quests.IsTutorial(i) then "TUTORIAL" else "QUEST " .. (i - Quests.TutorialCount)
		if state == "offer" then
			text, pct = "Talk to Sensei Hikari", 0
		elseif state == "ready" then
			text, pct = "✔ " .. q.title .. "! Return to Sensei Hikari", 1
		elseif q.need > 1 then
			text, pct = q.title .. "  (" .. prog .. "/" .. q.need .. ")", math.clamp(prog / q.need, 0, 1)
		else
			text, pct = q.title, 0
		end
	else
		goalTitle.Text = "GOAL"
		text, pct = "Every quest complete! Raids and the Tower are coming soon", 1
	end
	goalText.Text = text
	TweenService:Create(goalBar, TweenInfo.new(0.3), { Size = UDim2.fromScale(pct, 1) }):Play()
end

-- Panels with 3D previews only rebuild when the inventory changes, not on every coin.
local HEAVY_PANELS = { Champions = true, Index = true, Fuse = true }

-- The server sets many attributes at once (one per stat), so the open menu is redrawn
-- once at the end of the frame instead of once per attribute.
local panelRefreshQueued = false
local function queuePanelRefresh()
	if panelRefreshQueued then return end
	panelRefreshQueued = true
	task.defer(function()
		panelRefreshQueued = false
		if openPanel and not HEAVY_PANELS[openPanel] and refreshers[openPanel] then refreshers[openPanel]() end
	end)
end

local WORLD_ATMOS = { [0] = Color3.fromRGB(210, 230, 255), [1] = Color3.fromRGB(200, 235, 255), [2] = Color3.fromRGB(255, 225, 200), [3] = Color3.fromRGB(215, 210, 255) }
local atmosWorld: number? = nil -- (the world the atmosphere tint was last set for)

-- Coins / gems: the number counts up to its new value and a "+N" (or "-N" when you spend)
-- floats up beside the pill. Quick changes (auto attack kills) are added together, so the
-- pill never fills up with overlapping numbers. The first value (your save) just appears.
local currencyReady = false
local function currencyCounter(valueLabel: TextLabel, attr: string, color: Color3): () -> ()
	local target = attrNumber(attr, 0)
	local shown = new("NumberValue", { Value = target })
	valueLabel.Text = Format.Short(target)
	shown.Changed:Connect(function(v: number) valueLabel.Text = Format.Short(math.floor(v + 0.5)) end)
	local pending, flushing = 0, false
	local function floatDelta(delta: number)
		local l = label({ Text = (if delta > 0 then "+" else "-") .. Format.Short(math.abs(delta)), AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(1, 10, 0.5, 0), Size = UDim2.fromOffset(120, 30), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if delta > 0 then color else THEME.red, ZIndex = 3, Parent = valueLabel.Parent })
		local rise = TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fade = TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(l, rise, { Position = UDim2.new(1, 10, 0.5, -28) }):Play()
		TweenService:Create(l, fade, { TextTransparency = 1 }):Play()
		local outline = l:FindFirstChildOfClass("UIStroke")
		if outline then TweenService:Create(outline, fade, { Transparency = 1 }):Play() end
		task.delay(0.9, function() l:Destroy() end)
	end
	return function()
		local v = attrNumber(attr, 0)
		if v == target then return end
		local delta = v - target
		target = v
		if not currencyReady then
			shown.Value = v
			return
		end
		TweenService:Create(shown, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = v }):Play()
		pop(valueLabel)
		pending += delta
		if flushing then return end
		flushing = true
		task.delay(0.3, function()
			flushing = false
			local total = pending
			pending = 0
			if total ~= 0 then floatDelta(total) end
		end)
	end
end
local syncCoins = currencyCounter(coinsText, "Coins", THEME.gold)
local syncGems = currencyCounter(gemsText, "Gems", THEME.gem)

local function refreshStats()
	syncCoins()
	syncGems()
	dpsText.Text = "DPS : " .. Format.Short(player:GetAttribute("TeamPower") or 0)
	luckText.Text = string.format("%.2gx", player:GetAttribute("Luck") or 1)
	coinMultText.Text = "1x"
	damageMultText.Text = string.format("%.2fx", player:GetAttribute("DamageMult") or 1)
	slotsText.Text = tostring(player:GetAttribute("EquipSlots") or 3)
	local wid = player:GetAttribute("World") or 0
	local w = Config.WorldById(wid)
	worldText.Text = w and w.name or ""
	-- (WorldAmbience owns the per-world lighting when it's there; this tint is the fallback)
	if wid ~= atmosWorld and not script.Parent:FindFirstChild("WorldAmbience") then
		atmosWorld = wid
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm and WORLD_ATMOS[wid] then TweenService:Create(atm, TweenInfo.new(1.5), { Color = WORLD_ATMOS[wid] }):Play() end
	end
	refreshGoal()
	queuePanelRefresh()
end
for _, a in { "Coins", "Gems", "TeamPower", "World", "Kills", "OrbsOpened", "Unlocked", "OpenCount", "EquipSlots", "TutorialDone", "Luck", "DamageMult",
	"QuestIndex", "QuestState", "QuestProgress", "PassAutoAttack", "PassAutoHatch", "PassExtraEquip", "InventorySize", "AttackRange",
	"DashCharges", "JumpCount", "UpgradeLevels", "BossKills" } do
	player:GetAttributeChangedSignal(a):Connect(refreshStats)
end
player:GetAttributeChangedSignal("Coins"):Connect(function() refreshFuseCost() end) -- (the pill's count-up + pop: currencyCounter)

Remotes.InventoryUpdated.OnClientEvent:Connect(function(c, e, idx)
	champions = if type(c) == "table" then c else {}
	equipped = if type(e) == "table" then e else {}
	if type(idx) == "table" then discovered = idx end
	if openPanel and HEAVY_PANELS[openPanel] and refreshers[openPanel] then refreshers[openPanel]() end
	refreshSummonButtons() -- (backpack space on the summon buttons)
	refreshSummonEquips() -- (EQUIP buttons on the summon result screen)
end)

-- proximity prompts open the matching menu
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local station = prompt:FindFirstAncestorWhichIsA("Model")
	if prompt.Name == "OrbPrompt" then
		if summonPhase == "cinematic" then return end -- (a summon is already playing)
		-- remember WHICH shrine opened the panel: the summon cinematic plays at its altar
		local shrine = shrineOf(prompt) or station
		local worldId = shrine and shrine:GetAttribute("WorldId")
		currentAltar = shrine
		currentOrbWorld = if type(worldId) == "number" then worldId else 1
		showPanel("Orb")
	elseif prompt.Name == "GatePrompt" then
		showPanel("Worlds")
	elseif prompt.Name == "IndexPrompt" then
		showPanel("Index")
	elseif prompt.Name == "FusePrompt" or (prompt.Name == "ComingSoonPrompt" and prompt:FindFirstAncestor("FusionMachine")) then
		-- (the second check keeps the machine working on maps that still have the old prompt)
		openFuse(nil)
	elseif prompt.Name == "ComingSoonPrompt" then
		toast((station and station:GetAttribute("Feature") or "This") .. " is coming soon!", THEME.orange)
	end
end)

----------------------------------------------------------------------------
-- reward + damage popups
----------------------------------------------------------------------------
local function floatText(position: Vector3, text: string, color: Color3, big: boolean?)
	local anchor = Instance.new("Part")
	anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false
	anchor.Transparency = 1; anchor.Size = Vector3.one
	anchor.Position = position + Vector3.new(math.random(-15, 15) / 10, 1, math.random(-15, 15) / 10)
	anchor.Parent = workspace
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(big and 220 or 130, big and 60 or 40), AlwaysOnTop = false, LightInfluence = 0, Parent = anchor })
	local l = label({ Text = text, Size = UDim2.fromScale(1, 1), TextColor3 = color, Parent = bb })
	TweenService:Create(anchor, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	game:GetService("Debris"):AddItem(anchor, 1.1)
end
local function enemyTop(enemy: Model): Vector3
	return enemy.PrimaryPart.Position + Vector3.new(0, enemy:GetAttribute("TopOffset") or enemy.PrimaryPart.Size.Y / 2, 0)
end
-- Boss kills get their own reward card (upper middle): the boss's name and the real coins
-- and gems the server sent, counting up. It needs no tap and leaves by itself.
local bossCard: Frame? = nil
local function bossRewardPopup(info: any)
	if summonPhase == "cinematic" then return end -- (never over the summon at the altar)
	local coins = tonumber(info.coins) or 0
	local gems = tonumber(info.gems) or 0
	-- every world has one boss, so the world you're in names it
	local w = Config.WorldById(attrNumber("World", 0))
	local bossDef = w and (w :: any).boss and (Config.Enemies :: any)[(w :: any).boss]
	-- the first kill of this boss opens the way to the next world: say so
	local nextLine: string? = nil
	if w and w.id > 0 and parsePairs(player:GetAttribute("BossKills"))[w.key] == 1 then
		local nextWorld = Config.Worlds[w.id + 1]
		if nextWorld then nextLine = nextWorld.name .. " can now be unlocked at the Teleporter!" end
	end
	if bossCard then bossCard:Destroy() end
	-- (white backgrounds: the UIGradients below give the real colours)
	local card = new("Frame", { Name = "BossReward", BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.34, 0),
		Size = UDim2.fromOffset(440, if nextLine then 186 else 158), ZIndex = 9, Parent = canvas },
		{ corner(20), stroke(4, THEME.gold), gradient(Color3.fromRGB(48, 40, 84), Color3.fromRGB(18, 16, 36)) })
	bossCard = card
	local ribbon = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(300, 46), ZIndex = 10, Parent = card }, { corner(14), stroke(3), gradient(Color3.fromRGB(255, 226, 120), Color3.fromRGB(235, 150, 20)) })
	label({ Text = "BOSS DEFEATED!", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 1, -12), ZIndex = 11, Parent = ribbon })
	label({ Text = if bossDef then bossDef.name else "Boss", Position = UDim2.fromOffset(20, 32), Size = UDim2.new(1, -40, 0, 30),
		TextColor3 = THEME.sub, ZIndex = 10, Parent = card })
	-- the rewards: the biggest text on the card, counting up from 0
	local coinLabel = label({ Text = "+$0", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(if gems > 0 then 0.6 else 0.5, if gems > 0 then -10 else 110, 0, 70),
		Size = UDim2.fromOffset(220, 54), TextXAlignment = if gems > 0 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center,
		TextColor3 = THEME.gold, ZIndex = 10, Parent = card })
	local gemLabel = if gems > 0 then label({ Text = "+◆0", Position = UDim2.new(0.6, 10, 0, 70), Size = UDim2.fromOffset(150, 54),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.gem, ZIndex = 10, Parent = card }) else nil
	if nextLine then
		label({ Text = nextLine, Position = UDim2.fromOffset(20, 134), Size = UDim2.new(1, -40, 0, 26), TextColor3 = THEME.green, ZIndex = 10, Parent = card })
	end
	local counter = new("NumberValue", { Value = 0, Parent = card })
	counter.Changed:Connect(function(k: number)
		coinLabel.Text = "+$" .. Format.Short(math.floor(coins * k + 0.5))
		if gemLabel then gemLabel.Text = "+◆" .. math.floor(gems * k + 0.5) end
	end)
	-- pop in, count up, hold, then shrink away
	local sc = new("UIScale", { Scale = 0.6, Parent = card })
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(counter, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 }):Play()
	playUiSound("chime")
	task.delay(3.4, function()
		if bossCard ~= card or not card.Parent then return end
		TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.8 }):Play()
		fadeAway(card, 0.25)
		task.wait(0.27)
		card:Destroy()
		if bossCard == card then bossCard = nil end
	end)
end

Remotes.Notify.OnClientEvent:Connect(function(kind, info)
	if kind == "Reward" and type(info) == "table" and typeof(info.position) == "Vector3" then
		local gems = tonumber(info.gems) or 0
		floatText(info.position + Vector3.new(0, 3, 0), "+$" .. Format.Short(tonumber(info.coins) or 0), THEME.gold, info.boss)
		if gems > 0 then floatText(info.position + Vector3.new(0, 4.5, 0), "+◆" .. gems, THEME.gem, true) end
		if info.boss then bossRewardPopup(info) end
	end
end)

-- newer server messages: Auto Hatch results and purchase / info toasts
Remotes.Notify.OnClientEvent:Connect(function(kind, info)
	if type(info) ~= "table" then return end
	if kind == "AutoHatch" then
		if type(info.results) == "table" then showAutoHatch(info.results, info.worldId) end
	elseif kind == "Purchase" then
		if info.msg ~= nil then toast(tostring(info.msg), THEME.gem) end
	end
end)

----------------------------------------------------------------------------
-- startup
----------------------------------------------------------------------------
if not player:GetAttribute("DataLoaded") then player:GetAttributeChangedSignal("DataLoaded"):Wait() end
local c, e, idx = Remotes.GetInventory:InvokeServer()
champions = if type(c) == "table" then c else {}
equipped = if type(e) == "table" then e else {}
discovered = if type(idx) == "table" then idx else {}
refreshStats()
currencyReady = true -- (from now on coin / gem changes count up and show "+N")
