--!strict
-- Settings: the ONE list of player settings, used by the server (SettingsService: saving and
-- checking) and the client (SettingsMenu: the menu, and every script that reacts to a setting).
--
-- Each setting has:
--   key      saved name (data.prefs[key]); published to the player as the attribute "Pref_<key>"
--   kind     "toggle" (true/false), "slider" (whole number min..max) or "choice" (one of options)
--   default  the value a new player starts with
--   section  which part of the menu it sits in
--   status   "live" = works now; "soon" = shown greyed out with COMING SOON (the game system
--            doesn't exist yet, so the row can't do anything); "always" = always on, nothing to change
-- Menu rows that are buttons (Config) are listed in Settings.Configs.

local Settings = {}

export type Def = {
	key: string, label: string, kind: string, default: any, section: string, status: string,
	min: number?, max: number?, step: number?, suffix: string?, options: { string }?, hint: string?,
}

Settings.Sections = { "Graphics", "Notifications", "Sound", "Gameplay" }

Settings.List = {
	-- GRAPHICS ------------------------------------------------------------------------------
	{ key = "HdMode", label = "HD Mode", kind = "toggle", default = true, section = "Graphics", status = "live",
		hint = "Sun rays, glow and floating world particles. Turn off for more FPS." },
	{ key = "CoinPopups", label = "Show Coin Popups", kind = "toggle", default = true, section = "Graphics", status = "live",
		hint = "The +$ and +◆ numbers over defeated enemies." },
	{ key = "HideAuras", label = "Disable Champion Auras", kind = "toggle", default = false, section = "Graphics", status = "live",
		hint = "Removes the sparkle and glow around Epic, Legendary and Mythic champions." },
	{ key = "LiteAbilityVfx", label = "Disable Ability VFX", kind = "toggle", default = false, section = "Graphics", status = "live",
		hint = "Abilities keep their ring and hit, without the big effects and ultimate banners." },
	{ key = "ShowMyAbilities", label = "Show My Abilities", kind = "toggle", default = true, section = "Graphics", status = "live",
		hint = "Off: your champions' abilities look like normal hits (they still deal full damage)." },
	{ key = "RenderOthers", label = "Render Other Champions", kind = "toggle", default = true, section = "Graphics", status = "live",
		hint = "Off: other players' champions are hidden on your screen." },
	{ key = "ShowOtherAbilities", label = "Show Other Abilities", kind = "toggle", default = true, section = "Graphics", status = "live",
		hint = "Off: other players' abilities look like normal hits." },

	-- NOTIFICATIONS -------------------------------------------------------------------------
	{ key = "GlobalPullAnnounce", label = "Global Rare Summon Announcements", kind = "toggle", default = true, section = "Notifications", status = "soon",
		hint = "Server-wide messages when someone summons a Mythic." },
	{ key = "SelfPullAnnounce", label = "Self Rare Summon Announcements", kind = "toggle", default = true, section = "Notifications", status = "live",
		hint = "The big LEGENDARY! / MYTHIC! banner when Auto Hatch gets you one." },
	{ key = "HideTags", label = "Hide Leaderboard Tags", kind = "toggle", default = false, section = "Notifications", status = "soon",
		hint = "Leaderboard tags above players' heads are not in the game yet." },
	{ key = "HideMyTags", label = "Hide Your Leaderboard Tags For Others", kind = "toggle", default = false, section = "Notifications", status = "soon",
		hint = "Leaderboard tags above players' heads are not in the game yet." },

	-- SOUND ---------------------------------------------------------------------------------
	-- (Shared.Audio applies these: a group's volume = Master x its own slider; Mute silences all)
	{ key = "MasterVolume", label = "Master Volume", kind = "slider", default = 80, min = 0, max = 100, step = 1, suffix = "%", section = "Sound", status = "live",
		hint = "Scales every sound in the game." },
	{ key = "MusicVolume", label = "Music", kind = "slider", default = 70, min = 0, max = 100, step = 1, suffix = "%", section = "Sound", status = "live",
		hint = "Hub, world, combat and boss music." },
	{ key = "SfxVolume", label = "Sound Effects", kind = "slider", default = 85, min = 0, max = 100, step = 1, suffix = "%", section = "Sound", status = "live",
		hint = "Champion attacks and abilities, summons, dashes and travel." },
	{ key = "AmbienceVolume", label = "Ambience", kind = "slider", default = 70, min = 0, max = 100, step = 1, suffix = "%", section = "Sound", status = "live",
		hint = "Birds, waves, wind: the background sound of each world." },
	{ key = "GuiVolume", label = "Interface", kind = "slider", default = 100, min = 0, max = 100, step = 1, suffix = "%", section = "Sound", status = "live",
		hint = "Button clicks, menus opening and closing, coin pickups." },
	{ key = "MuteAll", label = "Mute All Sound", kind = "toggle", default = false, section = "Sound", status = "live",
		hint = "Silences everything. Your sliders are kept for when you turn it off." },

	-- GAMEPLAY ------------------------------------------------------------------------------
	{ key = "AutoAbility", label = "Auto Ability", kind = "toggle", default = true, section = "Gameplay", status = "always",
		hint = "Always on: every champion casts its ability by itself after 5 hits." },
	{ key = "CriticalHits", label = "Critical Hits", kind = "toggle", default = true, section = "Gameplay", status = "soon",
		hint = "Critical hits are not in the game yet." },
	{ key = "AutoClick", label = "Auto Click", kind = "toggle", default = true, section = "Gameplay", status = "always",
		hint = "Not needed: your champions attack on their own. Clicking only picks the target (or use Auto Attack)." },
	{ key = "AttackPriority", label = "Auto Attack Target", kind = "choice", default = "Nearest", options = { "Nearest", "Bosses First", "Weakest", "Strongest" },
		section = "Gameplay", status = "live", hint = "Which enemy Auto Attack picks next." },
	{ key = "AutoSprint", label = "Auto-Sprint", kind = "toggle", default = false, section = "Gameplay", status = "live",
		hint = "Always sprint. Off: hold Left Ctrl (keyboard) or click the left stick (controller) to sprint." },
	{ key = "FastSummons", label = "Fast Summons", kind = "toggle", default = false, section = "Gameplay", status = "live",
		hint = "Summon animations play faster and Common/Uncommon pulls use the short version. Results are the same." },
	{ key = "SprintSpeed", label = "Sprint Speed", kind = "slider", default = 60, min = 0, max = 100, step = 1, suffix = "%", section = "Gameplay", status = "live",
		hint = "0% = walking pace (16), 60% = 27, 100% = 34 studs per second." },
} :: { Def }

-- The Config buttons (Gameplay). status as above; the menu opens a panel for "live" ones.
Settings.Configs = {
	{ key = "AutoAttackConfig", label = "Auto Attack Config", status = "live" },
	{ key = "OrbConfig", label = "Orb Config", status = "live" },
	{ key = "GearConfig", label = "Gear Config", status = "soon" },
	{ key = "RuneConfig", label = "Rune Config", status = "soon" },
}

Settings.ByKey = {} :: { [string]: Def }
for _, d in Settings.List do Settings.ByKey[d.key] = d end

-- Walking speed (Roblox default) and the sprint speed a SprintSpeed value gives.
Settings.WalkSpeed = 16
Settings.SprintMax = 34 -- (champions follow at up to 34 studs/s, so they keep up)
function Settings.SprintWalkSpeed(percent: number): number
	local p = math.clamp(percent, 0, 100) / 100
	return math.floor(Settings.WalkSpeed + (Settings.SprintMax - Settings.WalkSpeed) * p + 0.5)
end

-- Auto-delete: champions picked in Orb Config are deleted the moment you summon them, and you
-- get this share of that orb's coin price back.
Settings.AutoDeleteRefund = 0.75

-- Checks a value for a setting. Returns the cleaned value, or nil if it isn't allowed.
-- (The server uses this for EVERY change a client asks for.)
function Settings.Clean(key: any, value: any): any
	local d = type(key) == "string" and Settings.ByKey[key] or nil
	if not d or d.status ~= "live" then return nil end
	if d.kind == "toggle" then
		return if type(value) == "boolean" then value else nil
	elseif d.kind == "slider" then
		if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
		return math.clamp(math.floor(value + 0.5), d.min :: number, d.max :: number)
	elseif d.kind == "choice" then
		return if type(value) == "string" and table.find(d.options :: { string }, value) then value else nil
	end
	return nil
end

return Settings
