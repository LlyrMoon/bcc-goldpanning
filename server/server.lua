-- VORP Gold Panning Mechanic Script (Refactored)
VORPcore = exports.vorp_core:GetCore()
local goldPanUse = {}


-- Utilities functions 

local function giveItem(_source, item, count, meta)
    exports.vorp_inventory:addItem(_source, item, count, meta)
end

local function takeItem(_source, item, count, meta)
    exports.vorp_inventory:subItem(_source, item, count, meta)
end

local function canCarry(_source, item, count)
    return exports.vorp_inventory:canCarryItem(_source, item, count, nil)
end

local function notify(_source, messageKey, duration)
    VORPcore.NotifyRightTip(_source, _U(messageKey), duration or 3000)
end


-- Generalize Bucket Fill


local function handleBucketFill(_source, inputItem, outputItem, notifyMsg, denyMsg)
    if canCarry(_source, outputItem, 1) then
        takeItem(_source, inputItem, 1)
        giveItem(_source, outputItem, 1)
        notify(_source, notifyMsg)
    else
        notify(_source, denyMsg)
    end
end

--Usable items 

exports.vorp_inventory:registerUsableItem(Config.emptyMudBucket, function(data)
    TriggerClientEvent('bcc-goldpanning:useEmptyMudBucket', data.source, data.item.amount)
    exports.vorp_inventory:closeInventory(data.source)
end)

exports.vorp_inventory:registerUsableItem(Config.goldwashProp, function(data)
    TriggerClientEvent('bcc-goldpanning:placeProp', data.source, Config.goldwashProp)
    takeItem(data.source, Config.goldwashProp, 1)
    exports.vorp_inventory:closeInventory(data.source)
end)

if Config.useWaterItems then
    exports.vorp_inventory:registerUsableItem(Config.emptyWaterBucket, function(data)
        TriggerClientEvent('bcc-goldpanning:useWaterBucket', data.source, data.item.amount)
        exports.vorp_inventory:closeInventory(data.source)
    end)
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

--Use and Return the Empty

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

-- Tool Durability

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
    goldPanUse[_source] = os.time() -- ⏱️ Used to limit pan success call timing
end)

--Make it pretty and Give Reward

RegisterServerEvent('bcc-goldpanning:placePropGlobal')
AddEventHandler('bcc-goldpanning:placePropGlobal', function(propName, x, y, z, heading)
    TriggerClientEvent('bcc-goldpanning:spawnPropForAll', -1, propName, x, y, z, heading)
end)

RegisterServerEvent('bcc-goldpanning:panSuccess')
AddEventHandler('bcc-goldpanning:panSuccess', function()
    local _source = source
    if not goldPanUse[_source] or os.time() - goldPanUse[_source] > 30 then
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

-- Can you carry it and item return

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

RegisterServerEvent('bcc-goldpanning:addMudBack')
AddEventHandler('bcc-goldpanning:addMudBack', function()
    giveItem(source, Config.emptyMudBucket, 1)
end)

RegisterServerEvent('bcc-goldpanning:addWaterBack')
AddEventHandler('bcc-goldpanning:addWaterBack', function()
    giveItem(source, Config.emptyWaterBucket, 1)
end)

RegisterServerEvent('bcc-goldpanning:checkCanCarry')
AddEventHandler('bcc-goldpanning:checkCanCarry', function(itemName)
    local _source = source
    TriggerClientEvent('bcc-goldpanning:canCarryResponse', _source, canCarry(_source, itemName, 1))
end)
