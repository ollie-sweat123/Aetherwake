--!strict
-- Stats: works out a player's numbers (damage, slots, luck...) from their data,
-- and shows them to the client through Attributes + leaderstats.
-- Rule of thumb: the server calculates, the client only displays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes

local Stats = {}

-- Adds up the bonuses of every milestone the player has reached.
function Stats.UpgradeBonus(data: any, kind: string): number
	local total = 0
	for _, step in Config.Upgrades[kind] do
		if (data[step.stat] or 0) >= step.need then total += step.bonus end
	end
	return total
end

function Stats.IndexCount(data: any): number
	local n = 0
	for _ in data.index do n += 1 end
	return n
end

-- Adds up the `value` of every Upgrades-shop level the player has bought of one kind.
-- kind = "Equip" / "Inventory" / "Range" / "Dash" / "Jump" (data.upgrades uses lowercase keys).
function Stats.ShopBonus(data: any, kind: string): number
	local levels = (Config.Shop :: any)[kind]
	local bought = data.upgrades and data.upgrades[string.lower(kind)] or 0
	local total = 0
	if levels then
		for i = 1, math.min(bought, #levels) do total += levels[i].value end
	end
	return total
end

-- One champion's damage per hit: base power, +50% per fusion star.
function Stats.ChampionPower(owned: any): number
	local def = owned and Config.ChampionById[owned.id]
	if not def then return 0 end
	return def.power * (1 + (owned.stars or 0) * Config.Fusion.powerPerStar)
end

-- Base slots + slots bought in the Upgrades shop + the +1 Equip pass. (Worlds no longer add slots.)
function Stats.EquipSlots(data: any): number
	return Config.Combat.BaseEquipSlots + Stats.ShopBonus(data, "Equip")
		+ (if data.passes and data.passes.ExtraEquip then 1 else 0)
end

function Stats.InventorySize(data: any): number
	return Config.InventoryBase + Stats.ShopBonus(data, "Inventory")
end

-- Auto-attack radius in studs (shown as a ring around the player).
function Stats.AttackRange(data: any): number
	return Config.Combat.AutoTargetBase + Stats.ShopBonus(data, "Range")
end

function Stats.DashCharges(data: any): number
	return Config.Movement.BaseDashCharges + Stats.ShopBonus(data, "Dash")
end

function Stats.JumpCount(data: any): number
	return Config.Movement.BaseJumpCount + Stats.ShopBonus(data, "Jump")
end

-- Auto toggles only count while the matching pass is owned.
function Stats.AutoAttackOn(data: any): boolean
	return data.passes.AutoAttack == true and data.settings.autoAttack == true
end

function Stats.AutoHatchOn(data: any): boolean
	return data.passes.AutoHatch == true and data.settings.autoHatch == true
end

function Stats.DamageMult(data: any): number
	return 1 + Stats.UpgradeBonus(data, "Damage") + Stats.IndexCount(data) * Config.Upgrades.IndexDamagePerChampion
end

function Stats.Luck(data: any): number
	return 1 + Stats.UpgradeBonus(data, "Luck")
end

function Stats.OpenCount(data: any): number
	return 1 + Stats.UpgradeBonus(data, "MultiOpen")
end

function Stats.TeamPower(data: any): number
	local power = 0
	for _, uid in data.equipped do
		power += Stats.ChampionPower(data.champions[uid])
	end
	return power
end

-- Damage your whole team deals each attack.
function Stats.HitDamage(data: any): number
	return Stats.TeamPower(data) * Stats.DamageMult(data)
end

-- (There is no click damage: players never deal damage, only their champions do.)

local function unlockedList(data: any): string
	local list = {}
	for _, w in Config.Worlds do
		if data.unlocked[w.key] then table.insert(list, w.key) end
	end
	return table.concat(list, ",")
end

-- "W1=3,W2=0,W3=0"
local function bossKillsText(data: any): string
	local list = {}
	for _, w in Config.Worlds do
		table.insert(list, w.key .. "=" .. tostring(data.bossKills[w.key] or 0))
	end
	return table.concat(list, ",")
end

-- "equip=0,inventory=1,range=0,dash=0,jump=0"
local function upgradeLevelsText(data: any): string
	local list = {}
	for _, kind in Config.ShopOrder do
		local key = string.lower(kind)
		table.insert(list, key .. "=" .. tostring(data.upgrades[key] or 0))
	end
	return table.concat(list, ",")
end

-- The name shown above a champion: its nickname, or its normal name.
function Stats.DisplayName(owned: any): string
	if type(owned.name) == "string" and owned.name ~= "" then return owned.name end
	local def = Config.ChampionById[owned.id]
	return def and def.name or owned.id
end

-- Pushes all the numbers the UI needs.
function Stats.Publish(player: Player, data: any)
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("Gems", data.gems)
	player:SetAttribute("World", data.world)
	player:SetAttribute("Kills", data.kills)
	player:SetAttribute("OrbsOpened", data.orbsOpened)
	player:SetAttribute("PlaySeconds", data.playSeconds)
	player:SetAttribute("TeamPower", Stats.HitDamage(data))
	player:SetAttribute("EquipSlots", Stats.EquipSlots(data))
	player:SetAttribute("DamageMult", Stats.DamageMult(data))
	player:SetAttribute("Luck", Stats.Luck(data))
	player:SetAttribute("OpenCount", Stats.OpenCount(data))
	player:SetAttribute("IndexCount", Stats.IndexCount(data))
	player:SetAttribute("Unlocked", unlockedList(data))
	player:SetAttribute("TutorialDone", data.tutorialDone == true)

	-- passes, toggles and upgrades (the HUD, range ring and movement scripts read these)
	player:SetAttribute("PassAutoAttack", data.passes.AutoAttack == true)
	player:SetAttribute("PassAutoHatch", data.passes.AutoHatch == true)
	player:SetAttribute("PassExtraEquip", data.passes.ExtraEquip == true)
	player:SetAttribute("AutoAttack", Stats.AutoAttackOn(data))
	player:SetAttribute("AutoHatch", Stats.AutoHatchOn(data))
	player:SetAttribute("AttackRange", Stats.AttackRange(data))
	player:SetAttribute("DashCharges", Stats.DashCharges(data))
	player:SetAttribute("JumpCount", Stats.JumpCount(data))
	player:SetAttribute("InventorySize", Stats.InventorySize(data))
	player:SetAttribute("BossKills", bossKillsText(data))
	player:SetAttribute("UpgradeLevels", upgradeLevelsText(data))

	-- equipped champions, so every client can draw everyone's followers
	-- (same order in all three lists)
	local ids, names, stars = {}, {}, {}
	for _, uid in data.equipped do
		local owned = data.champions[uid]
		if owned then
			table.insert(ids, owned.id)
			table.insert(names, Stats.DisplayName(owned))
			table.insert(stars, tostring(owned.stars or 0))
		end
	end
	player:SetAttribute("EquippedIds", table.concat(ids, ","))
	player:SetAttribute("EquippedNames", table.concat(names, "|"))
	player:SetAttribute("EquippedStars", table.concat(stars, ","))

	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		for _, n in { "Coins", "Power" } do
			local v = Instance.new("NumberValue"); v.Name = n; v.Parent = stats
		end
		stats.Parent = player
	end
	(stats :: any).Coins.Value = data.coins
	;(stats :: any).Power.Value = math.floor(Stats.HitDamage(data))
end

-- Sends the full champion list to that player's UI.
function Stats.SyncInventory(player: Player, data: any)
	Remotes.InventoryUpdated:FireClient(player, data.champions, data.equipped, data.index)
end

return Stats
