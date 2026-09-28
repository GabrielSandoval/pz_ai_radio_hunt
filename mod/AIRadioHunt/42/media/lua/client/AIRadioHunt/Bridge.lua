require "AIRadioHunt/Config"
require "AIRadioHunt/Json"

local Config = AIRadioHunt.Config
local Json = AIRadioHunt.Json

local Bridge = {}
AIRadioHunt.Bridge = Bridge

-- Same global (non-mod-scoped) getFileWriter/getFileReader as DispatchAI's
-- Bridge.lua - writes to a fixed <Zomboid save dir>/Lua/ location regardless
-- of whether the mod is a local copy or Steam Workshop install (confirmed
-- there: getModFileWriter/getModFileReader resolve to different,
-- install-source-dependent paths instead). Prefixed with the mod id since
-- this Lua/ folder is shared across all mods.
local REQUEST_FILE = "AIRadioHunt_request.json"
local RESPONSE_FILE = "AIRadioHunt_response.json"

local nextId = 0
local lastConsumedId = -1

--- Writes the player's message + context to disk for the companion process
--- to pick up. `kind` is "chat" (player typed this), "start" (the hunt just
--- began), "sound" (a real conditional-speech-style reaction the player's
--- own character had - genuinely their own voice, not ambient noise),
--- "near" (Mara visually spots the player, `context.spottedItem` set),
--- "very_near" (she's decided to leave right now - the reply is note text,
--- written into the reward/note items spawned ahead of arrival, not shown
--- in chat), or "found" (player reached the target square - the reveal:
--- she explains why she left, and the hunt is marked complete). Returns the
--- request id.
function Bridge.sendRequest(playerMessage, context, kind)
    nextId = nextId + 1

    local payload = {
        id = nextId,
        playerMessage = playerMessage,
        context = context,
        kind = kind or "chat",
    }

    local ok, writer = pcall(getFileWriter, REQUEST_FILE, true, false)
    if ok and writer then
        local okWrite, writeErr = pcall(function()
            writer:write(Json.encode(payload))
            writer:close()
        end)
        if okWrite then
            print("[AIRadioHunt] " .. REQUEST_FILE .. " write succeeded (id=" .. nextId .. ", kind=" .. tostring(kind) .. ")")
        else
            print("[AIRadioHunt] " .. REQUEST_FILE .. " write FAILED: " .. tostring(writeErr))
        end
    else
        print("[AIRadioHunt] getFileWriter FAILED: " .. tostring(writer))
    end

    return nextId
end

--- Checks for a reply matching the most recent request. Returns the whole
--- decoded response table (e.g. {reply=..., found=..., note=...}) once, or
--- nil if there's nothing new yet. Unlike DispatchAI's Bridge, callers here
--- need more than just the reply text - a kind:"found" response also
--- carries a `note` and a `found` flag.
function Bridge.pollResponse()
    local ok, reader = pcall(getFileReader, RESPONSE_FILE, false)
    if not ok or not reader then
        return nil
    end

    local lines = {}
    local line = reader:readLine()
    while line do
        table.insert(lines, line)
        line = reader:readLine()
    end
    reader:close()

    local text = table.concat(lines, "\n")
    if text == "" then
        return nil
    end

    local okDecode, decoded = pcall(Json.decode, text)
    if not okDecode or not decoded then
        return nil
    end

    if decoded.id == nil or decoded.id == lastConsumedId or decoded.id ~= nextId then
        return nil
    end

    lastConsumedId = decoded.id
    return decoded
end

return Bridge
