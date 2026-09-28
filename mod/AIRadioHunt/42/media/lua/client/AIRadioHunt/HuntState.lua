require "AIRadioHunt/Config"

local Config = AIRadioHunt.Config

local HuntState = {}
AIRadioHunt.HuntState = HuntState

--- Lazily initializes and returns this character's hunt-lifecycle table,
--- persisted in their own ModData (survives save/load, distinct per
--- character - same pattern Context.lua uses for its characterId).
--- `activeHuntIndex` is this character's position in `hunts` (this
--- character's own randomly-generated location/channel per Config.Hunts
--- slot - see ensureHuntsGenerated below) - starts at 1 (the first
--- survivor) and advances by one each time completeHunt finishes a hunt
--- that has a next entry in the chain. `itemsSpawned` tracks whether the
--- reward/note have been placed for the *current* hunt (done early, at
--- VERY_NEAR - see spawnLeaveItems), separately from `found` (only set
--- once the player actually reaches the target square - see completeHunt).
local function getState(player)
    local modData = player:getModData()
    if not modData.AIRadioHunt_State then
        modData.AIRadioHunt_State = {
            activeHuntIndex = 1,
            started = false,
            found = false,
            itemsSpawned = false,
            startingItemsGiven = false,
        }
    end
    return modData.AIRadioHunt_State
end

--- Fisher-Yates shuffle into a new table - never mutates `list`.
local function shuffledCopy(list)
    local copy = {}
    for i, v in ipairs(list) do
        copy[i] = v
    end
    for i = #copy, 2, -1 do
        local j = ZombRand(i) + 1
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

--- Randomly picks `count` entries from Config.SpawnPointPool, preferring
--- ones at least Config.MinHuntSeparation tiles from every other pick so
--- consecutive survivors don't end up awkwardly close together purely by
--- chance. Falls back to filling any remaining slots without that
--- constraint (never leaving a hunt without a location) if the pool can't
--- satisfy it for every slot.
local function pickSpawnPoints(count)
    local shuffled = shuffledCopy(Config.SpawnPointPool)
    local picked = {}

    local function farEnough(candidate)
        for _, p in ipairs(picked) do
            local dx, dy = candidate.x - p.x, candidate.y - p.y
            if math.sqrt(dx * dx + dy * dy) < Config.MinHuntSeparation then
                return false
            end
        end
        return true
    end

    for _, candidate in ipairs(shuffled) do
        if #picked >= count then break end
        if farEnough(candidate) then
            table.insert(picked, candidate)
        end
    end

    if #picked < count then
        for _, candidate in ipairs(shuffled) do
            if #picked >= count then break end
            local alreadyPicked = false
            for _, p in ipairs(picked) do
                if p == candidate then
                    alreadyPicked = true
                    break
                end
            end
            if not alreadyPicked then
                table.insert(picked, candidate)
            end
        end
    end

    return picked
end

local function isClearOfVanillaStations(channel)
    for _, freq in ipairs(Config.VanillaStationFrequencies) do
        if math.abs(channel - freq) < Config.ChannelMinSeparation then
            return false
        end
    end
    return true
end

--- Randomly picks `count` distinct channels inside
--- Config.ChannelMin-ChannelMax, on the real Config.ChannelStep grid, each
--- kept Config.ChannelMinSeparation clear of both real vanilla station
--- frequencies and every other picked channel. Bounded retry per slot
--- (200 attempts) rather than an unbounded loop - the configured range
--- comfortably has room for a handful of channels even with the exclusion
--- zones, but this guarantees termination regardless.
local function pickChannels(count)
    local channels = {}
    local steps = math.floor((Config.ChannelMax - Config.ChannelMin) / Config.ChannelStep)

    local function farFromPicked(candidate)
        for _, c in ipairs(channels) do
            if math.abs(candidate - c) < Config.ChannelMinSeparation then
                return false
            end
        end
        return true
    end

    for _ = 1, count do
        local candidate
        local attempts = 0
        repeat
            candidate = Config.ChannelMin + ZombRand(steps + 1) * Config.ChannelStep
            attempts = attempts + 1
        until (isClearOfVanillaStations(candidate) and farFromPicked(candidate)) or attempts > 200
        table.insert(channels, candidate)
    end

    return channels
end

--- Lazily generates (once per character, persisted in ModData) this
--- character's own real location + channel for every entry in Config.Hunts
--- - random per Config.SpawnPointPool/Config.VanillaStationFrequencies
--- (see pickSpawnPoints/pickChannels above), not read from a fixed list, so
--- two different characters get two different (but equally valid, equally
--- reachable) hunts. Returns the same shape Config.Hunts entries used to
--- carry directly (id, personaName, targetX/Y/Z, city, channel,
--- nextChannel), so every other function in this file and Context.lua
--- needed zero changes beyond reading from here instead.
function HuntState.ensureHuntsGenerated(player)
    local state = getState(player)
    if state.hunts then
        return state.hunts
    end

    local count = #Config.Hunts
    local points = pickSpawnPoints(count)
    local channels = pickChannels(count)

    local hunts = {}
    for i, template in ipairs(Config.Hunts) do
        local point = points[i]
        hunts[i] = {
            id = template.id,
            personaName = template.personaName,
            targetX = point.x,
            targetY = point.y,
            targetZ = point.z,
            city = point.city,
            channel = channels[i],
            nextChannel = channels[i + 1], -- nil for the last hunt, correctly
        }
    end

    state.hunts = hunts
    print("[AIRadioHunt] generated random hunt locations/channels for this character")
    return hunts
end

--- Returns this character's own generated hunts[activeHuntIndex], or nil
--- once every hunt in the chain has been completed (nothing left to do).
function HuntState.getActiveHunt(player)
    local hunts = HuntState.ensureHuntsGenerated(player)
    return hunts[getState(player).activeHuntIndex]
end

function HuntState.getActiveHuntIndex(player)
    return getState(player).activeHuntIndex
end

function HuntState.isStarted(player)
    return getState(player).started
end

function HuntState.isFound(player)
    return getState(player).found
end

function HuntState.areItemsSpawned(player)
    return getState(player).itemsSpawned
end

-- Even moving the send to a regular OnPlayerUpdate tick (see
-- AIRadioHunt.lua) wasn't late enough on its own - testing showed a
-- sendClientCommand call still completing with no Lua error on tick 1 of
-- a brand new connection, yet never once showing up in the server's own
-- debug log. Rather than guess a single "safe" delay, ensureStartingItems
-- below retries periodically and only considers itself done once the
-- radio is actually confirmed present in the inventory - self-correcting
-- regardless of how long the connection really takes to become ready, and
-- also self-healing for a character whose `startingItemsGiven` flag got
-- stuck true by an earlier, non-verifying version of this function
-- (marked "given" the instant a send was attempted, not once it actually
-- arrived).
local STARTING_ITEMS_RETRY_TICKS = 300 -- ~5 seconds at 60 ticks/sec between attempts

--- True if `player`'s inventory already contains an item of `fullType`
--- (e.g. "Base.WalkieTalkie3") - real vanilla `ItemContainer:contains(...)`
--- API, confirmed against `client/ContextMenuCode.lua`'s own usage, which
--- takes the short type (module prefix stripped), not the full type.
local function playerHasItemType(player, fullType)
    local ok, inv = pcall(function() return player:getInventory() end)
    if not ok or not inv then
        return false
    end
    local shortType = tostring(fullType):gsub("^Base%.", "")
    local okContains, has = pcall(function() return inv:contains(shortType) end)
    return okContains and has
end

--- Gives the player a starting radio (already on, but not yet tuned to the
--- first hunt's channel) and a torn note hinting at that frequency, once
--- per character - meant to be called unconditionally from every
--- OnPlayerUpdate tick (see AIRadioHunt.lua). This is onboarding for
--- Config.Hunts[1] specifically - later hunts are reached via the previous
--- hunt's found-note instead.
---
--- Delegates the actual item creation to the server (see
--- media/lua/server/AIRadioHunt/ServerCommands.lua's `giveStartingItems`)
--- via sendClientCommand rather than calling
--- player:getInventory():AddItem(...) directly here - an item added purely
--- client-side exists only in this client's local snapshot, not on the
--- server, which is why an earlier version of this (client-only) could add
--- the radio to the UI but the player couldn't equip or drop it: the
--- server never actually owned it, so it rejected/silently ignored
--- interactions requiring server validation.
function HuntState.ensureStartingItems(player)
    local state = getState(player)

    if state.startingItemsGiven then
        if playerHasItemType(player, Config.StartingRadioItem) then
            return -- genuinely done
        end
        -- Recovery for a character stuck by the old sync-then-forget
        -- version of this flag - the radio was never actually confirmed,
        -- so treat it as not given after all and resume retrying.
        print("[AIRadioHunt] ensureStartingItems: startingItemsGiven was true but radio not found - retrying")
        state.startingItemsGiven = false
    end

    if playerHasItemType(player, Config.StartingRadioItem) then
        state.startingItemsGiven = true
        print("[AIRadioHunt] ensureStartingItems: confirmed radio present in inventory, done")
        return
    end

    state.startingItemsRetryTicks = (state.startingItemsRetryTicks or 0) + 1
    if state.startingItemsRetryTicks < STARTING_ITEMS_RETRY_TICKS then
        return
    end
    state.startingItemsRetryTicks = 0

    -- The starting note names hunt #1's real, randomly-generated channel -
    -- ensureHuntsGenerated is idempotent, so calling it here just reads the
    -- (already generated, in the common case) hunts back rather than
    -- regenerating anything.
    local firstHunt = HuntState.ensureHuntsGenerated(player)[1]
    local noteText = string.format(Config.StartingNoteTextTemplate, firstHunt.channel / 1000)

    print("[AIRadioHunt] ensureStartingItems: sending giveStartingItems client command (attempt)")
    local ok, err = pcall(sendClientCommand, player, "AIRadioHunt", "giveStartingItems", {
        radioItem = Config.StartingRadioItem,
        radioInitialChannel = Config.StartingRadioInitialChannel,
        radioVolume = Config.StartingRadioVolume,
        noteItem = Config.StartingNoteItem,
        noteTitle = Config.StartingNoteTitle,
        noteText = noteText,
    })
    if ok then
        print("[AIRadioHunt] ensureStartingItems: sendClientCommand call completed without error")
    else
        print("[AIRadioHunt] ensureStartingItems: sendClientCommand THREW: " .. tostring(err))
    end
end

--- Flips the current hunt to "started" the first time this is called since
--- the last advance (idempotent).
function HuntState.ensureStarted(player)
    local state = getState(player)
    if state.started then
        return
    end
    state.started = true
end

--- The next hunt's frequency, appended to the note as a fixed,
--- never-LLM-generated postscript. Returns "" (no postscript) if `hunt` is
--- the last one in the chain.
local function nextFrequencyPostscript(hunt)
    if not hunt.nextChannel then
        return ""
    end
    return string.format(
        "\n\nIf you're still looking for people out there - I think someone else is " ..
        "broadcasting too. Try %.1fMHz.",
        hunt.nextChannel / 1000
    )
end

--- Spawns the reward + note for the current hunt (idempotent via
--- `itemsSpawned`) at that hunt's own target square - deliberately not the
--- player's current square, since this now happens at VERY_NEAR range (up
--- to 15 tiles out), before the player has actually reached the hideout.
--- `noteText` is the companion's kind:"very_near" note-writing response -
--- never invented locally, per the design doc's "the note must never
--- invent events that didn't happen" rule (the appended frequency postscript
--- is game truth, not something the LLM wrote). This is silent from the
--- player's perspective - no chat line, no overlay - the items are just
--- quietly there once they arrive.
---
--- Delegates the actual item creation to the server (see
--- media/lua/server/AIRadioHunt/ServerCommands.lua's `spawnFoundItems`) via
--- sendClientCommand, same reasoning as ensureStartingItems above.
function HuntState.spawnLeaveItems(player, noteText)
    local state = getState(player)
    if state.itemsSpawned then
        return
    end
    state.itemsSpawned = true

    local hunt = HuntState.ensureHuntsGenerated(player)[state.activeHuntIndex]
    local fullText = (noteText or "...") .. nextFrequencyPostscript(hunt)

    sendClientCommand(player, "AIRadioHunt", "spawnFoundItems", {
        rewardItem = Config.RewardItem,
        noteItem = Config.NoteItem,
        noteText = fullText,
        personaName = hunt.personaName,
        x = hunt.targetX,
        y = hunt.targetY,
        z = hunt.targetZ,
    })

    print("[AIRadioHunt] items spawned ahead of arrival for " .. hunt.personaName)
end

--- Marks the current hunt found (idempotent) - called once the player
--- actually reaches the exact square, separately from (and always after)
--- spawnLeaveItems above. Advances to the next hunt in Config.Hunts if one
--- exists, resetting started/found/itemsSpawned so the chain continues once
--- the player tunes to the new channel.
function HuntState.completeHunt(player)
    local state = getState(player)
    if state.found then
        return
    end
    state.found = true

    local nextIndex = state.activeHuntIndex + 1
    if Config.Hunts[nextIndex] then
        state.activeHuntIndex = nextIndex
        state.started = false
        state.found = false
        state.itemsSpawned = false
        print("[AIRadioHunt] advancing to hunt #" .. nextIndex .. " (" .. Config.Hunts[nextIndex].personaName .. ")")
    end
end

return HuntState
