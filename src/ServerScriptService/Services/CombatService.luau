--!strict
-- CombatService: click an enemy -> your champions attack it.
-- The client only says WHICH enemy it wants. The server checks everything
-- (range, world, click speed) and calculates all damage and rewards.
-- Players deal no damage themselves: a click only picks the target, and ONLY
-- champions hurt enemies.
--
-- Each equipped champion attacks on its own timer. Every hit charges its
-- ability bar; after Config.Combat.HitsPerAbility hits it performs its ability
-- (one big hit). The server tells every client what each champion is doing
-- (Remotes.ChampionAction) so they can play the matching animation; the
-- damage itself is applied here when the swing/ability "lands".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local Stats = require(script.Parent.Stats)
local AbilityInfo = require(ReplicatedStorage.Shared.AbilityInfo)
local QuestEvents = require(script.Parent.QuestEvents)

local CombatService = {}

type Slot = { uid: string, id: string, nextAction: number, busyUntil: number, hits: number }
type State = { target: any?, clicks: { number }, slots: { Slot }, slotKey: string }
local states: { [Player]: State } = {}

local function stateFor(p: Player): State
	local s = states[p]
	if not s then
		s = { target = nil, clicks = {}, slots = {}, slotKey = "" }
		states[p] = s
	end
	return s
end

-- Keep one Slot per equipped champion. Rebuilt when the team changes OR a
-- champion's stars change (fusion), so the key holds both: "uid:stars,uid:stars".
local function syncSlots(s: State, data: any)
	local parts = {}
	for _, uid in data.equipped do
		local owned = data.champions[uid]
		table.insert(parts, tostring(uid) .. ":" .. tostring(owned and owned.stars or 0))
	end
	local key = table.concat(parts, ",")
	if key == s.slotKey then return end
	local old = {}
	for _, sl in s.slots do old[sl.uid] = sl end
	local now = os.clock()
	s.slots = {}
	for i, uid in data.equipped do
		local owned = data.champions[uid]
		if owned then
			table.insert(s.slots, old[uid] or { uid = uid, id = owned.id, nextAction = now + (i - 1) * 0.22, busyUntil = 0, hits = 0 })
		end
	end
	s.slotKey = key
end

local function rootOf(p: Player): BasePart?
	local char = p.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setTarget(p: Player, enemy: any?)
	stateFor(p).target = enemy
	p:SetAttribute("Target", enemy and enemy.model.Name or nil)
end

-- True if this click is allowed (max N clicks in any 1 second).
local function allowClick(s: State): boolean
	local now = os.clock()
	local recent = {}
	for _, t in s.clicks do
		if now - t < 1 then table.insert(recent, t) end
	end
	s.clicks = recent
	if #recent >= Config.Combat.MaxClicksPerSecond then return false end
	table.insert(s.clicks, now)
	return true
end

local function inRange(p: Player, enemy: any, range: number): boolean
	local root = rootOf(p)
	return root ~= nil and (EnemyService.Position(enemy) - root.Position).Magnitude <= range
end

-- Damage one owned champion deals per hit (fusion stars included).
-- Stats.ChampionPower does the real maths; the fallback is just the base power.
local function championPower(owned: any): number
	local fn = (Stats :: any).ChampionPower
	if fn then return fn(owned) end
	local def = Config.ChampionById[owned.id]
	return def and def.power or 1
end

-- Auto attack needs BOTH the pass (owned) and the toggle (switched on).
local function autoAttackOn(data: any): boolean
	return data.passes ~= nil and data.passes.AutoAttack == true
		and data.settings ~= nil and data.settings.autoAttack == true
end

-- How far auto attack looks for enemies (grows with the Range upgrade).
local function autoRange(data: any): number
	local fn = (Stats :: any).AttackRange
	if fn then return fn(data) end
	return (Config.Combat :: any).AutoTargetBase or 40
end

-- A click/tap only picks (or keeps) your target - it deals no damage.
local function onAttack(p: Player, model: any)
	local s = stateFor(p)
	if not allowClick(s) then return end -- anti-spam: max N Attack calls per second
	local data = DataService.Get(p)
	if not data then return end
	local enemy = EnemyService.Get(model) -- (checks that `model` really is a living enemy)
	if not enemy or enemy.worldId ~= data.world then return end
	if not inRange(p, enemy, Config.Combat.MaxTargetDistance) then return end
	if s.target ~= enemy then setTarget(p, enemy) end
end

-- Old HUD remote. Same rules as SetToggle: ignored unless the Auto Attack pass is owned.
local function onToggleAuto(p: Player, on: any)
	if typeof(on) ~= "boolean" then return end
	local data = DataService.Get(p)
	if not data then return end
	if not (data.passes and data.passes.AutoAttack) then
		p:SetAttribute("AutoAttack", false) -- tell the HUD it is still off
		return
	end
	data.settings = data.settings or {}
	data.settings.autoAttack = on -- saved, so it survives AFK rejoins
	p:SetAttribute("AutoAttack", on)
end

-- A boss's drop with Config.BossDropBonus added (other enemies: unchanged). Coins are
-- rounded; the gem fraction becomes a chance of one extra gem, rolled per player.
local rng = Random.new()
local function dropFor(def: any): (number, number)
	if not def.boss then return def.coins, def.gems end
	local mult = 1 + (Config.BossDropBonus or 0)
	local coins = math.floor(def.coins * mult + 0.5)
	local exactGems = def.gems * mult
	local gems = math.floor(exactGems)
	if rng:NextNumber() < exactGems - gems then gems += 1 end
	return coins, gems
end

-- Everyone who hit the enemy gets the full reward (teamwork is never punished).
local function onKilled(enemy: any)
	local def = enemy.def
	-- boss kills are counted per world: the next world only unlocks after beating this boss
	local bossWorld = if def.boss then Config.WorldById(enemy.worldId) else nil
	for p in enemy.damageBy do
		local data = DataService.Get(p)
		if data and p.Parent then
			local coins, gems = dropFor(def)
			data.coins += coins
			data.gems += gems
			data.kills += 1
			if bossWorld then
				data.bossKills = data.bossKills or {}
				data.bossKills[bossWorld.key] = (data.bossKills[bossWorld.key] or 0) + 1
			end
			Stats.Publish(p, data)
			QuestEvents.Fire(p, "kill", enemy.key, 1)
			Remotes.Notify:FireClient(p, "Reward", {
				coins = coins, gems = gems, position = EnemyService.Position(enemy), boss = def.boss == true,
			})
		end
	end
	for p, s in states do
		if s.target == enemy then setTarget(p, nil) end
	end
end

local function tick()
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local data = DataService.Get(p)
		local root = rootOf(p)
		if data and root then
			local s = stateFor(p)
			-- drop targets that died, moved worlds or got too far away
			if s.target and (not s.target.alive or s.target.worldId ~= data.world
				or not inRange(p, s.target, Config.Combat.MaxTargetDistance + 10)) then
				setTarget(p, nil)
			end
			if not s.target and autoAttackOn(data) then
				-- (the player's "Auto Attack Target" setting; a saved, server-checked value)
				local mode = type(data.prefs) == "table" and data.prefs.AttackPriority or nil
				local e = EnemyService.Pick(data.world, root.Position, autoRange(data), mode)
				if e then setTarget(p, e) end
			end
			syncSlots(s, data)
			local enemy = s.target
			if enemy then
				local mult = Stats.DamageMult(data)
				for i, slot in s.slots do
					if now >= slot.nextAction and now >= slot.busyUntil then
						local owned = data.champions[slot.uid]
						local power = (if owned then championPower(owned) else 1) * mult
						local kind, impact, amount
						if slot.hits >= Config.Combat.HitsPerAbility then
							local info = AbilityInfo[slot.id] or { impact = 1, duration = 1.6 }
							kind, impact, amount = "ability", info.impact, power * Config.Combat.AbilityMultiplier
							slot.hits = 0
							slot.busyUntil = now + info.duration
							slot.nextAction = slot.busyUntil + 0.35
							QuestEvents.Fire(p, "ability", slot.id, 1)
						else
							kind, impact, amount = "attack", Config.Combat.AttackImpact, power
							slot.hits += 1
							slot.nextAction = now + Config.Combat.AttackInterval
						end
						Remotes.ChampionAction:FireAllClients({
							u = p.UserId, s = i, c = slot.id, k = kind, tg = enemy.model.Name, a = amount, h = slot.hits, it = impact,
						})
						task.delay(impact, function()
							if enemy.alive and p.Parent then EnemyService.Damage(enemy, p, amount) end
						end)
					end
				end
			end
		end
	end
end

function CombatService.ClearTarget(p: Player)
	setTarget(p, nil)
end

-- Finds a RemoteEvent in Remotes, or creates it if it's missing.
local function remoteEvent(name: string): RemoteEvent
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r :: RemoteEvent
end

function CombatService.Start()
	remoteEvent("ChampionAction")
	remoteEvent("Attack").OnServerEvent:Connect(onAttack)
	remoteEvent("ToggleAuto").OnServerEvent:Connect(onToggleAuto)
	EnemyService.OnKilled(onKilled)
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			tick()
		end
	end)
end

return CombatService
