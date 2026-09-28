AIRadioHunt = AIRadioHunt or {}

local Config = {}
AIRadioHunt.Config = Config

-- Must match companion/config.json's "modId".
Config.ModID = "AIRadioHunt"

-- How often (in game ticks, ~60/sec) to check for a pending AI reply.
Config.PollIntervalTicks = 30

-- Fallback display name, only ever used if HuntState.getActiveHunt somehow
-- returns nothing (shouldn't happen in normal play - see onTick's authorName
-- fallback in AIRadioHunt.lua).
Config.DefaultPersonaName = "Unknown"

-- The ordered chain of survivor personas - identity and order ONLY.
-- Location (targetX/Y/Z/city) and channel are deliberately NOT here - they
-- are randomly generated once per character (see
-- HuntState.ensureHuntsGenerated in HuntState.lua) from Config.SpawnPointPool
-- and Config.VanillaStationFrequencies below, then persisted in that
-- character's own save data, so two different players get two different
-- (but equally valid) hunts. HuntState tracks each character's progress
-- through this list (see HuntState.getActiveHunt/completeHunt) - finding
-- one survivor advances to the next.
Config.Hunts = {
    { id = "mara", personaName = "Mara" },
    { id = "jonah", personaName = "Jonah" },
    { id = "ellis", personaName = "Ellis" },
    { id = "nadia", personaName = "Nadia" },
    { id = "reyes", personaName = "Reyes" },
}

-- Real, verified, walkable spawn-point squares on the loaded map, pulled
-- directly from the installed game's own "maps/Riverside, KY/spawnpoints.lua"
-- (poor_houses/medium_houses/rich_houses groups - not hand-picked guesses,
-- not fabricated) - every entry here is guaranteed a valid, loaded,
-- walkable interior tile without needing to hand-verify a square in-game
-- first. HuntState.ensureHuntsGenerated randomly picks one per hunt
-- (without repeats, and kept some distance apart via
-- Config.MinHuntSeparation below).
Config.SpawnPointPool = {
    { x = 5739, y = 5258, z = 0 },
    { x = 5832, y = 5233, z = 0 },
    { x = 6021, y = 5364, z = 0 },
    { x = 6076, y = 5375, z = 0 },
    { x = 6117, y = 5473, z = 0 },
    { x = 6167, y = 5412, z = 0 },
    { x = 6443, y = 5562, z = 0 },
    { x = 6408, y = 5498, z = 0 },
    { x = 7342, y = 5981, z = 0 },
    { x = 7396, y = 6017, z = 0 },
    { x = 5814, y = 5233, z = 0 },
    { x = 6081, y = 5344, z = 0 },
    { x = 6817, y = 5259, z = 0 },
    { x = 6067, y = 5457, z = 0 },
    { x = 6502, y = 5517, z = 0 },
    { x = 6762, y = 5372, z = 0 },
    { x = 6327, y = 5412, z = 0 },
    { x = 6726, y = 5514, z = 0 },
}

-- The one `city` fact every survivor is allowed to state outright if asked
-- (see the shared "you may name your city" rule in companion/index.js's
-- buildSystemPrompt/baseMessages) - real coordinates, street names, and
-- exact addresses stay off-limits regardless. Every Config.SpawnPointPool
-- entry above is on this one loaded map; a future pool covering a different
-- map would need its own city value per entry instead of this single
-- constant.
Config.SpawnPointCity = "Riverside"

-- Minimum tile distance required between any two of one character's
-- randomly-picked hunt locations, so consecutive survivors don't end up
-- awkwardly close together purely by chance. If the pool can't satisfy
-- this for every slot (not an issue at the current pool size vs hunt
-- count), HuntState.ensureHuntsGenerated falls back to filling remaining
-- slots without the constraint rather than leaving a hunt without a
-- location.
Config.MinHuntSeparation = 100

-- `channel`/`nextChannel` are PZ's own raw DeviceData channel units (divide
-- by 1000 for the MHz value shown in the in-game radio UI; confirmed
-- against RadioCom/RadioWindowModules/RWMGeneral.lua's own frequency
-- display). A carried radio only counts as tuned to the currently active
-- hunt's survivor if its channel is within ChannelTolerance of that hunt's
-- `channel` - merely carrying a switched-on two-way radio on some other
-- channel never counts.
Config.ChannelTolerance = 50

-- Real vanilla station frequencies (raw units) to keep every randomly
-- generated hunt channel clear of - confirmed against the installed game's
-- own media/radio/RadioData.xml: Hitz FM 89.4, Civilian Radio 91.2, LBMW
-- 93.2, USR 94.2, Classified M1A1 95.0, NNR Radio 98.0, KnoxTalk Radio
-- 101.2, Unknown Frequency 107.6 (all in raw units below, i.e. MHz * 1000).
Config.VanillaStationFrequencies = { 89400, 91200, 93200, 94200, 95000, 98000, 101200, 107600 }

-- Randomly generated hunt channels are kept inside this range and to a
-- step of 200 (0.2 MHz) - the real step the in-game tuning UI itself snaps
-- to (`RadioCom/RadioWindowModules/RWMChannel.lua`'s preset slider, via
-- `ISUIRadio/ISSliderPanel.lua:setCurrentValue`'s rounding to
-- `self.stepValue = 0.2`), so every generated frequency is actually
-- reachable by a player using the normal in-game dial, not just by typing
-- a number. 75000-150000 (75.0-150.0 MHz) comfortably sits inside
-- WalkieTalkie3's real MinChannel/MaxChannel (25000/300000).
-- ChannelMinSeparation keeps generated channels at least this many raw
-- units clear of both the vanilla list above and each other.
Config.ChannelMin = 75000
Config.ChannelMax = 150000
Config.ChannelStep = 200
Config.ChannelMinSeparation = 2000

-- Real, named landmarks with real coordinates (all confirmed against the
-- installed game's own "maps/Riverside, KY/spawnpoints.lua", same source
-- used to pick the hunts' own targetX/Y above - not guessed or invented).
-- `Context.build` (see Context.lua) computes the nearest one to whichever
-- hunt is currently active via `Proximity.nearestPointOfInterest`, rather
-- than a hardcoded per-hunt `landmark` string - this is what keeps landmark
-- disclosure working once hunt locations are chosen randomly instead of
-- from the fixed Config.Hunts list above: any real x/y just gets checked
-- against this same table at request time.
--
-- This list only covers what's independently verifiable from spawnpoints.lua
-- - it's deliberately small rather than guessed. Expand it with more real
-- coordinates (from further map/building data) to give landmark disclosure
-- more variety across the map.
Config.PointsOfInterest = {
    { name = "the police station", x = 6119, y = 5257 },
    { name = "the fire station", x = 6081, y = 5255 },
    { name = "the doctor's clinic", x = 6658, y = 5247 },
}

-- How close (in tiles) a hunt's targetX/Y must be to a Config.PointsOfInterest
-- entry before it counts as "near" that landmark - roughly the same scale as
-- the NEAR proximity tier above. A target square that isn't within this
-- distance of anything in the list just doesn't get a landmark at all
-- (the survivor still may state `city`, just not a specific nearby place).
Config.LandmarkMaxDistance = 60

-- Starting radio + note given once via Events.OnCreatePlayer (see
-- HuntState.ensureStartingItems) - this is onboarding for the *first* hunt
-- in Config.Hunts specifically, not a per-hunt thing (later hunts are
-- reached via the previous hunt's found-note instead). WalkieTalkie3
-- ("Premium Tech. Walkie Talkie") is deliberately chosen: its real
-- MinChannel/MaxChannel (25000/300000, confirmed in the installed game's
-- own scripts/generated/items/radio.txt) comfortably covers the whole
-- 75000-150000 hunt-channel band above. StartingRadioInitialChannel is kept
-- well outside that band so actually tuning in is a real action, not a
-- coincidence of the item's default state.
Config.StartingRadioItem = "Base.WalkieTalkie3"
Config.StartingRadioInitialChannel = 250000
Config.StartingRadioVolume = 5

Config.StartingNoteItem = "Base.Notepad"
Config.StartingNoteTitle = "Mara's letter" -- always Mara's - this is onboarding for Config.Hunts[1] specifically, not a per-hunt title
-- %.1f gets replaced with this character's own randomly-generated hunt #1
-- channel (in MHz) at the point the note is actually created - see
-- HuntState.ensureStartingItems - since that's no longer a fixed constant.
Config.StartingNoteTextTemplate = "please... if anyone out there can hear this... tune in to Channel %.1fMHz."

-- Reward + note items spawned on the player's square once a hunt is found.
-- Base.Notepad is a vanilla Literature item with CanBeWrite=true, so it
-- supports item:addPage()/:setLockedBy() - see HuntState.lua. No second
-- walkie-talkie is spawned here - the survivor's radio going silent is the
-- whole point, the note (with the next hunt's channel appended, if any) is
-- the only artifact left behind, not another physical radio to carry.
Config.RewardItem = "Base.Bandage"
Config.NoteItem = "Base.Notepad"

-- Euclidean tile-distance thresholds for each proximity tier, checked
-- closest-first (see Proximity.lua). EXTREMELY_NEAR is treated as "found".
Config.ProximityTiers = {
    EXTREMELY_NEAR = 5,
    VERY_NEAR = 20,
    NEAR = 60,
    FAR = 200,
}

-- Moodle types checked for conditional-speech-style triggers (see
-- MOODLE_TRIGGERS in AIRadioHunt.lua) - real, audible reactions the
-- player's own character has, which the active survivor can plausibly
-- overhear over an open channel. Names must match the real MoodleType enum
-- constants (ALL_CAPS - confirmed against the installed game's compiled
-- classes, same gotcha DispatchAI's own Config.lua documents).
Config.MoodleTypesToTrack = {
    "BORED", "STRESS", "PANIC", "UNHAPPY",
    "HUNGRY", "THIRST", "TIRED",
    "SICK", "HAS_A_COLD", "PAIN", "INJURED", "BLEEDING",
    "WET", "HYPOTHERMIA", "HYPERTHERMIA",
    "DRUNK", "HEAVY_LOAD", "ENDURANCE",
}

-- Canned line shown (locally, no LLM call) when the player's proximity
-- tier changes without anything actually being said or heard - the active
-- survivor has no real way to sense distance from that far out, so this
-- reads as ambiguous radio interference rather than a knowing reaction.
-- Never sent to the companion.
Config.NoiseReplyText = "What's that? I'm hearing some noise in there..."

return Config
