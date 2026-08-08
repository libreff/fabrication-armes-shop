local runtime = nil
local contacts = {}
local contactGeneration = 0
local pendingRuntime = nil
local dialogue = { active = false, ped = nil, cam = nil, menu = nil, purchased = false }
local voiceWaiters = {}
local currentVoice = nil
local voiceSequence = 0

local function notify(description, kind)
    lib.notify({ title = "Fabrication d'armes", description = description, type = kind or 'inform' })
end

local function messageForCode(code, response)
    local messages = {
        too_far = Config.Locale.tooFar,
        not_enough_money = "Vous n'avez pas assez d'argent.",
        inventory_full = Config.Locale.inventoryFull,
        payment_failed = Config.Locale.purchaseFailed,
        rate_limit = 'Veuillez patienter un instant.',
        no_permission = Config.Locale.noPermission,
        not_configured = 'Cet élément n’est pas configuré.'
    }
    local message = messages[code] or 'Action impossible.'
    if code == 'no_permission' and response and response.group then
        message = ('%s Groupe détecté : %s.'):format(message, response.group)
    end
    return message
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(50) end
    return HasModelLoaded(hash) and hash or nil
end

local function requestAnim(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(50) end
    return HasAnimDictLoaded(dict)
end

local function deleteContacts()
    for _, ped in pairs(contacts) do
        if DoesEntityExist(ped) then
            exports.ox_target:removeLocalEntity(ped)
            DeleteEntity(ped)
        end
    end
    contacts = {}
end

local function rebuildContacts()
    contactGeneration = contactGeneration + 1
    local generation = contactGeneration
    deleteContacts()
    if not runtime then return end

    local function spawn(kind, data)
        if not data then return end
        local hash = requestModel(data.model)
        if not hash or generation ~= contactGeneration then
            if hash then SetModelAsNoLongerNeeded(hash) end
            return
        end
        local ped = CreatePed(4, hash, data.coords.x, data.coords.y, data.coords.z - 1.0, data.heading, false, false)
        SetModelAsNoLongerNeeded(hash)
        if ped == 0 then return end
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedCanRagdoll(ped, false)
        contacts[kind] = ped
        exports.ox_target:addLocalEntity(ped, {
            {
                name = ('armes_shop_%s'):format(kind),
                icon = kind == 'voyante' and 'fa-solid fa-eye' or 'fa-solid fa-scroll',
                label = kind == 'voyante' and Config.Locale.voyanteTarget or Config.Locale.baronneTarget,
                distance = Config.Interaction.targetDistance,
                canInteract = function() return not dialogue.active end,
                onSelect = function()
                    if kind == 'voyante' then TriggerEvent('armes_shop:client:talkVoyante', ped)
                    else TriggerEvent('armes_shop:client:talkBaronne', ped) end
                end
            }
        })
    end

    CreateThread(function() spawn('voyante', runtime.voyante) end)
    CreateThread(function() spawn('baronne', runtime.baronne) end)
end

local animations = {
    { dict = 'misscarsteal4@actor', name = 'actor_berating_loop', duration = 5200 },
    { dict = 'gestures@m@standing@casual', name = 'gesture_bring_it_on', duration = 3600 },
    { dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', name = 'idle_a', duration = 4700 }
}

local function animateConversation(ped)
    CreateThread(function()
        local index = 1
        while dialogue.active and dialogue.ped == ped and DoesEntityExist(ped) do
            local animation = animations[index]
            if requestAnim(animation.dict) and dialogue.active and dialogue.ped == ped then
                TaskPlayAnim(ped, animation.dict, animation.name, 2.0, 2.0, animation.duration, 49, 0.0, false, false, false)
                Wait(animation.duration - 250)
            else
                Wait(400)
            end
            index = index % #animations + 1
        end
    end)
end

local function beginDialogue(ped)
    if dialogue.active or not DoesEntityExist(ped) then return false end
    dialogue = { active = true, ped = ped, cam = nil, menu = nil, purchased = false }
    FreezeEntityPosition(cache.ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    TaskTurnPedToFaceEntity(cache.ped, ped, 700)
    TaskTurnPedToFaceEntity(ped, cache.ped, 700)
    Wait(450)

    local position = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.02, 0.69)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, position.x, position.y, position.z)
    PointCamAtPedBone(cam, ped, 31086, 0.0, 0.0, 0.02, true)
    SetCamFov(cam, 41.0)
    dialogue.cam = cam
    RenderScriptCams(true, true, 650, true, true)
    animateConversation(ped)
    return true
end

local function endDialogue()
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
    if dialogue.ped and DoesEntityExist(dialogue.ped) then ClearPedTasks(dialogue.ped) end
    if dialogue.cam and DoesCamExist(dialogue.cam) then
        RenderScriptCams(false, true, 650, true, true)
        DestroyCam(dialogue.cam, false)
    end
    FreezeEntityPosition(cache.ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    dialogue = { active = false, ped = nil, cam = nil, menu = nil, purchased = false }
    if pendingRuntime then
        runtime = pendingRuntime
        pendingRuntime = nil
        rebuildContacts()
    end
end

local function playVoice(name)
    local state = lib.callback.await('armes_shop:server:startVoice', false, name)
    if not state or not state.ok then return false end
    voiceSequence = voiceSequence + 1
    local id = voiceSequence
    local waiter = promise.new()
    voiceWaiters[id] = waiter
    currentVoice = { id = id, name = name, nonce = state.nonce, skippable = state.skippable == true, waiter = waiter }
    SendNUIMessage({ action = 'playVoice', name = name, id = id, skippable = state.skippable == true, skipLabel = Config.Voice.skipLabel })
    SetTimeout(140000, function()
        if voiceWaiters[id] then
            voiceWaiters[id] = nil
            if currentVoice and currentVoice.id == id then currentVoice = nil end
            SendNUIMessage({ action = 'stopVoice', id = id })
            waiter:resolve(false)
        end
    end)
    local completed = Citizen.Await(waiter)
    SendNUIMessage({ action = 'hideVoice', id = id })
    return completed == true
end

local function openVoyanteMenu()
    dialogue.menu = 'voyante'
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openVoyante' })
end

local function openBaronneMenu(state)
    dialogue.menu = 'baronne'
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openBaronne', economy = state.economy, schemaCount = state.schemaCount })
end

RegisterNetEvent('armes_shop:client:talkVoyante', function(ped)
    if not beginDialogue(ped) then return end
    CreateThread(function()
        playVoice('voyante_intro')
        if dialogue.active then openVoyanteMenu() end
    end)
end)

RegisterNetEvent('armes_shop:client:talkBaronne', function(ped)
    if not beginDialogue(ped) then return end
    CreateThread(function()
        playVoice('baronne_intro')
        if not dialogue.active then return end
        local state = lib.callback.await('armes_shop:server:getShopState', false)
        if not state or not state.ok then
            notify(messageForCode(state and state.code, state), 'error')
            endDialogue()
            return
        end
        openBaronneMenu(state)
    end)
end)

RegisterNUICallback('audioFinished', function(data, cb)
    cb({ ok = true })
    local id = tonumber(data and data.id)
    local waiter = id and voiceWaiters[id]
    if not waiter then return end
    local playback = currentVoice and currentVoice.id == id and currentVoice or nil
    voiceWaiters[id] = nil
    currentVoice = nil
    local completed = data.completed == true
    if completed and playback then
        completed = lib.callback.await('armes_shop:server:completeVoice', false, playback.name, playback.nonce) == true
    end
    waiter:resolve(completed)
end)

RegisterCommand(Config.Voice.skipCommand, function()
    local playback = currentVoice
    if not playback or not playback.skippable or not voiceWaiters[playback.id] then return end
    voiceWaiters[playback.id] = nil
    currentVoice = nil
    SendNUIMessage({ action = 'stopVoice', id = playback.id })
    playback.waiter:resolve(false)
end, false)

RegisterKeyMapping(Config.Voice.skipCommand, 'Passer une voix déjà écoutée', 'keyboard', Config.Voice.skipKey)

RegisterNUICallback('voyanteAnswer', function(data, cb)
    if not dialogue.active or dialogue.menu ~= 'voyante' then cb({ ok = false }); return end
    local answer = data and data.answer == 'yes' and 'yes' or 'no'
    cb({ ok = true })
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    dialogue.menu = nil
    CreateThread(function()
        playVoice(answer == 'yes' and 'voyante_joueur_oui' or 'voyante_joueur_non')
        endDialogue()
    end)
end)

RegisterNUICallback('buySchema', function(_, cb)
    if not dialogue.active or dialogue.menu ~= 'baronne' then cb({ ok = false }); return end
    local response = lib.callback.await('armes_shop:server:buySchema', false)
    cb({ ok = response and response.ok or false, message = response and response.ok and Config.Locale.purchaseSuccess or messageForCode(response and response.code, response) })
    if not response or not response.ok then return end
    dialogue.purchased = true
    dialogue.menu = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    CreateThread(function()
        notify(Config.Locale.purchaseSuccess, 'success')
        playVoice('baronne_achat_schema_sns')
        endDialogue()
    end)
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    if not dialogue.active then SetNuiFocus(false, false); return end
    local menu = dialogue.menu
    local purchased = dialogue.purchased
    dialogue.menu = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    CreateThread(function()
        if menu == 'baronne' and not purchased then playVoice('baronne_sans_achat') end
        endDialogue()
    end)
end)

RegisterNetEvent('armes_shop:client:syncConfig', function(config)
    if dialogue.active then pendingRuntime = config return end
    runtime = config
    rebuildContacts()
end)

local function creatorSave(kind, payload)
    local response = lib.callback.await('armes_shop:server:creatorSave', false, kind, payload)
    if response and response.ok then
        runtime = response.config
        notify(Config.Locale.creatorSaved, 'success')
    else
        notify(messageForCode(response and response.code, response), 'error')
    end
    return response and response.ok
end

local function askPedModel(title, current)
    local input = lib.inputDialog(title, {
        { type = 'input', label = 'Modèle du PNJ', default = current, required = true, min = 2, max = 64 }
    })
    if not input then return nil end
    local model = tostring(input[1]):lower()
    local hash = requestModel(model)
    if not hash or not IsModelAPed(hash) then
        if hash then SetModelAsNoLongerNeeded(hash) end
        notify('Modèle de PNJ invalide.', 'error')
        return nil
    end
    SetModelAsNoLongerNeeded(hash)
    return model
end

local function deletePreview(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

local function raycastPed(model)
    Wait(300)
    local heading = GetEntityHeading(cache.ped)
    local preview = nil
    local selected = nil
    lib.showTextUI(Config.Locale.creatorRaycast, { position = 'right-center', icon = 'crosshairs' })
    while true do
        Wait(0)
        local hit, _, coords = lib.raycast.fromCamera(Config.Creator.raycastFlags, 4, Config.Creator.raycastDistance)
        local valid = hit and coords and #(GetEntityCoords(cache.ped) - coords) <= Config.Creator.raycastDistance + 1.0
        if IsControlJustPressed(0, 174) then heading = (heading + Config.Creator.rotationStep) % 360.0 end
        if IsControlJustPressed(0, 175) then heading = (heading - Config.Creator.rotationStep) % 360.0 end
        if valid then
            if not preview then
                local hash = requestModel(model)
                if hash then
                    preview = CreatePed(4, hash, coords.x, coords.y, coords.z, heading, false, false)
                    SetModelAsNoLongerNeeded(hash)
                    if preview ~= 0 then
                        SetEntityInvincible(preview, true)
                        SetEntityCollision(preview, false, false)
                        SetEntityAlpha(preview, Config.Creator.previewAlpha, false)
                        FreezeEntityPosition(preview, true)
                    end
                end
            end
            if preview and preview ~= 0 and DoesEntityExist(preview) then
                SetEntityVisible(preview, true, false)
                SetEntityCoordsNoOffset(preview, coords.x, coords.y, coords.z, false, false, false)
                SetEntityHeading(preview, heading)
            end
        elseif preview and DoesEntityExist(preview) then
            SetEntityVisible(preview, false, false)
        end
        if valid and IsControlJustReleased(0, 38) then
            selected = { coords = { x = coords.x, y = coords.y, z = coords.z + 1.0 }, heading = heading, model = model }
            break
        end
        if IsControlJustReleased(0, 177) then break end
    end
    lib.hideTextUI()
    deletePreview(preview)
    return selected
end

local openCreator

local function placeContact(kind, label, fallback)
    local model = askPedModel(label, runtime[kind] and runtime[kind].model or fallback)
    if not model then openCreator(); return end
    local placement = raycastPed(model)
    if placement then creatorSave(kind, placement) end
    openCreator()
end

local function deleteContact(kind, label)
    local answer = lib.alertDialog({
        header = ('Supprimer %s ?'):format(label),
        content = 'Le PNJ disparaîtra immédiatement pour tous les joueurs.',
        centered = true,
        cancel = true,
        labels = { confirm = 'Supprimer', cancel = 'Annuler' }
    })
    if answer == 'confirm' then
        local response = lib.callback.await('armes_shop:server:creatorDelete', false, kind)
        if response and response.ok then
            runtime = response.config
            notify(Config.Locale.creatorDeleted, 'success')
        else
            notify(messageForCode(response and response.code, response), 'error')
        end
    end
    openCreator()
end

local function editEconomy()
    local economy = runtime.economy
    local input = lib.inputDialog('Schéma SNS Pistol', {
        { type = 'input', label = "Item d'argent", default = economy.moneyItem, required = true },
        { type = 'input', label = 'Item du schéma', default = economy.schemaItem, required = true },
        { type = 'number', label = 'Prix du schéma', default = economy.schemaPrice, min = 0, required = true }
    })
    if input then creatorSave('economy', { moneyItem = input[1], schemaItem = input[2], schemaPrice = input[3] }) end
    openCreator()
end

openCreator = function()
    local options = {
        {
            title = 'La Voyante',
            description = runtime.voyante and ('%s — replacer au raycast'):format(runtime.voyante.model) or 'Placer au raycast',
            icon = 'eye',
            onSelect = function() placeContact('voyante', 'La Voyante', Config.Defaults.voyanteModel) end
        },
        {
            title = 'La Baronne',
            description = runtime.baronne and ('%s — replacer au raycast'):format(runtime.baronne.model) or 'Placer au raycast',
            icon = 'scroll',
            onSelect = function() placeContact('baronne', 'La Baronne', Config.Defaults.baronneModel) end
        },
        {
            title = 'Économie et item',
            description = ('%s — $%s'):format(runtime.economy.schemaItem, runtime.economy.schemaPrice),
            icon = 'coins',
            onSelect = editEconomy
        }
    }
    if runtime.voyante then
        options[#options + 1] = { title = 'Supprimer la Voyante', icon = 'trash', iconColor = '#b84d4d', onSelect = function() deleteContact('voyante', 'la Voyante') end }
    end
    if runtime.baronne then
        options[#options + 1] = { title = 'Supprimer la Baronne', icon = 'trash', iconColor = '#b84d4d', onSelect = function() deleteContact('baronne', 'la Baronne') end }
    end
    lib.registerContext({ id = 'armes_shop_creator', title = "Fabrication d'armes — Créateur", options = options })
    lib.showContext('armes_shop_creator')
end

RegisterCommand(Config.Commands.creator, function()
    CreateThread(function()
        local allowed, group = lib.callback.await('armes_shop:server:isAdmin', false)
        if not allowed then
            notify(('%s Groupe détecté : %s.'):format(Config.Locale.noPermission, group or 'inconnu'), 'error')
            return
        end
        if not runtime then runtime = lib.callback.await('armes_shop:server:getConfig', false) end
        openCreator()
    end)
end, false)

CreateThread(function()
    runtime = lib.callback.await('armes_shop:server:getConfig', false)
    rebuildContacts()
end)

AddEventHandler('onResourceStop', function(stopped)
    if stopped ~= GetCurrentResourceName() then return end
    endDialogue()
    deleteContacts()
end)
