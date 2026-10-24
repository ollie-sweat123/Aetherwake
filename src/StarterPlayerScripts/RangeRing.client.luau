-- RangeRing (client): a thin glowing ring on the ground around your feet that
-- shows how far Auto Attack reaches. Only shown once you own the Auto Attack pass.
-- Bright and pulsing while Auto Attack is ON, faint while it is OFF.
-- The radius is the AttackRange attribute the server publishes (grows with the
-- Range upgrade). Purely visual: only you can see your ring.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local SEGMENTS = 48             -- small neon bricks that together make the circle
local DEFAULT_RANGE = 40        -- used until the server sends AttackRange
local COLOR = Color3.fromRGB(110, 230, 255)
local THICKNESS = 0.3           -- how wide the ring line is (studs)
local HEIGHT = 0.08             -- how tall each brick is (studs)
local LIFT = 0.06               -- float just above the floor so it never flickers into it
local SPIN_SPEED = 0.25         -- radians per second while Auto Attack is on

-- the bricks live in their own client-only folder
local folder = Instance.new("Folder")
folder.Name = "ClientRangeRing"
folder.Parent = workspace

local bricks: { BasePart } = {}
local cframes: { CFrame } = {}
for i = 1, SEGMENTS do
	local p = Instance.new("Part")
	p.Name = "Segment" .. i
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false -- clicks/rays go straight through it
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = COLOR
	p.Size = Vector3.new(THICKNESS, HEIGHT, 1)
	p.Transparency = 1 -- hidden until we know you own the pass
	p.Parent = folder
	bricks[i] = p
	cframes[i] = CFrame.identity
end

local hidden = true
local lastRadius = -1
local lastTransparency = 1
local groundY: number? = nil
local spin = 0

local function setTransparency(t: number)
	if math.abs(t - lastTransparency) < 0.005 then return end -- skip tiny changes (cheaper)
	lastTransparency = t
	for _, p in bricks do p.Transparency = t end
end

local function hide()
	if hidden then return end
	hidden = true
	setTransparency(1)
end

local function currentRange(): number
	local r = player:GetAttribute("AttackRange")
	if typeof(r) ~= "number" or r ~= r or r <= 0 then return DEFAULT_RANGE end
	return math.clamp(r, 4, 400)
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if player:GetAttribute("PassAutoAttack") ~= true or not root or not hum or hum.Health <= 0 then
		hide()
		groundY = nil
		return
	end

	-- the floor under your feet: root height minus hip height and half the root.
	-- While jumping we keep the last floor height so the ring stays on the ground.
	local feetY = root.Position.Y - hum.HipHeight - root.Size.Y / 2
	if groundY == nil or hum.FloorMaterial ~= Enum.Material.Air then groundY = feetY end
	local y = (groundY :: number) + LIFT

	local radius = currentRange()
	if radius ~= lastRadius then
		-- each brick is one straight chord of the circle (+2% so the joins don't show gaps)
		local length = 2 * radius * math.sin(math.pi / SEGMENTS) * 1.02
		for _, p in bricks do p.Size = Vector3.new(THICKNESS, HEIGHT, length) end
		lastRadius = radius
	end

	local on = player:GetAttribute("AutoAttack") == true
	if on then
		spin = (spin + dt * SPIN_SPEED) % (math.pi * 2)
		-- bright, gently pulsing
		setTransparency(0.15 + 0.25 * (0.5 + 0.5 * math.sin(os.clock() * 4)))
	else
		setTransparency(0.8) -- faint: you own the pass but Auto Attack is switched off
	end
	hidden = false

	-- place every brick around your feet (one bulk move = cheap)
	local cx, cz = root.Position.X, root.Position.Z
	for i = 1, SEGMENTS do
		local a = (i - 0.5) / SEGMENTS * math.pi * 2 + spin
		-- turning by -a lines the brick's long side up with the circle at that point
		cframes[i] = CFrame.new(cx + math.cos(a) * radius, y, cz + math.sin(a) * radius) * CFrame.Angles(0, -a, 0)
	end
	workspace:BulkMoveTo(bricks, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end)
