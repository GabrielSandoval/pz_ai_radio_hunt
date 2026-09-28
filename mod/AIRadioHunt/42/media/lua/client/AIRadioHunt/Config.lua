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

-- The ordered chain of survivor hunts. HuntState tracks each character's
-- progress through this list (see HuntState.getActiveHunt/completeHunt) -
-- finding one survivor advances to the next, whose frequency is exactly
-- what the previous one's found-note points to (nextChannel). Testing this
-- vertical slice's continuity mechanic only needs two entries; add more
-- the same way.
--
-- `targetX/Y/Z` are real occupation spawn-point squares pulled directly
-- from the installed game's own "maps/Riverside, KY/spawnpoints.lua" (not
-- hand-picked guesses) - spawn points are always valid, loaded, walkable
-- interior tiles, so both are guaranteed good for testing without having
-- to hand-verify a square in-game first.
--
-- `channel`/`nextChannel` are PZ's own raw DeviceData channel units (divide
-- by 1000 for the MHz value shown in the in-game radio UI; confirmed
-- against RadioCom/RadioWindowModules/RWMGeneral.lua's own frequency
-- display). A carried radio only counts as tuned to the currently active
-- hunt's survivor if its channel is within ChannelTolerance of that hunt's
-- `channel` - merely carrying a switched-on two-way radio on some other
-- channel never counts.
--
-- Every hunt channel below is deliberately kept to two constraints,
-- confirmed against the installed game's own files rather than guessed:
-- (1) a multiple of 200 (0.2 MHz) - the real step the in-game tuning UI
-- itself snaps to (`RadioCom/RadioWindowModules/RWMChannel.lua`'s preset
-- slider, via `ISUIRadio/ISSliderPanel.lua:setCurrentValue`'s rounding to
-- `self.stepValue = 0.2`) - so every frequency here is actually reachable
-- by a player using the normal in-game dial, not just by typing a number.
-- (2) inside 75000-150000 (75.0-150.0 MHz) and kept several MHz clear of
-- every real vanilla station broadcasting in that band (confirmed against
-- `media/radio/RadioData.xml`: Hitz FM 89.4, Civilian Radio 91.2, LBMW
-- 93.2, USR 94.2, Classified M1A1 95.0, NNR Radio 98.0, KnoxTalk Radio
-- 101.2, Unknown Frequency 107.6) - so scanning around never crosses actual
-- vanilla broadcast content.
--
-- `city` is the only location fact every survivor is allowed to state
-- outright if asked (see the shared "you may name your city" rule in
-- companion/index.js's buildSystemPrompt/baseMessages) - real coordinates,
-- street names, and landmarks stay off-limits regardless. All five hunts
-- below are real spawnpoints on the same loaded map, so they share one
-- value; if a future hunt ever moves to a different map, give that entry
-- its own `city` instead.
Config.Hunts = {
    {
        id = "mara",
        personaName = "Mara",
        targetX = 6021, targetY = 5364, targetZ = 0, -- poor_houses entry
        city = "Riverside",
        channel = 76000, -- 76.000 MHz
        nextChannel = 84000, -- 84.000 MHz - Jonah, below
    },
    {
        id = "jonah",
        personaName = "Jonah",
        targetX = 6119, targetY = 5257, targetZ = 0, -- police_station entry
        city = "Riverside",
        channel = 84000, -- 84.000 MHz
        nextChannel = 112000, -- 112.000 MHz - Ellis, below
    },
    {
        id = "ellis",
        personaName = "Ellis",
        targetX = 7342, targetY = 5981, targetZ = 0, -- poor_houses entry, deliberately the most isolated one (paranoid/reclusive fit)
        city = "Riverside",
        channel = 112000, -- 112.000 MHz
        nextChannel = 128000, -- 128.000 MHz - Nadia, below
    },
    {
        id = "nadia",
        personaName = "Nadia",
        targetX = 6817, targetY = 5259, targetZ = 0, -- medium_houses entry
        city = "Riverside",
        channel = 128000, -- 128.000 MHz
        nextChannel = 144000, -- 144.000 MHz - Reyes, below
    },
    {
        id = "reyes",
        personaName = "Reyes",
        targetX = 6081, targetY = 5255, targetZ = 1, -- fire_station entry (upper floor) - fits the ex-military/emergency-services background
        city = "Riverside",
        channel = 144000, -- 144.000 MHz
        nextChannel = nil, -- last hunt in the chain for now
    },
}
Config.ChannelTolerance = 50

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
Config.StartingNoteText = "please... if anyone out there can hear this... tune in to Channel 76.0MHz."

-- Reward + note items spawned on the player's square once a hunt is found.
-- Base.Notepad is a vanilla Literature item with CanBeWrite=true, so it
-- supports item:addPage()/:setLockedBy() - see HuntState.lua. No second
-- walkie-talkie is spawned here - the survivor's radio going silent is the
-- whole point, the note (with the next hunt's channel appended, if any) is
-- the only artifact left behind, not another physical radio to carry.
Config.RewardItem = "Base.Bandage"
Config.NoteItem = "Base.Notepad"

-- Euclidean tile-distance thresholds for each proximity tier, checked
-- closest-first (see Proximity.lua). SAME_SQUARE is treated as "found".
Config.ProximityTiers = {
    SAME_SQUARE = 1,
    VERY_NEAR = 15,
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
