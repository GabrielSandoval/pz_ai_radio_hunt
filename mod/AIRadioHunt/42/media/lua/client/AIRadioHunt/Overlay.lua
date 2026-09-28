require "ISUI/ISUIElement"

AIRadioHunt = AIRadioHunt or {}

local Overlay = {}
AIRadioHunt.Overlay = Overlay

-- Renders Mara's reply as a transient text bubble anchored to the player's
-- own screen position, exactly like DispatchAI's Overlay.lua - reads like a
-- radio crackling to life next to you, not a log entry. See that file for
-- the full positioning rationale; unchanged here.
local AIRadioHuntBubble = ISUIElement:derive("AIRadioHuntBubble")

local BASE_DURATION_MS = 3000
local MS_PER_CHAR = 60
local MAX_DURATION_MS = 12000

local MAX_LINE_WIDTH = 320
local PADDING = 8
local LINE_SPACING = 2

local HEAD_OFFSET = 170

local function wrapText(font, text)
    local lines = {}
    local current = ""

    for word in text:gmatch("%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if getTextManager():MeasureStringX(font, candidate) > MAX_LINE_WIDTH and current ~= "" then
            table.insert(lines, current)
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then
        table.insert(lines, current)
    end

    return lines
end

function AIRadioHuntBubble:prerender()
    if not self.lines then
        if self:getIsVisible() then
            self:setVisible(false)
        end
        return
    end

    if getTimestampMs() > self.expireAt then
        self.lines = nil
        self:setVisible(false)
        return
    end

    local player = getPlayer()
    if not player then
        self:setVisible(false)
        return
    end

    local playerNum = player:getPlayerNum()
    local zoom = getCore():getZoom(playerNum)
    local dx = -getPlayerScreenLeft(playerNum)
    local dy = -getPlayerScreenTop(playerNum)

    local anchorX = isoToScreenX(playerNum, player:getX(), player:getY(), player:getZ()) + dx
    local anchorY = isoToScreenY(playerNum, player:getX(), player:getY(), player:getZ()) + dy

    self:setWidth(self.bubbleWidth)
    self:setHeight(self.bubbleHeight)
    self:setX(anchorX - self.bubbleWidth / 2)
    self:setY(anchorY - HEAD_OFFSET / zoom - self.bubbleHeight)
end

-- Three visual styles sharing one bubble widget: "survivor" (default,
-- Mara's own lines - greenish radio-tinted border), "found" (gold border,
-- reserved for the one-time closing line when the hunt ends), and "player"
-- (grey, for the player's own muttered conditional-speech reaction to a
-- moodle/fire/weapon trigger - shown immediately, separately from whatever
-- Mara says back, same distinction DispatchAI's Overlay.lua makes).
local STYLES = {
    survivor = { border = { a = 0.6, r = 0.35, g = 0.55, b = 0.35 }, text = { r = 0.85, g = 0.95, b = 0.85 } },
    found = { border = { a = 0.7, r = 0.75, g = 0.65, b = 0.25 }, text = { r = 1.0, g = 0.95, b = 0.8 } },
    player = { border = { a = 0.5, r = 0.6, g = 0.6, b = 0.6 }, text = { r = 0.9, g = 0.9, b = 0.9 } },
}

function AIRadioHuntBubble:render()
    if not self.lines then
        return
    end

    local style = STYLES[self.variant] or STYLES.survivor

    self:drawRect(0, 0, self.bubbleWidth, self.bubbleHeight, 0.75, 0.05, 0.05, 0.05)
    self:drawRectBorder(0, 0, self.bubbleWidth, self.bubbleHeight, style.border.a, style.border.r, style.border.g, style.border.b)

    local lineHeight = getTextManager():getFontHeight(self.font)
    for i, line in ipairs(self.lines) do
        self:drawText(line, PADDING, PADDING + (i - 1) * (lineHeight + LINE_SPACING), style.text.r, style.text.g, style.text.b, 1, self.font)
    end
end

function AIRadioHuntBubble:show(text, variant)
    self.font = UIFont.Small
    self.variant = variant or "survivor"
    self.lines = wrapText(self.font, text)

    local lineHeight = getTextManager():getFontHeight(self.font)
    local widest = 0
    for _, line in ipairs(self.lines) do
        widest = math.max(widest, getTextManager():MeasureStringX(self.font, line))
    end

    self.bubbleWidth = widest + PADDING * 2
    self.bubbleHeight = (#self.lines * lineHeight) + ((#self.lines - 1) * LINE_SPACING) + PADDING * 2

    local duration = math.min(BASE_DURATION_MS + #text * MS_PER_CHAR, MAX_DURATION_MS)
    self.expireAt = getTimestampMs() + duration
    self:setVisible(true)
end

function AIRadioHuntBubble:new()
    local o = ISUIElement:new(0, 0, 10, 10)
    setmetatable(o, self)
    self.__index = self
    o.wantMouseEvents = false
    o.lines = nil
    return o
end

local instance = nil

--- Shows `text` as a fading bubble above the local player, replacing
--- whatever bubble (if any) is currently displayed. `variant` is "survivor"
--- (default - Mara's ordinary lines), "found" (gold, the one-time closing
--- line), or "player" (grey, the player's own muttered reaction to a
--- conditional-speech trigger).
function Overlay.show(text, variant)
    if not instance then
        instance = AIRadioHuntBubble:new()
        instance:initialise()
        instance:addToUIManager()
    end
    instance:show(text, variant)
end

return Overlay
