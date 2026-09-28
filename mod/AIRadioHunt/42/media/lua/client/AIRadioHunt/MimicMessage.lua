AIRadioHunt = AIRadioHunt or {}

--- Builds a plain-Lua object matching enough of the vanilla ChatMessage
--- interface to be passed to ISChat.instance:addLineInChat(). This avoids
--- needing a real Java ChatMessage/ChatBase instance, which mods can't
--- easily construct standalone. (Pattern based on the same technique used
--- by the OmiChat/OmiLibrary mods' "MimicMessage".)
function AIRadioHunt.newMimicMessage(args)
    args = args or {}

    local self = {}
    self._text = args.text or ""
    self._author = args.author or ""
    self._chatType = args.chatType or "radio"
    self._textColor = args.textColor or { r = 255, g = 255, b = 255 }

    function self:getText() return self._text end
    function self:getTextWithReplacedParentheses() return self._text end

    function self:getTextWithPrefix()
        return "[" .. self._author .. "]: " .. self._text
    end

    function self:getAuthor() return self._author end
    function self:isShowAuthor() return true end
    function self:isServerAuthor() return false end
    function self:isShowInChat() return true end
    function self:isScramble() return false end
    function self:isOverHeadSpeech() return false end
    function self:isFromDiscord() return false end
    function self:isLocal() return true end
    function self:isShouldAttractZombies() return false end
    function self:getRadioChannel() return -1 end
    function self:getTextColor() return self._textColor end
    function self:isCustomColor() return true end
    function self:getCustomTag() return "" end
    function self:getChatType() return self._chatType end
    function self:getDatetime() return nil end

    function self:getDatetimeStr()
        if getHourMinute then
            return getHourMinute()
        end
        return ""
    end

    return self
end
