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

-- Real, verified, walkable spawn-point squares, pulled directly from each
-- town's own installed "maps/<Town>, KY/spawnpoints.lua"
-- (poor_houses/medium_houses/rich_houses groups - not hand-picked guesses,
-- not fabricated) - every entry here is guaranteed a valid, loaded,
-- walkable interior tile without needing to hand-verify a square in-game
-- first. Covers five towns now, not just Riverside, so hunts spread across
-- Knox County instead of always landing in the same one place.
-- HuntState.ensureHuntsGenerated randomly picks one entry per hunt (without
-- repeats, and kept some distance apart via Config.MinHuntSeparation below -
-- note that separation check only really matters within a town; entries in
-- different towns are already thousands of tiles apart).
--
-- `city` is the one location fact every survivor is allowed to state
-- outright if asked (see the shared "you may name your city" rule in
-- companion/index.js's buildSystemPrompt/baseMessages) - real coordinates,
-- street names, and exact addresses stay off-limits regardless. Carried
-- per-entry now (not one shared constant), since the pool spans multiple
-- towns.
Config.SpawnPointPool = {
    -- Riverside, KY
    { x = 5739, y = 5258, z = 0, city = "Riverside" },
    { x = 5832, y = 5233, z = 0, city = "Riverside" },
    { x = 6021, y = 5364, z = 0, city = "Riverside" },
    { x = 6076, y = 5375, z = 0, city = "Riverside" },
    { x = 6117, y = 5473, z = 0, city = "Riverside" },
    { x = 6167, y = 5412, z = 0, city = "Riverside" },
    { x = 6443, y = 5562, z = 0, city = "Riverside" },
    { x = 6408, y = 5498, z = 0, city = "Riverside" },
    { x = 7342, y = 5981, z = 0, city = "Riverside" },
    { x = 7396, y = 6017, z = 0, city = "Riverside" },
    { x = 5814, y = 5233, z = 0, city = "Riverside" },
    { x = 6081, y = 5344, z = 0, city = "Riverside" },
    { x = 6817, y = 5259, z = 0, city = "Riverside" },
    { x = 6067, y = 5457, z = 0, city = "Riverside" },
    { x = 6502, y = 5517, z = 0, city = "Riverside" },
    { x = 6762, y = 5372, z = 0, city = "Riverside" },
    { x = 6327, y = 5412, z = 0, city = "Riverside" },
    { x = 6726, y = 5514, z = 0, city = "Riverside" },
    -- Muldraugh, KY
    { x = 10770, y = 10271, z = 0, city = "Muldraugh" },
    { x = 10637, y = 10267, z = 0, city = "Muldraugh" },
    { x = 10720, y = 10195, z = 0, city = "Muldraugh" },
    { x = 10997, y = 9699, z = 0, city = "Muldraugh" },
    { x = 10819, y = 9437, z = 0, city = "Muldraugh" },
    { x = 10695, y = 9383, z = 0, city = "Muldraugh" },
    { x = 10776, y = 9764, z = 0, city = "Muldraugh" },
    { x = 10911, y = 10037, z = 0, city = "Muldraugh" },
    { x = 10721, y = 10630, z = 0, city = "Muldraugh" },
    { x = 10718, y = 9989, z = 0, city = "Muldraugh" },
    { x = 11018, y = 9419, z = 0, city = "Muldraugh" },
    { x = 10656, y = 10137, z = 0, city = "Muldraugh" },
    { x = 10810, y = 10037, z = 0, city = "Muldraugh" },
    { x = 10820, y = 9419, z = 0, city = "Muldraugh" },
    { x = 10654, y = 9371, z = 0, city = "Muldraugh" },
    { x = 10715, y = 9532, z = 0, city = "Muldraugh" },
    { x = 10919, y = 10137, z = 0, city = "Muldraugh" },
    { x = 10754, y = 10214, z = 0, city = "Muldraugh" },
    -- West Point, KY
    { x = 11308, y = 6671, z = 0, city = "West Point" },
    { x = 11218, y = 6796, z = 0, city = "West Point" },
    { x = 10936, y = 6645, z = 0, city = "West Point" },
    { x = 11536, y = 6934, z = 0, city = "West Point" },
    { x = 12023, y = 6980, z = 0, city = "West Point" },
    { x = 11936, y = 6749, z = 0, city = "West Point" },
    { x = 11735, y = 6691, z = 0, city = "West Point" },
    { x = 10955, y = 6964, z = 0, city = "West Point" },
    { x = 11913, y = 7070, z = 0, city = "West Point" },
    { x = 11967, y = 6749, z = 0, city = "West Point" },
    { x = 11945, y = 7049, z = 0, city = "West Point" },
    { x = 11417, y = 6877, z = 0, city = "West Point" },
    { x = 11835, y = 6993, z = 0, city = "West Point" },
    { x = 11187, y = 6733, z = 0, city = "West Point" },
    { x = 10933, y = 6728, z = 0, city = "West Point" },
    { x = 11182, y = 6860, z = 0, city = "West Point" },
    { x = 11967, y = 7079, z = 0, city = "West Point" },
    { x = 11767, y = 6673, z = 0, city = "West Point" },
    -- Rosewood, KY
    { x = 7976, y = 11402, z = 0, city = "Rosewood" },
    { x = 7822, y = 11286, z = 0, city = "Rosewood" },
    { x = 8035, y = 11560, z = 0, city = "Rosewood" },
    { x = 8078, y = 11547, z = 1, city = "Rosewood" },
    { x = 8042, y = 11439, z = 1, city = "Rosewood" },
    { x = 8303, y = 11689, z = 0, city = "Rosewood" },
    { x = 8495, y = 11550, z = 0, city = "Rosewood" },
    { x = 7989, y = 11755, z = 0, city = "Rosewood" },
    { x = 8114, y = 12223, z = 0, city = "Rosewood" },
    { x = 8431, y = 12135, z = 0, city = "Rosewood" },
    { x = 7911, y = 11409, z = 1, city = "Rosewood" },
    { x = 7995, y = 11414, z = 0, city = "Rosewood" },
    { x = 8284, y = 11721, z = 1, city = "Rosewood" },
    { x = 8446, y = 11729, z = 0, city = "Rosewood" },
    { x = 8168, y = 12394, z = 1, city = "Rosewood" },
    { x = 8197, y = 11557, z = 1, city = "Rosewood" },
    { x = 8469, y = 11558, z = 1, city = "Rosewood" },
    { x = 8471, y = 11891, z = 1, city = "Rosewood" },
    -- March Ridge, KY - this town's own spawnpoints.lua only defines one
    -- spawn group at all (no poor/medium/rich_houses split, no named
    -- landmark group), matching this project's own earlier note that March
    -- Ridge never had its own gun store/fire department/auto shop either.
    { x = 9883, y = 12812, z = 0, city = "March Ridge" },
}

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

-- Real, named landmarks with real coordinates, one small set per town
-- (confirmed against each town's own installed "maps/<Town>,
-- KY/spawnpoints.lua" - same source used for Config.SpawnPointPool above,
-- not guessed or invented). `Context.build` (see Context.lua) computes the
-- nearest one to whichever hunt is currently active via
-- `Proximity.nearestPointOfInterest`, rather than a hardcoded per-hunt
-- `landmark` string - this is what keeps landmark disclosure working once
-- hunt locations are chosen randomly: any real x/y just gets checked
-- against this same table at request time, regardless of which town it's
-- actually in. Reusing generic names ("the police station") across
-- different towns is intentional and harmless - nearest-neighbor lookup
-- only ever surfaces the one actually close to that hunt's real location.
--
-- This list only covers what's independently verifiable from each town's
-- spawnpoints.lua - it's deliberately small rather than guessed (March
-- Ridge has no entry at all here - its own spawnpoints.lua defines no
-- named landmark group, matching this project's earlier note that it never
-- had its own gun store/fire department/auto shop). Expand it with more
-- real coordinates (from further map/building data, or more towns) to give
-- landmark disclosure more variety.
Config.PointsOfInterest = {
    -- Riverside, KY
    { name = "the police station", x = 6119, y = 5257 },
    { name = "the fire station", x = 6081, y = 5255 },
    { name = "the doctor's clinic", x = 6658, y = 5247 },
    -- Muldraugh, KY
    { name = "the police station", x = 10637, y = 10418 },
    { name = "the doctor's clinic", x = 10878, y = 10021 },
    -- West Point, KY
    { name = "the doctor's clinic", x = 11531, y = 6972 },
    { name = "the fire station", x = 12275, y = 7032 },
    -- Rosewood, KY
    { name = "the fire station", x = 8137, y = 11746 },
    { name = "the police station", x = 8066, y = 11726 },
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
