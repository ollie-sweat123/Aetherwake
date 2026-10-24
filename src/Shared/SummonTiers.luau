-- SummonTiers: everything that makes each rarity's summon LOOK and SOUND different.
-- SummonCinematic reads this table; it has no rarity-specific code of its own.
--
-- Adding a new tier later = add its id to SummonTiers.order (lowest -> highest)
-- and add one entry to SummonTiers.tiers (copy the closest tier and tweak it).
--
-- Field guide (all optional except palette/times; missing fields use DEFAULT):
--   palette      main / light / dark / glow colours of the effects
--   times        seconds for each phase: charge (altar absorbs energy), build (sphere grows),
--                reveal (champion on screen), outro (fade back). Total = the summon length.
--                Targets: Common 1-2 s, Uncommon 2-3, Rare 3-4, Epic 4-5, Legendary 5-7, Mythic 7-10.
--   silence      seconds of quiet between build and reveal (Mythic). Skipped by quick summons.
--   rings        energy rings around the sphere      ringSpeed     radians per second
--   counterRotate  every other ring spins the other way
--   spiral       glowing wisps spiral up into the sphere
--   lightning    0..1 how often bolts crackle off the sphere
--   runes        floating rune tablets orbiting the sphere
--   floorBeams   light shafts rising from the summon circle
--   pillars      giant light pillars around the summon spot
--   altarBeams   how many of the altar's floor beams feed the crystal
--   sphereScale  sphere size (1 = 3.4 studs wide)
--   pulses       sphere throbs (each throb pushes out a ring)
--   shockwave    radius (studs) of the ground shockwave at the reveal (0 = none)
--   flash        0..0.35 max screen-flash opacity (keep it gentle!)
--   shake        0..0.35 camera shake strength (keep it gentle!)
--   darken       0..0.5 how much the scene darkens during the build-up
--   camera       "hold" | "push" | "orbit" | "zoom"
--   banner       nil | "LEGENDARY" | "MYTHIC" (big title on screen)   bannerStyle: how it looks
--   darkSpread   dark energy spreads over the ground before the colour erupts (Mythic)
--   falseColor   colour shown first during the charge before the real one (Mythic fakes gold)
--   darkPalette  palette of the dark-energy moment (darkSpread tiers)
--   championScale / pose   how big the champion appears and its Shared.Anim pose name
--   converge     particles per second flowing into the sphere
--   burst        sparkles thrown out at the reveal
--   rays         light rays fanning out behind the champion at the big reveal (0 = none)   raySpeed: their spin
--   rayDark      every other ray is dark (palette.dark) instead of glowing: a crimson + black fan (Mythic)
--   revealDarken how dark the scene stays while the champion is revealed (default: darken * 0.55)
--   sounds       asset ids ("rbxassetid://...") or nil. Only ids verified in Studio are used.
--   soundTweaks  optional volume / pitch per sound hook

local SummonTiers = {}

local hex = Color3.fromHex
local function id(n: number): string
	return "rbxassetid://" .. tostring(n)
end

-- Verified sounds (each was loaded in Studio: IsLoaded = true and TimeLength > 0).
-- Names come from the Creator Store listing.
local SFX = {
	magicCharge     = id(5696557721),      -- "Magic Charge" (2.0 s)
	chargeBurst     = id(122439012218772), -- "Magic Energy Charge Burst" (2.9 s)
	sparkleWhoosh   = id(9125635247),      -- "Magical Exit Sparkling Pass By" (3.8 s, Pro Sound Effects)
	holyCharge      = id(101919830811678), -- "Holy Magic Charge" (6.9 s)
	forceFieldLoop  = id(9116386800),      -- "Magic Force Field Constant" hum loop (36 s, Pro Sound Effects)
	eerieRumbleLoop = id(9112775629),      -- "Eerie Presence" low rumble loop (36 s, Pro Sound Effects)
	noiseBuild      = id(1837834264),      -- "Reverse Hard Stop - Noise Build 03" (4.0 s, APM)
	bruteRise       = id(9045201066),      -- "Brute Force Rise" (6.8 s, APM)
	orchestralRiser = id(9040281199),      -- "Heated Hijack" orchestral riser (6.1 s, APM)
	heartStopRise   = id(9048833789),      -- "Heart Stopper Rise" (9.7 s, APM)
	chimeSoft       = id(9116394545),      -- "Magic Glows Soft Chiming Hits 1" (1.4 s, Pro Sound Effects)
	chimeBright     = id(9116395089),      -- "Magic Glows Soft Chiming Hits 4" (2.5 s, Pro Sound Effects)
	chimeLong       = id(9116395085),      -- "Magic Glows Soft Chiming Hits 5" (4.5 s, Pro Sound Effects)
	bellTree        = id(9119447936),      -- "Sparkle Bell Tree Wind Chimes" (5.3 s, Pro Sound Effects)
	slamShockwave   = id(74149238738530),  -- "Ground Slam Impact Shockwave" (2.2 s)
	bigHit          = id(1835345220),      -- "Big Enemies Hit" (6.1 s, APM)
	lowImpact       = id(9113436052),      -- "Big Low-End Impacts, Resonant Hit" (7.0 s, Pro Sound Effects)
	metalHit        = id(9041754067),      -- "Ghost With The Most Metal Hit" (5.6 s, APM)
	lightning       = id(9116274992),      -- "Lightning Flashes Quick Electrical Bursts" (4.7 s, Pro Sound Effects)
	uiClick         = id(117649901456711), -- "ui_button_click" (0.55 s)
}
SummonTiers.SFX = SFX

-- Sounds for the summon UI (the HUD can play these through SummonCinematic.PlayUiSound)
SummonTiers.ui = { click = SFX.uiClick }

-- Lowest -> highest. Used to find the best result of a multi-summon.
SummonTiers.order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- The colour EVERY summon starts with, so a low roll isn't spoiled in the first moment.
-- The tier's own colour creeps in from ~40 % of the charge.
SummonTiers.neutral = { main = hex("#BFE3FF"), light = hex("#FFFFFF"), dark = hex("#2A3A58"), glow = hex("#E3F3FF") }

-- Safe values for any field a tier leaves out (and for unknown rarity ids).
local DEFAULT = {
	palette = { main = hex("#D8DDE8"), light = hex("#FFFFFF"), dark = hex("#7D8597"), glow = hex("#EEF3FF") },
	times = { charge = 0.55, build = 0.5, reveal = 0.75, outro = 0.2 },
	rings = 1, ringSpeed = 1.6, counterRotate = false, spiral = false, lightning = 0, runes = 0,
	floorBeams = 0, pillars = 0, altarBeams = 2, sphereScale = 0.8, pulses = 0, shockwave = 6,
	flash = 0.06, shake = 0, darken = 0.08, camera = "hold", banner = nil, bannerStyle = nil,
	darkSpread = false, converge = 10, burst = 20, rays = 0, raySpeed = 0.25, championScale = 1.3, pose = "handsOnHips",
	sounds = { charge = SFX.magicCharge, reveal = SFX.chimeSoft },
	soundTweaks = {},
}
SummonTiers.DEFAULT = DEFAULT

SummonTiers.tiers = {
	-- small, quick and clean: white/silver sparkle
	Common = {
		palette = { main = hex("#D8DDE8"), light = hex("#FFFFFF"), dark = hex("#7D8597"), glow = hex("#EEF3FF") },
		times = { charge = 0.5, build = 0.45, reveal = 0.7, outro = 0.15 }, -- 1.8 s
		rings = 1, ringSpeed = 1.6, sphereScale = 0.75, shockwave = 6, flash = 0.06, shake = 0,
		darken = 0.08, camera = "hold", altarBeams = 2, converge = 10, burst = 20,
		sounds = { charge = SFX.magicCharge, reveal = SFX.chimeSoft },
		soundTweaks = { charge = { volume = 0.35 }, reveal = { volume = 0.45 } },
	},
	-- green rings + a rising spiral
	Uncommon = {
		palette = { main = hex("#5BE37A"), light = hex("#C9FFD5"), dark = hex("#1E7A3A"), glow = hex("#8CFFA6") },
		times = { charge = 0.7, build = 0.75, reveal = 0.95, outro = 0.2 }, -- 2.6 s
		rings = 2, ringSpeed = 2.0, spiral = true, sphereScale = 0.9, pulses = 1, shockwave = 8,
		flash = 0.08, shake = 0.03, darken = 0.12, camera = "hold", altarBeams = 3, converge = 14, burst = 28,
		sounds = { charge = SFX.magicCharge, reveal = SFX.chimeBright },
		soundTweaks = { charge = { volume = 0.38, pitch = 1.08 }, reveal = { volume = 0.45 } },
	},
	-- blue lightning, counter-rotating rings, small shockwave
	Rare = {
		palette = { main = hex("#4AA8FF"), light = hex("#CFE8FF"), dark = hex("#1546A0"), glow = hex("#7CC4FF") },
		times = { charge = 0.9, build = 1.2, reveal = 1.15, outro = 0.25 }, -- 3.5 s
		rings = 2, ringSpeed = 2.6, counterRotate = true, lightning = 0.45, sphereScale = 1.05, pulses = 1,
		shockwave = 11, flash = 0.12, shake = 0.08, darken = 0.2, camera = "push", altarBeams = 4,
		converge = 20, burst = 36, rays = 10, pose = "victory",
		sounds = { ambience = SFX.forceFieldLoop, charge = SFX.chargeBurst, build = SFX.noiseBuild,
			reveal = SFX.bellTree, impact = SFX.slamShockwave, lightning = SFX.lightning },
		soundTweaks = { ambience = { volume = 0.25 }, charge = { volume = 0.4 }, build = { volume = 0.35 },
			reveal = { volume = 0.45 }, impact = { volume = 0.22, pitch = 1.15 }, lightning = { volume = 0.2 } },
	},
	-- purple runes, floor light shafts, multi-pulse burst, camera move
	Epic = {
		palette = { main = hex("#B45CFF"), light = hex("#EBD2FF"), dark = hex("#4A1A8C"), glow = hex("#D39BFF") },
		times = { charge = 1.05, build = 1.7, reveal = 1.45, outro = 0.3 }, -- 4.5 s
		rings = 3, ringSpeed = 3.0, counterRotate = true, lightning = 0.3, runes = 6, floorBeams = 6,
		sphereScale = 1.2, pulses = 3, shockwave = 14, flash = 0.16, shake = 0.12, darken = 0.3,
		camera = "push", altarBeams = 5, converge = 26, burst = 48, rays = 14, pose = "victory",
		sounds = { ambience = SFX.forceFieldLoop, charge = SFX.sparkleWhoosh, build = SFX.bruteRise,
			reveal = SFX.chimeLong, impact = SFX.slamShockwave, lightning = SFX.lightning },
		soundTweaks = { ambience = { volume = 0.3 }, charge = { volume = 0.45 }, build = { volume = 0.4 },
			reveal = { volume = 0.5 }, impact = { volume = 0.35 }, lightning = { volume = 0.18 } },
	},
	-- gold everything: pillars, big sphere, cinematic orbit, flash, LEGENDARY banner
	Legendary = {
		palette = { main = hex("#FFC23D"), light = hex("#FFF3C4"), dark = hex("#A8620A"), glow = hex("#FFE08A") },
		times = { charge = 1.3, build = 2.4, reveal = 1.9, outro = 0.3 }, -- 5.9 s
		rings = 3, ringSpeed = 3.4, counterRotate = true, spiral = true, lightning = 0.35, runes = 8,
		floorBeams = 6, pillars = 4, sphereScale = 1.45, pulses = 3, shockwave = 18, flash = 0.24,
		shake = 0.18, darken = 0.38, camera = "orbit", altarBeams = 6, converge = 32, burst = 64, rays = 18, raySpeed = 0.3,
		championScale = 1.4, pose = "victory",
		banner = "LEGENDARY",
		bannerStyle = { font = Enum.Font.LuckiestGuy, top = hex("#FFF6CF"), bottom = hex("#FFB31A"),
			stroke = hex("#5A3000"), shine = true, band = false, glitch = false },
		sounds = { ambience = SFX.forceFieldLoop, charge = SFX.holyCharge, build = SFX.orchestralRiser,
			reveal = SFX.chimeLong, impact = SFX.bigHit, lightning = SFX.lightning },
		soundTweaks = { ambience = { volume = 0.3, pitch = 0.9 }, charge = { volume = 0.45 }, build = { volume = 0.45 },
			reveal = { volume = 0.5, pitch = 0.92 }, impact = { volume = 0.5 }, lightning = { volume = 0.16 } },
	},
	-- crimson + black: dark energy spreads, then crimson erupts. Red lightning, zoom, big shockwave.
	Mythic = {
		-- (light is a deeper rose than a plain tint, so the shell, bolts and rays read crimson, not pink)
		palette = { main = hex("#FF2E50"), light = hex("#FF9DAD"), dark = hex("#14000A"), glow = hex("#FF5C76") },
		times = { charge = 1.5, build = 3.0, reveal = 2.4, outro = 0.4 }, -- 7.3 s + 0.6 s silence = 7.9 s
		silence = 0.6, -- a held breath before the reveal: the riser cuts out, then the hit
		rings = 4, ringSpeed = 3.8, counterRotate = true, spiral = true, lightning = 0.85, runes = 8,
		floorBeams = 8, pillars = 0, sphereScale = 1.6, pulses = 4, shockwave = 24, flash = 0.3,
		shake = 0.25, darken = 0.5, camera = "zoom", altarBeams = 6, converge = 36, burst = 72, rays = 22, raySpeed = -0.35,
		rayDark = true, revealDarken = 0.4, -- the reveal stays darker than any other tier: the champion is the only bright thing
		darkSpread = true, championScale = 1.45, pose = "victory",
		falseColor = hex("#FFC23D"), -- looks like a Legendary at first...
		darkPalette = { main = hex("#5A0A22"), light = hex("#2A0010"), dark = hex("#000000"), glow = hex("#8C1434") },
		banner = "MYTHIC",
		bannerStyle = { font = Enum.Font.PermanentMarker, top = hex("#FFD6DC"), bottom = hex("#FF1F45"),
			stroke = hex("#000000"), shine = false, band = true, glitch = true },
		sounds = { ambience = SFX.eerieRumbleLoop, charge = SFX.holyCharge, build = SFX.heartStopRise,
			reveal = SFX.chimeLong, impact = SFX.lowImpact, banner = SFX.metalHit, lightning = SFX.lightning },
		soundTweaks = { ambience = { volume = 0.4 }, charge = { volume = 0.4, pitch = 0.75 }, build = { volume = 0.45 },
			reveal = { volume = 0.45, pitch = 0.8 }, impact = { volume = 0.55 }, banner = { volume = 0.4 },
			lightning = { volume = 0.22, pitch = 0.8 } },
	},
}

-- Fill every tier's missing fields from DEFAULT once, so the cinematic never meets a nil.
local function fill(tier: { [string]: any }, rarityId: string)
	tier.id = rarityId
	for k, v in DEFAULT do
		if tier[k] == nil then tier[k] = v end
	end
	for _, sub in { "palette", "times" } do
		for k, v in DEFAULT[sub] do
			if tier[sub][k] == nil then tier[sub][k] = v end
		end
	end
	return tier
end
for rarityId, tier in SummonTiers.tiers do fill(tier, rarityId) end

-- rank: position in SummonTiers.order (1 = lowest). Unknown ids rank 0.
function SummonTiers.rank(rarityId: string?): number
	return (rarityId and table.find(SummonTiers.order, rarityId)) or 0
end

-- get: the tier for a rarity id. Unknown ids get a safe tier built from DEFAULT,
-- coloured with Config's rarity colour when Config knows that rarity.
local fallbackCache = {}
function SummonTiers.get(rarityId: string?): { [string]: any }
	local tier = rarityId and SummonTiers.tiers[rarityId]
	if tier then return tier end
	local key = tostring(rarityId)
	if fallbackCache[key] then return fallbackCache[key] end
	local made = { palette = table.clone(DEFAULT.palette), times = table.clone(DEFAULT.times) }
	local ok, Config = pcall(function() return require(script.Parent:WaitForChild("Config", 2)) end)
	local info = ok and Config and Config.RarityById and Config.RarityById[key]
	if info and typeof(info.color) == "Color3" then
		made.palette.main = info.color
		made.palette.glow = info.color:Lerp(Color3.new(1, 1, 1), 0.35)
		made.palette.light = info.color:Lerp(Color3.new(1, 1, 1), 0.7)
		made.palette.dark = info.color:Lerp(Color3.new(0, 0, 0), 0.6)
	end
	fill(made, key)
	fallbackCache[key] = made
	return made
end

-- best: the highest rarity id in a list of ids (ignores unknown ones unless all are unknown)
function SummonTiers.best(rarityIds: { string }): string?
	local bestId, bestRank = nil, -1
	for _, r in rarityIds do
		local rk = SummonTiers.rank(r)
		if rk > bestRank then bestId, bestRank = r, rk end
	end
	return bestId
end

-- total seconds a single summon of this rarity takes (handy for UI timers)
function SummonTiers.duration(rarityId: string?): number
	local tier = SummonTiers.get(rarityId)
	local t = tier.times
	return t.charge + t.build + (tonumber(tier.silence) or 0) + t.reveal + t.outro
end

return SummonTiers
