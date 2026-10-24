--!strict
-- AfkService: lets players stay AFK past Roblox's 20-minute idle kick.
--
-- The client notices ~16 minutes without input and fires Remotes.AfkRejoin.
-- We teleport the player back into the game: into THIS server if possible
-- (else any server), with their world, position and auto toggles in TeleportData.
-- Their progress is saved by DataService when they leave; the next server (or this
-- one again) waits for that save / session lock before loading it.
--
-- TeleportData travels through the player's device, so it is never trusted: on
-- arrival every value is checked again (world unlocked, spot inside that world,
-- toggles only if the pass is owned).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes
local DataService = require(script.Parent.DataService)

local AfkService = {}

local REJOIN_COOLDOWN = 60   -- seconds between rejoin requests from one player
local WORLD_HALF_SIZE = 1100 -- a saved spot must be this close (X and Z) to its world's origin
local MIN_Y, MAX_Y = -50, 500

local lastRequest: { [Player]: number } = {}
local teleporting: { [Player]: boolean } = {} -- we started a rejoin teleport for this player
local retried: { [Player]: boolean } = {}     -- already tried the "any server" fallback

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < 1e6
end

local function buildTeleportData(player: Player, data: any): { [string]: any }
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local td: { [string]: any } = {
		afk = true,
		world = data.world,
		autoAttack = data.settings.autoAttack == true,
		autoHatch = data.settings.autoHatch == true,
	}
	if root then
		td.x, td.y, td.z = root.Position.X, root.Position.Y, root.Position.Z
	end
	return td
end

-- sameServer = true tries to rejoin this exact server first.
local function rejoin(player: Player, sameServer: boolean)
	local data = DataService.Get(player)
	if not data or not player.Parent then return end
	local options = Instance.new("TeleportOptions")
	if sameServer then options.ServerInstanceId = game.JobId end
	options:SetTeleportData(buildTeleportData(player, data))
	teleporting[player] = true
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn(`[AfkService] rejoin failed for {player.Name}: {err}`)
		if sameServer and not retried[player] then
			retried[player] = true
			rejoin(player, false) -- try any server instead
		else
			teleporting[player] = nil
		end
	end
end

local function onRejoinRequest(player: Player)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < REJOIN_COOLDOWN then return end
	lastRequest[player] = now
	if not DataService.Get(player) then return end
	if RunService:IsStudio() then
		warn("[AfkService] AFK rejoin skipped in Studio (teleports only work in a live server).")
		return
	end
	retried[player] = false
	rejoin(player, true)
end

-- Called by Main when a profile loads. Returns { world = id, position = Vector3? } for a
-- valid AFK rejoin (and restores the auto toggles), or nil for a normal join.
function AfkService.ReadRejoin(player: Player, data: any): any?
	local ok, joinData = pcall(function() return player:GetJoinData() end)
	if not ok or type(joinData) ~= "table" then return nil end
	if joinData.SourcePlaceId ~= nil and joinData.SourcePlaceId ~= game.PlaceId then return nil end
	local td = joinData.TeleportData
	if type(td) ~= "table" or td.afk ~= true then return nil end

	-- world: a whole number, a real world, and one this player may be in
	local worldId = td.world
	if type(worldId) ~= "number" or worldId ~= math.floor(worldId) then return nil end
	local world = Config.WorldById(worldId)
	if not world then return nil end
	if worldId ~= 0 and (not data.tutorialDone or not data.unlocked[world.key]) then return nil end

	-- position: real numbers inside that world, otherwise the world's spawn is used
	local position: Vector3? = nil
	local x, y, z = td.x, td.y, td.z
	if isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z) then
		local origin = world.origin
		if math.abs(x - origin.X) <= WORLD_HALF_SIZE and math.abs(z - origin.Z) <= WORLD_HALF_SIZE
			and y >= MIN_Y and y <= MAX_Y then
			position = Vector3.new(x, y, z)
		end
	end

	-- toggles: only if the matching pass is owned
	if type(td.autoAttack) == "boolean" and data.passes.AutoAttack then data.settings.autoAttack = td.autoAttack end
	if type(td.autoHatch) == "boolean" and data.passes.AutoHatch then data.settings.autoHatch = td.autoHatch end

	return { world = worldId, position = position }
end

function AfkService.Start()
	if not Remotes:FindFirstChild("AfkRejoin") then
		local e = Instance.new("RemoteEvent"); e.Name = "AfkRejoin"; e.Parent = Remotes
	end
	local remote = Remotes:FindFirstChild("AfkRejoin") :: RemoteEvent
	remote.OnServerEvent:Connect(onRejoinRequest) -- (any arguments the client sends are ignored)

	-- the same-server rejoin can fail (server full, closing...): try any server once
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		if not teleporting[player] then return end
		warn(`[AfkService] teleport for {player.Name} failed ({result.Name}): {message}`)
		if retried[player] or not player.Parent then
			teleporting[player] = nil
			return
		end
		retried[player] = true
		task.wait(1)
		rejoin(player, false)
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastRequest[p] = nil
		teleporting[p] = nil
		retried[p] = nil
	end)
end

return AfkService
