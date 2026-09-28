AIRadioHunt = AIRadioHunt or {}

local Log = {}
AIRadioHunt.Log = Log

local entries = {}
local MAX_ENTRIES = 12

--- Records a short event description (e.g. "Killed a zombie") for later
--- inclusion in the context sent to the AI.
function Log.add(text)
    table.insert(entries, text)
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
    end
end

--- Returns a copy of the recent event log, oldest first.
function Log.getRecent()
    local copy = {}
    for i, v in ipairs(entries) do
        copy[i] = v
    end
    return copy
end

return Log
