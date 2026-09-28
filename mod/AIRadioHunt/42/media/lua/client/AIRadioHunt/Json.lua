AIRadioHunt = AIRadioHunt or {}

--- Minimal self-contained JSON encode/decode. Vendored instead of relying on
--- a built-in `Json`/`require "Json"` module, since that isn't reliably
--- available across PZ builds (confirmed: `require("Json")` fails on 42.20.4).

local Json = {}
AIRadioHunt.Json = Json

local ESCAPE_OUT = {
    ['\\'] = '\\\\',
    ['"'] = '\\"',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local ESCAPE_IN = {
    ['"'] = '"',
    ['\\'] = '\\',
    ['/'] = '/',
    b = '\b',
    f = '\f',
    n = '\n',
    r = '\r',
    t = '\t',
}

local function escapeString(s)
    return (s:gsub('[\\"\n\r\t]', ESCAPE_OUT))
end

local encodeValue

local function isArray(t)
    local count = 0
    for k in pairs(t) do
        count = count + 1
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
    end
    if count == 0 then
        return false -- empty tables encode as {}
    end
    for i = 1, count do
        if t[i] == nil then
            return false
        end
    end
    return true
end

encodeValue = function(v)
    local t = type(v)
    if t == "string" then
        return '"' .. escapeString(v) .. '"'
    elseif t == "number" then
        return tostring(v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "table" then
        if isArray(v) then
            local parts = {}
            for i = 1, #v do
                parts[i] = encodeValue(v[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                parts[#parts + 1] = '"' .. escapeString(tostring(k)) .. '":' .. encodeValue(val)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

--- Encodes a Lua value (string/number/boolean/nested table) to a JSON string.
function Json.encode(value)
    return encodeValue(value)
end

--- Decodes a JSON string into a Lua value.
function Json.decode(str)
    local pos = 1

    local function skipWhitespace()
        local _, e = str:find("^%s*", pos)
        pos = e + 1
    end

    local function decodeError(msg)
        error("JSON decode error at position " .. pos .. ": " .. msg)
    end

    local decodeValueAt

    local function decodeString()
        pos = pos + 1
        local parts = {}
        while true do
            local c = str:sub(pos, pos)
            if c == "" then
                decodeError("unterminated string")
            elseif c == '"' then
                pos = pos + 1
                break
            elseif c == "\\" then
                local nextC = str:sub(pos + 1, pos + 1)
                if ESCAPE_IN[nextC] then
                    parts[#parts + 1] = ESCAPE_IN[nextC]
                    pos = pos + 2
                elseif nextC == 'u' then
                    local hex = str:sub(pos + 2, pos + 5)
                    local code = tonumber(hex, 16) or 63
                    parts[#parts + 1] = code < 128 and string.char(code) or "?"
                    pos = pos + 6
                else
                    parts[#parts + 1] = nextC
                    pos = pos + 2
                end
            else
                parts[#parts + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(parts)
    end

    local function decodeNumber()
        local s, e = str:find("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
        local numStr = str:sub(s, e)
        pos = e + 1
        return tonumber(numStr)
    end

    local function decodeArray()
        pos = pos + 1
        local arr = {}
        skipWhitespace()
        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        while true do
            skipWhitespace()
            arr[#arr + 1] = decodeValueAt()
            skipWhitespace()
            local c = str:sub(pos, pos)
            if c == "," then
                pos = pos + 1
            elseif c == "]" then
                pos = pos + 1
                break
            else
                decodeError("expected , or ]")
            end
        end
        return arr
    end

    local function decodeObject()
        pos = pos + 1
        local obj = {}
        skipWhitespace()
        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end
        while true do
            skipWhitespace()
            if str:sub(pos, pos) ~= '"' then
                decodeError("expected string key")
            end
            local key = decodeString()
            skipWhitespace()
            if str:sub(pos, pos) ~= ":" then
                decodeError("expected :")
            end
            pos = pos + 1
            skipWhitespace()
            obj[key] = decodeValueAt()
            skipWhitespace()
            local c = str:sub(pos, pos)
            if c == "," then
                pos = pos + 1
            elseif c == "}" then
                pos = pos + 1
                break
            else
                decodeError("expected , or }")
            end
        end
        return obj
    end

    decodeValueAt = function()
        skipWhitespace()
        local c = str:sub(pos, pos)
        if c == '"' then
            return decodeString()
        elseif c == "{" then
            return decodeObject()
        elseif c == "[" then
            return decodeArray()
        elseif c == "t" then
            pos = pos + 4
            return true
        elseif c == "f" then
            pos = pos + 5
            return false
        elseif c == "n" then
            pos = pos + 4
            return nil
        else
            return decodeNumber()
        end
    end

    skipWhitespace()
    local ok, result = pcall(decodeValueAt)
    if not ok then
        return nil
    end
    return result
end

return Json
