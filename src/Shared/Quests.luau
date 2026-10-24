--!strict
-- Quests: Sensei Hikari's quest line. One quest is active at a time, in order.
-- The first five quests are the tutorial (rewards are given instantly, "auto");
-- after that you return to Sensei Hikari (or her hologram in each world) to claim.
--
-- kind:
--   ability  - unleash N champion abilities
--   kill     - defeat N enemies of type `key` (Config.Enemies key)
--   orb      - open N orbs that roll world `key`'s champions
--   equip    - have N champions equipped
--   starter  - talk to Sensei and choose your starter champion
--   travel   - travel to world `key`
--   unlock   - unlock world `key` ("W2", "W3")

local Quests = {}

Quests.GiverName = "Sensei Hikari"
Quests.TutorialCount = 5 -- quests 1..5 are the tutorial

Quests.List = {
	-- TUTORIAL ------------------------------------------------------------------
	{ id = "FirstAbility", kind = "ability", need = 1, auto = true, world = 0,
		title = "Unleash an Ability",
		reward = { coins = 25 },
		lines = {
			"Welcome to Champion City, rookie! I'm Sensei Hikari.",
			"Every champion charges an ability with each hit. Five hits... then BOOM.",
			"Tap a training dummy and watch your partner fight. Go!",
		} },
	{ id = "Dummies", kind = "kill", key = "TrainingDummy", need = 5, auto = true, world = 0,
		title = "Defeat 5 Training Dummies",
		reward = { coins = 150 }, -- enough for the first orb straight away
		lines = { "Did you see that? That's the power of a champion's ability!", "Now clear out the training grounds." } },
	{ id = "FirstOrb", kind = "orb", key = 1, need = 1, auto = true, world = 0,
		title = "Open a Starter Orb",
		reward = { gems = 25 },
		lines = { "Coins buy orbs, and orbs summon new champions.", "Head to the Orb Shrine and open one!" } },
	{ id = "EquipTeam", kind = "equip", need = 2, auto = true, world = 0,
		title = "Equip your best team",
		reward = { coins = 50 },
		lines = { "A new friend! Champions only fight when they're equipped.", "Press BEST to bring your strongest team." } },
	{ id = "Graduation", kind = "starter", need = 1, auto = true, world = 0,
		title = "Return to Sensei Hikari",
		reward = {},
		lines = { "You're ready. Come back to me for your graduation gift!" },
		done = { "Every hero needs a true partner.", "Three spirits answered the Rift's call. Choose one!" } },

	-- VERDANT RIFT --------------------------------------------------------------
	{ id = "GoVerdant", kind = "travel", key = 1, need = 1, auto = true, world = 0,
		title = "Travel to Verdant Rift",
		reward = { coins = 100 },
		lines = { "The Rift Legion is crawling all over Verdant Rift.", "Use the Teleporter. My hologram will meet you there!" } },
	{ id = "Grunts", kind = "kill", key = "LegionGrunt", need = 15, world = 1,
		title = "Defeat 15 Legion Grunts",
		reward = { coins = 250 },
		lines = { "Start with the grunts near the meadow." },
		done = { "Nicely done! Here's your pay." } },
	{ id = "RiftOrbs", kind = "orb", key = 1, need = 5, world = 1,
		title = "Open 5 Rift Orbs",
		reward = { coins = 300, gems = 10 },
		lines = { "A bigger team hits harder. Open some Rift Orbs." },
		done = { "Your team's growing fast!" } },
	{ id = "Scouts", kind = "kill", key = "LegionScout", need = 10, world = 1,
		title = "Defeat 10 Legion Scouts",
		reward = { coins = 600, gems = 10 },
		lines = { "Scouts guard the camp up the path. Break through!" },
		done = { "The camp is ours!" } },
	{ id = "Elites", kind = "kill", key = "LegionElite", need = 5, world = 1,
		title = "Defeat 5 Legion Elites",
		reward = { coins = 1200, gems = 15 },
		lines = { "The Elites hold the crystal ridge. They hit hard, so watch out." },
		done = { "Only their commander remains." } },
	{ id = "Vexor", kind = "kill", key = "CommanderVexor", need = 1, world = 1,
		title = "Defeat Commander Vexor",
		reward = { coins = 2000, gems = 30 },
		lines = { "Commander Vexor waits in the arena. Take him down!" },
		done = { "Incredible! Verdant Rift is free!" } },
	{ id = "UnlockHarbor", kind = "unlock", key = "W2", need = 1, auto = true, world = 1,
		title = "Unlock Coral Harbor ($25K)",
		reward = { gems = 30 },
		lines = { "Raiders took over Coral Harbor. Save up and unlock it at the Teleporter." } },

	-- CORAL HARBOR --------------------------------------------------------------
	{ id = "Thugs", kind = "kill", key = "DeckThug", need = 20, world = 2,
		title = "Defeat 20 Deck Thugs",
		reward = { coins = 3000, gems = 15 },
		lines = { "Clear the docks of those Deck Thugs!" },
		done = { "The docks are safe again." } },
	{ id = "TideOrbs", kind = "orb", key = 2, need = 10, world = 2,
		title = "Open 10 Tide Orbs",
		reward = { coins = 6000, gems = 20 },
		lines = { "Harbor champions are strong. Recruit some from the Tide Orb!" },
		done = { "What a crew!" } },
	{ id = "Raiders", kind = "kill", key = "CutlassRaider", need = 12, world = 2,
		title = "Defeat 12 Cutlass Raiders",
		reward = { coins = 10000, gems = 20 },
		lines = { "Cutlass Raiders patrol the market. Sink them!" },
		done = { "Their crew is falling apart!" } },
	{ id = "Bruisers", kind = "kill", key = "AnchorBruiser", need = 6, world = 2,
		title = "Defeat 6 Anchor Bruisers",
		reward = { coins = 20000, gems = 25 },
		lines = { "The Anchor Bruisers guard the shipyard." },
		done = { "Only the captain is left!" } },
	{ id = "Barnacle", kind = "kill", key = "CaptainBarnacle", need = 1, world = 2,
		title = "Defeat Captain Barnacle",
		reward = { coins = 40000, gems = 40 },
		lines = { "Captain Barnacle rules from his flagship. End this!" },
		done = { "Coral Harbor is free! You're becoming a legend." } },
	{ id = "UnlockSkyforge", kind = "unlock", key = "W3", need = 1, auto = true, world = 2,
		title = "Unlock Skyforge Academy ($400K)",
		reward = { gems = 40 },
		lines = { "Something is wrong at Skyforge Academy. Unlock it at the Teleporter." } },

	-- SKYFORGE ACADEMY ----------------------------------------------------------
	{ id = "Trainees", kind = "kill", key = "RogueTrainee", need = 20, world = 3,
		title = "Defeat 20 Rogue Trainees",
		reward = { coins = 40000, gems = 20 },
		lines = { "Some trainees have gone rogue. Teach them a lesson!" },
		done = { "Class dismissed!" } },
	{ id = "ForgeOrbs", kind = "orb", key = 3, need = 10, world = 3,
		title = "Open 10 Forge Orbs",
		reward = { coins = 100000, gems = 25 },
		lines = { "The academy's champions are the strongest yet. Recruit them!" },
		done = { "An elite squad!" } },
	{ id = "Enforcers", kind = "kill", key = "GearEnforcer", need = 12, world = 3,
		title = "Defeat 12 Gear Enforcers",
		reward = { coins = 150000, gems = 30 },
		lines = { "Gear Enforcers lock down the workshop. Break their gears!" },
		done = { "The workshop is open again!" } },
	{ id = "Sentinels", kind = "kill", key = "ForgeSentinel", need = 6, world = 3,
		title = "Defeat 6 Forge Sentinels",
		reward = { coins = 300000, gems = 40 },
		lines = { "Forge Sentinels guard the Headmaster's hall." },
		done = { "The way to the Headmaster is clear!" } },
	{ id = "Headmaster", kind = "kill", key = "HeadmasterUnit", need = 1, world = 3,
		title = "Defeat the Headmaster Unit",
		reward = { coins = 750000, gems = 100 },
		lines = { "The Headmaster Unit has taken over the academy. This is your final test!" },
		done = { "You did it! You're a true Rift Champion.", "More quests are coming in the next update!" } },
}

Quests.ById = {}
for i, q in Quests.List do
	(q :: any).index = i
	Quests.ById[q.id] = q
end

function Quests.Get(index: number): any?
	return Quests.List[index]
end

function Quests.IsTutorial(index: number): boolean
	return index <= Quests.TutorialCount
end

return Quests
