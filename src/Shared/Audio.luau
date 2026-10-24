-- Audio (CLIENT ONLY): the one sound manager. Every script plays sounds through this, so the
-- volume settings, rate limits and broken-id checks apply everywhere.
--
--   Audio.Play(name, opts?)            2D sound (UI, music stings, your own big moments)
--   Audio.PlayAt(name, where, opts?)   3D sound at a Vector3 or a BasePart (others hear it fade with distance)
--   Audio.Music(list | nil)            crossfade to a list of track names (nil = silence)
--   Audio.Ambience(list | nil)         crossfade the ambience loops
--   Audio.Duck(on)                     lower music + ambience (summons); on = true/false
--   Audio.Group(groupName)             the SoundGroup ("Music", "Ambience", "Sfx", "Ui")
--   Audio.Adopt(sound, groupName)      put a Sound another script made into a group
--   Audio.Preview(key, value)          the Settings menu: hear a slider move before the server saves it
--   Audio.Exists(name)                 true if the name is in AudioConfig and its id hasn't failed
-- opts: volume (multiplier), pitch (exact), delay (s), owner (Player: other players' are quieter)
--
-- Settings (Shared.Settings, published as Pref_<key> attributes by the server):
--   MasterVolume, MusicVolume, AmbienceVolume, SfxVolume, GuiVolume (0..100) and MuteAll.
-- A group's volume = Master x its own slider (0 when muted).

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local AudioConfig = require(script.Parent:WaitForChild("AudioConfig"))

local Audio = {}

local GROUPS = { Music = "MusicVolume", Ambience = "AmbienceVolume", Sfx = "SfxVolume", Ui = "GuiVolume" }
local DEFAULT_PREFS = { MasterVolume = 80, MusicVolume = 70, AmbienceVolume = 70, SfxVolume = 85, GuiVolume = 100, MuteAll = false }
local POOL_PER_SOUND = 4   -- 2D copies of one sound that can overlap
local MAX_EMITTERS = 24    -- 3D sounds playing at once (more are dropped)

local player = Players.LocalPlayer
local started = false
local groups: { [string]: SoundGroup } = {}
local preview: { [string]: any } = {}     -- Settings menu values not saved yet
local broken: { [string]: boolean } = {}  -- ids that failed to load (never played again)
local warned: { [string]: boolean } = {}
local lastPlayed: { [string]: number } = {}
local burst: { [string]: { at: number, n: number } } = {}
local duck = Instance.new("NumberValue")
duck.Value = 1

----------------------------------------------------------------------------
-- volumes
----------------------------------------------------------------------------
local function pref(key: string): any
	if preview[key] ~= nil then return preview[key] end
	local v = player and player:GetAttribute("Pref_" .. key)
	if v == nil then return DEFAULT_PREFS[key] end
	return v
end
local function level(key: string): number
	return math.clamp((tonumber(pref(key)) or 0) / 100, 0, 1)
end

local function applyVolumes()
	local muted = pref("MuteAll") == true
	local master = level("MasterVolume")
	for name, key in GROUPS do
		local g = groups[name]
		if g then
			local v = if muted then 0 else master * level(key)
			if name == "Music" or name == "Ambience" then v *= duck.Value end
			g.Volume = v
		end
	end
end

local function makeGroups()
	for name in GROUPS do
		local gname = "AW_" .. name
		local g = SoundService:FindFirstChild(gname)
		if not (g and g:IsA("SoundGroup")) then
			g = Instance.new("SoundGroup")
			g.Name = gname
			g.Parent = SoundService
		end
		groups[name] = g :: SoundGroup
	end
end

----------------------------------------------------------------------------
-- sounds
----------------------------------------------------------------------------
local folder: Folder? = nil
local function soundFolder(): Folder
	if folder and folder.Parent then return folder end
	local f = SoundService:FindFirstChild("AW_Sounds")
	if not f then
		f = Instance.new("Folder")
		f.Name = "AW_Sounds"
		f.Parent = SoundService
	end
	folder = f :: Folder
	return folder :: Folder
end

local function defOf(name: string): AudioConfig.SoundDef?
	local d = AudioConfig.Sounds[name]
	if not d then
		if not warned[name] then
			warned[name] = true
			warn("[Audio] no sound called " .. tostring(name) .. " in AudioConfig")
		end
		return nil
	end
	if broken[d.id] then return nil end
	return d
end

-- rate limits: per sound (def.gap) and per group (AudioConfig.Burst per 0.25 s)
local function allowed(name: string, d: AudioConfig.SoundDef): boolean
	local now = os.clock()
	if d.gap and now - (lastPlayed[name] or -1) < d.gap then return false end
	local b = burst[d.group]
	if not b or now - b.at > 0.25 then
		b = { at = now, n = 0 }
		burst[d.group] = b
	end
	if b.n >= (AudioConfig.Burst[d.group] or 8) then return false end
	b.n += 1
	lastPlayed[name] = now
	return true
end

local function setup(s: Sound, d: AudioConfig.SoundDef, opts: { [string]: any }?)
	local o = opts or {}
	s.SoundId = d.id
	s.SoundGroup = groups[d.group]
	s.Looped = d.looped == true
	local vol = (d.volume or 0.4) * (tonumber(o.volume) or 1)
	if o.owner and o.owner ~= player then vol *= AudioConfig.OtherPlayersVolume end
	s.Volume = math.clamp(vol, 0, 1)
	local pitch = tonumber(o.pitch) or d.pitch or 1
	if d.pitchJitter and not o.pitch then pitch *= 1 + (math.random() * 2 - 1) * d.pitchJitter end
	s.PlaybackSpeed = pitch
end

local pools: { [string]: { Sound } } = {}
local function pooled2D(name: string): Sound
	local list = pools[name]
	if not list then
		list = {}
		pools[name] = list
	end
	for _, s in list do
		if s.Parent and not s.IsPlaying then return s end
	end
	if #list < POOL_PER_SOUND then
		local s = Instance.new("Sound")
		s.Name = name
		s.Parent = soundFolder()
		table.insert(list, s)
		return s
	end
	-- all busy: restart the one that has played longest
	local oldest = list[1]
	for _, s in list do
		if s.TimePosition > oldest.TimePosition then oldest = s end
	end
	return oldest
end

local emitters: { BasePart } = {}
local emitterFolder: Folder? = nil
local function freeEmitter(): BasePart?
	for _, e in emitters do
		local s = e:FindFirstChildOfClass("Sound")
		if e.Parent and s and not s.IsPlaying then return e end
	end
	if #emitters >= MAX_EMITTERS then return nil end
	if not emitterFolder or not emitterFolder.Parent then
		local fx = workspace:FindFirstChild("ClientEffects") or workspace
		local f = Instance.new("Folder")
		f.Name = "AudioEmitters"
		f.Parent = fx
		emitterFolder = f
	end
	local p = Instance.new("Part")
	p.Name = "Emitter"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	local s = Instance.new("Sound")
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = AudioConfig.MinDistance
	s.RollOffMaxDistance = AudioConfig.MaxDistance
	s.Parent = p
	p.Parent = emitterFolder
	table.insert(emitters, p)
	return p
end

local function start(s: Sound, opts: { [string]: any }?)
	local delay = opts and tonumber(opts.delay)
	if delay and delay > 0 then
		task.delay(delay, function() s.TimePosition = 0; s:Play() end)
	else
		s.TimePosition = 0
		s:Play()
	end
end

function Audio.Exists(name: string): boolean
	local d = AudioConfig.Sounds[name]
	return d ~= nil and not broken[d.id]
end

function Audio.Play(name: string?, opts: { [string]: any }?): Sound?
	if not name then return nil end
	if not started then Audio.Start(); if not started then return nil end end
	local d = defOf(name)
	if not d or not allowed(name, d) then return nil end
	local s = pooled2D(name)
	setup(s, d, opts)
	start(s, opts)
	return s
end

-- where: a Vector3, or a BasePart (the sound follows it while it plays)
function Audio.PlayAt(name: string?, where: any, opts: { [string]: any }?): Sound?
	if not name then return nil end
	if not started then Audio.Start(); if not started then return nil end end
	local d = defOf(name)
	if not d then return nil end
	local pos = if typeof(where) == "Vector3" then where
		elseif typeof(where) == "Instance" and where:IsA("BasePart") then where.Position else nil
	if not pos then return Audio.Play(name, opts) end
	if not allowed(name, d) then return nil end
	local e = freeEmitter()
	if not e then return nil end
	e.CFrame = CFrame.new(pos)
	local s = e:FindFirstChildOfClass("Sound") :: Sound
	setup(s, d, opts)
	start(s, opts)
	if typeof(where) == "Instance" then
		-- follow the part (a dashing champion) while the sound plays
		task.spawn(function()
			local t0 = os.clock()
			while s.IsPlaying and where.Parent and os.clock() - t0 < 3 do
				e.CFrame = (where :: BasePart).CFrame
				RunService.Heartbeat:Wait()
			end
		end)
	end
	return s
end

function Audio.Group(name: string): SoundGroup?
	return groups[name]
end

function Audio.Adopt(sound: Instance?, groupName: string)
	if sound and sound:IsA("Sound") and groups[groupName] then sound.SoundGroup = groups[groupName] end
end

function Audio.Preview(key: string, value: any)
	preview[key] = value
	applyVolumes()
end

----------------------------------------------------------------------------
-- music + ambience: crossfading "beds"
----------------------------------------------------------------------------
type Bed = { key: string, sounds: { Sound }, token: number }
local beds: { [string]: Bed? } = { Music = nil, Ambience = nil }
local bedToken = 0

local function fadeOut(list: { Sound }, time: number)
	for _, s in list do
		local tw = TweenService:Create(s, TweenInfo.new(time, Enum.EasingStyle.Sine), { Volume = 0 })
		tw:Play()
		tw.Completed:Connect(function() s:Stop(); s:Destroy() end)
	end
end

local function bedSound(name: string, looped: boolean): (Sound?, number)
	local d = defOf(name)
	if not d then return nil, 0 end
	local s = Instance.new("Sound")
	s.Name = "Bed_" .. name
	s.SoundId = d.id
	s.SoundGroup = groups[d.group]
	s.Looped = looped
	s.Volume = 0
	s.Parent = soundFolder()
	return s, d.volume or 0.35
end

local function fadeIn(s: Sound, to: number, time: number)
	s:Play()
	TweenService:Create(s, TweenInfo.new(time, Enum.EasingStyle.Sine), { Volume = to }):Play()
end

-- Music: the tracks play one after another and the list repeats.
function Audio.Music(list: { string }?)
	if not started then Audio.Start(); if not started then return nil end end
	local key = if list then table.concat(list, ",") else ""
	local cur = beds.Music
	if (cur and cur.key or "") == key then return end
	local fade = AudioConfig.MusicFade
	if cur then fadeOut(cur.sounds, fade) end
	beds.Music = nil
	if not list or #list == 0 then return end
	bedToken += 1
	local bed: Bed = { key = key, sounds = {}, token = bedToken }
	beds.Music = bed
	local index = math.random(1, #list)
	local function playNext(first: boolean)
		if beds.Music ~= bed then return end
		local name = list[index]
		index = index % #list + 1
		local s, vol = bedSound(name, #list == 1)
		if not s then return end
		table.clear(bed.sounds)
		table.insert(bed.sounds, s)
		fadeIn(s, vol, if first then fade else 0.4)
		if #list > 1 then
			s.Ended:Once(function()
				if beds.Music == bed then s:Destroy(); playNext(false) end
			end)
		end
	end
	playNext(true)
end

-- Ambience: every loop in the list plays at once (layers).
function Audio.Ambience(list: { string }?)
	if not started then Audio.Start(); if not started then return nil end end
	local key = if list then table.concat(list, ",") else ""
	local cur = beds.Ambience
	if (cur and cur.key or "") == key then return end
	local fade = AudioConfig.AmbienceFade
	if cur then fadeOut(cur.sounds, fade) end
	beds.Ambience = nil
	if not list or #list == 0 then return end
	bedToken += 1
	local bed: Bed = { key = key, sounds = {}, token = bedToken }
	beds.Ambience = bed
	for _, name in list do
		local s, vol = bedSound(name, true)
		if s then
			table.insert(bed.sounds, s)
			fadeIn(s, vol, fade)
		end
	end
end

-- Duck: music + ambience drop to AudioConfig.SummonDuck while on (summons, cutscenes).
local duckTween: Tween? = nil
function Audio.Duck(on: boolean, time: number?)
	if duckTween then duckTween:Cancel() end
	local tw = TweenService:Create(duck, TweenInfo.new(time or 0.6, Enum.EasingStyle.Sine), { Value = if on then AudioConfig.SummonDuck else 1 })
	duckTween = tw
	tw:Play()
end

----------------------------------------------------------------------------
-- start (once per client)
----------------------------------------------------------------------------
-- Missing-asset handling: every id is preloaded once in the background. One that fails
-- (deleted, moderated, no permission) is marked broken and silently skipped from then on.
local function preloadAll()
	local seen: { [string]: boolean } = {}
	local list = {}
	for _, d in AudioConfig.Sounds do
		if not seen[d.id] then
			seen[d.id] = true
			local s = Instance.new("Sound")
			s.SoundId = d.id
			table.insert(list, s)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list, function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure then
				broken[contentId] = true
				warn("[Audio] couldn't load " .. contentId .. " - it will be skipped")
			end
		end)
	end)
	for _, s in list do s:Destroy() end
end

function Audio.Start()
	if started or not RunService:IsClient() then return end
	started = true
	makeGroups()
	applyVolumes()
	duck.Changed:Connect(applyVolumes)
	for key in DEFAULT_PREFS do
		player:GetAttributeChangedSignal("Pref_" .. key):Connect(function()
			preview[key] = nil -- the server's value wins once it arrives
			applyVolumes()
		end)
	end
	task.spawn(preloadAll)
end

return Audio
