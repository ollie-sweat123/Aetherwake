--!strict
-- AudioConfig: every sound the game uses outside the summon cinematic, in ONE place.
-- (The summon's own sounds stay in Shared.SummonTiers, which this file reuses.)
--
-- Rules for adding a sound:
--   * Only ids that were loaded in Studio (ContentProvider:PreloadAsync, IsLoaded = true,
--     TimeLength > 0) go in here. Never guess an id.
--   * Prefer Roblox's licensed libraries: Pro Sound Effects (PSE) and APM Music. Both are free
--     for every experience. User uploads are marked "(user upload)" so they are easy to swap.
--   * A missing or broken id is never fatal: Shared.Audio skips it and warns once.
--
-- Groups (each has its own slider in Settings > Sound, and Master scales them all):
--   Music     background music            Ambience  world ambience loops
--   Sfx       abilities, hits, movement, summons, world events
--   Ui        menu clicks, panel open/close, rewards

local SummonTiers = require(script.Parent:WaitForChild("SummonTiers"))

local AudioConfig = {}

local function id(n: number): string
	return "rbxassetid://" .. tostring(n)
end
local S = SummonTiers.SFX

export type SoundDef = {
	id: string, group: string, volume: number?, pitch: number?, pitchJitter: number?,
	looped: boolean?, gap: number?, -- gap = shortest time (s) between two plays of this sound
}

-- Every sound by name. volume is the sound's own level before the player's sliders.
AudioConfig.Sounds = {
	-- MUSIC (APM Music) ----------------------------------------------------------------------
	hubMusic1    = { id = id(1846523270), group = "Music", volume = 0.35 },  -- "Dream Walk B" (133 s)
	hubMusic2    = { id = id(1846811686), group = "Music", volume = 0.35 },  -- "Positive Progression B" (122 s)
	worldMusic   = { id = id(1844412739), group = "Music", volume = 0.32 },  -- "Heroic Sentiment" (93 s)
	combatMusic  = { id = id(9045942872), group = "Music", volume = 0.3 },   -- "Secret Warrior - Alternative Mix" (118 s)
	bossMusic1   = { id = id(9046505640), group = "Music", volume = 0.34 },  -- "Imminent Closure (Underscore A)" (111 s)
	bossMusic2   = { id = id(1837267934), group = "Music", volume = 0.34 },  -- "The King Immortal" (93 s)
	bossMusic3   = { id = id(1846428560), group = "Music", volume = 0.34 },  -- "Forces Of Nature B" (122 s)
	rewardSting  = { id = id(94590027038118), group = "Music", volume = 0.4 }, -- "Victorious Journey Sting" (7 s)

	-- AMBIENCE (Pro Sound Effects) -----------------------------------------------------------
	ambHub       = { id = id(9112749254), group = "Ambience", volume = 0.3, looped = true },  -- "Birds Park 1" (36 s loop)
	ambVerdant   = { id = id(9114894364), group = "Ambience", volume = 0.32, looped = true }, -- "Jungle Dawn 5" (62 s)
	ambCoral     = { id = id(9112751378), group = "Ambience", volume = 0.3, looped = true },  -- "British Surf Birds 1" (36 s loop)
	ambSkyforge  = { id = id(9112832288), group = "Ambience", volume = 0.28, looped = true }, -- "Mountain Birds 1" (31 s loop)
	ambSkyforge2 = { id = id(9112832297), group = "Ambience", volume = 0.2, looped = true },  -- "Mountain Birds" #2 (40 s)
	ambBoss      = { id = S.eerieRumbleLoop, group = "Ambience", volume = 0.18, looped = true }, -- "Eerie Presence" (36 s loop)

	-- COMBAT: weapons and hits ---------------------------------------------------------------
	swordSwish1  = { id = id(84614813463533), group = "Sfx", volume = 0.35, pitchJitter = 0.08, gap = 0.04 },  -- sword swing (user upload, 1.1 s)
	swordSwish2  = { id = id(133897513992414), group = "Sfx", volume = 0.35, pitchJitter = 0.08, gap = 0.04 }, -- sword swing (user upload, 1.3 s)
	swordDraw    = { id = id(9119742466), group = "Sfx", volume = 0.35, pitchJitter = 0.05 }, -- PSE sword draw (0.7 s)
	swordDraw2   = { id = id(9119742750), group = "Sfx", volume = 0.35, pitchJitter = 0.05 }, -- PSE sword draw (0.7 s)
	punch1       = { id = id(74041775202019), group = "Sfx", volume = 0.4, pitchJitter = 0.08, gap = 0.04 },  -- heavy punch (user upload, 2.8 s)
	punch2       = { id = id(126976659766267), group = "Sfx", volume = 0.35, pitchJitter = 0.1, gap = 0.04 }, -- punch (user upload, 1.5 s)
	whipHit      = { id = id(9113637277), group = "Sfx", volume = 0.3, pitchJitter = 0.08, gap = 0.04 },  -- PSE whip crack (0.8 s)
	arrow        = { id = id(9113166206), group = "Sfx", volume = 0.35, pitchJitter = 0.06, gap = 0.05 }, -- PSE arrow fly-by (2.6 s)
	arrow2       = { id = id(9113166361), group = "Sfx", volume = 0.35, pitchJitter = 0.06, gap = 0.05 }, -- PSE arrow fly-by (2.7 s)
	slam         = { id = S.slamShockwave, group = "Sfx", volume = 0.45, pitchJitter = 0.05 },            -- "Ground Slam Impact Shockwave"
	bigHit       = { id = S.bigHit, group = "Sfx", volume = 0.4 },                                        -- APM "Big Enemies Hit"
	lowImpact    = { id = S.lowImpact, group = "Sfx", volume = 0.4 },                                     -- PSE resonant low hit
	metalHit     = { id = S.metalHit, group = "Sfx", volume = 0.3 },                                      -- APM metal hit

	-- ELEMENTS (Pro Sound Effects unless noted) ----------------------------------------------
	fireWhoosh   = { id = id(9114446852), group = "Sfx", volume = 0.4, pitchJitter = 0.06 }, -- fire whoosh (0.8 s)
	fireWhoosh2  = { id = id(9114444008), group = "Sfx", volume = 0.4, pitchJitter = 0.06 }, -- fire burst (1.4 s)
	waterSplash  = { id = id(9125703162), group = "Sfx", volume = 0.4, pitchJitter = 0.06 }, -- splash (0.8 s)
	bigSplash    = { id = id(9120585252), group = "Sfx", volume = 0.4 },                     -- big splash (3.6 s)
	bubbles      = { id = id(9112872239), group = "Sfx", volume = 0.35, pitchJitter = 0.1 },  -- bubbles (0.8 s)
	zap          = { id = id(9116277954), group = "Sfx", volume = 0.3, pitchJitter = 0.08 },  -- electric zap (2.0 s)
	lightning    = { id = S.lightning, group = "Sfx", volume = 0.25 },                        -- quick electrical bursts
	magicCharge  = { id = S.magicCharge, group = "Sfx", volume = 0.3, pitchJitter = 0.05 },   -- "Magic Charge" (2.0 s)
	chargeBurst  = { id = S.chargeBurst, group = "Sfx", volume = 0.3 },                       -- "Magic Energy Charge Burst"
	holyCharge   = { id = S.holyCharge, group = "Sfx", volume = 0.3 },                        -- "Holy Magic Charge" (6.9 s)
	sparkle      = { id = S.sparkleWhoosh, group = "Sfx", volume = 0.3 },                     -- "Magical Exit Sparkling Pass By"
	chimeSoft    = { id = S.chimeSoft, group = "Sfx", volume = 0.3, pitchJitter = 0.08 },     -- soft chiming hit
	chimeBright  = { id = S.chimeBright, group = "Sfx", volume = 0.3 },                       -- bright chiming hit

	-- MOVEMENT -------------------------------------------------------------------------------
	airWhoosh    = { id = id(9114157793), group = "Sfx", volume = 0.3, pitchJitter = 0.08, gap = 0.05 }, -- PSE air whoosh (2.3 s)
	airWhoosh2   = { id = id(9114159112), group = "Sfx", volume = 0.3, pitchJitter = 0.08, gap = 0.05 }, -- PSE air whoosh (2.1 s)

	-- WORLD + UI -----------------------------------------------------------------------------
	coins        = { id = id(9113849492), group = "Ui", volume = 0.3, pitchJitter = 0.06, gap = 0.08 }, -- PSE "Coins Or Keys Jingle 6" (1.2 s)
	coinDrop     = { id = id(9113704038), group = "Ui", volume = 0.35 },                             -- PSE "Coin Drops Insert Vending 4" (1.6 s)
	uiClick      = { id = S.uiClick, group = "Ui", volume = 0.25, gap = 0.06 },                      -- "ui_button_click"
	uiOpen       = { id = S.uiClick, group = "Ui", volume = 0.22, pitch = 1.18, gap = 0.08 },        -- (same click, higher)
	uiClose      = { id = S.uiClick, group = "Ui", volume = 0.2, pitch = 0.86, gap = 0.08 },         -- (same click, lower)
	uiChime      = { id = S.chimeBright, group = "Ui", volume = 0.45 },                              -- boss reward / big moments
	equip        = { id = id(9119742466), group = "Ui", volume = 0.25, pitch = 1.1, gap = 0.15 },    -- PSE sword draw, light
	portal       = { id = S.sparkleWhoosh, group = "Sfx", volume = 0.35 },                           -- world travel
} :: { [string]: SoundDef }

----------------------------------------------------------------------------
-- music and ambience by place
----------------------------------------------------------------------------
-- Music categories. A list plays its tracks in turn (each track plays once, then the next).
AudioConfig.Music = {
	hub = { "hubMusic1", "hubMusic2" },
	world = { "worldMusic" },
	combat = { "combatMusic" },
	boss = { "bossMusic1" },
}
-- Each world's boss gets its own track (World id -> sound name).
AudioConfig.BossMusicByWorld = { [1] = "bossMusic1", [2] = "bossMusic2", [3] = "bossMusic3" }
-- Ambience loops by World id (0 = the hub). More than one name = layered.
AudioConfig.AmbienceByWorld = {
	[0] = { "ambHub" },
	[1] = { "ambVerdant" },
	[2] = { "ambCoral" },
	[3] = { "ambSkyforge", "ambSkyforge2" },
}

AudioConfig.MusicFade = 1.6       -- seconds for a music crossfade
AudioConfig.AmbienceFade = 2.2    -- seconds for an ambience crossfade
AudioConfig.CombatEnterAfter = 2  -- seconds of fighting before the combat music starts
AudioConfig.CombatExitAfter = 7   -- seconds without a target before it goes back to the world music
AudioConfig.SummonDuck = 0.12     -- music + ambience level while a summon plays (the summon has its own sound)

----------------------------------------------------------------------------
-- champion abilities: four layers, timed by ChampionController
--   windup   the anticipation / power-up    move     the step back and any dash
--   impact   exactly when the damage lands  tail     the follow-through after the hit
-- Built from the champion's weapon style + element, then any per-champion override.
----------------------------------------------------------------------------
AudioConfig.StyleAbility = {
	punch   = { move = "airWhoosh",  impact = "punch1" },
	kick    = { move = "airWhoosh",  impact = "punch1" },
	claws   = { move = "airWhoosh2", impact = "whipHit" },
	sword   = { move = "swordDraw",  impact = "swordSwish1" },
	hammer  = { move = "airWhoosh",  impact = "slam" },
	wrench  = { move = "airWhoosh",  impact = "slam" },
	spear   = { move = "airWhoosh2", impact = "whipHit" },
	trident = { move = "airWhoosh2", impact = "whipHit" },
	staff   = { move = "airWhoosh2", impact = "chargeBurst" },
	magic   = { move = "airWhoosh2", impact = "chargeBurst" },
	bow     = { move = "airWhoosh",  impact = "arrow" },
}
-- element keywords (matched against AbilityInfo.element, lower case) -> layers
AudioConfig.ElementAbility = {
	{ match = "fire",      windup = "fireWhoosh2", impact2 = "fireWhoosh",  tail = nil },
	{ match = "flame",     windup = "fireWhoosh2", impact2 = "fireWhoosh",  tail = "chimeSoft" },
	{ match = "lightning", windup = "zap",         impact2 = "lightning",   tail = nil },
	{ match = "storm",     windup = "zap",         impact2 = "lightning",   tail = nil },
	{ match = "arc",       windup = "zap",         impact2 = "chimeSoft",   tail = nil },
	{ match = "tide",      windup = "bubbles",     impact2 = "bigSplash",   tail = nil },
	{ match = "water",     windup = "bubbles",     impact2 = "waterSplash", tail = nil },
	{ match = "sea",       windup = "bubbles",     impact2 = "waterSplash", tail = nil },
	{ match = "riptide",   windup = "bubbles",     impact2 = "waterSplash", tail = nil },
	{ match = "bubble",    windup = "bubbles",     impact2 = "bubbles",     tail = "chimeSoft" },
	{ match = "wind",      windup = "airWhoosh2",  impact2 = "airWhoosh",   tail = nil },
	{ match = "gale",      windup = "airWhoosh2",  impact2 = "airWhoosh",   tail = nil },
	{ match = "clockwork", windup = "magicCharge", impact2 = "metalHit",    tail = nil },
	{ match = "rift",      windup = "chargeBurst", impact2 = "chimeBright", tail = nil },
	{ match = "aether",    windup = "holyCharge",  impact2 = "chimeBright", tail = nil },
	{ match = "star",      windup = "holyCharge",  impact2 = "chimeBright", tail = nil },
	{ match = "light",     windup = "magicCharge", impact2 = "chimeSoft",   tail = nil },
	{ match = "spirit",    windup = "magicCharge", impact2 = "chimeSoft",   tail = nil },
	{ match = "abyss",     windup = "holyCharge",  impact2 = "bigSplash",   tail = nil },
	{ match = "nature",    windup = "magicCharge", impact2 = "chimeSoft",   tail = nil },
	{ match = "wood",      windup = "magicCharge", impact2 = nil,           tail = nil },
}
AudioConfig.DefaultWindup = "magicCharge"
-- Legendary + Mythic ultimates add a heavy layer under the impact and a low tail.
AudioConfig.UltimateImpact = "bigHit"
AudioConfig.UltimateTail = "lowImpact"
-- per-champion overrides (any layer; false = no sound for that layer)
AudioConfig.ChampionAbility = {
	KaitoEmberfist = { windup = "fireWhoosh2", impact = "punch1", impact2 = "fireWhoosh" },
	RinTidecutter = { impact = "swordSwish2", impact2 = "waterSplash" },
	JunoGaleshot = { impact = "arrow2", impact2 = "airWhoosh" },
	BubbleBo = { impact = "punch2", impact2 = "bubbles" },
	CadetBolt = { impact = "punch2", impact2 = "zap" },
	Gearling = { windup = "magicCharge", impact = "slam", impact2 = "metalHit" },
	InstructorRen = { windup = "swordDraw2", impact = "swordSwish2", impact2 = false },
	HarpoonRook = { impact2 = "bigSplash" },
	LeviathanNerissa = { tail = "bigSplash" },
	ParagonAstra = { windup = "holyCharge", impact2 = "chimeBright" }, -- ("Starfire" would match fire)
	VerdantOriel = { windup = "holyCharge" },
}

-- basic attacks: one short sound at the hit, by weapon style (your own champions are louder)
AudioConfig.StyleAttack = {
	punch = { "punch2" }, kick = { "punch2" }, claws = { "whipHit" },
	sword = { "swordSwish1", "swordSwish2" }, hammer = { "slam" }, wrench = { "slam" },
	spear = { "whipHit" }, trident = { "whipHit" }, staff = { "chimeSoft" }, magic = { "chimeSoft" },
	bow = { "arrow", "arrow2" },
}
AudioConfig.AttackVolume = 0.45      -- basic attacks are quieter than abilities
AudioConfig.OtherPlayersVolume = 0.5 -- other players' champions are this much quieter
AudioConfig.OtherPlayersAttacks = false -- other players' BASIC attacks make no sound (crowds get noisy)

-- 3D sounds: full volume within MinDistance, silent past MaxDistance
AudioConfig.MinDistance = 12
AudioConfig.MaxDistance = 110

-- rate limiting: at most this many new sounds per group per 0.25 s (extra ones are dropped)
AudioConfig.Burst = { Sfx = 10, Ui = 6, Music = 4, Ambience = 4 }

return AudioConfig
