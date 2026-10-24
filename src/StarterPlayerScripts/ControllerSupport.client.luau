-- ControllerSupport (client): makes Aetherwake playable with an Xbox or PlayStation controller
-- (and any gamepad on PC), alongside the mouse, keyboard and touch controls.
--
--   * InputMode: the local Player attribute InputMode = "Gamepad" / "Touch" / "Keyboard" follows the
--     last device used, so the HUD, the tutorial and the target card show the right hints.
--   * Menu focus: when a menu opens on a controller, the focus goes to a sensible button and stays
--     inside that menu (D-pad / left stick move it, A presses it, B goes back). Closing a menu sends
--     the focus back to where it came from, or back to the game.
--   * Gameplay buttons: Y = Champions, D-pad up = the menu grid, LT = Auto Attack, B = back.
--     (LB / RB targeting is in CombatInput, RT dash in Movement, X = the proximity prompts and
--     A = jump are Roblox's own; the left stick moves and the right stick turns the camera.)
--   * A small legend of those buttons with the right Xbox / PlayStation pictures, and button
--     badges on SKIP, CLOSE and the menus' close buttons, only while a controller is in use.
-- Everything is set up ONCE when the script starts (StarterPlayerScripts don't restart on respawn),
-- so reopening menus or respawning never adds a second copy of anything. Nothing here talks to
-- the server: menus still go through the HUD and the server checks everything as before.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local canvas = hud:WaitForChild("Canvas")
local command = hud:WaitForChild("Command") :: BindableFunction

local GOLD = Color3.fromRGB(255, 210, 70)
local BEGIN = Enum.UserInputState.Begin
local SINK, PASS = Enum.ContextActionResult.Sink, Enum.ContextActionResult.Pass

----------------------------------------------------------------------------
-- which device is in use
----------------------------------------------------------------------------
-- (mouse MOVEMENT doesn't count: a nudged mouse next to a controller would flip the hints back
-- and forth; a click or a key does)
local function modeOf(kind: Enum.UserInputType): string?
	if string.find(kind.Name, "Gamepad") then return "Gamepad" end
	if kind == Enum.UserInputType.Touch then return "Touch" end
	if kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
		return "Keyboard"
	end
	return nil
end
local function onPad(): boolean
	return player:GetAttribute("InputMode") == "Gamepad"
end
do
	local start = modeOf(UserInputService:GetLastInputType())
	if GuiService:IsTenFootInterface() then
		start = "Gamepad" -- (a console)
	elseif not start then
		start = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard"
	end
	player:SetAttribute("InputMode", start)
end
-- Roblox's console guidelines: no chat window on Xbox / PlayStation (PC and phones keep it)
if GuiService:IsTenFootInterface() then
	pcall(function()
		local window = game:GetService("TextChatService"):WaitForChild("ChatWindowConfiguration", 10)
		if window then (window :: any).Enabled = false end
	end)
end
UserInputService.LastInputTypeChanged:Connect(function(kind)
	local mode = modeOf(kind)
	if mode and mode ~= player:GetAttribute("InputMode") then player:SetAttribute("InputMode", mode) end
end)

----------------------------------------------------------------------------
-- the focus ring: a gold outline around whatever the controller is on
----------------------------------------------------------------------------
local ring = Instance.new("Frame")
ring.Name = "AetherwakeSelection"
ring.BackgroundTransparency = 1
ring.Size = UDim2.new(1, 12, 1, 12)
ring.Position = UDim2.fromOffset(-6, -6)
local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(0, 16)
ringCorner.Parent = ring
local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = 4
ringStroke.Color = GOLD
ringStroke.Parent = ring
playerGui.SelectionImageObject = ring
-- it breathes a little, so it's easy to find on a TV across the room
RunService.Heartbeat:Connect(function()
	if GuiService.SelectedObject then
		ringStroke.Transparency = 0.15 * (0.5 + 0.5 * math.sin(os.clock() * 5))
	end
end)

----------------------------------------------------------------------------
-- which menu is open, and which button it should start on
----------------------------------------------------------------------------
-- is this really on screen? (it and everything above it visible, in an enabled ScreenGui)
local function shown(g: Instance?): boolean
	if not g or not g.Parent then return false end
	local a: Instance? = g
	while a and a ~= playerGui do
		if a:IsA("GuiObject") and not a.Visible then return false end
		if a:IsA("LayerCollector") and not a.Enabled then return false end
		a = a.Parent
	end
	return a == playerGui
end

-- the button each menu starts on (by name; otherwise the first button from the top left)
local DEFAULTS: { [string]: { string } } = {
	Orb = { "OpenOne" },                     -- the summon overlay: SUMMON 1X
	Worlds = { "FastTravel" },               -- the Galaxy Map: the big travel button
	results = { "SummonAgain", "CloseResults" }, -- the summon result screen
}
-- (a list that's longer than its box: with the focus on it, the stick / D-pad scrolls it, so
-- read-only lists like the Index, Quests and Updates can be scrolled without a mouse)
local function scrollable(d: Instance): boolean
	return d:IsA("ScrollingFrame") and d.ScrollingEnabled
		and (d.AbsoluteCanvasSize.Y > d.AbsoluteWindowSize.Y + 4 or d.AbsoluteCanvasSize.X > d.AbsoluteWindowSize.X + 4)
end
local function firstButton(root: Instance): GuiObject?
	local best: GuiObject? = nil
	local bestY, bestX = math.huge, math.huge
	for _, d in root:GetDescendants() do
		if ((d:IsA("GuiButton") and d.Selectable) or scrollable(d)) and (d :: GuiObject).AbsoluteSize.X > 4 and shown(d) then
			-- the menu's own buttons first; a long list if there are none (read-only menus);
			-- the menu's close button only if there's nothing else
			local rank = if d:FindFirstAncestor("Header") then 2 elseif d:IsA("ScrollingFrame") then 1 else 0
			local y = (d :: GuiObject).AbsolutePosition.Y + rank * 100000
			local x = d.AbsolutePosition.X
			if y < bestY - 4 or (math.abs(y - bestY) <= 4 and x < bestX) then
				best, bestY, bestX = d, y, x
			end
		end
	end
	return best
end
local function defaultFor(name: string?, root: Instance): GuiObject?
	for _, wanted in (name and DEFAULTS[name]) or {} do
		local found = root:FindFirstChild(wanted, true)
		if found and not found:IsA("GuiButton") then found = firstButton(found) end
		if found and found:IsA("GuiButton") and found.Selectable and shown(found) then return found end
	end
	return firstButton(root)
end

-- What's on screen that the controller should be in: a menu, the summon result screen, the
-- summon cinematic (nothing to focus: A skips) or nothing (playing).
local function currentRoot(): (string?, GuiObject?)
	local phase = hud:GetAttribute("SummonPhase") or "idle"
	if phase == "results" then
		local reveal = canvas:FindFirstChild("Reveal")
		return "results", reveal and reveal:FindFirstChild("ResultsLayer") :: GuiObject?
	end
	if phase == "cinematic" then return "cinematic", nil end
	local name = hud:GetAttribute("OpenPanel")
	if type(name) == "string" then return name, canvas:FindFirstChild(name) :: GuiObject? end
	return nil, nil
end

-- keeps the focus inside an open menu (it can't wander onto the HUD behind it)
local function trap(root: GuiObject)
	-- long lists can take the focus (and so be scrolled with the stick / D-pad)
	for _, d in root:GetDescendants() do
		if scrollable(d) and not (d :: ScrollingFrame).Selectable then (d :: ScrollingFrame).Selectable = true end
	end
	if root.SelectionGroup then return end
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
end

local function setFocus(g: GuiObject?)
	if GuiService.SelectedObject ~= g then
		pcall(function() GuiService.SelectedObject = g end)
	end
end

-- put the focus in the open menu (if it isn't already on one of its buttons).
-- fresh = the menu has just opened: its own start button wins, because Roblox may already have
-- moved the focus onto some other button of it by itself when the HUD behind it hid. (If the
-- player has moved the focus since we placed it, that choice is kept.)
local autoPicked: GuiObject? = nil -- the button we placed the focus on when the menu opened
local function focusRoot(fresh: boolean?)
	if not onPad() then return end
	local name, root = currentRoot()
	if root then
		trap(root)
		local sel = GuiService.SelectedObject
		local inside = sel ~= nil and sel:IsDescendantOf(root) and shown(sel)
		if inside and not fresh then return end
		if inside and fresh and autoPicked ~= nil and sel ~= autoPicked then return end
		autoPicked = defaultFor(name, root)
		setFocus(autoPicked)
	elseif name == "cinematic" then
		setFocus(nil) -- (A skips the summon: nothing may be focused)
	end
end

-- When a menu opens, remember the HUD button the focus was on (you were browsing the menu grid
-- with the D-pad); when it closes, go back there, otherwise back to the game with no focus.
local lastRoot: string? = nil
local browseFrom: GuiObject? = nil
local function onRootChanged()
	local name = currentRoot()
	if name == lastRoot then return end
	local previous = lastRoot
	lastRoot = name
	if name == nil then
		-- (a moment later: the HUD behind a full-screen menu comes back just after it closes)
		task.delay(0.05, function()
			if currentRoot() ~= nil then return end -- (another menu opened meanwhile)
			if onPad() and browseFrom and shown(browseFrom) then
				setFocus(browseFrom)
			else
				browseFrom = nil
				setFocus(nil)
			end
		end)
		return
	end
	if previous == nil then
		local sel = GuiService.SelectedObject
		browseFrom = if sel and sel:IsDescendantOf(canvas) and shown(sel) then sel else nil
	end
	-- (menus fill in their buttons as they open, some a moment later)
	autoPicked = nil
	task.delay(0.05, focusRoot, true)
	task.delay(0.35, focusRoot, true)
end
hud:GetAttributeChangedSignal("OpenPanel"):Connect(onRootChanged)
hud:GetAttributeChangedSignal("SummonPhase"):Connect(onRootChanged)

-- Safety net, 4 times a second: the focus never stays on something that vanished (closed,
-- hidden, destroyed), and while a menu is open the focus is inside it.
task.spawn(function()
	while true do
		task.wait(0.25)
		local sel = GuiService.SelectedObject
		local name, root = currentRoot()
		if sel and sel:IsDescendantOf(playerGui) and not shown(sel) then
			if root and onPad() then setFocus(defaultFor(name, root)) else setFocus(nil) end
		elseif root and onPad() and not (sel and sel:IsDescendantOf(root)) then
			focusRoot()
		end
	end
end)

----------------------------------------------------------------------------
-- buttons (bound once; each one passes its button on when it has nothing to do)
----------------------------------------------------------------------------
-- B: close the result screen or the open menu; when browsing the HUD, leave it
ContextActionService:BindActionAtPriority("AetherwakePadBack", function(_, state)
	if state ~= BEGIN then return PASS end
	local name = currentRoot()
	if name and name ~= "cinematic" then
		local ok, closed = pcall(function() return command:Invoke("back") end)
		if ok and closed then return SINK end
	end
	local sel = GuiService.SelectedObject
	if sel and sel:IsDescendantOf(canvas) then
		browseFrom = nil
		setFocus(nil)
		return SINK
	end
	return PASS
end, false, Enum.ContextActionPriority.High.Value + 5, Enum.KeyCode.ButtonB)

-- Y: the Champions menu (open / close)
ContextActionService:BindAction("AetherwakePadChampions", function(_, state)
	if state ~= BEGIN then return PASS end
	local name = currentRoot()
	if name == "cinematic" then return PASS end
	pcall(function() command:Invoke("toggle", "Champions") end)
	return SINK
end, false, Enum.KeyCode.ButtonY)

-- D-pad up while playing: put the focus on the menu grid (Shop, Champions, Index, Teleport...)
-- so every menu and HUD button can be reached. (Inside menus the D-pad moves the focus as usual.)
ContextActionService:BindAction("AetherwakePadMenu", function(_, state)
	if state ~= BEGIN then return PASS end
	if currentRoot() ~= nil or GuiService.SelectedObject ~= nil then return PASS end
	local first = canvas:FindFirstChild("ShopButton", true)
	if first and shown(first) then
		setFocus(first :: GuiObject)
		return SINK
	end
	return PASS
end, false, Enum.KeyCode.DPadUp)

-- LT: Auto Attack on / off (opens the Store if you don't have the pass yet, like the button)
ContextActionService:BindAction("AetherwakePadAuto", function(_, state)
	if state ~= BEGIN then return PASS end
	if currentRoot() ~= nil then return PASS end
	pcall(function() command:Invoke("autoAttack") end)
	return SINK
end, false, Enum.KeyCode.ButtonL2)

----------------------------------------------------------------------------
-- what the buttons do, shown with the controller's own pictures (Roblox picks Xbox or
-- PlayStation ones): a legend while playing, and badges on buttons
----------------------------------------------------------------------------
local function padImage(key: Enum.KeyCode): string
	local ok, image = pcall(function() return UserInputService:GetImageForKeyCode(key) end)
	return if ok and type(image) == "string" then image else ""
end

local legendGui = Instance.new("ScreenGui")
legendGui.Name = "ControllerHints"
legendGui.ResetOnSpawn = false
legendGui.IgnoreGuiInset = true
legendGui.DisplayOrder = 1
legendGui.Parent = playerGui
local legend = Instance.new("Frame")
legend.Name = "Legend"
legend.AnchorPoint = Vector2.new(0, 1)
legend.AutomaticSize = Enum.AutomaticSize.X
legend.Size = UDim2.fromOffset(0, 40)
legend.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
legend.BackgroundTransparency = 0.25
legend.Visible = false
legend.Parent = legendGui
local legendCorner = Instance.new("UICorner")
legendCorner.CornerRadius = UDim.new(0, 12)
legendCorner.Parent = legend
local legendPad = Instance.new("UIPadding")
legendPad.PaddingLeft, legendPad.PaddingRight = UDim.new(0, 10), UDim.new(0, 12)
legendPad.Parent = legend
local legendList = Instance.new("UIListLayout")
legendList.FillDirection = Enum.FillDirection.Horizontal
legendList.VerticalAlignment = Enum.VerticalAlignment.Center
legendList.Padding = UDim.new(0, 14)
legendList.SortOrder = Enum.SortOrder.LayoutOrder
legendList.Parent = legend
local legendScale = Instance.new("UIScale")
legendScale.Parent = legend
local LEGEND = {
	{ keys = { Enum.KeyCode.ButtonY }, text = "Champions" },
	{ keys = { Enum.KeyCode.DPadUp }, text = "Menu" },
	{ keys = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }, text = "Target" },
	{ keys = { Enum.KeyCode.ButtonR2 }, text = "Dash" },
	{ keys = { Enum.KeyCode.ButtonL2 }, text = "Auto" },
}
for i, item in LEGEND do
	local entry = Instance.new("Frame")
	entry.BackgroundTransparency = 1
	entry.AutomaticSize = Enum.AutomaticSize.X
	entry.Size = UDim2.fromOffset(0, 30)
	entry.LayoutOrder = i
	entry.Parent = legend
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 4)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = entry
	for k, key in item.keys do
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(28, 28)
		icon.Image = padImage(key)
		icon.LayoutOrder = k
		icon.Parent = entry
	end
	local words = Instance.new("TextLabel")
	words.BackgroundTransparency = 1
	words.Font = Enum.Font.FredokaOne
	words.TextSize = 18
	words.TextColor3 = Color3.new(1, 1, 1)
	words.Text = item.text
	words.AutomaticSize = Enum.AutomaticSize.X
	words.Size = UDim2.fromOffset(0, 28)
	words.LayoutOrder = 10
	local outline = Instance.new("UIStroke")
	outline.Thickness = 1.5
	outline.Parent = words
	words.Parent = entry
end
-- same scaling as the HUD (designed at 1280 x 720), inside the TV safe area on consoles,
-- bottom left (under the menu grid, clear of the AUTO buttons in the middle)
local function placeLegend()
	local vp = workspace.CurrentCamera.ViewportSize
	local margin = if GuiService:IsTenFootInterface() then 0.05 else 0
	local sc = math.clamp(math.min(vp.X * (1 - margin * 2) / 1280, vp.Y * (1 - margin * 2) / 720), 0.5, 2)
	legendScale.Scale = sc
	legend.Position = UDim2.fromOffset(vp.X * margin + 14 * sc, vp.Y * (1 - margin) - 14 * sc)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placeLegend)
placeLegend()

-- only while playing with a controller (not over menus, summons or while browsing the HUD)
local function refreshLegend()
	legend.Visible = onPad() and currentRoot() == nil and GuiService.SelectedObject == nil
end

-- badges: the button that does the same thing as this on-screen button
local BADGES: { [string]: Enum.KeyCode } = {
	SkipButton = Enum.KeyCode.ButtonA,
	CloseResults = Enum.KeyCode.ButtonB,
	CloseSummon = Enum.KeyCode.ButtonB,
	BackButton = Enum.KeyCode.ButtonB,
	ChampionsButton = Enum.KeyCode.ButtonY,
	AutoButton = Enum.KeyCode.ButtonL2,
}
local badges: { ImageLabel } = {}
local function addBadge(button: GuiObject, key: Enum.KeyCode)
	if button:FindFirstChild("PadBadge") then return end
	local badge = Instance.new("ImageLabel")
	badge.Name = "PadBadge"
	badge.BackgroundTransparency = 1
	badge.Image = padImage(key)
	badge.Size = UDim2.fromOffset(28, 28)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(2, 2) -- (the top left corner)
	badge.ZIndex = button.ZIndex + 5
	badge.Visible = onPad()
	badge.Parent = button
	table.insert(badges, badge)
end
local function scanBadges()
	for _, d in canvas:GetDescendants() do
		if d:IsA("GuiButton") then
			local key = BADGES[d.Name]
			-- every menu's X (the close button in its header) closes with B
			if not key and d.Parent and d.Parent.Name == "Header" and (d :: any).Text == "X" then key = Enum.KeyCode.ButtonB end
			if key then addBadge(d, key) end
		end
	end
end
local function refreshBadges()
	local pad = onPad()
	for _, b in badges do b.Visible = pad end
end
task.delay(2, scanBadges) -- (the HUD builds its menus when it starts)

player:GetAttributeChangedSignal("InputMode"):Connect(function()
	if onPad() then
		focusRoot()
	else
		-- mouse / touch: no focus ring
		local sel = GuiService.SelectedObject
		if sel and sel:IsDescendantOf(playerGui) then setFocus(nil) end
		browseFrom = nil
	end
	if #badges == 0 then scanBadges() end
	refreshBadges()
	refreshLegend()
end)
hud:GetAttributeChangedSignal("OpenPanel"):Connect(refreshLegend)
hud:GetAttributeChangedSignal("SummonPhase"):Connect(refreshLegend)
GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(refreshLegend)
refreshLegend()
