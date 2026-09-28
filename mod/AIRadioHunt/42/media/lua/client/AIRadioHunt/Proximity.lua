AIRadioHunt = AIRadioHunt or {}

local Proximity = {}
AIRadioHunt.Proximity = Proximity

-- Checked closest-first so a player standing on the target square reads as
-- SAME_SQUARE, not just the loosest tier its distance also happens to
-- satisfy.
local TIER_ORDER = { "SAME_SQUARE", "VERY_NEAR", "NEAR", "FAR" }

--- Euclidean tile distance from the player to a target x/y. Z (floor) is
--- ignored - which floor the player is on doesn't matter for "how close"
--- purposes in this vertical slice.
function Proximity.tileDistance(player, targetX, targetY)
    local dx = player:getX() - targetX
    local dy = player:getY() - targetY
    return math.sqrt(dx * dx + dy * dy)
end

--- Buckets a distance into one of TIER_ORDER using `thresholds` (a table
--- keyed the same way, e.g. Config.ProximityTiers). Falls back to "FAR" if
--- the distance exceeds every configured threshold.
function Proximity.tierFor(distance, thresholds)
    for _, tier in ipairs(TIER_ORDER) do
        local threshold = thresholds[tier]
        if threshold and distance <= threshold then
            return tier
        end
    end
    return "FAR"
end

return Proximity
