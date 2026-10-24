--!strict
-- ShopService: the Upgrades shop (paid with Gems), the passes (Gems OR Robux)
-- and the auto toggles (Auto Attack / Auto Hatch).
--
-- A pass can be owned two ways, both saved in data.passes:
--   * bought with Gems in the shop
--   * bought with Robux (a Roblox game pass): granted when the purchase finishes,
--     and checked again every time the player joins
-- The toggles only work while the matching pass is owned (Stats.AutoAttackOn / AutoHatchOn).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = ReplicatedStorage.Remotes
local DataService = require(script.Parent.DataService)
local Stats = require(script.Parent.Stats)

local ShopService = {}

-- toggle key (data.settings) <-> the pass it needs (data.passes)
local TOGGLE_PASS: { [string]: string } = { autoAttack = "AutoAttack", autoHatch = "AutoHatch" }
local PASS_TOGGLE: { [string]: string } = { AutoAttack = "autoAttack", AutoHatch = "autoHatch" }
local TOGGLE_COOLDOWN = 0.2 -- seconds; ignores toggle spam

local lastToggle: { [Player]: number } = {}

local function ensureRemote(name: string, className: string)
	if not Remotes:FindFirstChild(name) then
		local r = Instance.new(className); r.Name = name; r.Parent = Remotes
	end
end

local function passKeyForGamePass(gamePassId: number): string?
	for key, pass in Config.Passes :: any do
		if pass.gamePassId > 0 and pass.gamePassId == gamePassId then return key end
	end
	return nil
end

-- Gives a pass. Getting a toggle pass also switches it on (that's why you bought it!).
local function givePass(player: Player, data: any, key: string)
	data.passes[key] = true
	local toggle = PASS_TOGGLE[key]
	if toggle then data.settings[toggle] = true end
	Stats.Publish(player, data)
end

-- Remotes.PurchaseUpgrade(kind) -> ok, msg. kind = "Equip"/"Inventory"/"Range"/"Dash"/"Jump".
local function purchaseUpgrade(player: Player, kind: any): (boolean, string)
	local data = DataService.Get(player)
	local levels = if type(kind) == "string" then (Config.Shop :: any)[kind] else nil
	if not data or type(levels) ~= "table" then return false, "Unknown upgrade." end
	local key = string.lower(kind)
	local level = data.upgrades[key] or 0
	local nextLevel = levels[level + 1]
	if not nextLevel then return false, "Already maxed out!" end
	if data.gems < nextLevel.cost then return false, "Not enough Gems." end

	data.gems -= nextLevel.cost
	data.upgrades[key] = level + 1
	Stats.Publish(player, data)
	return true, nextLevel.label .. "!"
end

-- Remotes.PurchasePass(key, method) -> ok, msg. method = "gems" or "robux".
local function purchasePass(player: Player, key: any, method: any): (boolean, string)
	local data = DataService.Get(player)
	local pass = if type(key) == "string" then (Config.Passes :: any)[key] else nil
	if not data or type(pass) ~= "table" then return false, "Unknown pass." end
	if data.passes[key] then return false, "You already own " .. pass.name .. "!" end

	if method == "gems" then
		if data.gems < pass.gems then return false, "Not enough Gems." end
		data.gems -= pass.gems
		givePass(player, data, key)
		return true, pass.name .. " unlocked!"
	elseif method == "robux" then
		if pass.gamePassId > 0 then
			-- Roblox shows its own purchase window; we grant it in PromptGamePassPurchaseFinished
			local ok = pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, pass.gamePassId)
			end)
			if not ok then return false, "Couldn't open the Robux window. Try again!" end
			return true, "Finish the purchase in the Roblox window."
		end
		return false, "Robux purchases are coming soon!"
	end
	return false, "Unknown payment method."
end

-- Turns an auto toggle on/off. Ignored unless the pass is owned. Returns true if it changed.
-- (CombatService's old ToggleAuto remote can call this too.)
function ShopService.SetToggle(player: Player, key: any, on: any): boolean
	local data = DataService.Get(player)
	local passKey = if type(key) == "string" then TOGGLE_PASS[key] else nil
	if not data or not passKey or type(on) ~= "boolean" then return false end
	if not data.passes[passKey] then
		Stats.Publish(player, data) -- puts the attributes back in case something else changed them
		return false
	end
	data.settings[key] = on
	player:SetAttribute("AutoAttack", Stats.AutoAttackOn(data))
	player:SetAttribute("AutoHatch", Stats.AutoHatchOn(data))
	return true
end

-- Studio testing / admin helper: gives a pass for free.
function ShopService.GivePass(player: Player, key: any): boolean
	local data = DataService.Get(player)
	if not data or type(key) ~= "string" or not (Config.Passes :: any)[key] then return false end
	givePass(player, data, key)
	return true
end

-- Robux passes bought earlier (or on the website) are checked every join.
local function checkOwnedGamePasses(player: Player)
	for key, pass in Config.Passes :: any do
		if pass.gamePassId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
			end)
			local data = DataService.Get(player) -- (look it up again: the check above waits)
			if ok and owns and data and not data.passes[key] then
				givePass(player, data, key)
			end
		end
	end
end

function ShopService.OnLoaded(player: Player, _data: any)
	task.spawn(checkOwnedGamePasses, player)
end

function ShopService.Start()
	ensureRemote("PurchaseUpgrade", "RemoteFunction")
	ensureRemote("PurchasePass", "RemoteFunction")
	ensureRemote("SetToggle", "RemoteEvent")

	local upgradeRemote = Remotes:FindFirstChild("PurchaseUpgrade") :: RemoteFunction
	local passRemote = Remotes:FindFirstChild("PurchasePass") :: RemoteFunction
	local toggleRemote = Remotes:FindFirstChild("SetToggle") :: RemoteEvent
	upgradeRemote.OnServerInvoke = purchaseUpgrade
	passRemote.OnServerInvoke = purchasePass
	toggleRemote.OnServerEvent:Connect(function(player: Player, key: any, on: any)
		local now = os.clock()
		if lastToggle[player] and now - lastToggle[player] < TOGGLE_COOLDOWN then return end
		lastToggle[player] = now
		ShopService.SetToggle(player, key, on)
	end)

	-- a Robux purchase finished (this event comes from Roblox, so wasPurchased can be trusted)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
		if not wasPurchased then return end
		local key = passKeyForGamePass(gamePassId)
		local data = DataService.Get(player)
		if not key or not data or data.passes[key] then return end
		givePass(player, data, key)
		Remotes.Notify:FireClient(player, "Purchase", { msg = "Thank you! " .. (Config.Passes :: any)[key].name .. " unlocked!" })
	end)

	Players.PlayerRemoving:Connect(function(p) lastToggle[p] = nil end)
end

return ShopService
