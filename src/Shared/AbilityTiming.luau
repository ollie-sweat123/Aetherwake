--!strict
-- AbilityTiming: the full shape of every champion's ability, used by the SERVER (CombatService:
-- when the damage lands, how long the champion is busy, how hard the hit is) and the CLIENT
-- (ChampionController: what plays when). Both read this one file, so they always agree.
--
-- An ability is staged in this order:
--   1. anticipation   the champion tenses and looks at the target
--   2. retreat        it steps back 3-5 studs in its own way (step, hop, slide, dash, leap, glide, blink)
--   3. power-up       energy gathers in its colours
--   4. the move       the champion's own ability module (Shared.Abilities.<Id>): its movement,
--                     the execution and the impact, timed exactly as in Shared.AbilityInfo
--   5. recovery       it settles back into its guard and returns to its spot
-- lead = 1 + 2 + 3. The hit lands at lead + AbilityInfo.impact; the ability lasts
-- lead + AbilityInfo.duration + recover. Normal abilities end up 2-4 s, ultimates
-- (Legendary + Mythic champions) 4-7 s.
--
-- Damage stays fair: a longer ability means fewer abilities per minute, so the ability hit
-- is scaled up (damageScale) to keep each champion's damage per second exactly what it was.

local Config = require(script.Parent:WaitForChild("Config"))
local AbilityInfo = require(script.Parent:WaitForChild("AbilityInfo"))

local AbilityTiming = {}

-- seconds the retreat takes, by approach style
AbilityTiming.RetreatTime = { step = 0.35, hop = 0.36, slide = 0.3, dash = 0.22, leap = 0.46, glide = 0.45, blink = 0.16 }

-- how each champion steps back before its ability (back = studs)
AbilityTiming.Approach = {
	-- Verdant Rift
	PipSprout = { style = "hop", back = 3.2 },         -- a springy little bunny hop
	BrambleKid = { style = "step", back = 3.4 },       -- heavy plant of the feet, hammer dragging
	LumenFox = { style = "leap", back = 4.2 },         -- fox backflip
	SageWillow = { style = "glide", back = 3.8 },      -- floats back on grove light
	RiftRangerKael = { style = "leap", back = 4.8 },   -- ranger's backflip to get an angle
	VerdantOriel = { style = "slide", back = 4.6 },    -- titan's blade-drag slide
	-- Coral Harbor
	DeckhandDex = { style = "slide", back = 3.2 },     -- skids back on sea spray
	BubbleBo = { style = "hop", back = 3.0 },          -- bouncy bubble hop
	TidecallerMina = { style = "glide", back = 3.8 },  -- drifts back on the tide
	HarpoonRook = { style = "step", back = 4.0 },      -- braces, harpoon lowered
	StormCorsairVale = { style = "dash", back = 4.4 }, -- pirate's quick back-dash
	LeviathanNerissa = { style = "glide", back = 4.6 },-- the queen rises and drifts back
	-- Skyforge Academy
	CadetBolt = { style = "dash", back = 3.4 },        -- lightning-quick hop out
	Gearling = { style = "slide", back = 3.2 },        -- skids back on its wheels
	SparkIvy = { style = "blink", back = 3.8 },        -- hologram blink
	InstructorRen = { style = "step", back = 3.6 },    -- one calm, precise step
	AetherCalder = { style = "slide", back = 4.2 },    -- knight's guarded slide
	ParagonAstra = { style = "leap", back = 5.0 },     -- soaring leap back
	-- starters
	KaitoEmberfist = { style = "slide", back = 3.6 },  -- fiery skid
	RinTidecutter = { style = "dash", back = 3.8 },    -- water-step dash
	JunoGaleshot = { style = "leap", back = 4.4 },     -- wind-borne backflip
}
local DEFAULT_APPROACH = { style = "step", back = 3.5 }

local NORMAL = { anticipation = 0.2, powerUp = 0.45, recover = 0.45 }
local ULTIMATE = { anticipation = 0.3, powerUp = 0.85, recover = 0.6 }

-- Legendary and Mythic champions have ultimates (by rarity NAME, never rank numbers)
function AbilityTiming.IsUltimate(id: string): boolean
	local def = Config.ChampionById[id]
	if not def or type(Config.RarityAtLeast) ~= "function" then return false end
	return Config.RarityAtLeast(def.rarity, "Legendary")
end

export type Timing = {
	approach: string, back: number, ultimate: boolean,
	anticipation: number, retreat: number, powerUp: number, lead: number, recover: number,
	moduleImpact: number, moduleDuration: number, -- the ability module's own timing (AbilityInfo)
	impact: number, duration: number,             -- from the start of the ability
	damageScale: number,                          -- x the normal ability hit (keeps DPS the same)
}

-- How many seconds one "ability cycle" lasts on the server: 5 hits, then the ability, then a
-- short gap (CombatService: nextAction = busyUntil + 0.35).
local GAP = 0.35
local function cycle(abilitySeconds: number): number
	local c = Config.Combat
	return c.HitsPerAbility * c.AttackInterval + abilitySeconds + GAP
end

local cache: { [string]: Timing } = {}

function AbilityTiming.For(id: string): Timing
	local hit = cache[id]
	if hit then return hit end
	local info = AbilityInfo[id] or { impact = 1, duration = 1.6 }
	local a = AbilityTiming.Approach[id] or DEFAULT_APPROACH
	local ult = AbilityTiming.IsUltimate(id)
	local k = if ult then ULTIMATE else NORMAL
	local retreat = AbilityTiming.RetreatTime[a.style] or 0.35
	local lead = k.anticipation + retreat + k.powerUp
	local duration = lead + info.duration + k.recover
	-- same damage per second as before: (hits + mult) per old cycle == (hits + mult') per new cycle
	local hits, mult = Config.Combat.HitsPerAbility, Config.Combat.AbilityMultiplier
	local newMult = (hits + mult) * cycle(duration) / cycle(info.duration) - hits
	local t: Timing = {
		approach = a.style, back = math.clamp(a.back, 3, 5), ultimate = ult,
		anticipation = k.anticipation, retreat = retreat, powerUp = k.powerUp, lead = lead, recover = k.recover,
		moduleImpact = info.impact, moduleDuration = info.duration,
		impact = lead + info.impact, duration = duration,
		damageScale = newMult / mult,
	}
	cache[id] = t
	return t
end

return AbilityTiming
