--!strict
-- DataService: loads, holds and saves every player's progress.
--
-- While a player is in the game their data lives in a plain Lua table on the
-- SERVER (the "profile"). Gameplay code changes that table through the
-- functions at the bottom. Only this module talks to DataStores.
--
-- Safety features (so nobody loses progress or duplicates champions):
--   * Every DataStore call is wrapped in pcall and retried with a growing delay.
--   * Every write uses UpdateAsync, never SetAsync.
--   * Session lock: one server "checks out" a profile at a time (stops dupes).
--   * Saves on autosave, when the player leaves, and when the server shuts down.
--   * If loading fails, the player is kicked instead of starting from zero
--     (a fresh profile would overwrite their real save on the next autosave).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local STORE_NAME = "RiftChampions_PlayerData_v1"
local AUTOSAVE_SECONDS = 60
local LOCK_STALE_SECONDS = AUTOSAVE_SECONDS * 3
local CURRENT_VERSION = 1

local DEFAULT_DATA = {
	version = CURRENT_VERSION,
	coins = 0,
	gems = 0,
	champions = {},      -- [uid] = { id = "PipSprout", stars = 0, name = nil } (stars = fusion level, name = nickname)
	equipped = {},       -- list of uids
	unlocked = { W1 = true },
	world = 0,           -- 0 = Champion City (hub)
	tutorialDone = false,
	starterChosen = false, -- id of the starter picked at the end of the tutorial
	starterGranted = false, -- the starter arrives a few seconds after the pick (after the ceremony)
	quest = { i = 1, p = 0, s = "offer" }, -- Sensei Hikari's quest line (see QuestService)
	kills = 0,
	orbsOpened = 0,
	pity = {},           -- [worldKey] = { Legendary = n, Mythic = n }
	playSeconds = 0,
	index = {},          -- [championId] = true once discovered
	nextUid = 1,
	passes = { AutoAttack = false, AutoHatch = false, ExtraEquip = false }, -- owned via Gems or Robux
	upgrades = { equip = 0, inventory = 0, range = 0, dash = 0, jump = 0 },  -- levels bought with Gems
	bossKills = {},      -- [worldKey] = how many times this player helped defeat that world's boss
	settings = { autoAttack = false, autoHatch = false }, -- the player's auto toggles
	prefs = {},          -- Settings menu choices (SettingsService fills in the defaults; AutoDelete = { [championId] = true })
}

-- These are tables whose sub-keys also get defaults (so old saves get new sub-keys too).
local NESTED_DEFAULTS = { "passes", "upgrades", "settings", "bossKills" }

-- Old save formats get upgraded step by step here. Empty for now.
local MIGRATIONS: { [number]: (any) -> any } = {}

-- saveSeq counts the saves started for this profile; newestWrite is the newest one that
-- reached the DataStore. Together they stop an older save from landing after a newer one.
type Profile = { data: any, released: boolean, saveSeq: number, newestWrite: number }

local DataService = {}
DataService.Loaded = Instance.new("BindableEvent") -- fires (player) once a profile is ready; use DataService.Get(player)

local store: DataStore? = nil
local offline = false
local profiles: { [Player]: Profile } = {}
-- How many saves are still talking to the DataStore. Shutdown waits for ALL of them,
-- including "player left" saves that started before the shutdown did.
local savesInFlight = 0
-- UserIds whose "leaving" save is still running on THIS server. If the same player
-- rejoins this server (AFK rejoin), we wait for that save before loading again.
local leavingSaves: { [number]: boolean } = {}

local function deepCopy(t: any): any
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in t do copy[k] = deepCopy(v) end
	return copy
end

local function reconcile(data: any)
	for k, v in DEFAULT_DATA do
		if data[k] == nil then data[k] = deepCopy(v) end
	end
	-- fill missing sub-keys (e.g. a new pass added in a later update)
	for _, k in NESTED_DEFAULTS do
		if type(data[k]) ~= "table" then data[k] = {} end
		for subKey, v in (DEFAULT_DATA :: any)[k] do
			if data[k][subKey] == nil then data[k][subKey] = deepCopy(v) end
		end
	end
	-- champions saved before fusion existed have no stars yet
	for _, owned in data.champions do
		if type(owned) == "table" and type(owned.stars) ~= "number" then owned.stars = 0 end
	end
	return data
end

local function migrate(data: any)
	while (data.version or 1) < CURRENT_VERSION do
		local step = MIGRATIONS[data.version or 1]
		if not step then error(`missing migration from v{data.version}`) end
		data = step(data)
		data.version = (data.version or 1) + 1
	end
	return data
end

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

local function withRetry(attempts: number, fn: () -> any): (boolean, any)
	local delaySeconds = 1
	local lastErr
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then return true, result end
		lastErr = result
		warn(`[DataService] attempt {attempt}/{attempts} failed: {result}`)
		if attempt < attempts then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
	end
	return false, lastErr
end

local function claimAndLoad(player: Player): any?
	if offline or not store then
		return reconcile(deepCopy(DEFAULT_DATA))
	end
	local ds = store :: DataStore
	for attempt = 1, 5 do
		local lockedByOther = false
		local ok, result = pcall(function()
			return ds:UpdateAsync(keyFor(player), function(old)
				lockedByOther = false
				local record = old or { data = deepCopy(DEFAULT_DATA) }
				local lock = record.lock
				if lock and lock.jobId ~= game.JobId and os.time() - lock.time < LOCK_STALE_SECONDS then
					lockedByOther = true
					return nil -- another server still has it; write nothing
				end
				record.data = reconcile(migrate(record.data))
				record.lock = { jobId = game.JobId, time = os.time() }
				return record
			end)
		end)
		if ok and result and not lockedByOther then
			return result.data
		end
		if not ok then warn(`[DataService] load failed for {player.Name}: {result}`) end
		if not player.Parent then return nil end
		task.wait(attempt * 2)
	end
	return nil
end

local function newProfile(data: any): Profile
	return { data = data, released = false, saveSeq = 0, newestWrite = 0 }
end

local function save(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile or profile.released then return end
	if release then profile.released = true end
	if offline or not store then return end

	-- Number this save. An older save (say an autosave that had to retry) that only reaches
	-- the DataStore after a newer one is dropped, instead of writing old data back over it
	-- (or locking a profile the player has already left with).
	profile.saveSeq += 1
	local seq = profile.saveSeq
	local snapshot = deepCopy(profile.data)
	local ds = store :: DataStore
	savesInFlight += 1
	local ok, err = withRetry(3, function()
		return ds:UpdateAsync(keyFor(player), function(old)
			if seq < profile.newestWrite then
				return nil -- a newer save already wrote; this one is out of date
			end
			if old and old.lock and old.lock.jobId ~= game.JobId then
				return nil -- another server owns this save now; don't overwrite it
			end
			local record = { data = snapshot, lock = nil :: any }
			if not release then
				record.lock = { jobId = game.JobId, time = os.time() }
			end
			profile.newestWrite = seq
			return record
		end)
	end)
	savesInFlight -= 1
	if not ok then warn(`[DataService] could not save {player.Name}: {err}`) end
end

-- True while an older copy of this user (same UserId, different Player object)
-- still has a live profile on this server (e.g. an AFK rejoin into this server).
local function olderCopyActive(player: Player): boolean
	for other, profile in profiles do
		if other ~= player and other.UserId == player.UserId and not profile.released then return true end
	end
	return false
end

local function onPlayerAdded(player: Player)
	-- wait for this user's "leaving" save on this server to finish first
	local waitUntil = os.clock() + 20
	while (leavingSaves[player.UserId] or olderCopyActive(player)) and os.clock() < waitUntil and player.Parent do
		task.wait(0.25)
	end
	local data = claimAndLoad(player)
	if not player.Parent then
		-- they left while we were loading: give the session lock back straight away,
		-- so their next server doesn't have to wait for it to go stale
		if data then
			profiles[player] = newProfile(data)
			save(player, true)
			profiles[player] = nil
		end
		return
	end
	if not data then
		player:Kick("Your save couldn't load. Please rejoin in a minute!")
		return
	end
	profiles[player] = newProfile(data)
	DataService.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	leavingSaves[userId] = true
	save(player, true)
	profiles[player] = nil
	leavingSaves[userId] = nil
end

-- Returns the player's data table, or nil if it hasn't loaded yet.
function DataService.Get(player: Player): any?
	local profile = profiles[player]
	return profile and not profile.released and profile.data or nil
end

function DataService.IsOffline(): boolean
	return offline
end

function DataService.Start()
	local ok, result = pcall(function()
		local ds = DataStoreService:GetDataStore(STORE_NAME)
		if RunService:IsStudio() then ds:GetAsync("__probe") end -- errors if API access is off
		return ds
	end)
	if ok then
		store = result
	else
		offline = true
		warn("[DataService] DataStores unavailable - progress will NOT save this session. "
			.. "Publish the place, then Home > Game Settings > Security > Enable Studio Access to API Services. ("
			.. tostring(result) .. ")")
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end

	-- Autosave one player at a time, spread across the interval.
	task.spawn(function()
		while true do
			local list = Players:GetPlayers()
			local gap = AUTOSAVE_SECONDS / math.max(#list, 1)
			for _, p in list do
				task.wait(gap)
				if profiles[p] then task.spawn(save, p, false) end
			end
			if #list == 0 then task.wait(AUTOSAVE_SECONDS) end
		end
	end)

	game:BindToClose(function()
		for p in profiles do task.spawn(save, p, true) end
		-- Wait for every save still running, not just the ones started here. Pressing Stop in
		-- Studio (and some server shutdowns) fires PlayerRemoving first: its save is already
		-- running, so save() above skips that player, and without this wait the server shut
		-- down mid-save and the player came back to their last autosave.
		local deadline = os.clock() + (RunService:IsStudio() and 8 or 25)
		while savesInFlight > 0 and os.clock() < deadline do task.wait() end
	end)
end

return DataService
