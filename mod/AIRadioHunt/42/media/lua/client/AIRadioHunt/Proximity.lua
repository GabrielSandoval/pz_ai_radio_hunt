AIRadioHunt = AIRadioHunt or {}

local Proximity = {}
AIRadioHunt.Proximity = Proximity

-- Checked closest-first so a player standing on the target square reads as
-- EXTREMELY_NEAR, not just the loosest tier its distance also happens to
-- satisfy.
local TIER_ORDER = { "EXTREMELY_NEAR", "VERY_NEAR", "NEAR", "FAR" }

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

--- Finds whichever entry in `pois` (a list of {name=..., x=..., y=...}) is
--- closest to (x, y), returning its `name` - or nil if the nearest one is
--- still farther than `maxDistance` (in tiles), so a target square that
--- isn't actually near anything nameable just doesn't get a landmark at
--- all, rather than always forcing a match to whatever's least-far-away.
--- Purely coordinate math - never invents a name, never guesses; `pois`
--- must already be real, verified coordinates (see Config.PointsOfInterest).
function Proximity.nearestPointOfInterest(x, y, pois, maxDistance)
    local best, bestDistance = nil, nil
    for _, poi in ipairs(pois) do
        local dx = x - poi.x
        local dy = y - poi.y
        local distance = math.sqrt(dx * dx + dy * dy)
        if not bestDistance or distance < bestDistance then
            best, bestDistance = poi, distance
        end
    end
    if best and bestDistance <= maxDistance then
        return best.name
    end
    return nil
end

return Proximity
