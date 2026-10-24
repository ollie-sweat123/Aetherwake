--!strict
-- WorldService: unlocking worlds and travelling between them.
-- To unlock a world you need: the tutorial done, the previous world unlocked,
-- the previous world's boss defeated at least once (world.requiresBoss), and the coins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes
local DataService = require(script.Parent.DataService)
local Stats = require(script.Parent.Stats)
local CombatService = require(script.Parent.CombatService)
local QuestEvents = require(script.Parent.QuestEvents)

local WorldService = {}

local function worldById(id: any)
	if type(id) ~= "number" then return nil end
	return Config.WorldById(id)
end

local function teleport(player: Player, world: any)
	local char = player.Character
	local spawn = workspace.Worlds:FindFirstChild(world.key)
	spawn = spawn and spawn:FindFirstChild("Spawn")
	if char and spawn then
		char:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
	end
end

-- "Defeat Commander Vexor first!" style message for a world that needs a boss kill.
local function bossGateMessage(data: any, world: any): string?
	local key = world.requiresBoss
	if not key or (data.bossKills[key] or 0) >= 1 then return nil end
	local bossWorld: any = Config.WorldByKey(key)
	local boss = bossWorld and bossWorld.boss and (Config.Enemies :: any)[bossWorld.boss]
	return "Defeat " .. (if boss then boss.name else "the previous boss") .. " first!"
end

local function travel(player: Player, worldId: any)
	local data = DataService.Get(player)
	local world = worldById(worldId)
	if not data or not world then return false, "Unknown world." end
	if world.id ~= 0 and not data.tutorialDone then
		return false, "Finish Sensei Hikari's training first!"
	end
	local justUnlocked = false
	if world.id ~= 0 and not data.unlocked[world.key] then
		local prev = worldById(world.id - 1)
		if not prev or not data.unlocked[prev.key] then
			return false, "Unlock " .. (prev and prev.name or "the previous world") .. " first."
		end
		local bossMessage = bossGateMessage(data, world)
		if bossMessage then return false, bossMessage end
		if data.coins < world.unlockCost then return false, "Not enough coins." end
		data.coins -= world.unlockCost
		data.unlocked[world.key] = true
		justUnlocked = true
	end
	data.world = world.id
	CombatService.ClearTarget(player)
	Stats.Publish(player, data)
	teleport(player, world)
	if justUnlocked then QuestEvents.Fire(player, "unlock", world.key) end
	QuestEvents.Fire(player, "travel", world.id)
	return true
end

-- firstSpawn (optional): where the FIRST character should appear instead of the
-- world's spawn pad (used by AFK rejoins to put you back where you stood).
function WorldService.OnLoaded(player: Player, data: any, firstSpawn: Vector3?)
	-- respawn in the world you were last in
	local pending = firstSpawn
	local function onCharacter()
		task.wait(0.1)
		local current = DataService.Get(player)
		if not current then return end
		if pending then
			local char = player.Character
			-- (the saved spot is the root part's position, so lift it just a little)
			if char then char:PivotTo(CFrame.new(pending + Vector3.new(0, 1, 0))) end
			pending = nil
			return
		end
		local world = worldById(current.world) or Config.Worlds[1]
		if world.id ~= 0 then teleport(player, world) end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then task.spawn(onCharacter) end
end

function WorldService.Start()
	Remotes.TravelToWorld.OnServerInvoke = travel
end

return WorldService
