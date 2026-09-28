require "AIRadioHunt/Config"

local Config = AIRadioHunt.Config

local HuntState = {}
AIRadioHunt.HuntState = HuntState

--- Lazily initializes and returns this character's hunt-lifecycle table,
--- persisted in their own ModData (survives save/load, distinct per
--- character - same pattern Context.lua uses for its characterId).
--- `activeHuntIndex` is this character's position in Config.Hunts - starts
--- at 1 (the first survivor) and advances by one each time completeHunt
--- finishes a hunt that has a next entry in the chain. `itemsSpawned`
--- tracks whether the reward/note have been placed for the *current* hunt
--- (done early, at VERY_NEAR - see spawnLeaveItems), separately from
--- `found` (only set once the player actually reaches the exact square -
--- see completeHunt).
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

--- Returns Config.Hunts[activeHuntIndex] for this character, or nil once
--- every hunt in the chain has been completed (nothing left to do).
function HuntState.getActiveHunt(player)
    return Config.Hunts[getState(player).activeHuntIndex]
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

    print("[AIRadioHunt] ensureStartingItems: sending giveStartingItems client command (attempt)")
    local ok, err = pcall(sendClientCommand, player, "AIRadioHunt", "giveStartingItems", {
        radioItem = Config.StartingRadioItem,
        radioInitialChannel = Config.StartingRadioInitialChannel,
        radioVolume = Config.StartingRadioVolume,
        noteItem = Config.StartingNoteItem,
        noteTitle = Config.StartingNoteTitle,
        noteText = Config.StartingNoteText,
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

    local hunt = Config.Hunts[state.activeHuntIndex]
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
