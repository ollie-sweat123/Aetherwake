-- AudioController (client): decides WHAT plays in the background, Shared.Audio plays it.
--
--   Music      hub (World 0) -> world -> combat (after a couple of seconds on a target)
--              -> boss (the target is a boss, each world has its own track). Crossfades.
--   Ambience   one loop (or layers) per World, plus a low rumble while you fight a boss.
--   Summons    music + ambience duck while the summon cinematic plays (it has its own sound).
--   Events     coin jingle on rewards (a sting on boss kills), a light sound when your team
--              changes. The summon's sounds, the travel whoosh and Roblox's own character
--              sounds (footsteps, jump, land) are moved into the volume groups too.
-- Every id comes from Shared.AudioConfig; nothing here invents one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local AudioConfig = require(Shared:WaitForChild("AudioConfig"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer
local enemies = workspace:WaitForChild("Enemies")

Audio.Start()

----------------------------------------------------------------------------
-- sounds other scripts make: put them in the right volume group
----------------------------------------------------------------------------
local function adoptFolder(folder: Instance, group: string)
	for _, s in folder:GetDescendants() do Audio.Adopt(s, group) end
	folder.DescendantAdded:Connect(function(s) Audio.Adopt(s, group) end)
end
task.spawn(function()
	local summon = SoundService:WaitForChild("SummonSounds", 30)
	if summon then adoptFolder(summon, "Sfx") end
end)
-- Roblox's character sounds (RbxCharacterSounds makes them on the client for every character)
local function adoptCharacter(char: Model)
	adoptFolder(char, "Sfx")
end
local function watchPlayer(p: Player)
	if p.Character then adoptCharacter(p.Character) end
	p.CharacterAdded:Connect(adoptCharacter)
end
for _, p in Players:GetPlayers() do watchPlayer(p) end
Players.PlayerAdded:Connect(watchPlayer)

----------------------------------------------------------------------------
-- what's going on
----------------------------------------------------------------------------
local function worldId(): number
	local w = player:GetAttribute("World")
	return if type(w) == "number" then w else 0
end

local function currentTarget(): Model?
	local name = player:GetAttribute("Target")
	local m = type(name) == "string" and enemies:FindFirstChild(name)
	if m and not m:GetAttribute("Dead") then return m :: Model end
	return nil
end

local function isBoss(m: Model?): boolean
	if not m then return false end
	local def = (Config.Enemies :: any)[m:GetAttribute("EnemyType") or ""]
	return def ~= nil and def.boss == true
end

-- the summon cinematic is required lazily (it may not be in every build)
local cinematic: any = nil
local function summonOnScreen(): boolean
	if cinematic == nil then
		local mod = Shared:FindFirstChild("SummonCinematic")
		local ok, m = pcall(function() return mod and require(mod) end)
		cinematic = if ok and type(m) == "table" then m else false
		if cinematic and cinematic.PhaseChanged then
			cinematic.PhaseChanged:Connect(function(phase)
				-- duck the moment a summon starts; come back once it's over
				Audio.Duck(phase ~= "done", if phase == "done" then 1.2 else 0.4)
			end)
		end
	end
	if not cinematic then return false end
	local ok, playing = pcall(function() return cinematic.IsPlaying() or cinematic.IsHolding() end)
	return ok and playing == true
end

----------------------------------------------------------------------------
-- music + ambience state, checked twice a second
----------------------------------------------------------------------------
local fightingSince: number? = nil
local lastTargetAt = -math.huge
local inCombat = false
local ducked = false

local function update()
	local now = os.clock()
	local target = currentTarget()
	local boss = isBoss(target)
	if target then
		fightingSince = fightingSince or now
		lastTargetAt = now
	elseif now - lastTargetAt > 1 then
		fightingSince = nil
	end
	-- combat music waits a moment (one quick hit shouldn't switch the music) and lingers after
	if not inCombat and fightingSince and now - fightingSince >= AudioConfig.CombatEnterAfter then
		inCombat = true
	elseif inCombat and not target and now - lastTargetAt >= AudioConfig.CombatExitAfter then
		inCombat = false
	end

	local w = worldId()
	local music
	if boss then
		music = { AudioConfig.BossMusicByWorld[w] or AudioConfig.Music.boss[1] }
	elseif inCombat and w ~= 0 then
		music = AudioConfig.Music.combat
	elseif w == 0 then
		music = AudioConfig.Music.hub
	else
		music = AudioConfig.Music.world
	end
	Audio.Music(music)

	local amb = table.clone(AudioConfig.AmbienceByWorld[w] or AudioConfig.AmbienceByWorld[0])
	if boss then table.insert(amb, "ambBoss") end
	Audio.Ambience(amb)

	-- fallback duck check (in case a PhaseChanged event was missed)
	local summon = summonOnScreen()
	if summon ~= ducked then
		ducked = summon
		Audio.Duck(summon)
	end
end

task.spawn(function()
	-- wait for the save to load (World + prefs) so the first track is the right one
	local waited = 0
	while player:GetAttribute("PrefsReady") ~= true and waited < 10 do waited += task.wait(0.25) end
	while true do
		local ok, err = pcall(update)
		if not ok then warn("[AudioController] " .. tostring(err)) end
		task.wait(0.5)
	end
end)

----------------------------------------------------------------------------
-- event sounds
----------------------------------------------------------------------------
Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind, info)
	if kind ~= "Reward" or type(info) ~= "table" then return end
	if info.boss then
		Audio.Play("coinDrop")
		Audio.Play("rewardSting")
	else
		Audio.Play("coins", { volume = 0.8 })
	end
end)

-- your team changed (equip / unequip / best team): a light "draw" sound
local lastEquipped = player:GetAttribute("EquippedIds")
player:GetAttributeChangedSignal("EquippedIds"):Connect(function()
	local now = player:GetAttribute("EquippedIds")
	if lastEquipped ~= nil and now ~= lastEquipped and player:GetAttribute("DataLoaded") == true then
		Audio.Play("equip")
	end
	lastEquipped = now
end)
