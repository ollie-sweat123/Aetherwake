--!strict
-- QuestService: Sensei Hikari's quest line (content lives in Shared.Quests).
--
-- data.quest = { i = quest index, p = progress, s = state }
--   "offer"    - talk to Sensei to accept it (only the very first quest)
--   "active"   - in progress
--   "ready"    - done; return to Sensei (or her hologram) to claim the reward
--   "finished" - no quests left
-- Tutorial quests are "auto": the reward arrives the moment you finish.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Quests = require(ReplicatedStorage.Shared.Quests)
local Remotes = ReplicatedStorage.Remotes
local DataService = require(script.Parent.DataService)
local Stats = require(script.Parent.Stats)
local ChampionService = require(script.Parent.ChampionService)
local QuestEvents = require(script.Parent.QuestEvents)

local QuestService = {}
local TALK_RANGE = 20
local STARTER_DELAY = 6 -- seconds: the summon ceremony plays before the starter joins your team
local givers: { Model } = {}
local rng = Random.new()

local function publish(player: Player, data: any)
	player:SetAttribute("QuestIndex", data.quest.i)
	player:SetAttribute("QuestProgress", data.quest.p)
	player:SetAttribute("QuestState", data.quest.s)
end

local function grant(data: any, quest: any)
	local r = quest.reward or {}
	if r.coins then data.coins += r.coins end
	if r.gems then data.gems += r.gems end
end

-- Objectives you can already have when the quest starts (checked straight away).
local function stateProgress(data: any, quest: any): number?
	if quest.kind == "equip" then return #data.equipped end
	if quest.kind == "unlock" then return if data.unlocked[quest.key] then 1 else 0 end
	if quest.kind == "travel" then return if data.world == quest.key then 1 else 0 end
	return nil
end

local advance: (Player, any) -> ()

-- Key of the world whose boss this enemy is ("W1"...), or nil if it isn't a boss.
local function bossWorldKey(enemyKey: any): string?
	for _, w in Config.Worlds do
		if w.boss ~= nil and w.boss == enemyKey then return w.key end
	end
	return nil
end

-- Extra kill reward: the small lucky gem drop from elites (gemChance / gemDrop in
-- Config.Enemies). CombatService already gave the normal coins/gems and counted boss kills.
local function onKillExtras(player: Player, data: any, enemyKey: any)
	local def = if type(enemyKey) == "string" then (Config.Enemies :: any)[enemyKey] else nil
	if not def or not def.gemChance or rng:NextNumber() >= def.gemChance then return end
	local amount = def.gemDrop or 1
	data.gems += amount
	Stats.Publish(player, data)
	Remotes.Notify:FireClient(player, "Purchase", {
		msg = `Lucky! The {def.name} dropped {amount} Gem{if amount == 1 then "" else "s"}!`,
	})
end

-- Gives the starter picked at graduation (only once).
local function grantStarter(player: Player)
	local data = DataService.Get(player)
	if not data or data.starterGranted then return end
	local id = data.starterChosen
	if type(id) ~= "string" or not Config.ChampionById[id] then return end
	data.starterGranted = true
	ChampionService.Grant(player, id, true)
end

local function complete(player: Player, data: any, quest: any)
	if quest.auto then
		grant(data, quest)
		Remotes.Notify:FireClient(player, "Quest", { event = "complete", index = quest.index, reward = quest.reward })
		advance(player, data)
	else
		data.quest.s = "ready"
		publish(player, data)
		Remotes.Notify:FireClient(player, "Quest", { event = "ready", index = quest.index })
	end
end

local function checkState(player: Player, data: any)
	local quest = Quests.Get(data.quest.i)
	if not quest or data.quest.s ~= "active" then return end
	local value = stateProgress(data, quest)
	if value == nil then return end
	data.quest.p = math.min(value, quest.need)
	publish(player, data)
	if value >= quest.need then complete(player, data, quest) end
end

function advance(player: Player, data: any)
	data.quest.i += 1
	data.quest.p = 0
	data.quest.s = if Quests.Get(data.quest.i) then "active" else "finished"
	Stats.Publish(player, data)
	publish(player, data)
	Remotes.Notify:FireClient(player, "Quest", { event = "new", index = data.quest.i })
	checkState(player, data)
end

local function onEvent(player: Player, kind: string, key: any, amount: number)
	local data = DataService.Get(player)
	if not data then return end
	if kind == "kill" then onKillExtras(player, data, key) end
	local quest = Quests.Get(data.quest.i)
	if not quest or data.quest.s ~= "active" then return end
	if stateProgress(data, quest) ~= nil then
		checkState(player, data)
		return
	end
	if quest.kind ~= kind or (quest.key ~= nil and quest.key ~= key) then return end
	data.quest.p = math.min(data.quest.p + amount, quest.need)
	publish(player, data)
	if data.quest.p >= quest.need then complete(player, data, quest) end
end

local function nearGiver(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end
	for _, g in givers do
		if g.Parent and (g:GetPivot().Position - root.Position).Magnitude <= TALK_RANGE then return true end
	end
	return false
end

-- Talking to Sensei: accept, claim, or open the starter choice.
local function talk(player: Player): any
	local data = DataService.Get(player)
	if not data then return nil end
	if not nearGiver(player) then return { result = "far" } end
	local q = data.quest
	local quest = Quests.Get(q.i)
	if not quest then return { result = "finished" } end
	if q.s == "offer" then
		q.s = "active"
		publish(player, data)
		checkState(player, data)
		return { result = "accepted", index = quest.index }
	end
	if q.s == "ready" then
		grant(data, quest)
		advance(player, data)
		return { result = "claimed", index = quest.index, reward = quest.reward, next = data.quest.i }
	end
	if quest.kind == "starter" then
		return { result = "starter", index = quest.index }
	end
	return { result = "active", index = quest.index }
end

local function chooseStarter(player: Player, id: any): (boolean, string?)
	local data = DataService.Get(player)
	if not data or type(id) ~= "string" then return false, "Something went wrong." end
	local quest = Quests.Get(data.quest.i)
	if not quest or quest.kind ~= "starter" or data.quest.s ~= "active" or data.starterChosen then
		return false, "You can't choose a starter right now."
	end
	if not table.find(Config.Starters, id) then return false, "Unknown champion." end
	if not nearGiver(player) then return false, "Stand next to Sensei Hikari." end
	data.starterChosen = id
	data.tutorialDone = true
	advance(player, data)
	-- the champion joins AFTER the summon ceremony has played on the client.
	-- (If the player leaves before that, OnLoaded gives it next time.)
	task.delay(STARTER_DELAY, function()
		if player.Parent then grantStarter(player) end
	end)
	return true
end

function QuestService.OnLoaded(player: Player, data: any)
	-- players who finished the old tutorial skip the new one
	if data.tutorialDone and data.quest.i <= Quests.TutorialCount then
		data.quest = { i = Quests.TutorialCount + 1, p = 0, s = "active" }
	end
	-- starter picked but not given yet (they left during the ceremony): give it now.
	-- Saves from before this update got it at pick time (it's already in their Index).
	if type(data.starterChosen) == "string" and not data.starterGranted then
		if data.index[data.starterChosen] then
			data.starterGranted = true
		else
			grantStarter(player)
		end
	end
	-- older saves: bosses already beaten in the quest line count as boss kills
	-- (quest passed, or done and waiting to be claimed)
	for _, q: any in Quests.List do
		local worldKey = if q.kind == "kill" then bossWorldKey(q.key) else nil
		local beaten = data.quest.i > q.index or (data.quest.i == q.index and data.quest.s == "ready")
		if worldKey and beaten and (data.bossKills[worldKey] or 0) < 1 then
			data.bossKills[worldKey] = 1
		end
	end
	Stats.Publish(player, data)
	publish(player, data)
	checkState(player, data)
end

function QuestService.Start()
	for _, name in { "QuestTalk", "ChooseStarter" } do
		if not Remotes:FindFirstChild(name) then
			local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = Remotes
		end
	end
	for _, d in workspace.Worlds:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("QuestGiver") then table.insert(givers, d) end
	end
	Remotes.QuestTalk.OnServerInvoke = talk
	Remotes.ChooseStarter.OnServerInvoke = chooseStarter
	QuestEvents.SetHandler(onEvent)
end

return QuestService
