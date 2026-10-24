-- CharacterKit (dev tool): builds Roblox-native anime characters.
--   * R15 body (CreateHumanoidModelFromDescription) with body colours
--   * accessories modelled in Blender, rebuilt here from vertex data (EditableMesh)
--   * anime face painted pixel-by-pixel into an EditableImage
local Players = game:GetService("Players")
local AssetService = game:GetService("AssetService")

local K = {}

local MATERIAL = {
	plastic = Enum.Material.SmoothPlastic,
	metal = Enum.Material.Metal,
	neon = Enum.Material.Neon,
}

-- R15 body at the origin: feet on y = 0, facing -Z (same layout the Blender side uses)
function K.NewRig(look)
	local d = Instance.new("HumanoidDescription")
	local skin = Color3.fromHex(look.skin)
	d.HeadColor = skin
	d.TorsoColor = Color3.fromHex(look.top or look.outfit or "#888888")
	d.LeftArmColor = Color3.fromHex(look.sleeve or look.top or "#888888")
	d.RightArmColor = d.LeftArmColor
	d.LeftLegColor = Color3.fromHex(look.pants or "#444444")
	d.RightLegColor = d.LeftLegColor
	local rig = Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	local animate = rig:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	for _, dec in rig.Head:GetChildren() do
		if dec:IsA("Decal") then dec:Destroy() end
	end
	-- hands/feet colours (gloves, boots)
	for _, n in { "LeftHand", "RightHand" } do rig[n].Color = Color3.fromHex(look.gloves or look.skin) end
	for _, n in { "LeftFoot", "RightFoot" } do rig[n].Color = Color3.fromHex(look.boots or "#2a2630") end
	if look.boots then
		for _, n in { "LeftLowerLeg", "RightLowerLeg" } do rig[n].Color = Color3.fromHex(look.boots) end
	end
	-- swap the dynamic head (it has sculpted eye sockets and ignores decals) for a smooth classic head
	local h = rig.Head
	h.TextureID = ""
	for _, n in { "FaceControls" } do local x = h:FindFirstChild(n); if x then x:Destroy() end end
	h.Transparency = 1
	local head = Instance.new("Part")
	head.Name = "AnimeHead"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = skin
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false; head.CanQuery = false; head.CanTouch = false; head.Massless = true
	head.CFrame = h.CFrame
	local sm = Instance.new("SpecialMesh"); sm.MeshType = Enum.MeshType.Head; sm.Scale = Vector3.new(1.25, 1.25, 1.25); sm.Parent = head
	local hw = Instance.new("WeldConstraint"); hw.Part0 = h; hw.Part1 = head; hw.Parent = head
	head.Parent = rig
	local hum = rig:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	rig.HumanoidRootPart.Anchored = true
	-- put the feet on y = 0
	local cf, size = rig:GetBoundingBox()
	rig:PivotTo(rig:GetPivot() + Vector3.new(-cf.X, -(cf.Y - size.Y / 2), -cf.Z))
	return rig
end

local function nums(s)
	local t = {}
	for n in string.gmatch(s, "-?%d+") do t[#t + 1] = tonumber(n) end
	return t
end

-- g = { j = joint part name, c = "#hex", k = "plastic"|"metal"|"neon", p = {x,y,z}, v = "...", f = "..." }
function K.MakeMeshPart(g)
	local em = AssetService:CreateEditableMesh()
	local vs = nums(g.v)
	local ids = table.create(#vs // 3)
	for i = 1, #vs, 3 do
		ids[#ids + 1] = em:AddVertex(Vector3.new(vs[i], vs[i + 1], vs[i + 2]) / 100)
	end
	local fs = nums(g.f)
	for i = 1, #fs, 3 do
		em:AddTriangle(ids[fs[i] + 1], ids[fs[i + 1] + 1], ids[fs[i + 2] + 1])
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em), { CollisionFidelity = Enum.CollisionFidelity.Box })
	mp.Color = Color3.fromHex(g.c)
	mp.Material = MATERIAL[g.k] or Enum.Material.SmoothPlastic
	mp.CanCollide = false
	mp.CanTouch = false
	mp.CanQuery = false
	mp.Massless = true
	mp.CastShadow = true
	mp.CFrame = CFrame.new(g.p[1], g.p[2], g.p[3])
	return mp
end

local B64 = {}
do
	local A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do B64[string.byte(A, i)] = i - 1 end
end
local function unpackInts(str, width, offset)
	local out = table.create(#str // width)
	for i = 1, #str, width do
		local n = 0
		for k = 0, width - 1 do n = n * 64 + B64[string.byte(str, i + k)] end
		out[#out + 1] = n - offset
	end
	return out
end

-- packed group: v = base64 2-char coords (x100, +2048), f = base64 indices (w chars each)
function K.MakeMeshPartPacked(g)
	local em = AssetService:CreateEditableMesh()
	local vs = unpackInts(g.v, 2, 2048)
	local ids = table.create(#vs // 3)
	for i = 1, #vs, 3 do
		ids[#ids + 1] = em:AddVertex(Vector3.new(vs[i], vs[i + 1], vs[i + 2]) / 100)
	end
	local fs = unpackInts(g.f, g.w or 2, 0)
	for i = 1, #fs, 3 do
		em:AddTriangle(ids[fs[i] + 1], ids[fs[i + 1] + 1], ids[fs[i + 2] + 1])
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em), { CollisionFidelity = Enum.CollisionFidelity.Box })
	mp.Color = Color3.fromHex(g.c)
	mp.Material = MATERIAL[g.k] or Enum.Material.SmoothPlastic
	mp.CanCollide = false; mp.CanTouch = false; mp.CanQuery = false; mp.Massless = true
	mp.CFrame = CFrame.new(g.p[1], g.p[2], g.p[3])
	return mp, em
end

function K.Fetch(name)
	local HttpService = game:GetService("HttpService")
	local body = HttpService:GetAsync("http://127.0.0.1:8765/" .. name .. ".json", true)
	return HttpService:JSONDecode(body)
end

function K.AddAccessories(rig, groups)
	local folder = rig:FindFirstChild("Accessories") or Instance.new("Folder")
	folder.Name = "Accessories"
	folder.Parent = rig
	for i, g in groups do
		local mp = if g.w then K.MakeMeshPartPacked(g) else K.MakeMeshPart(g)
		mp.Name = g.j .. "_" .. i
		local part = rig:FindFirstChild(g.j) or rig.UpperTorso
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = mp
		w.Parent = mp
		mp.Parent = folder
		mp:SetAttribute("Joint", g.j)
	end
end

----------------------------------------------------------------------------
-- tiny rasterizer for anime faces (256 x 256 RGBA)
----------------------------------------------------------------------------
local S = 256
local function newCanvas()
	return buffer.create(S * S * 4)
end
local function blend(buf, x, y, r, g, b, a)
	if x < 0 or y < 0 or x >= S or y >= S or a <= 0 then return end
	local i = (y * S + x) * 4
	local da = buffer.readu8(buf, i + 3) / 255
	local oa = a + da * (1 - a)
	if oa <= 0 then return end
	local function ch(off, c)
		local dc = buffer.readu8(buf, i + off) / 255
		buffer.writeu8(buf, i + off, math.floor(((c * a + dc * da * (1 - a)) / oa) * 255 + 0.5))
	end
	ch(0, r); ch(1, g); ch(2, b)
	buffer.writeu8(buf, i + 3, math.floor(oa * 255 + 0.5))
end
local function hex(h)
	local c = Color3.fromHex(h)
	return c.R, c.G, c.B
end
-- filled ellipse with soft edge; optional clip(x, y) -> bool
local function ellipse(buf, cx, cy, rx, ry, col, alpha, clip, rot)
	local r, g, b = hex(col)
	alpha = alpha or 1
	local cr, sr = math.cos(rot or 0), math.sin(rot or 0)
	local ext = math.max(rx, ry) + 2
	for y = math.floor(cy - ext), math.ceil(cy + ext) do
		for x = math.floor(cx - ext), math.ceil(cx + ext) do
			local dx, dy = x + 0.5 - cx, y + 0.5 - cy
			local lx, ly = dx * cr + dy * sr, -dx * sr + dy * cr
			local d = math.sqrt((lx / rx) ^ 2 + (ly / ry) ^ 2)
			local edge = math.clamp((1 - d) * math.min(rx, ry) + 0.5, 0, 1)
			if edge > 0 and (not clip or clip(x, y)) then blend(buf, x, y, r, g, b, edge * alpha) end
		end
	end
end
-- brush stroke along an elliptical arc (angles in degrees, 0 = right, 90 = down)
local function arc(buf, cx, cy, rx, ry, a0, a1, w0, w1, col, alpha)
	local steps = math.max(12, math.floor(math.abs(a1 - a0) / 3))
	for i = 0, steps do
		local t = i / steps
		local a = math.rad(a0 + (a1 - a0) * t)
		local w = w0 + (w1 - w0) * t
		ellipse(buf, cx + math.cos(a) * rx, cy + math.sin(a) * ry, w, w, col, alpha)
	end
end
local function line(buf, x0, y0, x1, y1, w0, w1, col, alpha)
	local steps = math.max(8, math.floor(math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / 1.5))
	for i = 0, steps do
		local t = i / steps
		ellipse(buf, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, w0 + (w1 - w0) * t, w0 + (w1 - w0) * t, col, alpha)
	end
end
local function shade(h, f)
	local c = Color3.fromHex(h)
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1)):ToHex()
end

-- style: "hero" | "cute" | "villain" | "calm" | "robot"
function K.DrawFace(face)
	local buf = newCanvas()
	local eye = face.eye or "#3a8cff"
	local lash = face.lash or "#1b1420"
	local brow = face.brow or lash
	local style = face.style or "hero"
	if style == "robot" then
		ellipse(buf, 128, 120, 92, 20, face.eye or "#ff4040", 1)
		ellipse(buf, 128, 120, 80, 9, "#ffffff", 0.7)
		return buf
	end
	local villain = style == "villain"
	local calm = style == "calm"
	for _, s in { -1, 1 } do
		local cx, cy = 128 + s * 44, 118
		local rx, ry = 25, villain and 24 or (calm and 26 or 33)
		-- lid clip for villains/calm (flat, slanted top)
		local clip = nil
		if villain then
			clip = function(x, y) return y > cy - 10 + (x - cx) * s * -0.35 end
		elseif calm then
			clip = function(x, y) return y > cy - 14 end
		end
		ellipse(buf, cx, cy, rx, ry, "#ffffff", 1, clip)
		-- iris: dark top, bright bottom, pupil, two highlights
		ellipse(buf, cx + s * 1, cy + 3, rx * 0.8, ry * 0.86, shade(eye, 0.55), 1, clip)
		ellipse(buf, cx + s * 1, cy + 8, rx * 0.72, ry * 0.62, eye, 1, clip)
		ellipse(buf, cx + s * 1, cy + 14, rx * 0.5, ry * 0.32, shade(eye, 1.35), 0.8, clip)
		ellipse(buf, cx + s * 1, cy + 4, rx * 0.34, ry * 0.42, "#140c1c", 1, clip)
		ellipse(buf, cx - s * 7, cy - 9, 7, 8, "#ffffff", 1, clip)
		ellipse(buf, cx + s * 8, cy + 16, 3.5, 3.5, "#ffffff", 0.9, clip)
		-- upper lash
		if villain then
			line(buf, cx + s * 30, cy - 14, cx - s * 26, cy - 2, 3, 5, lash, 1)
			line(buf, cx + s * 30, cy - 14, cx + s * 38, cy - 20, 3, 1.5, lash, 1)
		elseif calm then
			line(buf, cx - 27, cy - 13, cx + 27, cy - 13, 4.5, 4.5, lash, 1)
			line(buf, cx + s * 27, cy - 13, cx + s * 35, cy - 18, 3.5, 1.5, lash, 1)
		else
			local a0, a1 = 195, 345
			arc(buf, cx, cy - 1, rx + 2, ry + 1, a0, a1, s < 0 and 5 or 3, s < 0 and 3 or 5, lash, 1)
			local fa = math.rad(s > 0 and 345 or 195)
			local fx, fy = cx + math.cos(fa) * (rx + 2), cy - 1 + math.sin(fa) * (ry + 1)
			line(buf, fx, fy, fx + s * 9, fy - 7, 3.5, 1.2, lash, 1)
		end
		arc(buf, cx, cy + 2, rx - 2, ry - 1, 60, 120, 1.2, 1.2, shade(lash, 1.8), 0.8)
		-- brows
		if villain then
			line(buf, cx + s * 30, cy - 34, cx - s * 22, cy - 22, 2, 4.5, brow, 1)
		elseif calm then
			line(buf, cx - 20, cy - 32, cx + 20, cy - 34, 2.5, 2.5, brow, 1)
		else
			arc(buf, cx, cy - 26, 22, 9, 200, 340, 2, 3, brow, 1)
		end
		if not villain and face.blush ~= false then
			ellipse(buf, cx + s * 6, cy + 42, 16, 6, "#ff7f96", 0.35)
		end
	end
	-- mouth
	local mc = "#6a2a34"
	if villain then
		line(buf, 112, 186, 148, 180, 2.5, 2.5, mc, 1)
	elseif face.mouth == "grin" then
		ellipse(buf, 128, 182, 15, 9, "#ffffff", 1, function(x, y) return y > 178 end)
		arc(buf, 128, 176, 16, 12, 10, 170, 2.2, 2.2, mc, 1)
	elseif face.mouth == "open" then
		ellipse(buf, 128, 183, 9, 7, mc, 1)
		ellipse(buf, 128, 187, 6, 3, "#ff7f8f", 1)
	else
		arc(buf, 128, 172, 12, 10, 20, 160, 2, 2, mc, 1)
	end
	return buf
end

function K.ApplyFace(rig, face)
	local buf = K.DrawFace(face)
	local img = AssetService:CreateEditableImage({ Size = Vector2.new(S, S) })
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), buf)
	local decal = Instance.new("Decal")
	decal.Name = "face"
	decal.Face = Enum.NormalId.Front
	decal.TextureContent = Content.fromObject(img)
	decal.Parent = rig:FindFirstChild("AnimeHead") or rig.Head
	return img
end

----------------------------------------------------------------------------
-- Final, savable characters: R15 body + uploaded clothing/face + Motor6D joints
----------------------------------------------------------------------------
-- Swap the physics-based AnimationConstraints for classic Motor6Ds so our code can
-- animate every joint by setting Motor6D.Transform (procedural animation, no uploads).
function K.ConvertToMotors(rig)
	for _, c in rig:GetDescendants() do
		if c:IsA("AnimationConstraint") then
			local a0, a1 = c.Attachment0, c.Attachment1
			if a0 and a1 then
				local m6 = Instance.new("Motor6D")
				m6.Name = c.Name
				m6.Part0 = a0.Parent
				m6.Part1 = a1.Parent
				m6.C0 = a0.CFrame
				m6.C1 = a1.CFrame
				m6.Parent = a1.Parent
			end
			c:Destroy()
		end
	end
	for _, c in rig:GetDescendants() do
		if c:IsA("BallSocketConstraint") or c:IsA("NoCollisionConstraint") then c:Destroy() end
	end
	for _, p in rig:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
		end
	end
end

function K.BuildFinal(id, data, assets)
	local rig = K.NewRig(data.look)
	rig.Name = id
	if assets then
		local shirt = Instance.new("Shirt"); shirt.Name = "Shirt"; shirt.ShirtTemplate = "rbxassetid://" .. assets.shirt; shirt.Parent = rig
		local pants = Instance.new("Pants"); pants.Name = "Pants"; pants.PantsTemplate = "rbxassetid://" .. assets.pants; pants.Parent = rig
		local face = Instance.new("Decal"); face.Name = "face"; face.Face = Enum.NormalId.Front
		face.Texture = "rbxassetid://" .. assets.face
		face.Parent = rig.AnimeHead
	end
	K.ConvertToMotors(rig)
	local hum = rig:FindFirstChildOfClass("Humanoid")
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	rig.PrimaryPart = rig.HumanoidRootPart
	-- measurements used by the game (health bars, follower placement)
	local cf, size = rig:GetBoundingBox()
	local hrp = rig.HumanoidRootPart
	rig:SetAttribute("GroundOffset", hrp.Position.Y - (cf.Y - size.Y / 2))
	rig:SetAttribute("TopOffset", (cf.Y + size.Y / 2) - hrp.Position.Y)
	rig:SetAttribute("Radius", math.max(size.X, size.Z) / 2)
	rig:SetAttribute("CharacterId", id)
	return rig
end

return K
