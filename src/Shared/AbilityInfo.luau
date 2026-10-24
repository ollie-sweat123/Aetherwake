-- Ability timing + style for every champion (from the ability design pass).
-- impact = seconds after the ability starts when its big hit lands; duration = total length.
-- telegraphRadius = size (studs) of the ground marker that shows where the hit lands
--   (area weapons like hammer/staff/magic 6-8, sword/spear/claws/punch 4-5, bow 4;
--    Legendary/Mythic "ultimates" are bigger). Missing = 5 (active) or 8 (ultimate).
return {
	PipSprout = { name = "Sproutling Haymaker", style = "punch", telegraphRadius = 4, element = "Nature (Leaf)", impact = 0.75, duration = 1.40, shake = 0.20, palette = { "#7BE36A", "#2E9E3F", "#FFF27A", "#FFFFFF" } },
	BrambleKid = { name = "Thornroot Bonk", style = "hammer", telegraphRadius = 6, element = "Wood (Thorn)", impact = 1.00, duration = 1.60, shake = 0.25, palette = { "#8B5A2B", "#4FAF3A", "#C9F27B", "#FFD27A" } },
	LumenFox = { name = "Foxfire Lantern Pounce", style = "claws", telegraphRadius = 5, element = "Light (Foxfire)", impact = 1.05, duration = 1.70, shake = 0.40, palette = { "#FF8A2A", "#FFD15C", "#FFF4D6", "#FF4FA0" } },
	SageWillow = { name = "Ancient Grove Verdict", style = "staff", telegraphRadius = 7, element = "Spirit (Grove Light)", impact = 1.25, duration = 1.95, shake = 0.55, palette = { "#2EC4B6", "#B8FFDF", "#F5F7E8", "#E6C76A" } },
	RiftRangerKael = { name = "Riftfall Shard", style = "bow", telegraphRadius = 6, element = "Rift (Crystal)", impact = 1.35, duration = 2.00, shake = 0.70, palette = { "#1FE08A", "#6A3CFF", "#9EF9FF", "#0B2A1E" } },
	VerdantOriel = { name = "Verdant Genesis Sunblade", style = "sword", telegraphRadius = 8, element = "Verdant Flame (Light)", impact = 1.65, duration = 2.50, shake = 0.95, palette = { "#00F0FF", "#12C46B", "#FFE680", "#FFFFFF" } },
	DeckhandDex = { name = "Bilge-Buster Dinghy", style = "staff", telegraphRadius = 6, element = "Sea Spray", impact = 0.65, duration = 1.30, shake = 0.20, palette = { "#E63946", "#2A6FDB", "#F1FAFF", "#C68B59" } },
	BubbleBo = { name = "Pop-Pop Bubble Boop", style = "punch", telegraphRadius = 4.5, element = "Bubble", impact = 0.90, duration = 1.40, shake = 0.25, palette = { "#8FE3FF", "#FFFFFF", "#FF9EDB", "#B8F2E6" } },
	TidecallerMina = { name = "Moonwell Crescent Tide", style = "magic", telegraphRadius = 7, element = "Tide", impact = 1.30, duration = 1.80, shake = 0.35, palette = { "#1B4F9C", "#3FD0E0", "#E8F7FF", "#9B7BFF" } },
	HarpoonRook = { name = "Undertow Reel", style = "spear", telegraphRadius = 5, element = "Riptide", impact = 1.45, duration = 2.10, shake = 0.50, palette = { "#0E7C86", "#F4D35E", "#FFFFFF", "#FF7B54" } },
	StormCorsairVale = { name = "Thunderhead Broadside", style = "sword", telegraphRadius = 7, element = "Storm", impact = 1.45, duration = 2.15, shake = 0.70, palette = { "#C1121F", "#FFD60A", "#2B2D42", "#9EF0FF" } },
	LeviathanNerissa = { name = "Coronation of the Abyss", style = "trident", telegraphRadius = 8, element = "Abyssal Tide", impact = 2.00, duration = 2.60, shake = 0.90, palette = { "#00F5D4", "#0B1D51", "#FFD166", "#C77DFF" } },
	CadetBolt = { name = "Rookie Thunder Rush", style = "punch", telegraphRadius = 4, element = "Lightning", impact = 0.60, duration = 1.25, shake = 0.20, palette = { "#FFE14A", "#5CE1FF", "#1E2A5A", "#FFFFFF" } },
	Gearling = { name = "Overclock Whirl", style = "wrench", telegraphRadius = 6, element = "Clockwork", impact = 0.80, duration = 1.40, shake = 0.25, palette = { "#FF8A2B", "#E8B04A", "#9FB4C7", "#3FE0C5" } },
	SparkIvy = { name = "Prism Lattice Theorem", style = "staff", telegraphRadius = 7, element = "Arc Hologram", impact = 1.05, duration = 1.70, shake = 0.35, palette = { "#A35CFF", "#FF4FD8", "#4FF0FF", "#F4F0FF" } },
	InstructorRen = { name = "Seven Quiet Lines", style = "sword", telegraphRadius = 5, element = "Silver Gale", impact = 1.42, duration = 2.00, shake = 0.50, palette = { "#E6EEF5", "#6FD3FF", "#2B2F7A", "#B9A6FF" } },
	AetherCalder = { name = "Skybreaker Oath", style = "sword", telegraphRadius = 7, element = "Aether Light", impact = 1.30, duration = 2.10, shake = 0.70, palette = { "#F2F6FF", "#3FA9FF", "#FFD86B", "#1A3C8F" } },
	ParagonAstra = { name = "Zenith Comet Lance", style = "spear", telegraphRadius = 8, element = "Starfire", impact = 1.60, duration = 2.50, shake = 0.90, palette = { "#FFC93C", "#FFF8E7", "#7B5CFF", "#FF6A2B" } },
	KaitoEmberfist = { name = "Cinderheart Breaker", style = "punch", telegraphRadius = 5, element = "Fire", impact = 1.50, duration = 2.20, shake = 0.70, palette = { "#FF4A1C", "#FFB020", "#FFF1A8", "#B3122E" } },
	RinTidecutter = { name = "Ebbline Mirror Dance", style = "sword", telegraphRadius = 4.5, element = "Water", impact = 1.05, duration = 1.75, shake = 0.50, palette = { "#1E3A8A", "#38BDF8", "#7DD3FC", "#E0F7FF" } },
	JunoGaleshot = { name = "Skylark Cyclone Arrow", style = "bow", telegraphRadius = 4, element = "Wind", impact = 1.35, duration = 2.20, shake = 0.55, palette = { "#22C55E", "#A7F3D0", "#F0FFF4", "#14B8A6" } },
}
