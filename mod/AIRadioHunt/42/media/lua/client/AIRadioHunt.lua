require "AIRadioHunt/Config"
require "AIRadioHunt/Json"
require "AIRadioHunt/Log"
require "AIRadioHunt/Context"
require "AIRadioHunt/Bridge"
require "AIRadioHunt/Overlay"
require "AIRadioHunt/MimicMessage"
require "AIRadioHunt/Proximity"
require "AIRadioHunt/HuntState"

local Config = AIRadioHunt.Config
local Log = AIRadioHunt.Log
local Context = AIRadioHunt.Context
local Bridge = AIRadioHunt.Bridge
local Proximity = AIRadioHunt.Proximity
local HuntState = AIRadioHunt.HuntState

-- Unlike DispatchAI's Bridge (single pendingRequestId is an accepted rough
-- edge there, since only user-initiated chat spam can overwrite it), this
-- mod's ambient start/sound/found triggers fire on their own from
-- OnPlayerUpdate. If those overwrote a still-in-flight request the same way,
-- Mara's one-shot opening line (or the found trigger) would risk getting
-- silently dropped (the Ollama round trip is slower than the next tick). So
-- ambient triggers below wait for `pendingRequestId` to clear before
-- sending another; player-typed chat intentionally does not wait, matching
-- DispatchAI's own existing (documented) behavior.
local pendingRequestId = nil

-- Tracks which `kind` the in-flight request was, since Bridge's response
-- payload is just {id, reply} - onTick needs this to know how to interpret
-- a given reply (e.g. kind:"very_near" replies are note text to write into
-- a spawned item, not something to show in chat - see onTick below).
local pendingRequestKind = nil

-- Gate: originally copied from DispatchAI.lua's "any switched-on two-way
-- radio" check, now narrowed to a specific frequency - a carried radio only
-- counts if it's ItemType.RADIO + portable + two-way + switched on (same
-- vanilla checks DispatchAI uses) AND its device channel is within
-- Config.ChannelTolerance of `targetChannel` (real vanilla
-- DeviceData:getChannel(), confirmed against RadioWindowModules/
-- RWMGeneral.lua's own frequency display - raw units, /1000 for MHz).
-- Merely carrying an on, two-way radio tuned to some other station no
-- longer triggers anything. Volume is still deliberately not part of this
-- gate, only of whether the reply is shown. `targetChannel` is whichever
-- survivor is currently active for this character (see
-- HuntState.getActiveHunt) - not a fixed value, since the chain in
-- Config.Hunts advances to a new channel each time one is found.
local function isTunedToChannel(item, targetChannel)
    if not item then
        return false
    end
    local ok, result = pcall(function()
        local scriptItem = item:getScriptItem()
        if not scriptItem or not scriptItem:isItemType(ItemType.RADIO) then
            return false
        end
        local device = item:getDeviceData()
        if not device then
            return false
        end
        if not (device:getIsPortable() and device:getIsTwoWay() and device:getIsTurnedOn()) then
            return false
        end
        local channel = device:getChannel()
        return channel ~= nil and math.abs(channel - targetChannel) <= Config.ChannelTolerance
    end)
    return ok and result
end

local MAX_RADIO_SEARCH_DEPTH = 4

local function findTunedRadio(container, depth, targetChannel)
    if not container or depth > MAX_RADIO_SEARCH_DEPTH then
        return nil
    end

    local ok, items = pcall(function() return container:getItems() end)
    if not ok or not items then
        return nil
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isTunedToChannel(item, targetChannel) then
            return item
        end
        if item.IsInventoryContainer and item:IsInventoryContainer() then
            local okNested, nested = pcall(function() return item:getInventory() end)
            if okNested and nested then
                local found = findTunedRadio(nested, depth + 1, targetChannel)
                if found then
                    return found
                end
            end
        end
    end
    return nil
end

--- True if the player is carrying a switched-on radio tuned to whichever
--- survivor is currently active for them (Config.Hunts via
--- HuntState.getActiveHunt) - false if every hunt in the chain has already
--- been completed.
local function isCarryingTunedRadio(player)
    local hunt = HuntState.getActiveHunt(player)
    if not hunt then
        return false
    end
    local ok, inv = pcall(function() return player:getInventory() end)
    return ok and inv ~= nil and findTunedRadio(inv, 0, hunt.channel) ~= nil
end

--- Returns the volume (0+) of a carried radio currently tuned to the active
--- survivor, or 0 if none is carried/tuned in. Checked at reply time, not
--- send time - see DispatchAI.lua's identical helper for why.
local function getCarriedRadioVolume(player)
    local hunt = HuntState.getActiveHunt(player)
    if not hunt then
        return 0
    end
    local ok, inv = pcall(function() return player:getInventory() end)
    if not ok or not inv then
        return 0
    end
    local item = findTunedRadio(inv, 0, hunt.channel)
    if not item then
        return 0
    end
    local okVolume, volume = pcall(function() return item:getDeviceData():getDeviceVolume() end)
    return (okVolume and volume) or 0
end

local lastTier = nil

--- Sends a "sound" request for a real, audible reaction the player's own
--- character just had (moodle/fire/weapon trigger below) - the only kind of
--- ambient event Mara is allowed to react to, since it's actually something
--- a person near an open mic would produce. Shows the player's own muttered
--- phrase immediately regardless of Bridge availability; only the Bridge
--- send itself waits for `pendingRequestId` to clear.
local function triggerSoundEvent(player, logText, phrase)
    Log.add(logText)
    AIRadioHunt.Overlay.show(phrase, "player")
    if pendingRequestId then
        return
    end
    local context = Context.build(player, lastTier, false)
    pendingRequestId = Bridge.sendRequest(phrase, context, "sound")
    pendingRequestKind = "sound"
end

-- Conditional-speech-style triggers, ported from DispatchAI.lua: real,
-- half-muttered reactions the player's own character has, which whichever
-- survivor is currently active can plausibly overhear over an open
-- channel. Phrases are lifted from the
-- "Conditional-Speech" mod (github.com/Chuckleberry-Finn/zomboid-cnd-speech)
-- for the same reason DispatchAI uses them - they read like something a
-- real character would mutter, not an invented sound effect. Each entry
-- fires once per moodle level going from 0 to non-zero, checked via
-- Events.OnPlayerUpdate (not OnPlayerGetDamage - the Pain moodle doesn't
-- update in the same instant a damage event fires, see DispatchAI.lua's
-- note on this).
local MOODLE_TRIGGERS = {
    BORED = { log = "Sighed, bored", phrase = "*sigh*" },
    STRESS = { log = "Stress rising", phrase = "*deep breath*" },
    PANIC = { log = "Panicking", phrase = "*gasp*" },
    UNHAPPY = { log = "Feeling unhappy", phrase = "how long can I keep going?" },
    HUNGRY = { log = "Hungry", phrase = "*stomach growls*" },
    THIRST = { log = "Thirsty", phrase = "my mouth is dry" },
    TIRED = { log = "Tired", phrase = "*yawn*" },
    SICK = { log = "Feeling sick", phrase = "I feel queasy" },
    HAS_A_COLD = { log = "Caught a cold", phrase = "my nose is runny" },
    PAIN = { log = "Grunted in pain", phrase = "ow" },
    INJURED = { log = "Got injured", phrase = "that's going to leave a mark" },
    BLEEDING = { log = "Started bleeding", phrase = "I am bleeding a bit" },
    WET = { log = "Got soaked", phrase = "I am soaked" },
    HYPOTHERMIA = { log = "Getting hypothermic", phrase = "it is so cold" },
    HYPERTHERMIA = { log = "Overheating", phrase = "this heat..." },
    DRUNK = { log = "Got drunk", phrase = "feeling tipsy" },
    HEAVY_LOAD = { log = "Straining under a heavy load", phrase = "*grunt*" },
    ENDURANCE = { log = "Winded", phrase = "I need a break" },
}

local lastMoodleLevel = {}

local function checkMoodleTriggers(player, moodlesObj)
    for _, name in ipairs(Config.MoodleTypesToTrack) do
        local mt = MoodleType[name]
        local trigger = MOODLE_TRIGGERS[name]
        if mt and trigger then
            local ok, level = pcall(function() return moodlesObj:getMoodleLevel(mt) end)
            if ok and level then
                if level > 0 and (lastMoodleLevel[name] or 0) <= 0 then
                    triggerSoundEvent(player, trigger.log, trigger.phrase)
                end
                lastMoodleLevel[name] = level
            end
        end
    end
end

-- Fire routes through the Panic phrase set in Conditional-Speech too (it
-- has no dedicated "on fire" lines), so this does the same.
local wasOnFire = false

local function checkFireTrigger(player)
    local ok, onFireNow = pcall(function() return player:isOnFire() end)
    if ok and onFireNow and not wasOnFire then
        triggerSoundEvent(player, "Caught fire", "oh god! ahhh!")
    end
    wasOnFire = ok and onFireNow or false
end

-- Ranged-weapon status triggers (jammed / low / out of ammo), same as
-- DispatchAI.lua - mirrors Conditional-Speech's own check_WeaponStatus,
-- hooked on OnWeaponSwing rather than every-tick spam.
local wasJammed = false
local wasOutOfAmmo = false
local wasLowAmmo = false

local function onWeaponSwing(player, weapon)
    if not player or player ~= getPlayer() or not weapon then
        return
    end
    if not isCarryingTunedRadio(player) or not HuntState.isStarted(player) or HuntState.isFound(player) then
        return
    end

    pcall(function()
        if weapon:getCategory() ~= "Weapon" or not weapon:isRanged() then
            return
        end

        local jammedNow = weapon:isJammed()
        local outOfAmmoNow = (weapon:haveChamber() and not weapon:isRoundChambered())
            or (not weapon:haveChamber() and weapon:getCurrentAmmoCount() <= 0)
        local lowAmmoNow = not outOfAmmoNow and weapon:getMaxAmmo() > 0
            and weapon:getCurrentAmmoCount() < (weapon:getMaxAmmo() / 4)

        if jammedNow and not wasJammed then
            triggerSoundEvent(player, "Weapon jammed", "damn thing is jammed")
        elseif outOfAmmoNow and not wasOutOfAmmo then
            triggerSoundEvent(player, "Ran out of ammo", "I am out")
        elseif lowAmmoNow and not wasLowAmmo then
            triggerSoundEvent(player, "Running low on ammo", "running low")
        end

        wasJammed = jammedNow
        wasOutOfAmmo = outOfAmmoNow
        wasLowAmmo = lowAmmoNow
    end)
end
Events.OnWeaponSwing.Add(onWeaponSwing)

-- Real (non-accessory) worn-clothing body locations, curated from the
-- installed game's own scripts/generated/items/clothing.txt BodyLocation
-- values - deliberately excludes small/hard-to-spot-from-a-distance slots
-- (glasses, jewelry, watches, gloves, socks, belt, makeup, underwear,
-- etc.), even where the game's own DisplayCategory field unhelpfully
-- lumps some of these in with "Accessory" too (e.g. every hat is
-- DisplayCategory=Accessory in vanilla, which is why body location, not
-- DisplayCategory, is what's actually checked here).
local VISIBLE_BODY_LOCATIONS = {
    hat = true, fullhat = true, jackethat = true, jackethat_bulky = true,
    jacket = true, jacket_bulky = true, jacket_down = true, jacketsuit = true,
    shirt = true, tshirt = true, shortsleeveshirt = true, sweater = true, sweaterhat = true,
    tanktop = true, jersey = true, dress = true, longdress = true, skirt = true, longskirt = true,
    pants = true, pants_skinny = true, shortpants = true, shortsshort = true,
    shoes = true, boilersuit = true, bathrobe = true, fullsuit = true, fullsuithead = true,
    mask = true, maskfull = true, maskeyes = true, scarf = true, cuirass = true,
    scba = true, scbanotank = true, vesttexture = true, torso = true, legs = true,
}

--- Picks a real, visually-obvious description of what the player is
--- wearing - preferring an actual outfit combination (e.g. "Lumberjack's
--- Shirt and Military Trousers") over a single item, and clothing over a
--- wielded weapon - so the active survivor can plausibly reference "someone
--- wearing/carrying ___" when she actually spots the player at NEAR range.
--- This is real game data gathered here in Lua and handed to the companion
--- as context; the LLM is never left to invent or guess what the player is
--- wearing.
local function findSpottedItem(player)
    local candidates = {}
    local okWorn, worn = pcall(function() return player:getWornItems() end)
    if okWorn and worn then
        local okSize, size = pcall(function() return worn:size() end)
        if okSize and size then
            for i = 0, size - 1 do
                local okItem, item = pcall(function() return worn:getItemByIndex(i) end)
                if okItem and item then
                    local okLoc, location = pcall(function() return item:getBodyLocation() end)
                    if okLoc and location then
                        local key = tostring(location):gsub("^base:", ""):lower()
                        if VISIBLE_BODY_LOCATIONS[key] then
                            table.insert(candidates, item)
                        end
                    end
                end
            end
        end
    end

    if #candidates > 0 then
        -- Shuffle (Fisher-Yates) so which piece(s) get named varies rather
        -- than always favoring whatever index worn items happen to sit at.
        for i = #candidates, 2, -1 do
            local j = ZombRand(i) + 1
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end

        local names = {}
        for i = 1, math.min(2, #candidates) do
            local okName, name = pcall(function() return candidates[i]:getDisplayName() end)
            if okName and name then
                table.insert(names, name)
            end
        end

        if #names == 2 then
            return names[1] .. " and " .. names[2]
        elseif #names == 1 then
            return names[1]
        end
    end

    -- No visible clothing found (or names failed to resolve) - fall back to
    -- a wielded weapon, still real game data either way.
    local okPrimary, primary = pcall(function() return player:getPrimaryHandItem() end)
    if okPrimary and primary then
        local okName, name = pcall(function() return primary:getDisplayName() end)
        if okName and name then
            return name
        end
    end

    return nil
end

--- Drives the hunt's ambient side: starting the hunt the first time a tuned
--- radio is carried, reacting to the player's own real conditional-speech
--- triggers, and reacting to proximity-tier changes relative to whichever
--- survivor is currently active (Config.Hunts via HuntState.getActiveHunt).
--- FAR is NOT treated as something the survivor actually perceives (no real
--- way to sense distance at range) - it shows a fixed, local "radio
--- interference" line with no LLM call. NEAR is a real LLM reaction (she
--- visually spots the player, referencing a real equipped item). VERY_NEAR
--- silently spawns the reward/note ahead of arrival (see
--- HuntState.spawnLeaveItems) - nothing shown to the player yet. EXTREMELY_NEAR
--- is the actual reveal: the survivor's "I had to go" line plays, the hunt
--- is marked found, and the chain may advance to the next survivor - see
--- HuntState.completeHunt. Mirrors DispatchAI's OnPlayerUpdate polling
--- cadence.
local function onPlayerUpdate(player)
    if not player or player ~= getPlayer() then
        return
    end

    -- Deliberately NOT sent from Events.OnCreatePlayer - confirmed in
    -- testing that a sendClientCommand call made there completes without
    -- any Lua-level error, but the packet never actually reaches the
    -- server (OnCreatePlayer fires too early in the connection lifecycle
    -- for that specific player's ClientCommand channel to be ready).
    -- ensureStartingItems is idempotent, so calling it unconditionally
    -- every tick is safe - it only actually sends once, on whichever tick
    -- first proves the connection is live (this one already reliably
    -- carries all the mod's other traffic).
    HuntState.ensureStartingItems(player)

    local hunt = HuntState.getActiveHunt(player)
    if not hunt then
        return -- every hunt in the chain has already been completed
    end

    if HuntState.isFound(player) then
        return
    end

    -- Once this hunt's reward/note are already spawned (VERY_NEAR already
    -- fired), completing it must NOT depend on the radio still being tuned
    -- to this hunt's own channel - the note already tells the player the
    -- next hunt's frequency, and retuning to try it early (entirely
    -- natural) would otherwise deadlock things: isCarryingTunedRadio would
    -- never match this still-active hunt's channel again, so it could
    -- never reach EXTREMELY_NEAR, activeHuntIndex would never advance, and
    -- the next survivor would never start either - confirmed exactly this
    -- happening in testing with Jonah -> Ellis.
    if HuntState.areItemsSpawned(player) then
        if not pendingRequestId then
            local distance = Proximity.tileDistance(player, hunt.targetX, hunt.targetY)
            local tier = Proximity.tierFor(distance, Config.ProximityTiers)
            if tier == "EXTREMELY_NEAR" then
                print("[AIRadioHunt] found: player reached " .. hunt.personaName .. "'s target square")
                local context = Context.build(player, tier, true)
                pendingRequestId = Bridge.sendRequest(nil, context, "found")
                pendingRequestKind = "found"
                lastTier = tier
            end
        end
        return
    end

    if not isCarryingTunedRadio(player) then
        return
    end

    if not HuntState.isStarted(player) then
        if not pendingRequestId then
            HuntState.ensureStarted(player)
            print("[AIRadioHunt] hunt started: " .. hunt.personaName)
            local context = Context.build(player, nil, true)
            pendingRequestId = Bridge.sendRequest(nil, context, "start")
            pendingRequestKind = "start"
        end
        return
    end

    checkFireTrigger(player)
    local moodlesObj = player.getMoodles and player:getMoodles()
    if moodlesObj then
        checkMoodleTriggers(player, moodlesObj)
    end

    local distance = Proximity.tileDistance(player, hunt.targetX, hunt.targetY)
    local tier = Proximity.tierFor(distance, Config.ProximityTiers)

    if tier == lastTier then
        return
    end

    if tier == "EXTREMELY_NEAR" or tier == "VERY_NEAR" then
        -- Reaching here at all means items haven't been spawned yet (the
        -- early return above already handles the found/reveal once they
        -- are), so this always means "write the note and spawn items now" -
        -- never the reveal itself directly, regardless of which of the two
        -- tiers this actually is. Treating EXTREMELY_NEAR the same as
        -- VERY_NEAR here specifically covers a player reaching the target
        -- square in a single jump without ever passing through VERY_NEAR
        -- range first (a vehicle covering more than 20 tiles in one tick,
        -- or a debug teleport) - without this, the reveal fired with no
        -- note/reward ever actually spawned (real bug, caught in testing).
        -- The reveal itself (kind:"found") is only ever sent from the
        -- areItemsSpawned branch above, once a later tick confirms items
        -- are actually there.
        if not pendingRequestId then
            local context = Context.build(player, tier, true)
            pendingRequestId = Bridge.sendRequest(nil, context, "very_near")
            pendingRequestKind = "very_near"
            lastTier = tier
        end
    elseif tier == "NEAR" then
        if not pendingRequestId then
            local context = Context.build(player, tier, true)
            context.spottedItem = findSpottedItem(player)
            pendingRequestId = Bridge.sendRequest(nil, context, "near")
            pendingRequestKind = "near"
            lastTier = tier
        end
    else
        -- FAR: not real noise, not player-generated - ambiguous static, no
        -- LLM call, always shown immediately (missing this one occasionally
        -- if a request happens to be in flight is low-stakes, unlike the
        -- tiers above).
        local volume = getCarriedRadioVolume(player)
        if volume > 0 then
            AIRadioHunt.Overlay.show(Config.NoiseReplyText)
        end
        local msg = AIRadioHunt.newMimicMessage({
            text = Config.NoiseReplyText,
            author = hunt.personaName,
            chatType = "radio",
        })
        ISChat.addLineInChat(msg, 0)
        lastTier = tier
    end
end
Events.OnPlayerUpdate.Add(onPlayerUpdate)

local _addLineInChat = ISChat.addLineInChat
function ISChat.addLineInChat(message, tabID)
    _addLineInChat(message, tabID)

    if not message then
        return
    end

    local player = getPlayer()
    if not player then
        return
    end

    local okAuthor, author = pcall(function() return message:getAuthor() end)
    if not okAuthor or author ~= player:getUsername() then
        return
    end

    local okText, text = pcall(function() return message:getText() end)
    if not okText or not text or text:trim() == "" then
        return
    end

    -- Debug-only: prints the current active hunt's target square (where
    -- that survivor's found-note ends up once the hunt is over) into chat,
    -- for testing without needing to look up Config.Hunts by hand. Never
    -- forwarded to Mara/the companion. Deliberately NOT slash-prefixed
    -- ("/aicoordinates") - PZ's own chat only calls ISChat.addLineInChat
    -- (what this mod hooks) for text that becomes a real chat message;
    -- anything starting with "/" that isn't a recognized built-in chat
    -- command instead gets sent straight to the server via
    -- SendCommandToServer and rejected there as unknown, without ever
    -- reaching this hook at all (confirmed in the installed game's own
    -- Chat/ISChat.lua, function ISChat:onCommandEntered).
    if text:trim():lower() == "aicoordinates" then
        local hunt = HuntState.getActiveHunt(player)
        local infoText
        if hunt then
            infoText = string.format(
                "Active hunt: %s (channel %.1fMHz) at %d, %d, %d",
                hunt.personaName, hunt.channel / 1000, hunt.targetX, hunt.targetY, hunt.targetZ
            )
        else
            infoText = "All hunts in Config.Hunts have already been completed."
        end
        local msg = AIRadioHunt.newMimicMessage({
            text = infoText,
            author = "AIRadioHunt",
            chatType = "radio",
        })
        ISChat.addLineInChat(msg, 0)
        return
    end

    if text:sub(1, 1) == "/" then
        return
    end

    if not isCarryingTunedRadio(player) then
        return
    end

    if not HuntState.isStarted(player) or HuntState.isFound(player) then
        return
    end

    print("[AIRadioHunt] sending chat request: " .. text)
    local context = Context.build(player, lastTier, false)
    pendingRequestId = Bridge.sendRequest(text, context, "chat")
    pendingRequestKind = "chat"
end

print("[AIRadioHunt] mod loaded, chat hook installed")

local tickCounter = 0
local function onTick()
    if not pendingRequestId then
        return
    end

    tickCounter = tickCounter + 1
    if tickCounter < Config.PollIntervalTicks then
        return
    end
    tickCounter = 0

    local response = Bridge.pollResponse()
    if not response then
        return
    end
    pendingRequestId = nil
    local kind = pendingRequestKind
    pendingRequestKind = nil

    local reply = response.reply
    if not reply or reply == "" then
        return
    end

    local player = getPlayer()

    if kind == "very_near" then
        -- Silent to the player: this is the note being written and the
        -- reward/note physically appearing at the survivor's hideout, ahead
        -- of the player actually arriving - no chat line, no overlay. The
        -- emotional reveal is reserved for EXTREMELY_NEAR (kind:"found" below).
        if player then
            HuntState.spawnLeaveItems(player, reply)
        end
        return
    end

    -- Resolve the hunt/volume/author BEFORE calling HuntState.completeHunt
    -- below - a "found" response advances state.activeHuntIndex to the
    -- *next* hunt in the chain, and this message is about the one that was
    -- just completed, not whatever comes after it.
    local hunt = player and HuntState.getActiveHunt(player)
    local volume = player and getCarriedRadioVolume(player) or 0
    local authorName = (hunt and hunt.personaName) or Config.DefaultPersonaName

    if kind == "found" then
        if player then
            HuntState.completeHunt(player)
            -- The chain may have just advanced to a new survivor at a new
            -- location - force the next proximity check to be treated as
            -- fresh rather than compared against the stale EXTREMELY_NEAR tier
            -- from whichever hunt just ended.
            lastTier = nil
        end
        if player and volume > 0 then
            AIRadioHunt.Overlay.show(reply, "found")
        end
    elseif player and volume > 0 then
        AIRadioHunt.Overlay.show(reply)
    end

    local msg = AIRadioHunt.newMimicMessage({
        text = reply,
        author = authorName,
        chatType = "radio",
    })
    ISChat.addLineInChat(msg, 0)
end
Events.OnTick.Add(onTick)
