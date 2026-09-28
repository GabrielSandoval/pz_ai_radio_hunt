-- Server-side half of the item-spawning bridge. Even in a Host game
-- (embedded server + client, both in the same process), client and server
-- Lua run as separate states with separate object graphs - an item added
-- purely client-side (e.g. `player:getInventory():AddItem(...)` called from
-- media/lua/client/) exists only in that client's local snapshot, not on
-- the server, so any action requiring server validation (equip, drop,
-- pick up, read-note) silently fails or gets reverted. Every vanilla
-- example of adding an item to a player's inventory or a world square lives
-- under media/lua/server/ for exactly this reason, and inventory adds
-- additionally call sendAddItemToContainer(container, item) right after
-- AddItem (confirmed pervasively - e.g. server/Fishing/BuildingObjects/
-- FishingNet.lua, server/ClientCommands.lua) - AddItem alone still only
-- updates the server's own copy, and sendAddItemToContainer is what
-- actually pushes that change to the owning client. World-square adds
-- (AddWorldInventoryItem) don't need an equivalent explicit sync call - see
-- server/Traps/STrapGlobalObject.lua, server/Camping/camping_tent.lua,
-- server/Vehicles/Vehicles.lua for real, un-synced-after-the-fact examples
-- - being done server-side at all is what was missing.
--
-- The mod's client-side Lua (AIRadioHunt/HuntState.lua) triggers these via
-- sendClientCommand(player, "AIRadioHunt", <command>, args) - the standard
-- vanilla client->server RPC pattern (see server/ClientCommands.lua's own
-- Events.OnClientCommand dispatcher for another example of the same
-- mechanism, used independently here rather than piggybacking on vanilla's
-- own Commands table).

local Commands = {}

--- Real character name (not Steam username) - "Forename Surname" via the
--- real vanilla IsoGameCharacter:getDescriptor() API (confirmed against
--- client/ISUI/PlayerStats/ISPlayerStatsUI.lua's own usage). Falls back to
--- "Survivor" if the descriptor is ever unavailable for some reason.
local function getPlayerDisplayName(player)
    local ok, name = pcall(function()
        local d = player:getDescriptor()
        local full = (d:getForename() or "") .. " " .. (d:getSurname() or "")
        return full:match("^%s*(.-)%s*$") -- trim
    end)
    if ok and name and name ~= "" then
        return name
    end
    return "Survivor"
end

--- args: { radioItem, radioInitialChannel, radioVolume, noteItem, noteTitle, noteText }
--- Configure-then-sync, not sync-then-configure: sendAddItemToContainer
--- pushes whatever state the item is in at the moment it's called - fields
--- set *after* that call don't reach the client until some other resync
--- happens (e.g. actually opening/refreshing the inventory), which is why
--- an earlier version of this showed the note as a plain, unnamed Notepad
--- until picked up. Configuring first means the very first sync already
--- carries the final state.
Commands.giveStartingItems = function(player, args)
    local inv = player:getInventory()

    local radio = inv:AddItem(args.radioItem)
    if radio then
        local ok, err = pcall(function()
            local device = radio:getDeviceData()
            device:setIsTurnedOn(true)
            device:setChannel(args.radioInitialChannel)
            device:setDeviceVolume(args.radioVolume)
        end)
        if not ok then
            print("[AIRadioHunt] giveStartingItems: failed to configure starting radio: " .. tostring(err))
        end
        sendAddItemToContainer(inv, radio)
    end

    local note = inv:AddItem(args.noteItem)
    if note then
        local ok, err = pcall(function()
            note:addPage(1, args.noteText)
            note:setName(args.noteTitle or "Torn Note")
            note:setCustomName(true)
            note:setLockedBy("AIRadioHunt")
        end)
        if not ok then
            print("[AIRadioHunt] giveStartingItems: failed to write starting note: " .. tostring(err))
        end
        sendAddItemToContainer(inv, note)
    end

    print("[AIRadioHunt] starting radio + note given (server)")
end

--- args: { rewardItem, noteItem, noteText, personaName, x, y, z }
--- Spawns at the hunt's own target square (args.x/y/z), NOT the player's
--- current square - this now runs at VERY_NEAR range (up to 15 tiles out),
--- ahead of the player actually reaching the hideout, so the items are
--- already sitting there waiting rather than spawning at the exact moment
--- of arrival.
---
--- The reward item has no custom fields, so a plain AddWorldInventoryItem
--- call is fine for it (nothing to desync). The note needs custom
--- name/pages, and there's no confirmed "resync this world item's fields"
--- API - the fix used here (matching a real vanilla pattern from
--- server/Camping/SCampfireGlobalObject.lua, which moves an item from a
--- container onto a square rather than configuring it after the fact) is
--- to build and fully configure the note in the player's own inventory
--- first (sync via sendAddItemToContainer, confirmed reliable - see
--- giveStartingItems above), then move that already-configured,
--- already-synced item onto the square, rather than creating a bare item
--- directly on the ground and mutating it afterward.
Commands.spawnFoundItems = function(player, args)
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if not square then
        print("[AIRadioHunt] spawnFoundItems: target square not loaded, skipping item spawn")
        return
    end

    square:AddWorldInventoryItem(args.rewardItem, 0.4, 0.6, 0.0)

    local inv = player:getInventory()
    local noteItem = inv:AddItem(args.noteItem)
    if noteItem then
        local playerName = getPlayerDisplayName(player)
        local ok, err = pcall(function()
            noteItem:addPage(1, args.noteText)
            noteItem:setName(args.personaName .. "'s notes to " .. playerName)
            noteItem:setCustomName(true)
            noteItem:setLockedBy("AIRadioHunt")
        end)
        if not ok then
            print("[AIRadioHunt] spawnFoundItems: failed to write note: " .. tostring(err))
        end
        sendAddItemToContainer(inv, noteItem)
        inv:Remove(noteItem)
        sendRemoveItemFromContainer(inv, noteItem)
        square:AddWorldInventoryItem(noteItem, 0.6, 0.4, 0.0)
    end

    print("[AIRadioHunt] found: reward + note spawned (server) for " .. tostring(args.personaName))
end

local function onClientCommand(module, command, player, args)
    print("[AIRadioHunt] server OnClientCommand: module=" .. tostring(module) .. " command=" .. tostring(command))
    if module == "AIRadioHunt" and Commands[command] then
        Commands[command](player, args)
    end
end
Events.OnClientCommand.Add(onClientCommand)
print("[AIRadioHunt] ServerCommands.lua loaded, OnClientCommand handler registered")
