--!strict
-- NoWeapons: players NEVER hold a weapon in AETHERWAKE (the champions do all the fighting).
--
--   * StarterPack and StarterGear are emptied, so nobody spawns with a Tool
--   * any Tool that appears in a Backpack or on a character (a free model, a plugin, gear,
--     an exploit) is removed at once, on every spawn and whenever one is added later
--   * avatar accessories that are weapons (a sword on the back, a katana, a gun...) are removed
--     from the character when it spawns; normal hats, hair and clothes stay
-- The client also hides Roblox's Backpack hotbar (SettingsMenu), so there is no tool bar at all.

local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")

local NoWeapons = {}

-- an accessory whose name contains one of these is treated as a weapon (lower-case match)
local WEAPON_WORDS = {
	"sword", "katana", "blade", "saber", "sabre", "gun", "rifle", "pistol", "blaster", "axe",
	"scythe", "spear", "bow", "crossbow", "dagger", "knife", "hammer", "mace", "weapon", "lance",
	"trident", "halberd", "glaive", "shuriken", "kunai", "sickle", "whip", "staff", "wand",
}
-- words that contain a weapon word but are not weapons ("rainbow", "elbow", "bowtie"...)
local SAFE_WORDS = {
	"rainbow", "elbow", "bowtie", "bow tie", "hairbow", "hair bow", "bowler", "ribbon", "bowl", "gunmetal",
	"relax", "grimace", "balance", "glance", "freelance",
}

local function isWeaponName(name: string): boolean
	local n = string.lower(name)
	for _, safe in SAFE_WORDS do
		if string.find(n, safe, 1, true) then return false end
	end
	for _, w in WEAPON_WORDS do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function strip(inst: Instance)
	if inst:IsA("BackpackItem") then -- Tools and HopperBins
		inst:Destroy()
	end
end

local function watchContainer(container: Instance)
	for _, child in container:GetChildren() do strip(child) end
	container.ChildAdded:Connect(function(child)
		task.defer(strip, child) -- (deferred: destroying during ChildAdded can warn)
	end)
end

local function onCharacter(char: Model)
	watchContainer(char)
	-- weapon accessories from the avatar (they arrive a moment after the character)
	local function checkAccessory(child: Instance)
		if child:IsA("Accessory") and isWeaponName(child.Name) then
			task.defer(function() if child.Parent then child:Destroy() end end)
		end
	end
	for _, child in char:GetChildren() do checkAccessory(child) end
	char.ChildAdded:Connect(checkAccessory)
end

local function onPlayer(player: Player)
	local gear = player:FindFirstChild("StarterGear")
	if gear then watchContainer(gear) end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") or child.Name == "StarterGear" then watchContainer(child) end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then watchContainer(backpack) end
	if player.Character then onCharacter(player.Character) end
	player.CharacterAdded:Connect(onCharacter)
end

function NoWeapons.Start()
	watchContainer(StarterPack) -- nothing in StarterPack, ever
	for _, p in Players:GetPlayers() do onPlayer(p) end
	Players.PlayerAdded:Connect(onPlayer)
end

NoWeapons.IsWeaponName = isWeaponName -- (for tests)

return NoWeapons
