--!strict
-- ChampionService: opening orbs (gacha), Auto Hatch, equipping, releasing,
-- fusing and renaming champions.
-- OpenOrb remote: (worldId, count) -> true, { { uid, id, new, rarity, power }, ... }
--                                   or false, "message for the player"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes
local DataService = require(script.Parent.DataService)
local Stats = require(script.Parent.Stats)
local QuestEvents = require(script.Parent.QuestEvents)
local SettingsService = require(script.Parent.SettingsService)
local Settings = require(ReplicatedStorage.Shared.Settings)

local ChampionService = {}
local rng = Random.new()

local SHRINE_RANGE = 30         -- studs: how close you must stand to a summon shrine
local AUTO_HATCH_SECONDS = 2.5  -- how often Auto Hatch opens orbs
local RENAME_COOLDOWN = 3       -- seconds between renames (text filtering is rate limited)
local MAX_NAME_LENGTH = 16
local SUMMON_COOLDOWN = 0.6     -- seconds between summons from the OpenOrb remote (Auto Hatch has its own timer)

local shrines: { Model } = {}  -- every summon shrine (found by the OrbShrine attribute)
local lastRename: { [Player]: number } = {}
local autoHatchPaused: { [Player]: string } = {} -- why Auto Hatch is paused, so we only say it once
local summoning: { [Player]: boolean } = {}  -- true while that player's OpenOrb request is running
local lastSummon: { [Player]: number } = {}  -- os.clock() of that player's last OpenOrb summon
-- STUDIO ONLY test hook (see ChampionService.ForceNextRarity): the rarity that player's
-- NEXT roll must give. Stays empty in the real game.
local studioForcedRarity: { [Player]: string } = {}

local function worldById(id: any)
	for _, w in Config.Worlds do
		if w.id == id then return w end
	end
	return nil
end

-- Picks a rarity using that world's odds. Luck boosts Config.LuckBoostFrom (Epic) and better;
-- pity (Config.Pity) guarantees Legendary / Mythic. Every check uses rarity NAMES through
-- Config.RarityAtLeast, never rank numbers, so adding a new tier can't shift behaviour.
local function rollRarity(player: Player, data: any, world: any): any
	local pity = data.pity[world.key] or {}
	data.pity[world.key] = pity

	-- 1) a Studio test force wins (used up right away), then pity (best rarity first)
	local forced: string? = studioForcedRarity[player]
	studioForcedRarity[player] = nil
	if not forced then
		for i = #Config.Rarities, 1, -1 do
			local id = Config.Rarities[i].id
			local limit = (Config.Pity :: any)[id]
			if limit and (pity[id] or 0) + 1 >= limit then
				forced = id
				break
			end
		end
	end

	-- 2) nothing forced: a normal weighted roll with this world's odds
	local rarity = forced and Config.RarityById[forced]
	if not rarity then
		local luck = Stats.Luck(data)
		local total = 0
		local weights = {}
		for _, r in Config.Rarities do
			local chance = (world.odds and world.odds[r.id]) or r.chance
			local w = chance * (if Config.RarityAtLeast(r.id, Config.LuckBoostFrom) then luck else 1)
			weights[r] = w
			total += w
		end
		local roll = rng:NextNumber() * total
		for _, r in Config.Rarities do
			roll -= weights[r]
			if roll <= 0 then rarity = r break end
		end
		rarity = rarity or Config.Rarities[1]
	end

	-- 3) pity counters: back to 0 when you got that rarity (or better), otherwise +1
	for id in Config.Pity do
		pity[id] = if Config.RarityAtLeast(rarity.id, id) then 0 else (pity[id] or 0) + 1
	end
	return rarity
end

-- A random champion of that world and rarity. If the world has none of that rarity
-- (e.g. a brand-new tier without champions yet) it steps down one rarity at a time.
local function pickChampion(worldId: number, rarityId: string): any
	local rarity = Config.RarityById[rarityId]
	local startRank = if rarity then (rarity :: any).rank else 1
	for rank = startRank, 1, -1 do
		local id = Config.Rarities[rank].id
		local pool = {}
		for _, c in Config.Champions do
			if c.world == worldId and c.rarity == id then table.insert(pool, c) end
		end
		if #pool > 0 then return pool[rng:NextInteger(1, #pool)] end
	end
	return nil
end

local function countOwned(data: any): number
	local n = 0
	for _ in data.champions do n += 1 end
	return n
end

-- True if EVERY champion that world's orb can give is picked for auto-delete: then the
-- orb needs no backpack space (nothing is added).
local function allAutoDeleted(data: any, worldId: number): boolean
	local any = false
	for _, c in Config.Champions do
		if c.world == worldId then
			any = true
			if not SettingsService.AutoDeletes(data, c.id) then return false end
		end
	end
	return any
end

local function giveChampion(data: any, id: string): string
	local uid = tostring(data.nextUid)
	data.nextUid += 1
	data.champions[uid] = { id = id, stars = 0 }
	data.index[id] = true
	return uid
end

-- A summon shrine is a Model with OrbShrine = true and a WorldId attribute.
-- Any number per world (e.g. one near the start and one next to the boss).
-- (A Model named "OrbShrine" or "BossShrine" with a WorldId also counts, in case the
-- attribute is missing.)
local function addShrine(inst: Instance)
	if not inst:IsA("Model") or typeof(inst:GetAttribute("WorldId")) ~= "number" then return end
	if inst:GetAttribute("OrbShrine") ~= true and inst.Name ~= "OrbShrine" and inst.Name ~= "BossShrine" then return end
	if not table.find(shrines, inst) then table.insert(shrines, inst) end
end

-- World id of the closest shrine within range of the player (optionally only
-- shrines of one world), or nil. The hub shrine sells Verdant Rift orbs (WorldId 1).
local function shrineNear(player: Player, onlyWorldId: number?): number?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local bestId, bestDist = nil, SHRINE_RANGE
	for i = #shrines, 1, -1 do
		local shrine = shrines[i]
		if not shrine.Parent then
			table.remove(shrines, i) -- shrine was removed from the map
		else
			local id = shrine:GetAttribute("WorldId")
			if typeof(id) == "number" and (onlyWorldId == nil or id == onlyWorldId) then
				local dist = (shrine:GetPivot().Position - root.Position).Magnitude
				if dist <= bestDist then bestId, bestDist = id, dist end
			end
		end
	end
	return bestId
end

-- Opens `count` orbs of `world` (the caller has already checked everything).
-- Used by BOTH the OpenOrb remote and Auto Hatch. Coins are taken once, each champion
-- is added once. Each result: { uid, id, new, rarity (id), power (damage per hit) }.
-- Auto-delete (Orb Config): a champion the player picked is NOT added; it still counts as
-- discovered (Index) and as an opened orb, and Settings.AutoDeleteRefund (75%) of the orb's
-- coin price comes back. Such a result has deleted = true, refund = coins and no uid.
local function doOpen(player: Player, data: any, world: any, count: number): { any }
	data.coins -= world.orb.cost * count
	local refundEach = math.floor(world.orb.cost * Settings.AutoDeleteRefund)
	local results = {}
	for _ = 1, count do
		local rarity = rollRarity(player, data, world)
		local def = pickChampion(world.id, rarity.id)
		if not def then
			-- (should never happen: every world has Common champions) give that orb's coins back
			data.coins += world.orb.cost
			warn(`[ChampionService] world {world.id} has no champion to give`)
		elseif SettingsService.AutoDeletes(data, def.id) then
			local isNew = not data.index[def.id]
			data.index[def.id] = true
			data.orbsOpened += 1
			data.coins += refundEach
			table.insert(results, {
				id = def.id,
				new = isNew,
				rarity = def.rarity,
				power = Stats.ChampionPower({ id = def.id, stars = 0 }),
				deleted = true,
				refund = refundEach,
			})
		else
			local isNew = not data.index[def.id]
			local uid = giveChampion(data, def.id)
			data.orbsOpened += 1
			table.insert(results, {
				uid = uid,
				id = def.id,
				new = isNew,
				rarity = def.rarity, -- the rarity id, e.g. "Epic" (the cinematic and result cards use it)
				power = Stats.ChampionPower(data.champions[uid]), -- damage per hit (new = 0 stars)
			})
		end
	end
	Stats.Publish(player, data)
	Stats.SyncInventory(player, data)
	QuestEvents.Fire(player, "orb", world.id, #results)
	return results
end

-- True only for a normal whole number. Exploiters can send anything (strings, tables,
-- NaN, infinity, 1.5...), so the remote checks this before using a number.
local function isWholeNumber(value: any): boolean
	return type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) < 1e9
end

-- The real work of the OpenOrb remote: checks EVERYTHING the client sent before spending coins.
local function tryOpenOrb(player: Player, worldId: any, count: any): (boolean, any)
	if not isWholeNumber(worldId) or not isWholeNumber(count) then
		return false, "Something went wrong."
	end
	local now = os.clock()
	if lastSummon[player] and now - lastSummon[player] < SUMMON_COOLDOWN then
		return false, "Slow down! Summoning again in a moment."
	end
	local data = DataService.Get(player)
	local world = worldById(worldId)
	if not data or not world then return false, "Something went wrong." end
	if count ~= 1 and count ~= Stats.OpenCount(data) then
		return false, "You can't open that many yet."
	end
	if not data.unlocked[world.key] then return false, "Unlock this world first." end
	if not shrineNear(player, world.id) then return false, "Walk up to the orb shrine first." end
	if countOwned(data) + count > Stats.InventorySize(data) and not allAutoDeleted(data, world.id) then
		return false, "Your backpack is full! Release or fuse some champions."
	end
	if data.coins < world.orb.cost * count then return false, "Not enough coins." end
	lastSummon[player] = now
	return true, doOpen(player, data, world, count)
end

-- OpenOrb remote. Only ONE request per player at a time: a second click while the first
-- is still running gets "Summoning...", so a double click can never open (or pay) twice.
local function openOrb(player: Player, worldId: any, count: any): (boolean, any)
	if summoning[player] then return false, "Summoning..." end
	summoning[player] = true
	local ok, success, result = pcall(tryOpenOrb, player, worldId, count)
	summoning[player] = nil -- (always cleared, even if something errored)
	if not ok then
		warn("[ChampionService] OpenOrb failed: " .. tostring(success))
		return false, "Something went wrong."
	end
	return success, result
end

-- Auto Hatch (pass + toggle): standing near a shrine opens as many orbs as you can
-- afford, up to your multi-open count. Pauses quietly when coins or space run out.
local function autoHatchFor(player: Player)
	local data = DataService.Get(player)
	if not data or not Stats.AutoHatchOn(data) then
		autoHatchPaused[player] = nil
		return
	end
	-- a manual OpenOrb request is running right now: let it finish, try again next tick
	-- (the manual 0.6 s cooldown does NOT apply to Auto Hatch)
	if summoning[player] then return end
	local worldId = shrineNear(player, nil)
	local world = worldId and worldById(worldId)
	if not world or not data.unlocked[world.key] then return end

	local space = if allAutoDeleted(data, world.id) then math.huge else Stats.InventorySize(data) - countOwned(data)
	local affordable = math.floor(data.coins / world.orb.cost)
	local count = math.min(Stats.OpenCount(data), space, affordable)
	if count < 1 then
		local reason = if space < 1 then "full" else "coins"
		if autoHatchPaused[player] ~= reason then
			autoHatchPaused[player] = reason -- tell the player once, not every few seconds
			Remotes.Notify:FireClient(player, "Purchase", {
				msg = if reason == "full"
					then "Auto Hatch paused: your backpack is full! Release or fuse some champions."
					else "Auto Hatch paused: not enough coins. It starts again when you can afford an orb.",
			})
		end
		return
	end
	autoHatchPaused[player] = nil
	local results = doOpen(player, data, world, count)
	Remotes.Notify:FireClient(player, "AutoHatch", { results = results, worldId = world.id })
end

local function equip(player: Player, uid: any, on: any)
	local data = DataService.Get(player)
	if not data or type(uid) ~= "string" or not data.champions[uid] then return false, "Unknown champion." end
	local idx = table.find(data.equipped, uid)
	if on then
		if idx then return true end
		if #data.equipped >= Stats.EquipSlots(data) then return false, "All equip slots are full." end
		table.insert(data.equipped, uid)
	elseif idx then
		table.remove(data.equipped, idx)
	end
	Stats.Publish(player, data)
	Stats.SyncInventory(player, data)
	QuestEvents.Fire(player, "equip")
	return true
end

local function equipBest(player: Player)
	local data = DataService.Get(player)
	if not data then return false end
	local list = {}
	for uid, owned in data.champions do
		table.insert(list, { uid = uid, power = Stats.ChampionPower(owned) })
	end
	table.sort(list, function(a, b) return a.power > b.power end)
	data.equipped = {}
	for i = 1, math.min(#list, Stats.EquipSlots(data)) do
		table.insert(data.equipped, list[i].uid)
	end
	Stats.Publish(player, data)
	Stats.SyncInventory(player, data)
	QuestEvents.Fire(player, "equip")
	return true
end

local function release(player: Player, uid: any)
	local data = DataService.Get(player)
	if not data or type(uid) ~= "string" or not data.champions[uid] then return false, "Unknown champion." end
	if countOwned(data) <= 1 then return false, "You need at least one champion." end
	data.champions[uid] = nil
	local idx = table.find(data.equipped, uid)
	if idx then table.remove(data.equipped, idx) end
	Stats.Publish(player, data)
	Stats.SyncInventory(player, data)
	return true
end

-- Fuse: the target + (copies - 1) other copies of the SAME champion -> target gets +1 star.
-- The copies used up are removed. Never trust the client: check every uid.
local function fuse(player: Player, targetUid: any, fodder: any): (boolean, string)
	local data = DataService.Get(player)
	if not data or type(targetUid) ~= "string" or type(fodder) ~= "table" then
		return false, "Something went wrong."
	end
	local target = data.champions[targetUid]
	local def = target and Config.ChampionById[target.id]
	if not target or not def then return false, "Unknown champion." end
	local stars = target.stars or 0
	if stars >= Config.Fusion.maxStars then return false, def.name .. " already has max stars!" end

	-- the fodder list must be exactly `need` different uids, all copies of the target
	local need = Config.Fusion.copies - 1
	local entries = 0
	for _ in fodder do entries += 1 end
	if entries ~= need then return false, `Pick {need} more copies of {def.name}.` end
	local used: { [string]: boolean } = {}
	for i = 1, need do
		local uid = fodder[i]
		if type(uid) ~= "string" or uid == targetUid or used[uid] then
			return false, "Pick different copies to fuse."
		end
		local owned = data.champions[uid]
		if not owned or owned.id ~= target.id then
			return false, `You can only fuse copies of {def.name}.`
		end
		used[uid] = true
	end

	-- the price is looked up by rarity NAME, so new tiers never change it
	local cost = Config.Fusion.cost(stars, def.rarity)
	if data.coins < cost then return false, "Not enough coins." end

	data.coins -= cost
	for uid in used do
		data.champions[uid] = nil
		local idx = table.find(data.equipped, uid)
		if idx then table.remove(data.equipped, idx) end
	end
	target.stars = stars + 1
	Stats.Publish(player, data)
	Stats.SyncInventory(player, data)
	QuestEvents.Fire(player, "fuse", target.id, 1)
	return true, `{Stats.DisplayName(target)} reached {target.stars} star` .. (if target.stars == 1 then "!" else "s!")
end

-- Rename: 0-16 characters, filtered by Roblox's text filter. "" goes back to the normal name.
-- Returns ok, filteredName (or an error message).
local function rename(player: Player, uid: any, text: any): (boolean, string)
	local data = DataService.Get(player)
	if not data or type(uid) ~= "string" or type(text) ~= "string" then return false, "Something went wrong." end
	if not data.champions[uid] then return false, "Unknown champion." end
	if #text > 200 then return false, `Names can be up to {MAX_NAME_LENGTH} letters.` end
	local now = os.clock()
	if lastRename[player] and now - lastRename[player] < RENAME_COOLDOWN then
		return false, "Slow down! Try again in a moment."
	end

	-- tidy up: no control characters or list separators (| ,), no spaces at the ends
	local clean = text:gsub("[%c|,]", "")
	clean = clean:gsub("^%s+", "")
	clean = clean:gsub("%s+$", "")
	local length = utf8.len(clean)
	if not length then return false, "That name has letters we can't use." end
	if length > MAX_NAME_LENGTH then return false, `Names can be up to {MAX_NAME_LENGTH} letters.` end
	lastRename[player] = now

	local filtered = ""
	if clean ~= "" then
		local ok, result = pcall(function()
			local filterResult = TextService:FilterStringAsync(clean, player.UserId, Enum.TextFilterContext.PublicChat)
			return filterResult:GetNonChatStringForBroadcastAsync()
		end)
		if not ok or type(result) ~= "string" then
			return false, "Couldn't check that name right now. Try again!"
		end
		filtered = result
	end

	-- (filtering waits on the internet, so look the champion up again afterwards)
	data = DataService.Get(player)
	local owned = data and data.champions[uid]
	if not owned then return false, "Unknown champion." end
	owned.name = if filtered ~= "" then filtered else nil
	Stats.Publish(player, data)
	Stats.SyncInventory(player, data)
	return true, filtered
end

-- Gives a champion straight to a player (quest rewards, starter pick, dev tools).
function ChampionService.Grant(player: Player, id: string, equipIt: boolean?): string?
	local data = DataService.Get(player)
	if not data or not Config.ChampionById[id] then return nil end
	local uid = giveChampion(data, id)
	if equipIt then
		if #data.equipped >= Stats.EquipSlots(data) then table.remove(data.equipped, 1) end
		table.insert(data.equipped, uid)
	end
	Stats.Publish(player, data)
	Stats.SyncInventory(player, data)
	QuestEvents.Fire(player, "equip")
	return uid
end

-- STUDIO ONLY test hook (Main's DevGive "forceRarity"): makes that player's NEXT orb roll
-- (manual or Auto Hatch) give `rarityId`, once. Pity counters still update normally.
-- Does nothing in the real game. Returns true if it was set.
function ChampionService.ForceNextRarity(player: Player, rarityId: any): boolean
	if not RunService:IsStudio() then return false end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	if type(rarityId) ~= "string" or not Config.RarityById[rarityId] then return false end
	studioForcedRarity[player] = rarityId
	return true
end

function ChampionService.GiveStarter(player: Player, data: any)
	if next(data.champions) == nil then
		local uid = giveChampion(data, "PipSprout")
		data.equipped = { uid }
	end
end

function ChampionService.Start()
	for _, name in { "FuseChampions", "RenameChampion" } do
		if not Remotes:FindFirstChild(name) then
			local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = Remotes
		end
	end
	Remotes.OpenOrb.OnServerInvoke = openOrb
	Remotes.EquipChampion.OnServerInvoke = equip
	Remotes.EquipBest.OnServerInvoke = equipBest
	Remotes.ReleaseChampion.OnServerInvoke = release
	Remotes.FuseChampions.OnServerInvoke = fuse
	Remotes.RenameChampion.OnServerInvoke = rename

	-- find every summon shrine now, and any added later
	for _, d in workspace.Worlds:GetDescendants() do addShrine(d) end
	workspace.Worlds.DescendantAdded:Connect(addShrine)

	Players.PlayerRemoving:Connect(function(p)
		lastRename[p] = nil
		autoHatchPaused[p] = nil
		summoning[p] = nil
		lastSummon[p] = nil
		studioForcedRarity[p] = nil
	end)

	-- Auto Hatch loop
	task.spawn(function()
		while true do
			task.wait(AUTO_HATCH_SECONDS)
			for _, p in Players:GetPlayers() do
				local ok, err = pcall(autoHatchFor, p)
				if not ok then warn("[ChampionService] auto hatch failed: " .. tostring(err)) end
			end
		end
	end)
	Remotes.GetInventory.OnServerInvoke = function(player: Player)
		local data = DataService.Get(player)
		if not data then return nil, nil, nil end
		return data.champions, data.equipped, data.index
	end
end

return ChampionService
