-- AccessoryImporter (Studio dev tool): attaches the Blender-made hair, armour and
-- weapons to every character after RiftChampions_Accessories.fbx is imported.
--
--   1. File > Import 3D > RiftChampions_Accessories.fbx (keep meshes separate, insert into the Workspace).
--   2. Command bar: print(require(game.ServerStorage.DevTools.AccessoryImporter).AttachAll())
--
-- How pieces line up: the FBX also holds four calibration cubes - CAL_O at the origin and
-- CAL_X / CAL_Y / CAL_Z six studs along each Roblox axis. Whatever scale, rotation or offset
-- the importer applied, they reveal it, so every piece maps back to the space the characters
-- were built in (feet centred on the origin, facing -Z; see CharacterKit.NewRig).

local AccessoryData = require(script.Parent.AccessoryData)

local MATERIAL = { plastic = Enum.Material.SmoothPlastic, metal = Enum.Material.Metal, neon = Enum.Material.Neon }
local CAL_SPAN = 6
local HOLO_COLOR = Color3.fromRGB(120, 225, 255)

local Importer = {}

-- The imported model (the top-level container holding CAL_O) and its parts by name.
local function findImport(): (Instance?, { [string]: BasePart })
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name:match("^CAL_O") then
			local root: Instance = d
			while root.Parent and root.Parent ~= workspace do root = root.Parent :: Instance end
			local parts = {}
			for _, p in root:GetDescendants() do
				if p:IsA("BasePart") then
					-- importers sometimes add suffixes like ".001"; keep the base name too
					parts[p.Name] = p
					local base = p.Name:match("^([%w_]+)")
					if base and not parts[base] then parts[base] = p end
				end
			end
			return root, parts
		end
	end
	return nil, {}
end

-- Every rig that should wear accessories.
local function targets(): { Model }
	local list = {}
	for _, folder in { game.ReplicatedStorage:FindFirstChild("ChampionModels"), game.ServerStorage:FindFirstChild("EnemyModels"),
		game.ServerStorage:FindFirstChild("NPCModels") } do
		if folder then
			for _, m in folder:GetChildren() do
				if m:IsA("Model") then table.insert(list, m) end
			end
		end
	end
	-- Sensei Hikari copies placed in the worlds (the real one + her holograms)
	for _, d in workspace.Worlds:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("CharacterId") == "SenseiHikari" then table.insert(list, d) end
	end
	return list
end

-- The space the character was built in: feet centre at the origin, same facing as the rig.
local function buildFrame(rig: Model): (CFrame, number)
	local acc = rig:FindFirstChild("Accessories")
	if acc then acc.Parent = nil end -- old accessories must not change the bounding box
	local cf, size = rig:GetBoundingBox()
	if acc then acc.Parent = rig end
	return cf * CFrame.new(0, -size.Y / 2, 0), rig:GetScale()
end

local function attach(rig: Model, parts: { [string]: BasePart }, cal: CFrame, k: number): (number, { string }, number)
	local id = rig:GetAttribute("CharacterId") or rig.Name
	local list = AccessoryData[id]
	if not list then return 0, {}, 0 end
	local frame, s = buildFrame(rig)
	local folder = rig:FindFirstChild("Accessories")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "Accessories"
		folder.Parent = rig
	end
	local holo = rig.Parent ~= nil and rig.Parent:GetAttribute("Hologram") == true
	local missing, off, added = {}, 0, 0
	for i, g in list do
		local src = parts[id .. "__" .. i]
		if not src then
			table.insert(missing, id .. "__" .. i)
			continue
		end
		local rel = cal:Inverse() * src.CFrame
		local want = Vector3.new(g.p[1], g.p[2], g.p[3])
		if (rel.Position / k - want).Magnitude > 0.35 then off += 1 end
		local mp = src:Clone()
		for _, c in mp:GetChildren() do c:Destroy() end -- importer extras (attachments, appearances)
		mp.Name = g.j .. "_" .. i
		mp.Size = src.Size / k * s
		mp.CFrame = frame * CFrame.new(want * s) * rel.Rotation
		mp.Color = Color3.fromHex(g.c)
		mp.Material = MATERIAL[g.k] or Enum.Material.SmoothPlastic
		if mp:IsA("MeshPart") then mp.TextureID = "" end
		mp.Anchored = false
		mp.CanCollide = false
		mp.CanTouch = false
		mp.CanQuery = false
		mp.Massless = true
		if holo then
			mp.Material = Enum.Material.SmoothPlastic
			mp.Color = HOLO_COLOR
			mp.Transparency = 0.3
			mp.CastShadow = false
		end
		local joint = rig:FindFirstChild(g.j) or rig:FindFirstChild("UpperTorso")
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = joint :: BasePart
		weld.Part1 = mp
		weld.Parent = mp
		mp:SetAttribute("Joint", g.j)
		mp.Parent = folder
		added += 1
	end
	return added, missing, off
end

function Importer.AttachAll(): string
	local root, parts = findImport()
	for _, n in { "CAL_O", "CAL_X", "CAL_Y", "CAL_Z" } do
		if not parts[n] then
			return "Couldn't find " .. n .. ". Import RiftChampions_Accessories.fbx into the Workspace first (keep meshes separate)."
		end
	end
	local o = parts.CAL_O.Position
	local ax, ay, az = parts.CAL_X.Position - o, parts.CAL_Y.Position - o, parts.CAL_Z.Position - o
	local k = (ax.Magnitude + ay.Magnitude + az.Magnitude) / (3 * CAL_SPAN) -- import units per stud
	if ax.Unit:Cross(ay.Unit):Dot(az.Unit) < 0.9 then
		return "The import is mirrored or skewed (calibration axes don't line up). Re-import with default settings."
	end
	local cal = CFrame.fromMatrix(o, ax.Unit, ay.Unit, az.Unit)

	local rigs, pieces, allMissing, allOff = 0, 0, {}, 0
	for _, rig in targets() do
		local added, missing, off = attach(rig, parts, cal, k)
		if added > 0 then rigs += 1 end
		pieces += added
		allOff += off
		for _, m in missing do table.insert(allMissing, m) end
	end

	-- keep the raw import out of the game world (but don't lose it)
	if root then
		root.Name = "ImportedAccessories"
		root.Parent = game.ServerStorage
	end
	local msg = string.format("Attached %d pieces to %d characters (import scale %.3f).", pieces, rigs, k)
	if #allMissing > 0 then
		msg ..= string.format(" %d pieces were missing from the import, e.g. %s.", #allMissing, table.concat(allMissing, ", ", 1, math.min(5, #allMissing)))
	end
	if allOff > 0 then
		msg ..= string.format(" %d pieces imported at an unexpected spot (placed from the saved data instead).", allOff)
	end
	return msg
end

return Importer
