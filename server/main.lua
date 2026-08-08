local ESX = exports.es_extended:getSharedObject()
local resourceName = GetCurrentResourceName()
local configFile = 'data/config.json'
local voicesFile = 'data/voices.json'

local runtime = {
    voyante = nil,
    baronne = nil,
    economy = {
        moneyItem = Config.Defaults.moneyItem,
        schemaItem = Config.Defaults.schemaItem,
        schemaPrice = Config.Defaults.schemaPrice
    }
}

local heardVoices = {}
local voiceSessions = {}
local rateLimits = {}

math.randomseed(os.time())

local function getGroup(player)
    if not player then return 'user' end
    local group
    if type(player.getGroup) == 'function' then
        local ok, value = pcall(player.getGroup)
        if not ok then ok, value = pcall(player.getGroup, player) end
        if ok then group = value end
    end
    if not group and type(player.group) == 'string' then group = player.group end
    if not group and type(player.variables) == 'table' then group = player.variables.group end
    if not group and type(player.get) == 'function' then
        local ok, value = pcall(player.get, 'group')
        if not ok then ok, value = pcall(player.get, player, 'group') end
        if ok then group = value end
    end
    return tostring(group or 'user'):lower():gsub('^%s+', ''):gsub('%s+$', '')
end

local function isAdmin(source)
    if source == 0 then return true end
    return Config.AdminGroups[getGroup(ESX.GetPlayerFromId(source))] == true
end

local function limited(source, key, delay)
    local id = ('%s:%s'):format(source, key)
    local now = GetGameTimer()
    if rateLimits[id] and now - rateLimits[id] < delay then return true end
    rateLimits[id] = now
    return false
end

local function copy(value)
    return json.decode(json.encode(value))
end

local function cleanCoords(coords)
    if type(coords) ~= 'table' then return nil end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z or math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 3000 then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function cleanModel(model, fallback)
    model = tostring(model or ''):lower():gsub('[^%w_]', '')
    if #model < 2 or #model > 64 then return fallback end
    return model
end

local function cleanItem(item, fallback)
    item = tostring(item or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #item < 1 or #item > 80 or item:find('[%c%s]') then return fallback end
    return item
end

local function cleanContact(data, fallbackModel)
    if type(data) ~= 'table' then return nil end
    local coords = cleanCoords(data.coords)
    if not coords then return nil end
    return {
        coords = coords,
        heading = (tonumber(data.heading) or 0.0) % 360.0,
        model = cleanModel(data.model, fallbackModel)
    }
end

local function distance(a, b)
    if not a or not b then return 99999.0 end
    local dx = (tonumber(a.x) or 0.0) - (tonumber(b.x) or 0.0)
    local dy = (tonumber(a.y) or 0.0) - (tonumber(b.y) or 0.0)
    local dz = (tonumber(a.z) or 0.0) - (tonumber(b.z) or 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function playerCoords(source)
    local ped = GetPlayerPed(source)
    return ped and ped ~= 0 and GetEntityCoords(ped) or nil
end

local function playerIdentifier(source)
    local identifier = GetPlayerIdentifierByType(source, 'license')
    if identifier and identifier ~= '' then return identifier end
    local identifiers = GetPlayerIdentifiers(source)
    return identifiers and identifiers[1] or ('source:%s'):format(source)
end

local function normalize(decoded)
    if type(decoded) ~= 'table' then return end
    runtime.voyante = cleanContact(decoded.voyante, Config.Defaults.voyanteModel)
    runtime.baronne = cleanContact(decoded.baronne, Config.Defaults.baronneModel)
    local economy = type(decoded.economy) == 'table' and decoded.economy or {}
    runtime.economy = {
        moneyItem = cleanItem(economy.moneyItem, Config.Defaults.moneyItem),
        schemaItem = cleanItem(economy.schemaItem, Config.Defaults.schemaItem),
        schemaPrice = math.max(0, math.floor(tonumber(economy.schemaPrice) or Config.Defaults.schemaPrice))
    }
end

local function loadConfig()
    local raw = LoadResourceFile(resourceName, configFile)
    if not raw or raw == '' then return end
    local ok, decoded = pcall(json.decode, raw)
    if ok then normalize(decoded) else print(('[%s] %s est invalide.'):format(resourceName, configFile)) end
end

local function saveConfig()
    SaveResourceFile(resourceName, configFile, json.encode(runtime), -1)
end

local function loadVoices()
    local raw = LoadResourceFile(resourceName, voicesFile)
    if not raw or raw == '' then return end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then heardVoices = decoded end
end

local function saveVoices()
    SaveResourceFile(resourceName, voicesFile, json.encode(heardVoices), -1)
end

loadConfig()
loadVoices()

local function inventoryCount(source, item)
    local ok, count = pcall(function()
        return exports[Config.Inventory]:GetItemCount(source, item, nil)
    end)
    return ok and math.max(0, tonumber(count) or 0) or 0
end

local function addItem(source, item, count)
    local ok, result = pcall(function()
        return exports[Config.Inventory]:AddItem(source, item, count)
    end)
    return ok and result == true
end

local function removeItem(source, item, count)
    local ok, result = pcall(function()
        return exports[Config.Inventory]:RemoveItem(source, item, count)
    end)
    return ok and result == true
end

local function publishConfig(target)
    TriggerClientEvent('armes_shop:client:syncConfig', target or -1, copy(runtime))
end

lib.callback.register('armes_shop:server:getConfig', function()
    return copy(runtime)
end)

lib.callback.register('armes_shop:server:isAdmin', function(source)
    return isAdmin(source), getGroup(ESX.GetPlayerFromId(source))
end)

lib.callback.register('armes_shop:server:startVoice', function(source, name)
    name = tostring(name or '')
    if not Config.Voice.durations[name] then return { ok = false } end
    local identifier = playerIdentifier(source)
    local playerVoices = type(heardVoices[identifier]) == 'table' and heardVoices[identifier] or {}
    heardVoices[identifier] = playerVoices
    if playerVoices[name] == true then
        voiceSessions[source] = nil
        return { ok = true, skippable = true }
    end
    local nonce = ('%s:%s:%s'):format(source, GetGameTimer(), math.random(100000, 999999))
    voiceSessions[source] = { name = name, nonce = nonce, startedAt = os.time() }
    return { ok = true, skippable = false, nonce = nonce }
end)

lib.callback.register('armes_shop:server:completeVoice', function(source, name, nonce)
    name = tostring(name or '')
    local duration = Config.Voice.durations[name]
    if not duration then return false end
    local identifier = playerIdentifier(source)
    local playerVoices = type(heardVoices[identifier]) == 'table' and heardVoices[identifier] or {}
    heardVoices[identifier] = playerVoices
    if playerVoices[name] == true then return true end
    local playback = voiceSessions[source]
    if not playback or playback.name ~= name or playback.nonce ~= nonce then return false end
    if os.time() - playback.startedAt < math.max(1, duration - Config.Voice.completionTolerance) then return false end
    playerVoices[name] = true
    voiceSessions[source] = nil
    saveVoices()
    return true
end)

lib.callback.register('armes_shop:server:getShopState', function(source)
    if not runtime.baronne or distance(playerCoords(source), runtime.baronne.coords) > Config.Interaction.serverValidationDistance then
        return { ok = false, code = 'too_far' }
    end
    return {
        ok = true,
        economy = copy(runtime.economy),
        schemaCount = inventoryCount(source, runtime.economy.schemaItem)
    }
end)

lib.callback.register('armes_shop:server:buySchema', function(source)
    if limited(source, 'buy_schema', 800) then return { ok = false, code = 'rate_limit' } end
    if not runtime.baronne or distance(playerCoords(source), runtime.baronne.coords) > Config.Interaction.serverValidationDistance then
        return { ok = false, code = 'too_far' }
    end
    local economy = runtime.economy
    if inventoryCount(source, economy.moneyItem) < economy.schemaPrice then return { ok = false, code = 'not_enough_money' } end
    if economy.schemaPrice > 0 and not removeItem(source, economy.moneyItem, economy.schemaPrice) then
        return { ok = false, code = 'payment_failed' }
    end
    if not addItem(source, economy.schemaItem, 1) then
        if economy.schemaPrice > 0 then addItem(source, economy.moneyItem, economy.schemaPrice) end
        return { ok = false, code = 'inventory_full' }
    end
    return { ok = true, schemaCount = inventoryCount(source, economy.schemaItem) }
end)

lib.callback.register('armes_shop:server:creatorSave', function(source, kind, payload)
    if not isAdmin(source) then return { ok = false, code = 'no_permission', group = getGroup(ESX.GetPlayerFromId(source)) } end
    if limited(source, 'creator_save', 300) then return { ok = false, code = 'rate_limit' } end

    if kind == 'economy' then
        if type(payload) ~= 'table' then return { ok = false, code = 'invalid' } end
        runtime.economy = {
            moneyItem = cleanItem(payload.moneyItem, runtime.economy.moneyItem),
            schemaItem = cleanItem(payload.schemaItem, runtime.economy.schemaItem),
            schemaPrice = math.max(0, math.floor(tonumber(payload.schemaPrice) or runtime.economy.schemaPrice))
        }
    elseif kind == 'voyante' or kind == 'baronne' then
        local entry = cleanContact(payload, kind == 'voyante' and Config.Defaults.voyanteModel or Config.Defaults.baronneModel)
        if not entry or distance(playerCoords(source), entry.coords) > Config.Creator.raycastDistance + 5.0 then
            return { ok = false, code = 'too_far' }
        end
        runtime[kind] = entry
    else
        return { ok = false, code = 'invalid' }
    end

    saveConfig()
    publishConfig()
    return { ok = true, config = copy(runtime) }
end)

lib.callback.register('armes_shop:server:creatorDelete', function(source, kind)
    if not isAdmin(source) then return { ok = false, code = 'no_permission', group = getGroup(ESX.GetPlayerFromId(source)) } end
    if kind ~= 'voyante' and kind ~= 'baronne' then return { ok = false, code = 'invalid' } end
    if not runtime[kind] then return { ok = false, code = 'not_configured' } end
    runtime[kind] = nil
    saveConfig()
    publishConfig()
    return { ok = true, config = copy(runtime) }
end)

AddEventHandler('playerDropped', function()
    voiceSessions[source] = nil
    for key in pairs(rateLimits) do
        if key:sub(1, #tostring(source) + 1) == tostring(source) .. ':' then rateLimits[key] = nil end
    end
end)
