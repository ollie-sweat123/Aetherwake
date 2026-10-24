--!strict
-- Config: ALL the game's numbers and content live here.
-- Adding a new world later = adding a new entry to Config.Worlds + its champions.

local Config = {}

Config.GameName = "Rift Champions"

Config.Rarities = {
	-- order matters: lowest to highest. Each rarity's `rank` = its place in this list
	-- (set at the bottom of this file). Code should NOT compare rank numbers: use
	-- Config.RarityAtLeast(id, "Epic") instead, so adding a new tier never shifts behaviour.
	-- `chance` = default odds (World 1). Each world has its own `odds` table below.
	{ id = "Common",    color = Color3.fromRGB(216, 221, 232), chance = 40 },  -- white / silver
	{ id = "Uncommon",  color = Color3.fromRGB(91, 227, 122),  chance = 20 },  -- green
	{ id = "Rare",      color = Color3.fromRGB(80, 160, 255),  chance = 27 },
	{ id = "Epic",      color = Color3.fromRGB(180, 90, 255),  chance = 10 },
	{ id = "Legendary", color = Color3.fromRGB(255, 190, 40),  chance = 2.7 },
	{ id = "Mythic",    color = Color3.fromRGB(255, 70, 110),  chance = 0.3 },
}

-- Pity: bad luck protection. After this many opens in one world without
-- getting that rarity (or better), the next open guarantees it.
Config.Pity = { Legendary = 75, Mythic = 400 }

-- Luck (from the Luck milestones) multiplies the odds of this rarity and every better one.
Config.LuckBoostFrom = "Epic"

Config.Combat = {
	AttackInterval = 1.0,     -- champions hit once per second
	-- (players deal no damage themselves any more: only champions do)
	MaxClicksPerSecond = 8,   -- anti-autoclicker-exploit cap
	MaxTargetDistance = 140,  -- how far away you can click an enemy to target it
	AutoTargetBase = 40,      -- auto-attack radius before Range upgrades (see Stats.AttackRange)
	AutoTargetRange = 40,     -- (old name, kept so older code keeps working; same as AutoTargetBase)
	EnemyRespawnSeconds = 1.5,
	BaseEquipSlots = 3,       -- more slots come from the Upgrades shop and the +1 Equip pass
	HitsPerAbility = 5,     -- every 5 basic hits fill the ability bar...
	AbilityMultiplier = 8,  -- ...then the ability lands one big hit worth 8 normal hits
	AttackImpact = 0.22,    -- seconds from swing start to the hit landing
}

Config.Upgrades = {
	-- automatic milestone upgrades (earned just by playing)
	Damage = {
		{ need = 500,     stat = "kills", bonus = 0.25, label = "Damage I" },
		{ need = 5000,    stat = "kills", bonus = 0.25, label = "Damage II" },
		{ need = 50000,   stat = "kills", bonus = 0.25, label = "Damage III" },
		{ need = 500000,  stat = "kills", bonus = 0.25, label = "Damage IV" },
	},
	Luck = {
		{ need = 3600,    stat = "playSeconds", bonus = 0.25, label = "Luck I (1 hour played)" },
		{ need = 10800,   stat = "playSeconds", bonus = 0.25, label = "Luck II (3 hours)" },
		{ need = 21600,   stat = "playSeconds", bonus = 0.25, label = "Luck III (6 hours)" },
		{ need = 86400,   stat = "playSeconds", bonus = 0.25, label = "Luck IV (24 hours)" },
	},
	MultiOpen = {
		{ need = 100,     stat = "orbsOpened", bonus = 2, label = "Triple Open (open 100 orbs)" },
	},
	IndexDamagePerChampion = 0.02, -- +2% damage for every unique champion discovered
}

-- Backpack size before Inventory upgrades (see Stats.InventorySize).
-- 200 to start; the 3 Backpack Space upgrades below take it to 250, 350 and 500.
Config.InventoryBase = 200
Config.BackpackSize = Config.InventoryBase -- (old name, kept so older code keeps working)

-- Movement before upgrades (see Stats.DashCharges / Stats.JumpCount).
Config.Movement = { BaseDashCharges = 1, BaseJumpCount = 2 } -- 2 = double jump

-- Passes: bought ONCE, with Gems or with Robux (either way gives the same thing).
-- gamePassId = 0 means the Robux pass isn't set up yet (the UI shows "Robux soon").
-- To sell for Robux: create the pass on the Creator Dashboard and paste its id here.
Config.PassOrder = { "AutoAttack", "AutoHatch", "ExtraEquip" }
Config.Passes = {
	AutoAttack = { name = "Auto Attack", gems = 100, robux = 49, gamePassId = 0,
		blurb = "Your champions attack the nearest enemy by themselves." },
	AutoHatch = { name = "Auto Hatch", gems = 150, robux = 79, gamePassId = 0,
		blurb = "Stand near a summon shrine and orbs open by themselves." },
	ExtraEquip = { name = "+1 Champion Equip", gems = 400, robux = 99, gamePassId = 0,
		blurb = "Bring one more champion into every fight." },
}

-- Upgrades shop (paid with Gems). Each kind is a list of levels, bought in order.
-- value = how much THAT level adds (slots, studs, charges, jumps).
Config.ShopOrder = { "Equip", "Inventory", "Range", "Dash", "Jump" }
Config.ShopInfo = {
	Equip     = { name = "Equip Slots",     blurb = "Bring more champions into every fight." },
	Inventory = { name = "Backpack Space",  blurb = "Carry more champions." },
	Range     = { name = "Auto-Attack Range", blurb = "Auto attack reaches enemies further away." },
	Dash      = { name = "Dash Charges",    blurb = "Dash more times in a row (Q)." },
	Jump      = { name = "Extra Jump",      blurb = "Double jump becomes triple jump." },
}
Config.Shop = {
	-- the most expensive items on purpose: every slot is a big damage boost
	Equip = {
		{ cost = 500,  value = 1, label = "+1 Equip Slot" },
		{ cost = 1200, value = 1, label = "+1 Equip Slot" },
		{ cost = 3000, value = 1, label = "+1 Equip Slot" },
	},
	-- 200 -> 250 -> 350 -> 500. Together they cost 460 Gems, the same as the old five +10 levels.
	-- (Players who bought more than 3 of the old levels simply count as maxed: Stats.ShopBonus caps it.)
	Inventory = {
		{ cost = 80,  value = 50,  label = "+50 Backpack Space" },
		{ cost = 150, value = 100, label = "+100 Backpack Space" },
		{ cost = 230, value = 150, label = "+150 Backpack Space" },
	},
	Range = {
		{ cost = 60,  value = 10, label = "+10 studs Range" },
		{ cost = 120, value = 10, label = "+10 studs Range" },
		{ cost = 200, value = 10, label = "+10 studs Range" },
		{ cost = 320, value = 10, label = "+10 studs Range" },
	},
	Dash = {
		{ cost = 120, value = 1, label = "2 Dash Charges" },
		{ cost = 280, value = 1, label = "3 Dash Charges" },
	},
	Jump = {
		{ cost = 250, value = 1, label = "Triple Jump" },
	},
}

-- Fusion Machine (Champion City): fuse a champion with 2 more copies of the SAME
-- champion -> it gains a star (+50% power per star). The 2 copies are used up.
-- Base price of the first star, by rarity NAME (so adding a tier never changes a price).
local FUSION_BASE_COST: { [string]: number } = {
	Common = 300, Uncommon = 800, Rare = 1500, Epic = 6000, Legendary = 25000, Mythic = 100000,
}
Config.Fusion = {
	copies = 3,          -- the target + 2 fodder copies
	maxStars = 5,
	powerPerStar = 0.5,  -- 5 stars = x3.5 power
	-- coins to go from `stars` to `stars + 1`. `rarity` is the rarity id ("Rare") or its
	-- rank number (Config.RarityById.Rare.rank): both give the same price.
	cost = function(stars: number, rarity: string | number): number
		local id = rarity
		if type(rarity) == "number" then
			-- a rank number: look up which rarity sits at that place in the list
			local r = Config.Rarities[rarity]
			id = if r then r.id else "Common"
		end
		local base = FUSION_BASE_COST[tostring(id)] or FUSION_BASE_COST.Common
		return base * 2 ^ stars
	end,
}

-- The spawn hub (tutorial + city stations). Not a numbered world.
Config.Hub = {
	id = 0, key = "Hub", name = "Champion City",
	blurb = "The spawn city. Training grounds, the Teleporter and special stations.",
	origin = Vector3.new(0, 0, 0),
	unlockCost = 0,
	orb = { name = "Starter Orb", cost = 150, pool = 1 }, -- the hub shrine sells Rift Orbs (World 1 odds and price)
	theme = { ground = Color3.fromRGB(110, 200, 90), path = Color3.fromRGB(70, 72, 80),
		accent = Color3.fromRGB(255, 205, 60), rock = Color3.fromRGB(150, 150, 160) },
	zones = { { enemy = "TrainingDummy", count = 6 } },
}

-- Worlds. Position = where the world's center sits in Workspace.
Config.Worlds = {
	{
		id = 1, key = "W1", name = "Verdant Rift",
		blurb = "Glowing grasslands split by a crystal rift.",
		origin = Vector3.new(2500, 0, 0),
		unlockCost = 0,
		orb = { name = "Rift Orb", cost = 150 },
		odds = { Common = 40, Uncommon = 20, Rare = 27, Epic = 10, Legendary = 2.7, Mythic = 0.3 },
		theme = { ground = Color3.fromRGB(98, 186, 92), path = Color3.fromRGB(214, 196, 140),
			accent = Color3.fromRGB(110, 255, 210), rock = Color3.fromRGB(120, 130, 140) },
		zones = {
			{ enemy = "LegionGrunt", count = 8 },
			{ enemy = "LegionScout", count = 7 },
			{ enemy = "LegionElite", count = 6 },
		},
		boss = "CommanderVexor",
	},
	{
		id = 2, key = "W2", name = "Coral Harbor",
		blurb = "A seaside trading port taken over by raiders.",
		origin = Vector3.new(5000, 0, 0),
		unlockCost = 25000,
		requiresBoss = "W1", -- must have helped defeat Verdant Rift's boss first
		orb = { name = "Tide Orb", cost = 2500 },
		odds = { Common = 42, Uncommon = 22, Rare = 25, Epic = 8.5, Legendary = 2.3, Mythic = 0.2 },
		theme = { ground = Color3.fromRGB(240, 215, 160), path = Color3.fromRGB(160, 110, 70),
			accent = Color3.fromRGB(255, 120, 140), rock = Color3.fromRGB(200, 130, 120) },
		zones = {
			{ enemy = "DeckThug", count = 8 },
			{ enemy = "CutlassRaider", count = 7 },
			{ enemy = "AnchorBruiser", count = 6 },
		},
		boss = "CaptainBarnacle",
	},
	{
		id = 3, key = "W3", name = "Skyforge Academy",
		blurb = "A floating academy where champions train. Home of the Tower (coming soon).",
		origin = Vector3.new(7500, 0, 0),
		unlockCost = 400000,
		requiresBoss = "W2",
		orb = { name = "Forge Orb", cost = 25000 },
		odds = { Common = 44, Uncommon = 24, Rare = 23, Epic = 7, Legendary = 1.85, Mythic = 0.15 },
		theme = { ground = Color3.fromRGB(200, 210, 235), path = Color3.fromRGB(120, 130, 170),
			accent = Color3.fromRGB(120, 200, 255), rock = Color3.fromRGB(90, 95, 120) },
		zones = {
			{ enemy = "RogueTrainee", count = 8 },
			{ enemy = "GearEnforcer", count = 7 },
			{ enemy = "ForgeSentinel", count = 6 },
		},
		boss = "HeadmasterUnit",
	},
}

-- Bosses drop this much extra on top of their coins and gems below (0.10 = +10%).
-- Gems stay whole: the leftover fraction is a chance of one extra gem, so the average
-- is exactly +10% without making gems common (CombatService applies it).
Config.BossDropBonus = 0.10

Config.Enemies = {
	-- look = how EnemyBuilder dresses the R15 body. scale = size multiplier.
	-- gems = given on every defeat. gemChance/gemDrop = a small lucky gem drop (elites).
	-- respawn = boss respawn seconds. (Numbers explained in economy_v2.md.)
	-- Hub (tutorial)
	TrainingDummy  = { name = "Training Dummy",   hp = 30,     coins = 6,      gems = 0,  scale = 1.0,
		look = { skin = Color3.fromRGB(205, 160, 105), outfit = Color3.fromRGB(170, 120, 75), outfit2 = Color3.fromRGB(140, 95, 60),
			hairStyle = "dummy", gear = { "belt" }, weapon = "none", eye = Color3.fromRGB(40, 30, 20) } },
	-- World 1: the Rift Legion (crystal-armoured soldiers)
	LegionGrunt    = { name = "Legion Grunt",     hp = 60,     coins = 5,      gems = 0,  scale = 1.0,
		look = { skin = Color3.fromRGB(235, 190, 150), outfit = Color3.fromRGB(30, 80, 90), outfit2 = Color3.fromRGB(230, 240, 240), armor = Color3.fromRGB(235, 245, 245),
			hair = Color3.fromRGB(30, 30, 40), hairStyle = "spiky", gear = { "chest", "pads", "belt" }, weapon = "blaster", eye = Color3.fromRGB(60, 200, 190) } },
	LegionScout    = { name = "Legion Scout",     hp = 400,    coins = 24,     gems = 0,  scale = 1.05,
		look = { skin = Color3.fromRGB(250, 220, 200), outfit = Color3.fromRGB(80, 50, 130), outfit2 = Color3.fromRGB(190, 195, 210), armor = Color3.fromRGB(190, 200, 215),
			hair = Color3.fromRGB(255, 110, 170), hairStyle = "mohawk", gear = { "chest", "pads", "visor", "belt" }, weapon = "sword", eye = Color3.fromRGB(255, 80, 160) } },
	LegionElite    = { name = "Legion Elite",     hp = 1800,   coins = 100,    gems = 0,  scale = 1.3, gemChance = 0.05, gemDrop = 1,
		look = { skin = Color3.fromRGB(150, 100, 70), outfit = Color3.fromRGB(140, 25, 40), outfit2 = Color3.fromRGB(240, 200, 80), armor = Color3.fromRGB(250, 205, 80),
			hair = Color3.fromRGB(240, 240, 250), hairStyle = "long", gear = { "chest", "bigpads", "belt", "cape" }, weapon = "spear", eye = Color3.fromRGB(255, 200, 60) } },
	CommanderVexor = { name = "Commander Vexor",  hp = 20000,  coins = 800,    gems = 1,  scale = 2.4, boss = true, respawn = 8,
		look = { skin = Color3.fromRGB(190, 170, 230), outfit = Color3.fromRGB(25, 20, 40), outfit2 = Color3.fromRGB(120, 60, 200), armor = Color3.fromRGB(255, 200, 70),
			hair = Color3.fromRGB(20, 15, 30), hairStyle = "horns", gear = { "chest", "bigpads", "belt", "cape" }, weapon = "greatsword", eye = Color3.fromRGB(255, 50, 80) } },
	-- World 2: harbor pirates
	DeckThug       = { name = "Deck Thug",        hp = 2000,   coins = 70,     gems = 0,  scale = 1.0,
		look = { skin = Color3.fromRGB(225, 175, 130), outfit = Color3.fromRGB(240, 240, 245), outfit2 = Color3.fromRGB(50, 70, 120),
			hair = Color3.fromRGB(200, 40, 40), hairStyle = "bandana", gear = { "belt", "stripes" }, weapon = "club", eye = Color3.fromRGB(60, 40, 30) } },
	CutlassRaider  = { name = "Cutlass Raider",   hp = 8000,   coins = 260,    gems = 0,  scale = 1.1,
		look = { skin = Color3.fromRGB(200, 150, 110), outfit = Color3.fromRGB(30, 45, 90), outfit2 = Color3.fromRGB(60, 40, 30), armor = Color3.fromRGB(230, 190, 80),
			hair = Color3.fromRGB(30, 25, 25), hairStyle = "tricorn", gear = { "coat", "belt" }, weapon = "cutlass", eye = Color3.fromRGB(40, 120, 200) } },
	AnchorBruiser  = { name = "Anchor Bruiser",   hp = 30000,  coins = 900,    gems = 0,  scale = 1.45, gemChance = 0.05, gemDrop = 2,
		look = { skin = Color3.fromRGB(170, 120, 85), outfit = Color3.fromRGB(110, 70, 45), outfit2 = Color3.fromRGB(60, 60, 70),
			hair = Color3.fromRGB(60, 40, 30), hairStyle = "bald", gear = { "vest", "belt", "beard" }, weapon = "anchor", eye = Color3.fromRGB(30, 30, 30) } },
	CaptainBarnacle= { name = "Captain Barnacle", hp = 250000, coins = 9000,   gems = 5,  scale = 2.4, boss = true, respawn = 10,
		look = { skin = Color3.fromRGB(215, 170, 130), outfit = Color3.fromRGB(150, 20, 30), outfit2 = Color3.fromRGB(30, 25, 30), armor = Color3.fromRGB(255, 210, 80),
			hair = Color3.fromRGB(240, 240, 240), hairStyle = "captain", gear = { "coat", "belt", "beard", "pads" }, weapon = "cutlass", eye = Color3.fromRGB(80, 200, 255) } },
	-- World 3: Skyforge Academy rogues and machines
	RogueTrainee   = { name = "Rogue Trainee",    hp = 18000,  coins = 500,    gems = 0,  scale = 1.0,
		look = { skin = Color3.fromRGB(245, 210, 180), outfit = Color3.fromRGB(40, 60, 150), outfit2 = Color3.fromRGB(30, 30, 40), armor = Color3.fromRGB(220, 40, 50),
			hair = Color3.fromRGB(255, 220, 70), hairStyle = "spiky", gear = { "tie", "belt" }, weapon = "fists", eye = Color3.fromRGB(255, 150, 40) } },
	GearEnforcer   = { name = "Gear Enforcer",    hp = 70000,  coins = 1800,   gems = 0,  scale = 1.15,
		look = { skin = Color3.fromRGB(230, 190, 160), outfit = Color3.fromRGB(90, 95, 110), outfit2 = Color3.fromRGB(240, 140, 50), armor = Color3.fromRGB(240, 140, 50),
			hair = Color3.fromRGB(40, 40, 50), hairStyle = "helmet", gear = { "chest", "pads", "belt" }, weapon = "hammer", eye = Color3.fromRGB(90, 220, 255) } },
	ForgeSentinel  = { name = "Forge Sentinel",   hp = 250000, coins = 6500,   gems = 0,  scale = 1.45, gemChance = 0.05, gemDrop = 4,
		look = { skin = Color3.fromRGB(170, 175, 190), outfit = Color3.fromRGB(70, 75, 90), outfit2 = Color3.fromRGB(230, 120, 40), armor = Color3.fromRGB(200, 205, 220),
			hair = Color3.fromRGB(60, 60, 70), hairStyle = "robot", gear = { "chest", "bigpads", "belt" }, weapon = "blaster", eye = Color3.fromRGB(255, 70, 50) } },
	HeadmasterUnit = { name = "Headmaster Unit",  hp = 1500000, coins = 60000, gems = 15, scale = 2.6, boss = true, respawn = 12,
		look = { skin = Color3.fromRGB(220, 225, 240), outfit = Color3.fromRGB(40, 50, 90), outfit2 = Color3.fromRGB(110, 200, 255), armor = Color3.fromRGB(255, 210, 90),
			hair = Color3.fromRGB(110, 200, 255), hairStyle = "robot", gear = { "chest", "bigpads", "belt", "cape" }, weapon = "greatsword", eye = Color3.fromRGB(110, 220, 255) } },
}

-- Champions. power = damage per hit (before fusion stars: see Stats.ChampionPower).
-- look: colors + hair/weapon style used to build their model.
Config.Champions = {
	-- Verdant Rift
	{ id = "PipSprout",     name = "Pip Sprout",       world = 1, rarity = "Common",    power = 5,
		look = { skin = Color3.fromRGB(255, 220, 180), outfit = Color3.fromRGB(110, 200, 90),  hair = Color3.fromRGB(70, 150, 60),  hairStyle = "leaf",   weapon = "none" } },
	{ id = "BrambleKid",    name = "Bramble Kid",      world = 1, rarity = "Uncommon",  power = 6,
		look = { skin = Color3.fromRGB(230, 180, 140), outfit = Color3.fromRGB(140, 100, 60),  hair = Color3.fromRGB(90, 60, 40),   hairStyle = "messy",  weapon = "stick" } },
	{ id = "LumenFox",      name = "Lumen Fox",        world = 1, rarity = "Rare",      power = 13,
		look = { skin = Color3.fromRGB(255, 225, 190), outfit = Color3.fromRGB(255, 150, 60),  hair = Color3.fromRGB(255, 120, 40),  hairStyle = "ears",   weapon = "none" } },
	{ id = "SageWillow",    name = "Sage Willow",      world = 1, rarity = "Epic",      power = 32,
		look = { skin = Color3.fromRGB(240, 210, 180), outfit = Color3.fromRGB(80, 160, 140),  hair = Color3.fromRGB(230, 240, 230), hairStyle = "long",   weapon = "staff" } },
	{ id = "RiftRangerKael",name = "Rift Ranger Kael", world = 1, rarity = "Legendary", power = 85,
		look = { skin = Color3.fromRGB(220, 170, 130), outfit = Color3.fromRGB(40, 70, 60),    hair = Color3.fromRGB(30, 30, 40),    hairStyle = "spiky",  weapon = "bow" } },
	{ id = "VerdantOriel",  name = "Verdant Titan Oriel", world = 1, rarity = "Mythic", power = 230,
		look = { skin = Color3.fromRGB(250, 230, 200), outfit = Color3.fromRGB(20, 120, 90),   hair = Color3.fromRGB(110, 255, 210), hairStyle = "flame",  weapon = "sword" } },
	-- Coral Harbor
	{ id = "DeckhandDex",   name = "Deckhand Dex",     world = 2, rarity = "Common",    power = 40,
		look = { skin = Color3.fromRGB(230, 180, 140), outfit = Color3.fromRGB(70, 110, 170),  hair = Color3.fromRGB(200, 60, 50),   hairStyle = "bandana", weapon = "stick" } },
	{ id = "BubbleBo",      name = "Bubble Bo",        world = 2, rarity = "Uncommon",  power = 45,
		look = { skin = Color3.fromRGB(255, 220, 190), outfit = Color3.fromRGB(120, 210, 230), hair = Color3.fromRGB(80, 170, 220),  hairStyle = "messy",  weapon = "none" } },
	{ id = "TidecallerMina",name = "Tidecaller Mina",  world = 2, rarity = "Rare",      power = 95,
		look = { skin = Color3.fromRGB(240, 200, 170), outfit = Color3.fromRGB(40, 150, 180),  hair = Color3.fromRGB(30, 80, 160),   hairStyle = "long",   weapon = "staff" } },
	{ id = "HarpoonRook",   name = "Harpoon Rook",     world = 2, rarity = "Epic",      power = 230,
		look = { skin = Color3.fromRGB(190, 140, 100), outfit = Color3.fromRGB(120, 80, 50),   hair = Color3.fromRGB(240, 240, 240), hairStyle = "spiky",  weapon = "spear" } },
	{ id = "StormCorsairVale", name = "Storm Corsair Vale", world = 2, rarity = "Legendary", power = 620,
		look = { skin = Color3.fromRGB(240, 205, 170), outfit = Color3.fromRGB(30, 30, 60),    hair = Color3.fromRGB(150, 40, 60),   hairStyle = "hat",    weapon = "sword" } },
	{ id = "LeviathanNerissa", name = "Leviathan Queen Nerissa", world = 2, rarity = "Mythic", power = 1650,
		look = { skin = Color3.fromRGB(220, 240, 250), outfit = Color3.fromRGB(20, 60, 120),   hair = Color3.fromRGB(80, 255, 230),  hairStyle = "crown",  weapon = "trident" } },
	-- Skyforge Academy
	{ id = "CadetBolt",     name = "Cadet Bolt",       world = 3, rarity = "Common",    power = 300,
		look = { skin = Color3.fromRGB(240, 200, 160), outfit = Color3.fromRGB(70, 80, 140),   hair = Color3.fromRGB(250, 220, 60),  hairStyle = "spiky",  weapon = "none" } },
	{ id = "Gearling",      name = "Gearling",         world = 3, rarity = "Uncommon",  power = 330,
		look = { skin = Color3.fromRGB(180, 190, 200), outfit = Color3.fromRGB(230, 140, 60),  hair = Color3.fromRGB(120, 130, 140), hairStyle = "antenna", weapon = "wrench" } },
	{ id = "SparkIvy",      name = "Spark Prodigy Ivy",world = 3, rarity = "Rare",      power = 720,
		look = { skin = Color3.fromRGB(255, 225, 200), outfit = Color3.fromRGB(240, 240, 255), hair = Color3.fromRGB(160, 90, 255),  hairStyle = "twin",   weapon = "staff" } },
	{ id = "InstructorRen", name = "Blade Instructor Ren", world = 3, rarity = "Epic",  power = 1750,
		look = { skin = Color3.fromRGB(220, 175, 140), outfit = Color3.fromRGB(30, 30, 35),    hair = Color3.fromRGB(200, 200, 210), hairStyle = "long",   weapon = "sword" } },
	{ id = "AetherCalder",  name = "Aether Knight Calder", world = 3, rarity = "Legendary", power = 4600,
		look = { skin = Color3.fromRGB(240, 210, 180), outfit = Color3.fromRGB(220, 230, 250), hair = Color3.fromRGB(60, 140, 255),  hairStyle = "helmet", weapon = "sword" } },
	{ id = "ParagonAstra",  name = "Skyforge Paragon Astra", world = 3, rarity = "Mythic", power = 12500,
		look = { skin = Color3.fromRGB(255, 235, 215), outfit = Color3.fromRGB(255, 200, 80),  hair = Color3.fromRGB(255, 255, 255), hairStyle = "flame",  weapon = "spear" } },
}

-- Starter champions: offered (pick 1 of 3) when the tutorial is finished. Not in any orb.
Config.Starters = { "KaitoEmberfist", "RinTidecutter", "JunoGaleshot" }
for _, c in {
	-- Common on purpose: a little stronger than Pip Sprout, so the first orbs still feel exciting
	{ id = "KaitoEmberfist", name = "Kaito Emberfist", world = 0, rarity = "Common", power = 7, starter = true, look = {} },
	{ id = "RinTidecutter",  name = "Rin Tidecutter",  world = 0, rarity = "Common", power = 7, starter = true, look = {} },
	{ id = "JunoGaleshot",   name = "Juno Galeshot",   world = 0, rarity = "Common", power = 7, starter = true, look = {} },
} do table.insert(Config.Champions, c) end

-- Quick lookups
Config.ChampionById = {}
for _, c in Config.Champions do Config.ChampionById[c.id] = c end
Config.RarityById = {}
for i, r in Config.Rarities do Config.RarityById[r.id] = r; (r :: any).rank = i end

-- True if `rarityId` is `threshold` or better, by NAME:
--   Config.RarityAtLeast("Mythic", "Epic") --> true,  Config.RarityAtLeast("Rare", "Epic") --> false
-- Use this instead of comparing rank numbers, so inserting a new tier never shifts behaviour.
-- Unknown ids give false. (A rarity table from Config.Rarities works too.)
function Config.RarityAtLeast(rarityId: any, threshold: string): boolean
	local id = if type(rarityId) == "table" then rarityId.id else rarityId
	local rarity = Config.RarityById[id]
	local limit = Config.RarityById[threshold]
	if not rarity or not limit then return false end
	return (rarity :: any).rank >= (limit :: any).rank
end

-- World 0 is the hub (Champion City); 1+ are the numbered worlds.
function Config.WorldById(id: number)
	if id == 0 then return Config.Hub end
	return Config.Worlds[id]
end

-- World by key ("Hub", "W1", ...). Returns nil if unknown.
function Config.WorldByKey(key: string)
	if key == Config.Hub.key then return Config.Hub end
	for _, w in Config.Worlds do
		if w.key == key then return w end
	end
	return nil
end

-- Update log (newest first), shown by the Updates button.
Config.UpdateLog = {
	{ version = "1.3", date = "22 Oct 2026", notes = {
		"New loading screen that shows what's loading and gets you in the moment you're ready.",
		"Every world has its own light and atmosphere now, from Champion City's warm afternoon to Skyforge's crisp sky air.",
		"Skyforge Academy is in bloom: white-blue blossom trees, banners, lanterns and lit paths. More flowers and details across every world.",
		"Each summon altar has its own orb: aether, crystal, tide and forge.",
		"Teleporters and world gates are now living portals, with a swirl and the world's name as you travel.",
		"Sensei Hikari waves when you arrive, watches you and nods while she talks.",
		"Enemies have more personality: they turn to face your champions, flinch harder from abilities, and bosses roar between fights.",
		"Clearer training: a step tracker, a trail to your next goal and a highlight on the button to press.",
		"Bosses drop 10% more coins and gems. Boss kills now show a BOSS DEFEATED card.",
		"Much bigger backpack: 200 champions to start, and Backpack Space upgrades take it to 250, 350 and 500.",
	} },
	{ version = "1.2", date = "21 Oct 2026", notes = {
		"Cinematic summons! Every altar now has a magic summoning circle, and each rarity gets its own summon sequence, from a quick silver sparkle to a crimson Mythic eruption.",
		"New rarity: Uncommon (green), between Common and Rare.",
		"Multi-summons burst into a lineup of crystal seeds that bloom one by one, saving the best for last.",
		"Tap SKIP to jump to your results, or hold the screen (or Space) to fast-forward.",
		"New results screen: Equip straight away, Summon Again or Close. Duplicates show how close you are to a fusion.",
		"Champion abilities now show a ring on the ground that fills up exactly when the hit lands.",
		"Legendary and Mythic champions announce their ultimate with a banner across your screen.",
		"Other players' champion effects are toned down, so busy fights stay easy to read.",
	} },
	{ version = "1.1", date = "18 Oct 2026", notes = {
		"New passes: Auto Attack, Auto Hatch and +1 Champion Equip. Earn Gems by playing to unlock them, or get them with Robux.",
		"New Upgrades shop: spend Gems on more equip slots, backpack space, auto-attack range, dash charges and triple jump.",
		"Press Q (or tap the dash button) to dash, and jump again in mid-air for a double jump!",
		"The Fusion Machine in Champion City works! Fuse 3 copies of the same champion to give it a star (+50% power, up to 5 stars).",
		"Rename your champions in the inventory. The inventory now shows each champion's DPS and ability.",
		"Champions show their name above their head and never push you or block your path.",
		"Every boss now has a summon shrine next to it, so you can hatch and fight at the same time.",
		"Bosses respawn much faster and always in the middle of their arena. Defeat a world's boss to unlock the next world.",
		"AFK friendly: if you stay idle for a long time you are rejoined automatically and keep your world, spot and auto settings.",
		"Click enemies from much further away. Your auto-attack range is shown as a ring around you.",
		"The ability bar now empties after each ability and fills up again with every hit.",
		"Your starter champion now joins you after the summon ceremony.",
		"Your champions do all the fighting now: they are your only source of damage.",
		"Balance: enemies are tougher, the best champions get rarer in each new world, and Gems mostly come from bosses and quests.",
		"This Updates button: check here to see what's new!",
	} },
	{ version = "1.0", date = "Launch", notes = {
		"Three worlds to explore: Verdant Rift, Coral Harbor and Skyforge Academy.",
		"Collect champions from orbs. Every champion has its own special ability.",
		"Sensei Hikari's training and quest line.",
		"Champion Index, milestone upgrades and bad-luck protection on orbs.",
	} },
}

return Config
