--!strict
-- EnemyService: spawns enemies in every zone, tracks their health,
-- and respawns them after they're defeated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

export type Enemy = {
	model: Model,
	key: string,
	def: any,
	hp: number,
	maxHp: number,
	worldId: number,
	alive: boolean,
	damageBy: { [Player]: number },
	bar: Frame,
	hpText: TextLabel,
	respawn: () -> (),
}

local EnemyService = {}
-- Functions to call when an enemy is defeated. (We use plain functions, not a
-- BindableEvent, because BindableEvents COPY tables - listeners wouldn't get the real enemy.)
local killedListeners: { (any) -> () } = {}
function EnemyService.OnKilled(fn: (any) -> ())
	table.insert(killedListeners, fn)
end

local folder: Folder
local byModel: { [Model]: Enemy } = {}
local counter = 0
local rng = Random.new()

local function makeHealthBar(root: BasePart, def: any): (Frame, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	-- sized in studs, so bars shrink with distance (bosses get a big one)
	bb.Size = if def.boss then UDim2.fromScale(14, 3) else UDim2.fromScale(5 * math.max(def.scale or 1, 1), 1.35 * math.max(def.scale or 1, 1))
	bb.StudsOffsetWorldSpace = Vector3.new(0, (root.Parent:GetAttribute("TopOffset") or root.Size.Y / 2) + 1.2, 0)
	bb.MaxDistance = def.boss and 260 or 130
	bb.AlwaysOnTop = false -- (AlwaysOnTop billboards weren't rendering in testing)
	bb.LightInfluence = 0

	local name = Instance.new("TextLabel")
	name.Size = UDim2.fromScale(1, 0.45)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = def.boss and Color3.fromRGB(255, 120, 100) or Color3.new(1, 1, 1)
	name.Text = def.name
	local s = Instance.new("UIStroke"); s.Thickness = 2; s.Parent = name
	name.Parent = bb

	local back = Instance.new("Frame")
	back.Position = UDim2.fromScale(0, 0.5)
	back.Size = UDim2.fromScale(1, 0.5)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	Instance.new("UICorner", back).CornerRadius = UDim.new(0.5, 0)
	local bs = Instance.new("UIStroke"); bs.Thickness = 2; bs.Color = Color3.fromRGB(15, 15, 20); bs.Parent = back
	back.Parent = bb

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = def.boss and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(110, 230, 90)
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	fill.Parent = back

	local hp = Instance.new("TextLabel")
	hp.Size = UDim2.fromScale(1, 1)
	hp.BackgroundTransparency = 1
	hp.Font = Enum.Font.FredokaOne
	hp.TextScaled = true
	hp.TextColor3 = Color3.new(1, 1, 1)
	hp.Text = Format.Short(def.hp) .. "/" .. Format.Short(def.hp) .. " HP"
	local hs = Instance.new("UIStroke"); hs.Thickness = 1.5; hs.Parent = hp
	hp.ZIndex = 2
	hp.Parent = back

	bb.Parent = root
	return fill, hp
end

local function randomPointIn(zone: BasePart): Vector3
	local half = zone.Size / 2
	local local_ = Vector3.new(rng:NextNumber(-half.X + 4, half.X - 4), 0, rng:NextNumber(-half.Z + 4, half.Z - 4))
	local p = zone.CFrame:PointToWorldSpace(local_)
	return Vector3.new(p.X, zone.Position.Y - zone.Size.Y / 2, p.Z)
end

local spawnEnemy
function spawnEnemy(key: string, worldId: number, getPosition: () -> Vector3)
	local def = Config.Enemies[key]
	local template = ServerStorage.EnemyModels:FindFirstChild(key) :: Model
	local model = template:Clone()
	counter += 1
	model.Name = "E" .. counter
	-- stream the whole enemy at once (otherwise players may get the body without its health bar)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("EnemyType", key)
	model:SetAttribute("WorldId", worldId)
	local root = model.PrimaryPart :: BasePart
	local ground = getPosition()
	-- bosses face the arena entrance (east); everyone else faces a random way
	local facing = if def.boss then CFrame.Angles(0, math.rad(-90), 0) else CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local groundOffset = model:GetAttribute("GroundOffset") or root.Size.Y / 2
	model:PivotTo(CFrame.new(ground + Vector3.new(0, groundOffset, 0)) * facing)

	local fill, hpText = makeHealthBar(root, def)
	local enemy: Enemy = {
		model = model, key = key, def = def, hp = def.hp, maxHp = def.hp,
		worldId = worldId, alive = true, damageBy = {}, bar = fill, hpText = hpText,
		respawn = function() spawnEnemy(key, worldId, getPosition) end,
	}
	byModel[model] = enemy
	model.Parent = folder

	-- (enemy idle/hit/death animations are played by each client - see EnemyAnimator)
end

function EnemyService.Get(model: Instance?): Enemy?
	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then return nil end
	local e = byModel[model :: Model]
	if e and e.alive then return e end
	return nil
end

function EnemyService.Position(enemy: Enemy): Vector3
	return (enemy.model.PrimaryPart :: BasePart).Position
end

-- Finds the closest living enemy to a position, in one world.
function EnemyService.Nearest(worldId: number, pos: Vector3, range: number): Enemy?
	local best, bestDist = nil, range
	for _, e in byModel do
		if e.alive and e.worldId == worldId then
			local d = (EnemyService.Position(e) - pos).Magnitude
			if d < bestDist then best, bestDist = e, d end
		end
	end
	return best
end

-- Auto Attack's pick (the player's "Auto Attack Target" setting), among living enemies in range:
--   "Nearest" (default), "Bosses First" (a boss if one is in range, else nearest),
--   "Weakest" (least health left), "Strongest" (most health left). Ties go to the nearer one.
function EnemyService.Pick(worldId: number, pos: Vector3, range: number, mode: string?): Enemy?
	if mode ~= "Bosses First" and mode ~= "Weakest" and mode ~= "Strongest" then
		return EnemyService.Nearest(worldId, pos, range)
	end
	local best, bestScore, bestDist = nil, -math.huge, math.huge
	for _, e in byModel do
		if e.alive and e.worldId == worldId then
			local d = (EnemyService.Position(e) - pos).Magnitude
			if d < range then
				local score = if mode == "Bosses First" then (if e.def.boss then 1 else 0)
					elseif mode == "Weakest" then -e.hp
					else e.hp
				if score > bestScore or (score == bestScore and d < bestDist) then
					best, bestScore, bestDist = e, score, d
				end
			end
		end
	end
	return best
end

-- Deals damage. Returns true if this hit defeated the enemy.
function EnemyService.Damage(enemy: Enemy, player: Player, amount: number): boolean
	if not enemy.alive or amount <= 0 then return false end
	local dealt = math.min(amount, enemy.hp)
	enemy.hp -= dealt
	enemy.damageBy[player] = (enemy.damageBy[player] or 0) + dealt
	enemy.bar.Size = UDim2.fromScale(math.max(enemy.hp / enemy.maxHp, 0), 1)
	enemy.hpText.Text = Format.Short(math.ceil(enemy.hp)) .. "/" .. Format.Short(enemy.maxHp) .. " HP"
	if enemy.hp <= 0 then
		enemy.alive = false
		byModel[enemy.model] = nil
		for _, fn in killedListeners do task.spawn(fn, enemy) end
		-- let clients play the defeat animation, then remove it and respawn later
		enemy.model:SetAttribute("Dead", true)
		local bar = enemy.model.PrimaryPart and enemy.model.PrimaryPart:FindFirstChild("HealthBar")
		if bar then bar.Enabled = false end
		-- bosses use their own (short) respawn time; everyone else uses the shared one
		local respawnIn = if enemy.def.boss then (enemy.def.respawn or Config.Combat.EnemyRespawnSeconds) else Config.Combat.EnemyRespawnSeconds
		task.delay(respawnIn, enemy.respawn)
		task.delay(0.9, function() enemy.model:Destroy() end)
		return true
	end
	return false
end

function EnemyService.Start()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
	for _, world in workspace.Worlds:GetChildren() do
		for _, marker in world.Zones:GetChildren() do
			local key = marker:GetAttribute("Enemy")
			local worldId = marker:GetAttribute("WorldId")
			-- skip anything that isn't a proper spawn marker (a part with a known enemy)
			if not marker:IsA("BasePart") or typeof(key) ~= "string" or not Config.Enemies[key]
				or not ServerStorage.EnemyModels:FindFirstChild(key) then
				continue
			end
			if marker.Name == "BossSpawn" then
				-- bosses always (re)spawn at the exact centre of their arena: the BossSpawn
				-- marker's middle, on the floor (read again on every respawn)
				local spot = marker :: BasePart
				spawnEnemy(key, worldId, function()
					return spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)
				end)
			else
				for _ = 1, marker:GetAttribute("Count") or 5 do
					spawnEnemy(key, worldId, function() return randomPointIn(marker) end)
				end
			end
		end
	end
end

return EnemyService
