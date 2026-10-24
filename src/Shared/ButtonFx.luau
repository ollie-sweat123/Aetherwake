-- ButtonFx: the shared "feel" of every button (HUD, quests, dash).
-- * hover (mouse) or controller selection: the button grows a little and its gloss brightens
-- * press: it squashes while held, then springs back (bounce) when the click lands
-- * gloss: a soft white shine over the top half, like the panel headers
-- One UIScale ("ClickScale") per button does all the sizing, so the effects never fight.
-- Purely visual: nothing here changes what a button does.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ButtonFx = {}

local HOVER_SCALE = 1.06
local PRESS_SCALE = 0.92
local GLOSS_IDLE = 0.72 -- (gloss BackgroundTransparency at rest / under the mouse)
local GLOSS_HOVER = 0.5

local hovered: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local pressed: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function tween(inst: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad), goal):Play()
end

function ButtonFx.scaleOf(g: GuiObject): UIScale
	local sc = g:FindFirstChild("ClickScale")
	if sc and sc:IsA("UIScale") then return sc end
	local new = Instance.new("UIScale")
	new.Name = "ClickScale"
	new.Parent = g
	return new
end

function ButtonFx.isHovered(g: GuiObject): boolean
	return hovered[g] == true
end

-- the size the button should settle at right now
local function restScale(g: GuiObject): number
	return if hovered[g] then HOVER_SCALE else 1
end

local function setGloss(g: GuiObject, bright: boolean)
	local gloss = g:FindFirstChild("Gloss")
	if gloss and gloss:IsA("Frame") then
		tween(gloss, 0.12, { BackgroundTransparency = if bright then GLOSS_HOVER else GLOSS_IDLE })
	end
end

-- The click "pop": squash, then spring back to the hover / rest size.
function ButtonFx.bounce(g: GuiObject)
	local sc = ButtonFx.scaleOf(g)
	sc.Scale = 0.88
	tween(sc, 0.2, { Scale = restScale(g) }, Enum.EasingStyle.Back)
end

-- Hover / select / press feedback. `target` is what grows (the button itself by default; some
-- buttons scale a holder around them instead).
function ButtonFx.feedback(b: GuiButton, target: GuiObject?)
	local g = target or b
	local function enter()
		hovered[g] = true
		setGloss(b, true)
		if not pressed[g] then tween(ButtonFx.scaleOf(g), 0.12, { Scale = HOVER_SCALE }) end
	end
	local function leave()
		hovered[g] = nil
		pressed[g] = nil
		setGloss(b, false)
		tween(ButtonFx.scaleOf(g), 0.12, { Scale = 1 })
	end
	b.MouseEnter:Connect(function()
		-- (no hover on touch screens: a tap would leave the button stuck big)
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		enter()
	end)
	b.MouseLeave:Connect(leave)
	b.SelectionGained:Connect(enter) -- (controller focus counts as hover)
	b.SelectionLost:Connect(leave)
	b.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
			or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA) then
			pressed[g] = true
			tween(ButtonFx.scaleOf(g), 0.07, { Scale = PRESS_SCALE })
		end
	end)
	b.InputEnded:Connect(function(input: InputObject)
		if not pressed[g] then return end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1 then
			pressed[g] = nil
			tween(ButtonFx.scaleOf(g), 0.14, { Scale = restScale(g) }, Enum.EasingStyle.Back)
		end
	end)
end

-- A soft shine across the top half of a button (rounded like the button). It sits under the
-- button's labels, and brightens on hover (see feedback).
function ButtonFx.gloss(b: GuiObject, inset: number?): Frame
	local old = b:FindFirstChild("Gloss")
	if old and old:IsA("Frame") then return old end
	local pad = inset or 3
	local frame = Instance.new("Frame")
	frame.Name = "Gloss"
	frame.Active = false
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = GLOSS_IDLE
	frame.Position = UDim2.fromOffset(pad, pad)
	frame.Size = UDim2.new(1, -pad * 2, 0.48, -pad)
	frame.ZIndex = 0 -- (ZIndexBehavior is Sibling everywhere: under the button's text and icons)
	local c = b:FindFirstChildOfClass("UICorner")
	if c then
		local r = Instance.new("UICorner")
		r.CornerRadius = UDim.new(c.CornerRadius.Scale, math.max(c.CornerRadius.Offset - pad, 2))
		r.Parent = frame
	end
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = frame
	frame.Parent = b
	return frame
end

-- A gentle top-light / bottom-shade on the button's own fill, for depth. (Kept light: on a
-- TextButton it also tints the bottom of the button's own text a touch.)
function ButtonFx.shade(b: GuiObject, bottom: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Name = "Shade"
	g.Rotation = 90
	local v = bottom or 0.72
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(v, v, v))
	g.Parent = b
	return g
end

-- A border that follows the button's colour (a darker shade of it), even when the button is
-- recoloured later (Equip -> Unequip, a greyed-out BUY...).
function ButtonFx.tintedEdge(b: GuiObject, s: UIStroke, darken: number?)
	local amount = darken or 0.6
	local function paint() s.Color = b.BackgroundColor3:Lerp(Color3.new(0, 0, 0), amount) end
	paint()
	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(paint)
end

return ButtonFx
