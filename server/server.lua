-- VORP Gold Panning Mechanic Script (Refactored & Documented)

local VORPcore = exports.vorp_core:GetCore()
local goldPanUse = {}

-- Config Debugging
local Config = Config or {}
Config.debug = Config.debug or false -- Set to true for debug logging
local function debugLog(msg)
    if Config.debug then
        print("[GoldPanning][DEBUG] " .. tostring(msg))
    end
end
-- ingame Debugging command- allows toggling from inserver console
-- Usage: /golddebug on or /golddebug off
RegisterCommand("golddebug", function(source, args, raw)
    if source ~= 0 then -- Only allow from server console or add admin check here
        print("You do not have permission to use this command.")
        return
    end
    if args[1] == "on" then
        Config.debug = true
        print("[GoldPanning] Debug mode ENABLED.")
    elseif args[1] == "off" then
        Config.debug = false
        print("[GoldPanning] Debug mode DISABLED.")
    else
        print("[GoldPanning] Usage: /golddebug [on|off]")
    end
end, false)
-- Whitelist for valid prop and item names (add more as needed)
local validProps = {
    [Config.goldwashProp] = true
}
local validItems = {
    [Config.goldwashProp] = true,
    [Config.emptyMudBucket] = true,
    [Config.mudBucket] = true,
    [Config.emptyWaterBucket] = true,
    [Config.waterBucket] = true,
    [Config.goldPan] = true,
    [Config.goldWashReward] = true,
    [Config.extraReward] = true
}

-- Utility: Give an item to a player, with error handling
local function giveItem(_source, item, count, meta)
    local success, err
    if meta and next(meta) ~= nil then
        success, err = pcall(function()
            exports.vorp_inventory:addItem(_source, item, count, meta)
        end)
    else
        success, err = pcall(function()
            exports.vorp_inventory:addItem(_source, item, count)
        end)
    end
    if not success then
        print(("[GoldPanning] Failed to give item %s to %s: %s"):format(item, _source, err))
        notify(_source, 'inventoryScriptError')
        debugLog(("Failed to give %s to %s: %s"):format(item, _source, err))
    end
end

-- Utility: Remove an item from a player, with error handling
local function takeItem(_source, item, count, meta)
    local success, err = pcall(function()
        exports.vorp_inventory:subItem(_source, item, count, meta)
    end)
    if not success then
        print(("[GoldPanning] Failed to remove item %s from %s: %s"):format(item, _source, err))
        notify(_source, 'inventoryScriptError')
        debugLog(("Failed to remove %s from %s: %s"):format(item, _source, err))
    end
end

-- Utility: Check if a player can carry an item, with error handling
local function canCarry(_source, item, count)
    local success, result = pcall(function()
        return exports.vorp_inventory:canCarryItem(_source, item, count, nil)
    end)
    if not success then
        print(("[GoldPanning] Error in canCarry: %s"):format(result))
        debugLog(("canCarry error for %s: %s"):format(_source, result))
        return false
    end
    return result
end

-- Utility: Notify a player with a localized message
local function notify(_source, messageKey, duration)
    local msg = _U(messageKey)
    if not msg or msg == messageKey then
        msg = "[Missing locale: " .. messageKey .. "]"
    end
    VORPcore.NotifyRightTip(_source, msg, duration or 3000)
end

-- Utility: Register a usable item and trigger a client event
local function registerUsableItem(item, clientEvent, take)
    exports.vorp_inventory:registerUsableItem(item, function(data)
        TriggerClientEvent(clientEvent, data.source, item)
        if take then takeItem(data.source, item, 1) end
        exports.vorp_inventory:closeInventory(data.source)
    end)
end

-- Register usable items and trigger appropriate client events
registerUsableItem(Config.emptyMudBucket, 'bcc-goldpanning:useEmptyMudBucket', false)
registerUsableItem(Config.goldwashProp, 'bcc-goldpanning:placeProp', true)
if Config.useWaterItems then
    registerUsableItem(Config.emptyWaterBucket, 'bcc-goldpanning:useWaterBucket', false)
end

-- Server Events - Buckets
--  Filling buckets (empty -> full)
RegisterServerEvent('bcc-goldpanning:fillBucket')
AddEventHandler('bcc-goldpanning:fillBucket', function(emptyItem, fullItem, successKey, failKey)
    local _source = source
    if canCarry(_source, fullItem, 1) then
        takeItem(_source, emptyItem, 1)
        giveItem(_source, fullItem, 1)
        notify(_source, successKey)
    else
        notify(_source, failKey)
    end
end)

--  Using buckets (full -> empty)
RegisterServerEvent('bcc-goldpanning:useBucket')
AddEventHandler('bcc-goldpanning:useBucket', function(fullItem, emptyItem, useKey, receiveKey, failKey, successEvent, failureEvent)
    local _source = source
    local count = exports.vorp_inventory:getItemCount(_source, nil, fullItem)
    if not canCarry(_source, emptyItem, 1) then
        notify(_source, failKey)
        return
    end
    if count > 0 then
        takeItem(_source, fullItem, 1)
        notify(_source, useKey)
        giveItem(_source, emptyItem, 1)
        notify(_source, receiveKey)
        if successEvent then TriggerClientEvent(successEvent, _source) end
    else
        notify(_source, failKey)
        if failureEvent then TriggerClientEvent(failureEvent, _source) end
    end
end)

-- Tool Durability: Handles gold pan usage and durability reduction
RegisterServerEvent('bcc-goldpanning:usegoldPan')
AddEventHandler('bcc-goldpanning:usegoldPan', function()
    local _source = source
    local count = exports.vorp_inventory:getItemCount(_source, nil, Config.goldPan)

    if count <= 0 then
        notify(_source, 'noPan')
        TriggerClientEvent('bcc-goldpanning:goldPanfailure', _source)
        return
    end

    local tool = exports.vorp_inventory:getItem(_source, Config.goldPan)
    if not tool then
        notify(_source, 'noPan')
        return
    end

    local durability = (tool.metadata and tool.metadata.durability or 100) - Config.ToolUsage
    takeItem(_source, Config.goldPan, 1, tool.metadata)

    if durability > 0 then
        giveItem(_source, Config.goldPan, 1, {
            description = Config.UsageLeft .. durability,
            durability = durability
        })
    else
        notify(_source, 'needNewTool', 4000)
    end

    TriggerClientEvent('bcc-goldpanning:goldPanUsedSuccess', _source)
    goldPanUse[_source] = true
    Citizen.SetTimeout(PAN_SUCCESS_TIMEOUT * 1000, function()
        goldPanUse[_source] = nil
    end)
end)

-- Prop placement: Broadcasts prop placement to all clients, with validation
RegisterServerEvent('bcc-goldpanning:placePropGlobal')
AddEventHandler('bcc-goldpanning:placePropGlobal', function(propName, x, y, z, heading)
    if not validProps[propName] then
        print(("[GoldPanning] Invalid propName from client: %s"):format(tostring(propName)))
        return
    end
    TriggerClientEvent('bcc-goldpanning:spawnPropForAll', -1, propName, x, y, z, heading)
end)

-- Gold panning reward logic, with anti-abuse timer
local PAN_SUCCESS_TIMEOUT = 30 -- seconds

-------------------------------------Handle Gold Rewards-------------------------------------
RegisterServerEvent('bcc-goldpanning:panSuccess')
AddEventHandler('bcc-goldpanning:panSuccess', function()
    local _source = source
    if exports.vorp_inventory:canCarryItem(_source, Config.goldWashReward, Config.goldWashRewardAmount) and goldPanUse[_source] then
        exports.vorp_inventory:addItem(_source, Config.goldWashReward, Config.goldWashRewardAmount)
        VORPcore.NotifyRightTip(_source, _U('receivedGoldFlakes'), 3000)
        if Config.debug then
            print("player " .. _source .. " has received " .. Config.goldWashRewardAmount .. " gold flakes")
        end
    else
        VORPcore.NotifyRightTip(_source, _U('cantCarryMoreGoldFlakes'), 3000)
    end

    if math.random(100) <= Config.extraRewardChance and goldPanUse[_source] then
        exports.vorp_inventory:addItem(_source, Config.extraReward, Config.extraRewardAmount)
        VORPcore.NotifyRightTip(_source, _U('receivedExtraReward'), 3000)
        if Config.debug then
            print("player " .. _source .. " has received " .. Config.extraRewardAmount .. " extra reward")
        end
    end

    if not goldPanUse[_source] then
        --prob cheater
        return
    end
    goldPanUse[_source] = nil
end)

-- Give prop back to player if they can carry it
RegisterServerEvent('bcc-goldpanning:givePropBack')
AddEventHandler('bcc-goldpanning:givePropBack', function()
    local _source = source
    if canCarry(_source, Config.goldwashProp, 1) then
        giveItem(_source, Config.goldwashProp, 1)
        notify(_source, 'propPickup')
    else
        notify(_source, 'propFull')
    end
end)

-- Utility events for returning buckets
RegisterServerEvent('bcc-goldpanning:addMudBack')
AddEventHandler('bcc-goldpanning:addMudBack', function()
    giveItem(source, Config.emptyMudBucket, 1)
end)

RegisterServerEvent('bcc-goldpanning:addWaterBack')
AddEventHandler('bcc-goldpanning:addWaterBack', function()
    giveItem(source, Config.emptyWaterBucket, 1)
end)

-- Check if player can carry an item, respond to client, with validation
RegisterServerEvent('bcc-goldpanning:checkCanCarry')
AddEventHandler('bcc-goldpanning:checkCanCarry', function(itemName)
    local _source = source
    if not validItems[itemName] then
        print(("[GoldPanning] Invalid itemName from client: %s"):format(tostring(itemName)))
        TriggerClientEvent('bcc-goldpanning:canCarryResponse', _source, false)
        return
    end
    TriggerClientEvent('bcc-goldpanning:canCarryResponse', _source, canCarry(_source, itemName, 1))
end)

-- Clear resources on restart
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    -- Clean up any server-side state if needed
    goldPanUse = {}
    -- Optionally, log or notify that the script was stopped
    print("[GoldPanning] Resource stopped and state cleared.")
end)