-- Main: starts every server system in the right order.
local Services = script.Parent.Services
local DataService = require(Services.DataService)
local Stats = require(Services.Stats)
local EnemyService = require(Services.EnemyService)
local CombatService = require(Services.CombatService)
local ChampionService = require(Services.ChampionService)
local WorldService = require(Services.WorldService)
local QuestService = require(Services.QuestService)
local ShopService = require(Services.ShopService)
local AfkService = require(Services.AfkService)
local SettingsService = require(Services.SettingsService)
local NoWeapons = require(Services.NoWeapons)
local Players = game:GetService("Players")

EnemyService.Start()
CombatService.Start()
ChampionService.Start()
WorldService.Start()
QuestService.Start()
ShopService.Start()  -- upgrades, passes, auto toggles (creates its remotes)
AfkService.Start()   -- AFK rejoin (creates Remotes.AfkRejoin)
SettingsService.Start() -- Settings menu: saving, checking, sprint speed (creates its remotes)
NoWeapons.Start()    -- players never hold a weapon

DataService.Loaded.Event:Connect(function(player)
	-- (events copy tables, so always grab the real profile table)
	local data = DataService.Get(player)
	if not data then return end
	ChampionService.GiveStarter(player, data)
	-- every session starts in Champion City... unless this is an AFK rejoin,
	-- then you go back to the (checked) world and spot you were AFK in
	local rejoin = AfkService.ReadRejoin(player, data)
	data.world = if rejoin then rejoin.world else 0
	Stats.Publish(player, data) -- (also sets AutoAttack/AutoHatch from the saved toggles + passes)
	Stats.SyncInventory(player, data)
	WorldService.OnLoaded(player, data, rejoin and rejoin.position)
	QuestService.OnLoaded(player, data)
	ShopService.OnLoaded(player, data) -- checks Robux passes in the background
	SettingsService.OnLoaded(player, data) -- publishes the Pref_ attributes, sets walk speed
	player:SetAttribute("DataLoaded", true)
end)
DataService.Start()

-- playtime clock (used by the Luck milestones)
task.spawn(function()
	local t = 0
	while true do
		task.wait(1)
		t += 1
		for _, p in Players:GetPlayers() do
			local data = DataService.Get(p)
			if data then
				data.playSeconds += 1
				if t % 10 == 0 then Stats.Publish(p, data) end
			end
		end
	end
end)

-- STUDIO ONLY testing helper (does nothing in the real game).
-- From the command bar while playing (Server view):
--   game.ServerStorage.DevGive:Invoke(game.Players:GetPlayers()[1], "coins", 100000)
--   game.ServerStorage.DevGive:Invoke(game.Players:GetPlayers()[1], "gems", 5000)
--   game.ServerStorage.DevGive:Invoke(game.Players:GetPlayers()[1], "pass", "AutoHatch")
--   game.ServerStorage.DevGive:Invoke(game.Players:GetPlayers()[1], "champion", "SageWillow")
--   game.ServerStorage.DevGive:Invoke(game.Players:GetPlayers()[1], "skipTutorial")
--   game.ServerStorage.DevGive:Invoke(game.Players:GetPlayers()[1], "forceRarity", "Mythic")
--     (the player's NEXT orb roll gives that rarity, once: handy for testing summon effects)
if game:GetService("RunService"):IsStudio() then
	local Quests = require(game:GetService("ReplicatedStorage").Shared.Quests)
	local devGive = Instance.new("BindableFunction")
	devGive.Name = "DevGive"
	devGive.OnInvoke = function(player, field, amount)
		local data = DataService.Get(player)
		if field == "skipTutorial" then -- marks the tutorial done so world travel works
			if not data then return "no data" end
			data.tutorialDone = true
			if data.quest.i <= Quests.TutorialCount then data.quest = { i = Quests.TutorialCount + 1, p = 0, s = "active" } end
			Stats.Publish(player, data)
			return "ok"
		end
		if field == "champion" then
			return ChampionService.Grant(player, amount, true) or "bad id"
		end
		if field == "pass" then
			return if ShopService.GivePass(player, amount) then "ok" else "bad pass"
		end
		if field == "forceRarity" then -- amount = a rarity id like "Mythic" (checked by ChampionService)
			return if ChampionService.ForceNextRarity(player, amount) then "ok" else "bad rarity"
		end
		if not data or type(data[field]) ~= "number" or type(amount) ~= "number" then return "bad field" end
		data[field] += amount
		Stats.Publish(player, data)
		return data[field]
	end
	devGive.Parent = game:GetService("ServerStorage")
end
