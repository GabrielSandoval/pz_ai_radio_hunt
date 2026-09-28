require "AIRadioHunt/Config"
require "AIRadioHunt/Proximity"

local Config = AIRadioHunt.Config
local Proximity = AIRadioHunt.Proximity

local Context = {}
AIRadioHunt.Context = Context

local function round1(n)
    if not n then return nil end
    return math.floor(n * 10 + 0.5) / 10
end

--- Returns a stable per-character id, generated once and persisted in the
--- character's own ModData (survives save/load). A separate ModData key
--- from DispatchAI's own characterId, so the two mods never collide on the
--- same character even if both are installed together.
local function getOrCreateCharacterId(player)
    local modData = player:getModData()
    if not modData.AIRadioHunt_CharacterId then
        local ts = (getTimestampMs and getTimestampMs()) or 0
        modData.AIRadioHunt_CharacterId = tostring(ts) .. "-" .. tostring(ZombRand(100000, 999999))
    end
    return modData.AIRadioHunt_CharacterId
end

--- Gathers the (deliberately coarse) snapshot sent alongside each request.
--- `proximityTier`/`tierChanged` are the only positional signal the active
--- survivor ever gets - raw player or target coordinates are never
--- included here, so the LLM can only react to distance in the same coarse
--- terms a real person would ("you're getting closer"), never claim to
--- know an exact location the game never told it.
---
--- `huntIndex` tells the companion which survivor in the chain this
--- request is for (so it can pick the right persona/prompt and keep each
--- survivor's conversation memory separate) - read directly out of the
--- same AIRadioHunt_State ModData table HuntState.lua manages, rather than
--- requiring that module here, to avoid coupling Context.lua's load order
--- to HuntState.lua's. Same reasoning for reading `state.hunts` (this
--- character's own randomly-generated per-hunt targetX/Y/city - see
--- HuntState.ensureHuntsGenerated) directly out of ModData here, rather
--- than calling into HuntState.lua for it - `Config.Hunts` itself is only
--- the identity/order template now (id/personaName), it does NOT carry
--- real location data any more. `city`/`landmark` are the only location
--- facts Lua actually hands the LLM - real coordinates, addresses, and
--- exact street names are never included here, only these two coarse,
--- game-truth facts the survivor is allowed to state outright. `landmark`
--- is computed here (via Proximity.nearestPointOfInterest against
--- Config.PointsOfInterest), not read from a hardcoded per-hunt field -
--- this is what keeps it working once hunt target squares are chosen
--- randomly.
function Context.build(player, proximityTier, tierChanged)
    local ctx = {}

    ctx.characterId = getOrCreateCharacterId(player)

    local modData = player:getModData()
    local state = modData.AIRadioHunt_State
    ctx.huntIndex = (state and state.activeHuntIndex) or 1

    local hunt = state and state.hunts and state.hunts[ctx.huntIndex]
    ctx.city = hunt and hunt.city
    ctx.landmark = hunt and Proximity.nearestPointOfInterest(
        hunt.targetX, hunt.targetY, Config.PointsOfInterest, Config.LandmarkMaxDistance
    )

    local gt = getGameTime()
    ctx.survivalTimeHours = gt and round1(gt:getWorldAgeHours()) or 0

    ctx.proximityTier = proximityTier
    ctx.tierChanged = tierChanged or false

    return ctx
end

return Context
