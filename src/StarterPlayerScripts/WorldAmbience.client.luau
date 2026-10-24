-- WorldAmbience (client): gives every place its own mood, without changing the bright style.
--
--   * one lighting profile per place (hub + 3 worlds): sky light, sun colour and time of day,
--     haze (Atmosphere), colour grade (ColorCorrection), Bloom and SunRays
--   * set instantly when you join, then tweened over ~1.5 s whenever your World attribute changes
--   * ONE gentle ambient particle emitter that follows the camera: petals in the hub, crystal
--     motes in Verdant Rift, sea sparkles in Coral Harbor, drifting glyph sparks in Skyforge
--
-- Rules it keeps:
--   * never touches Lighting.ExposureCompensation or the "SummonGrade" colour correction
--     (both belong to the summon cinematic)
--   * Atmosphere.Color uses the same per-world colours the HUD already tweens, so they never fight
--   * cheap: one RenderStepped connection that only moves one invisible part now and then

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local MOTE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" -- built-in texture the game already uses
local BOX = Vector3.new(64, 22, 64) -- the space around the camera where motes appear
local BOX_LIFT = 7                  -- centre that space a little above the player's head
local MOVE_STEP = 2                 -- only re-centre it after the camera moved this many studs

local rgb = Color3.fromRGB

-- NumberSequence from { {time, value}, ... }
local function curve(points: { { number } }): NumberSequence
	local keys = {}
	for i, p in points do keys[i] = NumberSequenceKeypoint.new(p[1], p[2]) end
	return NumberSequence.new(keys)
end

-- Each profile: `look` = properties per Lighting object, `motes` = ParticleEmitter properties.
-- Rates stay at 8 per second or less (performance budget).
local PROFILES = {
	-- Champion City: warm, friendly midday
	[0] = {
		look = {
			lighting = { Ambient = rgb(122, 114, 112), OutdoorAmbient = rgb(162, 154, 150), ClockTime = 13.4,
				Brightness = 2.6, ColorShift_Top = rgb(255, 238, 214) },
			atmosphere = { Density = 0.27, Offset = 0.15, Color = rgb(210, 230, 255), Decay = rgb(150, 165, 210),
				Glare = 0.28, Haze = 0.85 },
			grade = { TintColor = rgb(255, 251, 244), Saturation = 0.14, Contrast = 0.05 },
			bloom = { Intensity = 0.6, Size = 24, Threshold = 1.6 },
			sunRays = { Intensity = 0.035, Spread = 0.15 },
		},
		motes = { -- drifting sakura petals
			Color = ColorSequence.new(rgb(255, 190, 215), rgb(255, 228, 236)),
			LightEmission = 0.2, LightInfluence = 0.6,
			Size = curve({ { 0, 0 }, { 0.15, 0.32 }, { 0.85, 0.28 }, { 1, 0 } }),
			Transparency = curve({ { 0, 1 }, { 0.15, 0.15 }, { 0.85, 0.2 }, { 1, 1 } }),
			Lifetime = NumberRange.new(7, 10), Rate = 5, Speed = NumberRange.new(0.5, 1.2),
			Acceleration = Vector3.new(0.35, -0.45, 0.15), Drag = 0.6,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-80, 80),
		},
	},
	-- Verdant Rift: fresh green-cyan air with a slight crystal glow (more bloom on Neon)
	[1] = {
		look = {
			lighting = { Ambient = rgb(104, 122, 124), OutdoorAmbient = rgb(142, 170, 168), ClockTime = 12.2,
				Brightness = 2.5, ColorShift_Top = rgb(225, 255, 240) },
			atmosphere = { Density = 0.3, Offset = 0.18, Color = rgb(200, 235, 255), Decay = rgb(105, 175, 190),
				Glare = 0.18, Haze = 1.05 },
			grade = { TintColor = rgb(244, 255, 251), Saturation = 0.17, Contrast = 0.06 },
			bloom = { Intensity = 0.75, Size = 26, Threshold = 1.45 },
			sunRays = { Intensity = 0.025, Spread = 0.12 },
		},
		motes = { -- violet-to-cyan crystal motes rising slowly, twinkling
			Color = ColorSequence.new(rgb(190, 145, 255), rgb(130, 255, 225)),
			LightEmission = 0.9, LightInfluence = 0.15,
			Size = curve({ { 0, 0 }, { 0.2, 0.3 }, { 0.5, 0.18 }, { 0.8, 0.3 }, { 1, 0 } }),
			Transparency = curve({ { 0, 1 }, { 0.2, 0.1 }, { 0.8, 0.2 }, { 1, 1 } }),
			Lifetime = NumberRange.new(6, 9), Rate = 6, Speed = NumberRange.new(0.2, 0.6),
			Acceleration = Vector3.new(0, 0.22, 0), Drag = 0.4,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40),
		},
	},
	-- Coral Harbor: warm golden sea light (later sun, golden haze, stronger sun rays)
	[2] = {
		look = {
			lighting = { Ambient = rgb(128, 114, 102), OutdoorAmbient = rgb(176, 156, 138), ClockTime = 15.9,
				Brightness = 2.7, ColorShift_Top = rgb(255, 214, 165) },
			atmosphere = { Density = 0.27, Offset = 0.12, Color = rgb(255, 225, 200), Decay = rgb(230, 165, 120),
				Glare = 0.5, Haze = 1 },
			grade = { TintColor = rgb(255, 246, 232), Saturation = 0.18, Contrast = 0.06 },
			bloom = { Intensity = 0.62, Size = 26, Threshold = 1.55 },
			sunRays = { Intensity = 0.06, Spread = 0.2 },
		},
		motes = { -- quick golden-white sparkles, like sun glinting off the sea
			Color = ColorSequence.new(rgb(255, 242, 200), rgb(195, 245, 255)),
			LightEmission = 1, LightInfluence = 0,
			Size = curve({ { 0, 0 }, { 0.3, 0.38 }, { 0.5, 0.12 }, { 0.7, 0.34 }, { 1, 0 } }),
			Transparency = curve({ { 0, 1 }, { 0.25, 0.05 }, { 0.75, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2.5, 4), Rate = 7, Speed = NumberRange.new(0.1, 0.35),
			Acceleration = Vector3.new(0.3, 0.05, 0), Drag = 0,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-30, 30),
		},
	},
	-- Skyforge Academy: cool, crisp blue-white high-altitude light (thin haze, a touch more contrast)
	[3] = {
		look = {
			lighting = { Ambient = rgb(112, 120, 140), OutdoorAmbient = rgb(158, 170, 198), ClockTime = 11.2,
				Brightness = 2.8, ColorShift_Top = rgb(226, 238, 255) },
			atmosphere = { Density = 0.22, Offset = 0.06, Color = rgb(215, 210, 255), Decay = rgb(120, 160, 230),
				Glare = 0.15, Haze = 0.5 },
			grade = { TintColor = rgb(243, 248, 255), Saturation = 0.08, Contrast = 0.09 },
			bloom = { Intensity = 0.5, Size = 22, Threshold = 1.65 },
			sunRays = { Intensity = 0.03, Spread = 0.12 },
		},
		motes = { -- pale blue glyph sparks drifting upward and turning
			Color = ColorSequence.new(rgb(205, 225, 255), rgb(255, 255, 255)),
			LightEmission = 0.8, LightInfluence = 0.2,
			Size = curve({ { 0, 0 }, { 0.2, 0.26 }, { 0.8, 0.22 }, { 1, 0 } }),
			Transparency = curve({ { 0, 1 }, { 0.2, 0.15 }, { 0.8, 0.25 }, { 1, 1 } }),
			Lifetime = NumberRange.new(6, 8), Rate = 5, Speed = NumberRange.new(0.4, 0.9),
			Acceleration = Vector3.new(0.1, 0.3, 0), Drag = 0.5,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(25, 70),
		},
	},
}

-- the Lighting objects a profile talks to (looked up each time: cheap, and survives edits)
local function lookTargets(): { [string]: Instance? }
	local grade = Lighting:FindFirstChild("ColorCorrection") -- our grade, NOT the cinematic's SummonGrade
	if grade and not grade:IsA("ColorCorrectionEffect") then grade = nil end
	return {
		lighting = Lighting,
		atmosphere = Lighting:FindFirstChildOfClass("Atmosphere"),
		grade = grade,
		bloom = Lighting:FindFirstChildOfClass("BloomEffect"),
		sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect"),
	}
end

local running: { Tween } = {}

local function applyLook(look, instant: boolean)
	-- stop a fade that is still playing (quick world hops) so two fades never fight
	for _, t in running do t:Cancel() end
	table.clear(running)
	local targets = lookTargets()
	for key, props in look do
		local inst = targets[key]
		if inst then
			if instant then
				for prop, value in props do (inst :: any)[prop] = value end
			else
				local t = TweenService:Create(inst, FADE, props)
				table.insert(running, t)
				t:Play()
			end
		end
	end
end

-- the ambient motes: one invisible box part in the camera (client-only), one emitter
local motesPart: Part? = nil
local emitter: ParticleEmitter? = nil
local currentId = 0

local function setMotes(settings)
	if not emitter then return end
	-- particles already in the air keep their old look and fade out: a natural cross-fade
	for prop, value in settings do (emitter :: any)[prop] = value end
end

local function ensureMotes(cam: Camera)
	if motesPart and motesPart.Parent then
		if motesPart.Parent ~= cam then motesPart.Parent = cam end
		return
	end
	local p = Instance.new("Part")
	p.Name = "AmbientMotes"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = BOX
	local e = Instance.new("ParticleEmitter")
	e.Name = "Motes"
	e.Texture = MOTE_TEXTURE
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.SpreadAngle = Vector2.new(180, 180)
	e.LockedToPart = false -- motes stay where they were born, so moving the box never drags them
	e.Parent = p
	p.Parent = cam
	motesPart, emitter = p, e
	setMotes(PROFILES[currentId].motes)
end

-- which profile: the World attribute (0 = hub, 1-3 = worlds); unknown or missing = hub
local function worldId(): number
	local w = player:GetAttribute("World")
	if type(w) == "number" and PROFILES[w] then return w end
	return 0
end

local seenWorld = player:GetAttribute("World") ~= nil

local function refresh(instant: boolean)
	local id = worldId()
	if id == currentId and not instant then return end
	currentId = id
	applyLook(PROFILES[id].look, instant)
	setMotes(PROFILES[id].motes)
end

refresh(true) -- on join: no fade, just the right mood
player:GetAttributeChangedSignal("World"):Connect(function()
	-- the very first World value (save loading) is also set instantly; real travel fades
	local instant = not seenWorld or player:GetAttribute("DataLoaded") ~= true
	seenWorld = true
	refresh(instant)
end)

local lastCenter = Vector3.new(math.huge, 0, 0)
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	if not (motesPart and motesPart.Parent == cam) then
		ensureMotes(cam)
		lastCenter = Vector3.new(math.huge, 0, 0) -- (a new or moved box: place it on this frame)
	end
	local part = motesPart
	if not part then return end
	-- follow the camera's focus (the player), but only move the box every few studs
	local center = cam.Focus.Position + Vector3.new(0, BOX_LIFT, 0)
	if (center - lastCenter).Magnitude > MOVE_STEP then
		lastCenter = center
		part.CFrame = CFrame.new(center)
	end
end)
