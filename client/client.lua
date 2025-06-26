-- Initialization
VORPcore = exports.vorp_core:GetCore()
BccUtils = exports['bcc-utils'].initiate()
Progressbar = exports["feather-progressbar"]:initiate()
local MiniGame = exports['bcc-minigames'].initiate()

local placing = false
local prompt = false
local BuildPrompt, DelPrompt, PlacingObj
local stage = "mudBucket"
local props = {}
local objectCounter = 0
local isAnimating = false -- Prevent animation overlap

-- Prompt Group Setup
local promptGroup = BccUtils.Prompt:SetupPromptGroup()
local useMudBucketPrompt = promptGroup:RegisterPrompt(_U('promptMudBucket'), Config.keys.E, 1, 1, true, 'hold', { timedeventhash = "MEDIUM_TIMED_EVENT" })
local useWaterBucketPrompt = promptGroup:RegisterPrompt(_U('promptWaterBucket'), Config.keys.R, 1, 1, true, 'hold', { timedeventhash = "MEDIUM_TIMED_EVENT" })
local useGoldPanPrompt = promptGroup:RegisterPrompt(_U('promptPan'), Config.keys.G, 1, 1, true, 'hold', { timedeventhash = "MEDIUM_TIMED_EVENT" })
local removeTablePrompt = promptGroup:RegisterPrompt(_U('promptPickUp'), Config.keys.F, 1, 1, true, 'hold', { timedeventhash = "MEDIUM_TIMED_EVENT" })

-- IS NEAR WATER UTILITY
local function IsNearWater()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed, true)
    local waterHash = Citizen.InvokeNative(0x5BA7A68A346A5A91, coords.x, coords.y, coords.z)
    local isInAllowedZone = false
    print(isInAllowedZone)
    for i = 1, #Config.waterTypes do
        local waterZone = Config.waterTypes[i]
        if waterHash == joaat(waterZone.hash) and IsPedOnFoot(playerPed) and IsEntityInWater(playerPed) then
            isInAllowedZone = true
            break
        end
    end

    if not isInAllowedZone then
        VORPcore.NotifyObjective(_U('noWater'), 4000)
        return false
    end
    return true
end

-- Gold Pan Handling
local goldPanObj = nil

local function AttachGoldPanProp()
    local playerPed = PlayerPedId()
    if goldPanObj and DoesEntityExist(goldPanObj) then
        DeleteObject(goldPanObj)
    end
    local coords = GetEntityCoords(playerPed)
    goldPanObj = CreateObject(GetHashKey("p_copperpan02x"), coords.x, coords.y, coords.z, true, true, false)
    AttachEntityToEntity(goldPanObj, playerPed, GetEntityBoneIndexByName(playerPed, "PH_R_Hand"), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 0, true, false, false)
end

local function RemoveGoldPanProp()
    if goldPanObj and DoesEntityExist(goldPanObj) then
        DeleteObject(goldPanObj)
        goldPanObj = nil
    end
end

--Clean up stubborn buckets
local function RemoveBucketProp()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local model = GetHashKey("p_wateringcan01x")
    local handle, obj = FindFirstObject()
    local success
    repeat
        if obj ~= 0 and GetEntityModel(obj) == model then
            local objCoords = GetEntityCoords(obj)
            if #(playerCoords - objCoords) < 3.0 then
                DeleteObject(obj)
            end
        end
        success, obj = FindNextObject(handle)
    until not success
    EndFindObject(handle)
end

-- Handlers for using empty mud bucket and empty water bucket from inventory
RegisterNetEvent('bcc-goldpanning:useEmptyMudBucket')
AddEventHandler('bcc-goldpanning:useEmptyMudBucket', function()
    if IsNearWater() then
        local playerPed = PlayerPedId()
        FreezeEntityPosition(playerPed, true)
        TaskStartScenarioInPlace(playerPed, joaat('WORLD_HUMAN_BUCKET_FILL'), -1, true, false, false, false)
        Progressbar.start(_U('collectingMud'), Config.bucketingTime, function(cancelled)
            if cancelled or not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then
                FreezeEntityPosition(playerPed, false)
                return
            end
            ClearPedTasksImmediately(playerPed)
            FreezeEntityPosition(playerPed, false)
            TriggerServerEvent('bcc-goldpanning:fillBucket',
    Config.emptyMudBucket, Config.mudBucket, 'receivedMudBucket', 'cannotCarryMoreMudBuckets')
        end, 'linear', 'rgba(255, 255, 255, 0.8)', '20vw',
            'rgba(255, 255, 255, 0.1)', 'rgba(211, 211, 211, 0.5)')
    else
        notify('noWater')
    end
end)

-- Water Bucket: Fill (from inventory)
RegisterNetEvent('bcc-goldpanning:useWaterBucket')
AddEventHandler('bcc-goldpanning:useWaterBucket', function()
    if IsNearWater() then
        local playerPed = PlayerPedId()
        FreezeEntityPosition(playerPed, true)
        TaskStartScenarioInPlace(playerPed, joaat('WORLD_HUMAN_BUCKET_FILL'), -1, true, false, false, false)
        Progressbar.start(_U('collectingWater'), Config.bucketingTime, function(cancelled)
            if cancelled or not DoesEntityExist(playerPed) or IsEntityDead(playerPed) then
                FreezeEntityPosition(playerPed, false)
                return
            end
            ClearPedTasksImmediately(playerPed)
            FreezeEntityPosition(playerPed, false)
            TriggerServerEvent('bcc-goldpanning:fillBucket',
    Config.emptyWaterBucket, Config.waterBucket, 'receivedWaterBucket', 'cantCarryMoreWaterBuckets')
        end, 'linear', 'rgba(255, 255, 255, 0.8)', '20vw',
            'rgba(255, 255, 255, 0.1)', 'rgba(211, 211, 211, 0.5)')
    else
        notify('noWater')
    end
end)

-- Handler for return table (canCarryResponse)
RegisterNetEvent('bcc-goldpanning:canCarryResponse')
AddEventHandler('bcc-goldpanning:canCarryResponse', function(canCarry)
    if canCarry then
        TriggerServerEvent('bcc-goldpanning:givePropBack')
    else
        VORPcore.NotifyObjective(_U('propFull'), 4000)
    end
end)

-- Improved RemoveTable: always finds and deletes the nearest prop
local function RemoveTable()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestObj, closestDist, closestId = nil, 2.0, nil
    for objectid, objdata in pairs(props) do
        if objdata.object and DoesEntityExist(objdata.object) then
            local dist = #(playerCoords - objdata.coords)
            if dist < closestDist then
                closestObj = objdata.object
                closestDist = dist
                closestId = objectid
            end
        end
    end
    if closestObj then
        DeleteEntity(closestObj)
        props[closestId] = nil
        TriggerServerEvent('bcc-goldpanning:checkCanCarry', Config.goldwashProp)
    else
        VORPcore.NotifyObjective(_U('noTableNearby'), 4000)
    end
    ResetActivePrompts()
end

-----------------------------------Mud Bucket-----------------------------------

local activePrompts = {
    mudBucket = false,
    waterBucket = false,
    goldPan = false,
    removeTable = true,
}

CreateThread(function()
    while true do
        Wait(5)
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local prop = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 2.0, GetHashKey(Config.goldwashProp), false, false, false)

        if props then
            for objectid, objdata in pairs(props) do
                local objCoords = objdata.coords
                local distance = GetDistanceBetweenCoords(playerCoords, objCoords, true)
                if distance < 2.0 and objdata.object and not placing then
                    if DoesEntityExist(objdata.object) then
                        promptGroup:ShowGroup("Gold Panning")

                        useMudBucketPrompt:TogglePrompt(activePrompts.mudBucket and stage == "mudBucket")
                        useWaterBucketPrompt:TogglePrompt(activePrompts.waterBucket and stage == "waterBucket")
                        useGoldPanPrompt:TogglePrompt(activePrompts.goldPan and stage == "goldPan")
                        removeTablePrompt:TogglePrompt(activePrompts.removeTable)

                        if stage == "mudBucket" and useMudBucketPrompt:HasCompleted() and activePrompts.mudBucket then
                            TriggerServerEvent('bcc-goldpanning:useBucket',
                                Config.mudBucket, Config.emptyMudBucket, 'usedMudBucket', 'receivedEmptyMudBucket', 'cannotCarryMoreMudBuckets',
                                'bcc-goldpanning:mudBucketUsedSuccess', 'bcc-goldpanning:mudBucketUsedfailure')
                            activePrompts.mudBucket = false
                        end
                        if stage == "waterBucket" and useWaterBucketPrompt:HasCompleted() and activePrompts.waterBucket then
                            TriggerServerEvent('bcc-goldpanning:useBucket',
                                Config.waterBucket, Config.emptyWaterBucket, 'usedWaterBucket', 'receivedEmptyWaterBucket', 'cantCarryMoreEmptyWaterCans',
                                'bcc-goldpanning:waterUsedSuccess', 'bcc-goldpanning:waterUsedfailure')
                            activePrompts.waterBucket = false
                        end
                        if stage == "goldPan" and useGoldPanPrompt:HasCompleted() and activePrompts.goldPan then
                            -- SET THE goldPanUse FLAG ON THE SERVER
                            TriggerServerEvent('bcc-goldpanning:usegoldPan')
                            MiniGame.Start('skillcheck', Config.Minigame, function(result)
                                if result.passed then
                                    RemoveBucketProp() -- Remove any held bucket prop
                                    AttachGoldPanProp() -- Attach the pan before animation
                                    PlayAnim("script_re@gold_panner@gold_success", "panning_idle", Config.goldWashTime, false, false)
                                    Wait(Config.goldWashTime / 2)
                                    TriggerServerEvent('bcc-goldpanning:panSuccess')
                                    VORPcore.NotifyObjective("[DEBUG] Triggered panSuccess event", 4000)
                                    Wait(Config.goldWashTime / 2)
                                    RemoveGoldPanProp() -- Remove the pan after animation
                                    stage = "mudBucket"
                                    ResetActivePrompts()
                                else
                                    notify('minigameFailed')
                                end
                            end)
                            activePrompts.goldPan = false
                        end
                        if removeTablePrompt:HasCompleted() and activePrompts.removeTable then
                            RemoveTable()
                            activePrompts.removeTable = false
                        end
                    else
                        ResetActivePrompts()
                    end
                else
                    ResetActivePrompts()
                end
            end
        end
    end
end)

function ResetActivePrompts()
    activePrompts.mudBucket = true
    activePrompts.waterBucket = true
    activePrompts.goldPan = true
    activePrompts.removeTable = true
end

-----------------------------------PROP STUFF-----------------------------------

-- Utility to setup a prompt
local function SetupPrompt(promptVar, labelKey, controlKey)
    local str = _U(labelKey)
    promptVar = Citizen.InvokeNative(0x04F97DE45A519419)
    PromptSetControlAction(promptVar, controlKey)
    str = CreateVarString(10, 'LITERAL_STRING', str)
    PromptSetText(promptVar, str)
    PromptSetEnabled(promptVar, false)
    PromptSetVisible(promptVar, false)
    PromptSetHoldMode(promptVar, true)
    PromptRegisterEnd(promptVar)
    return promptVar
end

-- Build and Delete prompts
local BuildPrompt, DelPrompt

local function SetupBuildPrompt()
    BuildPrompt = SetupPrompt(BuildPrompt, 'BuildPrompt', Config.keys.R)
end

local function SetupDelPrompt()
    DelPrompt = SetupPrompt(DelPrompt, 'DelPrompt', Config.keys.E)
end

RegisterNetEvent('bcc-goldpanning:placeProp')
AddEventHandler('bcc-goldpanning:placeProp', function(propName)
    SetupBuildPrompt()
    SetupDelPrompt()
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed, true)
    local waterHash = Citizen.InvokeNative(0x5BA7A68A346A5A91, coords.x, coords.y, coords.z)
    local pos = coords

    -- Check if in allowed water zone
    local isInAllowedZone = false
    for _, waterZone in ipairs(Config.waterTypes) do
        if waterHash == GetHashKey(waterZone.hash) and IsPedOnFoot(playerPed) and IsEntityInWater(playerPed) then
            isInAllowedZone = true
            break
        end
    end

    if not isInAllowedZone then
        VORPcore.NotifyObjective(_U('noWater'), 4000)
        TriggerServerEvent('bcc-goldpanning:givePropBack')
        return
    end

    local pHead = GetEntityHeading(playerPed)
    local object = GetHashKey(propName)
    if not HasModelLoaded(object) then
        RequestModel(object)
    end
    while not HasModelLoaded(object) do
        Wait(5)
    end

    placing = true
    PlacingObj = CreateObject(object, pos.x, pos.y, pos.z, false, true, false)
    SetEntityHeading(PlacingObj, pHead)
    SetEntityAlpha(PlacingObj, 51)
    AttachEntityToEntity(PlacingObj, playerPed, 0, 0.0, 1.0, -0.7, 0.0, 0.0, 0.0, true, false, false, false, false, true)

    while placing do
        Wait(10)
        if not prompt then
            if BuildPrompt then
                PromptSetEnabled(BuildPrompt, true)
                PromptSetVisible(BuildPrompt, true)
            end
            if DelPrompt then
                PromptSetEnabled(DelPrompt, true)
                PromptSetVisible(DelPrompt, true)
            end
            prompt = true
        end

        if BuildPrompt and PromptHasHoldModeCompleted(BuildPrompt) then
            PromptSetEnabled(BuildPrompt, false)
            PromptSetVisible(BuildPrompt, false)
            PromptSetEnabled(DelPrompt, false)
            PromptSetVisible(DelPrompt, false)
            prompt = false
            local PropPos = GetEntityCoords(PlacingObj, true)
            local PropHeading = GetEntityHeading(PlacingObj)
            DeleteObject(PlacingObj)
            Progressbar.start(_U('buildingTable'), Config.washBuildTime, function() end,
                'linear', 'rgba(255, 255, 255, 0.8)', '20vw',
                'rgba(255, 255, 255, 0.1)', 'rgba(211, 211, 211, 0.5)')
            TaskStartScenarioInPlace(playerPed, GetHashKey('WORLD_HUMAN_SLEDGEHAMMER'), -1, true, false, false, false)
            Citizen.Wait(Config.washBuildTime)
            ClearPedTasksImmediately(playerPed)
            if propName == Config.goldwashProp then
                TempObj = CreateObject(object, PropPos.x, PropPos.y, PropPos.z, true, true, true)
                SetEntityHeading(TempObj, PropHeading)
                PlaceObjectOnGroundProperly(TempObj)
                placing = false
                if TempObj then
                    objectCounter = objectCounter + 1
                    local objectId = "obj_" .. objectCounter
                    props[objectId] = { object = TempObj, coords = vector3(PropPos.x, PropPos.y, PropPos.z) }
                else
                    print("Failed to create " .. propName)
                end
            end
            break
        end

        if DelPrompt and PromptHasHoldModeCompleted(DelPrompt) then
            PromptSetEnabled(BuildPrompt, false)
            PromptSetVisible(BuildPrompt, false)
            PromptSetEnabled(DelPrompt, false)
            PromptSetVisible(DelPrompt, false)
            DeleteObject(PlacingObj)
            prompt = false
            TriggerServerEvent('bcc-goldpanning:givePropBack')
            break
        end
    end
end)


AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    prompt = false
    ResetActivePrompts()
    if BuildPrompt then
        PromptSetEnabled(BuildPrompt, false)
        PromptSetVisible(BuildPrompt, false)
    end
    if DelPrompt then
        PromptSetEnabled(DelPrompt, false)
        PromptSetVisible(DelPrompt, false)
    end
    if PlacingObj then
        DeleteEntity(PlacingObj)
    end
    -- Remove all placed props on resource stop
    for objectid, objdata in pairs(props) do
        if objdata.object and DoesEntityExist(objdata.object) then
            DeleteEntity(objdata.object)
        end
    end
end)

-----------------------------------Animations-----------------------------------

-- Utility: Play an animation, optionally with a raking prop and progress bar
function PlayAnim(animDict, animName, time, raking, loopUntilTimeOver)
    if isAnimating then return end
    isAnimating = true
    local playerPed = PlayerPedId()
    local animTime = time
    local flag = loopUntilTimeOver and 1 or 16

    -- Request animation dictionary only once
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(50)
    end

    -- Play animation
    TaskPlayAnim(playerPed, animDict, animName, 1.0, 1.0, loopUntilTimeOver and -1 or animTime, flag, 0, true, 0, false, 0, false)

    if raking then
        local playerCoords = GetEntityCoords(playerPed)
        local rakeObj = CreateObject(Config.goldSiftingProp, playerCoords.x, playerCoords.y, playerCoords.z, true, true, false)
        AttachEntityToEntity(rakeObj, playerPed, GetEntityBoneIndexByName(playerPed, "PH_R_Hand"), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, true, false, 0, true, false, false)
        Progressbar.start(_U('siftingGold'), time, function()
            if DoesEntityExist(rakeObj) then
                DeleteObject(rakeObj)
            end
            ClearPedTasksImmediately(playerPed)
            isAnimating = false
        end, 'linear', 'rgba(255, 255, 255, 0.8)', '20vw', 'rgba(255, 255, 255, 0.1)', 'rgba(211, 211, 211, 0.5)')
    else
        Wait(time)
        ClearPedTasksImmediately(playerPed)
        isAnimating = false
    end
end

-- Utility: Play a scenario in place, freezing the player during the action
function ScenarioInPlace(hash, time)
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    TaskStartScenarioInPlace(playerPed, joaat(hash), time, true, false, false, false)
    Wait(time)
    ClearPedTasksImmediately(playerPed)
    FreezeEntityPosition(playerPed, false)
end

-- Utility function for notifications (optional, for DRYness)
local function notify(key, duration)
    local msg = _U(key)
    if not msg or msg == key then
        msg = "[Missing locale: " .. key .. "]"
    end
    VORPcore.NotifyObjective(msg, duration or 4000)
end

-- Gold Pan Used Success
RegisterNetEvent('bcc-goldpanning:goldPanUsedSuccess')
AddEventHandler('bcc-goldpanning:goldPanUsedSuccess', function()
    notify('goldPanUsed')
    PlayAnim("script_re", "gold_panner_scoop", 4000, true, false)
end)

-- Gold Pan Failure
RegisterNetEvent('bcc-goldpanning:goldPanfailure')
AddEventHandler('bcc-goldpanning:goldPanfailure', function()
    notify('noPan')
end)

-- Mud Bucket: Pour (at table)
RegisterNetEvent('bcc-goldpanning:mudBucketUsedSuccess')
AddEventHandler('bcc-goldpanning:mudBucketUsedSuccess', function()
        local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    TaskStartScenarioInPlace(playerPed, joaat('WORLD_HUMAN_BUCKET_POUR_LOW'), -1, true, false, false, false)
    Progressbar.start(_U('pouringMud'), Config.bucketingTime, function(cancelled)
        if not cancelled and DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
            Wait(500) -- Let the scenario finish naturally
            ClearPedTasks(playerPed)
            RemoveBucketProp() -- <--- Add this line here
        end
        FreezeEntityPosition(playerPed, false)
        stage = "waterBucket"
        ResetActivePrompts()
    end, 'linear', 'rgba(255, 255, 255, 0.8)', '20vw',
        'rgba(255, 255, 255, 0.1)', 'rgba(211, 211, 211, 0.5)')
end)

-- Mud Bucket: Failure
RegisterNetEvent('bcc-goldpanning:mudBucketUsedfailure')
AddEventHandler('bcc-goldpanning:mudBucketUsedfailure', function()
    notify('dontHaveMudBucket')
    stage = "mudBucket"
    ResetActivePrompts()
end)

-- Water Bucket: Pour (at table)
RegisterNetEvent('bcc-goldpanning:waterUsedSuccess')
AddEventHandler('bcc-goldpanning:waterUsedSuccess', function()
    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    TaskStartScenarioInPlace(playerPed, joaat('WORLD_HUMAN_BUCKET_POUR_LOW'), -1, true, false, false, false)
    Progressbar.start(_U('pouringWater'), Config.bucketingTime, function(cancelled)
        if not cancelled and DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
            Wait(500)
            ClearPedTasks(playerPed)
            RemoveBucketProp() -- <--- Add this line here
        end
        FreezeEntityPosition(playerPed, false)
        stage = "goldPan"
        ResetActivePrompts()
    end, 'linear', 'rgba(255, 255, 255, 0.8)', '20vw',
        'rgba(255, 255, 255, 0.1)', 'rgba(211, 211, 211, 0.5)')
end)

-- Water Bucket: Failure
RegisterNetEvent('bcc-goldpanning:waterUsedfailure')
AddEventHandler('bcc-goldpanning:waterUsedfailure', function()
    notify('dontHaveWaterBucket')
    stage = "waterBucket"
    ResetActivePrompts()
end)