-- VORP Gold Panning Mechanic Script (Refactored & Documented)

local VORPcore = exports.vorp_core:GetCore()
local goldPanUse = {}

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
    local success, err = pcall(function()
        exports.vorp_inventory:addItem(_source, item, count, meta)
    end)
    if not success then
        print(("[GoldPanning] Failed to give item %s to %s: %s"):format(item, _source, err))
        notify(_source, 'inventoryError')
    end
end

-- Utility: Remove an item from a player, with error handling
local function takeItem(_source, item, count, meta)
    local success, err = pcall(function()
        exports.vorp_inventory:subItem(_source, item, count, meta)
    end)
    if not success then
        print(("[GoldPanning] Failed to remove item %s from %s: %s"):format(item, _source, err))
        notify(_source, 'inventoryError')
    end
end

-- Utility: Check if a player can carry an item, with error handling
local function canCarry(_source, item, count)
    local success, result = pcall(function()
        return exports.vorp_inventory:canCarryItem(_source, item, count, nil)
    end)
    if not success then
        print(("[GoldPanning] Error in canCarry: %s"):format(result))
        return false
    end
    return result
end

-- Utility: Notify a player with a localized message
local function notify(_source, messageKey, duration)
    VORPcore.NotifyRightTip(_source, _U(messageKey), duration or 3000)
end

-- Utility: Register a usable item and trigger a client event
local function registerUsableItem(item, clientEvent, take)
    exports.vorp_inventory:registerUsableItem(item, function(data)
        TriggerClientEvent(clientEvent, data.source, item)
        if take then takeItem(data.source, item, 1) end
        exports.vorp_inventory:closeInventory(data.source)
    end)
end

-- Generalized bucket fill logic to avoid code duplication
local function handleBucketFill(_source, inputItem, outputItem, notifyMsg, denyMsg)
    if canCarry(_source, outputItem, 1) then
        takeItem(_source, inputItem, 1)
        giveItem(_source, outputItem, 1)
        notify(_source, notifyMsg)
    else
        notify(_source, denyMsg)
    end
end

-- Generalized use-and-return-empty logic for buckets
local function useItemAndReturnEmpty(_source, itemFull, itemEmpty, useMsg, receiveMsg, failMsg, successEvent, failureEvent)
    local count = exports.vorp_inventory:getItemCount(_source, nil, itemFull)
    if not canCarry(_source, itemEmpty, 1) then
        notify(_source, 'cannotCarryMoreMudBuckets')
        return
    end
    if count > 0 then
        takeItem(_source, itemFull, 1)
        notify(_source, useMsg)
        giveItem(_source, itemEmpty, 1)
        notify(_source, receiveMsg)
        TriggerClientEvent(successEvent, _source)
    else
        notify(_source, failMsg)
        TriggerClientEvent(failureEvent, _source)
    end
end

-- Register usable items and trigger appropriate client events
registerUsableItem(Config.emptyMudBucket, 'bcc-goldpanning:useEmptyMudBucket', false)
registerUsableItem(Config.goldwashProp, 'bcc-goldpanning:placeProp', true)
if Config.useWaterItems then
    registerUsableItem(Config.emptyWaterBucket, 'bcc-goldpanning:useWaterBucket', false)
end

-- Server Events - Buckets
RegisterServerEvent('bcc-goldpanning:mudBuckets')
AddEventHandler('bcc-goldpanning:mudBuckets', function()
    handleBucketFill(source, Config.emptyMudBucket, Config.mudBucket, 'receivedEmptyMudBucket', 'cannotCarryMoreMudBuckets')
end)

RegisterServerEvent('bcc-goldpanning:waterBuckets')
AddEventHandler('bcc-goldpanning:waterBuckets', function()
    handleBucketFill(source, Config.emptyWaterBucket, Config.waterBucket, 'receivedEmptyWaterBucket', 'cantCarryMoreEmptyWaterCans')
end)

-- Use a full bucket and return an empty one
RegisterServerEvent('bcc-goldpanning:useMudBucket')
AddEventHandler('bcc-goldpanning:useMudBucket', function()
    useItemAndReturnEmpty(source, Config.mudBucket, Config.emptyMudBucket,
        'usedMudBucket', 'receivedEmptyMudBucket', 'dontHaveMudBucket',
        'bcc-goldpanning:mudBucketUsedSuccess', 'bcc-goldpanning:mudBucketUsedfailure')
end)

RegisterServerEvent('bcc-goldpanning:useWaterBucket')
AddEventHandler('bcc-goldpanning:useWaterBucket', function()
    useItemAndReturnEmpty(source, Config.waterBucket, Config.emptyWaterBucket,
        'usedWaterBucket', 'receivedEmptyWaterBucket', 'dontHaveWaterBucket',
        'bcc-goldpanning:waterUsedSuccess', 'bcc-goldpanning:waterUsedfailure')
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
    goldPanUse[_source] = os.time() -- Used to limit pan success call timing
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

RegisterServerEvent('bcc-goldpanning:panSuccess')
AddEventHandler('bcc-goldpanning:panSuccess', function()
    local _source = source
    if not goldPanUse[_source] or os.time() - goldPanUse[_source] > PAN_SUCCESS_TIMEOUT then
        print("[WARNING] Player " .. _source .. " triggered panSuccess without recent goldPan use.")
        return
    end

    if canCarry(_source, Config.goldWashReward, Config.goldWashRewardAmount) then
        giveItem(_source, Config.goldWashReward, Config.goldWashRewardAmount)
        notify(_source, 'receivedGoldFlakes')
    else
        notify(_source, 'cantCarryMoreGoldFlakes')
    end

    if math.random(100) <= Config.extraRewardChance then
        giveItem(_source, Config.extraReward, Config.extraRewardAmount)
        notify(_source, 'receivedExtraReward')
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