--!strict
-- SettingsService: saves and checks every player setting (the list is ReplicatedStorage.Shared.Settings).
--
--   * Settings live in the profile as data.prefs, so they save with everything else
--     (autosave + leaving + shutdown: no extra DataStore calls).
--   * Each setting is published to the player as the attribute "Pref_<key>" (the client reads
--     those), plus "Pref_AutoDelete" = the comma list of champion ids picked in Orb Config.
--   * The client can only ASK for a change. Every request is rate limited and checked with
--     Settings.Clean; anything odd is ignored. Settings never touch coins, damage or rewards.
--   * Sprint: the server sets WalkSpeed itself (walk 16, sprint from the Sprint Speed setting).
--
-- Remotes (created here):
--   SetPreference(key, value)        RemoteEvent
--   SetAutoDelete(ids, on)           RemoteEvent  ids = a champion id or a list of them
--   SetSprint(on)                    RemoteEvent  true while the sprint key is held

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Settings = require(ReplicatedStorage.Shared.Settings)
local Remotes = ReplicatedStorage.Remotes
local DataService = require(script.Parent.DataService)

local SettingsService = {}

-- rate limit: a bucket of 20 requests that refills 6 per second (a slider drag sends a few)
local BUCKET_SIZE = 20
local REFILL_PER_SECOND = 6
local bucket: { [Player]: { tokens: number, at: number } } = {}
local sprintHeld: { [Player]: boolean } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = bucket[player]
	if not b then
		b = { tokens = BUCKET_SIZE, at = now }
		bucket[player] = b
	end
	b.tokens = math.min(BUCKET_SIZE, b.tokens + (now - b.at) * REFILL_PER_SECOND)
	b.at = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

local function ensureRemote(name: string, className: string): Instance
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		;(r :: Instance).Name = name
		;(r :: Instance).Parent = Remotes
	end
	return r :: Instance
end

-- data.prefs with every setting present and valid (old saves and bad values get the default)
local function prefsOf(data: any): any
	if type(data.prefs) ~= "table" then data.prefs = {} end
	local prefs = data.prefs
	for _, d in Settings.List do
		if d.status == "live" then
			if Settings.Clean(d.key, prefs[d.key]) == nil then prefs[d.key] = d.default end
		else
			prefs[d.key] = nil -- ("soon" / "always" rows have nothing to save)
		end
	end
	if type(prefs.AutoDelete) ~= "table" then prefs.AutoDelete = {} end
	for id in prefs.AutoDelete do
		if not Config.ChampionById[id] then prefs.AutoDelete[id] = nil end -- (a champion that was removed)
	end
	return prefs
end

-- The value of one setting (always valid).
function SettingsService.Get(data: any, key: string): any
	return prefsOf(data)[key]
end

-- True if champion `id` is picked for auto-delete (Orb Config).
function SettingsService.AutoDeletes(data: any, id: string): boolean
	return prefsOf(data).AutoDelete[id] == true
end

local function publishAutoDelete(player: Player, prefs: any)
	local ids = {}
	for id in prefs.AutoDelete do table.insert(ids, id) end
	table.sort(ids)
	player:SetAttribute("Pref_AutoDelete", table.concat(ids, ","))
end

-- Walking speed: sprint (Auto-Sprint on, or the sprint key held) uses the Sprint Speed setting.
local function applySpeed(player: Player)
	local data = DataService.Get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not data or not hum then return end
	local prefs = prefsOf(data)
	local sprinting = prefs.AutoSprint == true or sprintHeld[player] == true
	local speed = if sprinting then Settings.SprintWalkSpeed(prefs.SprintSpeed) else Settings.WalkSpeed
	if hum.WalkSpeed ~= speed then hum.WalkSpeed = speed end
	player:SetAttribute("Sprinting", sprinting and speed > Settings.WalkSpeed)
end

local function publishAll(player: Player, data: any)
	local prefs = prefsOf(data)
	for _, d in Settings.List do
		if d.status == "live" then player:SetAttribute("Pref_" .. d.key, prefs[d.key]) end
	end
	publishAutoDelete(player, prefs)
	player:SetAttribute("PrefsReady", true)
end

-- Called by Main once the player's data has loaded.
function SettingsService.OnLoaded(player: Player, data: any)
	publishAll(player, data)
	applySpeed(player)
end

local function setPreference(player: Player, key: any, value: any)
	if not allow(player) then return end
	local data = DataService.Get(player)
	if not data then return end
	local clean = Settings.Clean(key, value)
	if clean == nil then
		-- refused: send the real value back so the menu shows the truth again
		if type(key) == "string" and Settings.ByKey[key] and Settings.ByKey[key].status == "live" then
			player:SetAttribute("Pref_" .. key, prefsOf(data)[key])
		end
		return
	end
	prefsOf(data)[key] = clean
	player:SetAttribute("Pref_" .. key, clean)
	if key == "AutoSprint" or key == "SprintSpeed" then applySpeed(player) end
end

local MAX_IDS_PER_REQUEST = 300
local function setAutoDelete(player: Player, ids: any, on: any)
	if typeof(on) ~= "boolean" or not allow(player) then return end
	local data = DataService.Get(player)
	if not data then return end
	local list = if type(ids) == "string" then { ids } elseif type(ids) == "table" then ids else nil
	if not list or #list > MAX_IDS_PER_REQUEST then return end
	local prefs = prefsOf(data)
	for _, id in list do
		if type(id) == "string" and Config.ChampionById[id] then
			prefs.AutoDelete[id] = if on then true else nil
		end
	end
	publishAutoDelete(player, prefs)
end

local function setSprint(player: Player, on: any)
	if typeof(on) ~= "boolean" then return end
	if sprintHeld[player] == on then return end
	if not allow(player) then return end
	sprintHeld[player] = on or nil
	applySpeed(player)
end

function SettingsService.Start()
	(ensureRemote("SetPreference", "RemoteEvent") :: RemoteEvent).OnServerEvent:Connect(setPreference)
	;(ensureRemote("SetAutoDelete", "RemoteEvent") :: RemoteEvent).OnServerEvent:Connect(setAutoDelete)
	;(ensureRemote("SetSprint", "RemoteEvent") :: RemoteEvent).OnServerEvent:Connect(setSprint)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			sprintHeld[player] = nil
			char:WaitForChild("Humanoid", 10)
			applySpeed(player)
		end)
	end
	for _, p in Players:GetPlayers() do onPlayer(p) end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		bucket[p] = nil
		sprintHeld[p] = nil
	end)

	-- the server keeps the speed it chose (other code or a respawn can't leave it wrong)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in Players:GetPlayers() do applySpeed(p) end
		end
	end)
end

return SettingsService
