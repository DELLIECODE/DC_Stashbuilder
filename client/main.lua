local ESX = exports.es_extended:getSharedObject()

local Zones = {}
local JobOptions = {}

local function jobsToText(value)
    if not value or value == '' then return '' end
    local ok, jobs = pcall(json.decode, value)
    if not ok or type(jobs) ~= 'table' then return value end
    local parts = {}
    for _, job in ipairs(jobs) do
        if type(job) == 'table' then
            parts[#parts + 1] = ('%s:%s'):format(job.name, job.grade or 0)
        else
            parts[#parts + 1] = tostring(job)
        end
    end
    return table.concat(parts, ', ')
end

local function decodeCoords(value)
    local ok, coords = pcall(json.decode, value)
    if not ok or type(coords) ~= 'table' then return nil end
    coords.x, coords.y, coords.z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    coords.heading = tonumber(coords.heading) or 0.0
    if not coords.x or not coords.y or not coords.z then return nil end
    return coords
end

local function getInventory()
    if Config.Inventory == 'ox' then
        return GetResourceState(Config.OxInventoryResource) == 'started' and 'ox' or nil
    end

    if Config.Inventory == 'qs' then
        return GetResourceState(Config.QSInventoryResource) == 'started' and 'qs' or nil
    end

    if GetResourceState(Config.OxInventoryResource) == 'started' then
        return 'ox'
    end

    if GetResourceState(Config.QSInventoryResource) == 'started' then
        return 'qs'
    end

    return nil
end

RegisterNetEvent('dc_stash:notify', function(notificationType, msg)
    local ok = type(Config.Notify) == 'function' and pcall(Config.Notify, notificationType, msg)
    if not ok then ESX.ShowNotification(msg) end
end)

RegisterNetEvent('dc_stash:clientOpen', function(stash)
    local inventory = getInventory()
    local row = type(stash) == 'table' and stash or { stash_name = stash }
    local stashName = row.stash_name
    if not stashName then return end

    if inventory == 'ox' then
        if row.personalKey then
            exports.ox_inventory:openInventory('stash', { id = stashName, owner = row.personalKey })
        else
            exports.ox_inventory:openInventory('stash', stashName)
        end
    elseif inventory == 'qs' then
        local qsStashId = row.qsStashId
        if not qsStashId then return ESX.ShowNotification('Identifiant du coffre QS manquant.') end
        TriggerServerEvent('inventory:server:OpenInventory', 'stash', qsStashId)
        TriggerEvent('inventory:client:SetCurrentStash', qsStashId)
    else
        ESX.ShowNotification('Aucun inventaire compatible n’est démarré.')
    end
end)

RegisterNetEvent('dc_stash:teleportApproved', function(coords)
    if type(coords) ~= 'table' then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, false)
end)

local function removeAllZones()
    for i = 1, #Zones do
        local name = Zones[i]
        pcall(function()
            exports.ox_target:removeZone(name)
        end)
    end
    Zones = {}
end

local function addZone(row)
    local c = decodeCoords(row.coords)
    if not c or not row.stash_name then return end
    local zoneName = ('dc_stash_%s'):format(row.stash_name)

    exports.ox_target:addBoxZone({
        name = zoneName,
        coords = vec3(c.x, c.y, c.z),
        size = vec3(Config.Target.width, Config.Target.length, (Config.Target.maxZ - Config.Target.minZ)),
        rotation = c.heading or 0.0,
        debug = false,
        options = {
            {
                label = row.label,
                icon = 'fa-solid fa-box-open',
                distance = row.distance or Config.DefaultDistance,
                onSelect = function()
                    TriggerServerEvent('dc_stash:open', row.stash_name)
                end
            }
        }
    })

    Zones[#Zones + 1] = zoneName
end

RegisterNetEvent('dc_stash:sync', function(rows)
    removeAllZones()
    rows = type(rows) == 'table' and rows or {}

    for _, r in ipairs(rows) do
        addZone(r)
    end
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('dc_stash:requestSync')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then removeAllZones() end
end)

-- Admin command: ox_lib menu / dialog
local function openCreateDialog()
    local input = exports.ox_lib:inputDialog('Créer un stash', {
        { type = 'input', label = 'Nom du stash (unique)', description = 'ex: lspd_armoury_1', required = true },
        { type = 'input', label = 'Label affiché', description = 'ex: Armurerie LSPD', required = false },
        { type = 'number', label = 'Slots', default = Config.DefaultSlots, required = true, min = 1, max = 500 },
        { type = 'number', label = 'Poids max (grammes)', default = Config.DefaultWeight, required = true, min = 1000, max = 5000000 },
        { type = 'select', label = 'Accès', required = true, options = {
            { label = 'Ouvert à tous', value = 'public' },
            { label = 'Bloqué à un ou plusieurs jobs', value = 'job' },
            { label = 'Personnel (un contenu par joueur)', value = 'personal' },
        }, default = 'public' },
        { type = 'multi-select', label = 'Jobs autorisés', description = 'Sélectionnez un ou plusieurs jobs', options = JobOptions, required = false },
        { type = 'input', label = 'Grades personnalisés (optionnel)', description = 'ex: police:2, ambulance:0', required = false },
        { type = 'number', label = 'Grade par défaut', description = 'Appliqué aux jobs sans grade personnalisé', default = 0, required = false, min = 0, max = 50 },
        { type = 'number', label = 'Distance interaction', default = Config.DefaultDistance, required = true, min = 1.0, max = 10.0 },
    })

    if not input then return end

    local name = input[1]
    local label = input[2] or ''
    local slots = tonumber(input[3]) or Config.DefaultSlots
    local weight = tonumber(input[4]) or Config.DefaultWeight
    local access_type = input[5] or 'public'
    local jobs = input[6] or {}
    local jobRules = input[7] or ''
    local min_grade = tonumber(input[8]) or 0
    local distance = tonumber(input[9]) or Config.DefaultDistance

    if access_type == 'job' and #jobs == 0 and jobRules:match('^%s*$') then
        ESX.ShowNotification('Tu dois renseigner le job.')
        return
    end

    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)

    TriggerServerEvent('dc_stash:create', {
        name = name,
        label = label,
        slots = slots,
        weight = weight,
        access_type = access_type,
        jobs = jobs,
        jobRules = jobRules,
        min_grade = min_grade,
        distance = distance,
        coords = { x = p.x, y = p.y, z = p.z, heading = h }
    })
end

local function openStashEdit(stash)
    local input = exports.ox_lib:inputDialog(('Modifier le coffre : %s'):format(stash.stash_name), {
        { type = 'input', label = 'Label affiché', default = stash.label, required = true },
        { type = 'number', label = 'Slots', default = tonumber(stash.slots), required = true, min = 1, max = 500 },
        { type = 'number', label = 'Poids max (grammes)', default = tonumber(stash.weight), required = true, min = 1000, max = 5000000 },
        { type = 'select', label = 'Accès', default = stash.access_type, required = true, options = {
            { label = 'Ouvert à tous', value = 'public' },
            { label = 'Bloqué à un ou plusieurs jobs', value = 'job' },
            { label = 'Personnel (un contenu par joueur)', value = 'personal' },
        } },
        { type = 'multi-select', label = 'Jobs autorisés', description = 'Sélectionnez un ou plusieurs jobs', options = JobOptions, required = false },
        { type = 'input', label = 'Grades personnalisés (optionnel)', description = 'ex: police:2, ambulance:0', default = jobsToText(stash.job), required = false },
        { type = 'number', label = 'Grade par défaut', description = 'Appliqué aux jobs sans grade personnalisé', default = tonumber(stash.min_grade) or 0, required = false, min = 0, max = 50 },
        { type = 'number', label = 'Distance interaction', default = tonumber(stash.distance) or Config.DefaultDistance, required = true, min = 1.0, max = 10.0 },
        { type = 'checkbox', label = 'Déplacer le coffre à ma position actuelle', checked = false },
    })

    if not input then return end
    local jobs = input[5] or {}
    local jobRules = input[6] or ''
    if input[4] == 'job' and #jobs == 0 and jobRules:match('^%s*$') then
        ESX.ShowNotification('Tu dois renseigner le job.')
        return
    end

    local coords = nil
    if input[9] then
        local ped = PlayerPedId()
        local p = GetEntityCoords(ped)
        coords = { x = p.x, y = p.y, z = p.z, heading = GetEntityHeading(ped) }
    end

    TriggerServerEvent('dc_stash:update', stash.stash_name, {
        label = input[1], slots = input[2], weight = input[3], access_type = input[4],
        jobs = jobs, jobRules = jobRules, min_grade = input[7], distance = input[8], coords = coords
    })
end

local function openStashActions(stash)
    lib.registerContext({
        id = 'dc_stash_actions', title = stash.label, menu = 'dc_stash_manage', options = {
            { title = 'Modifier', description = 'Modifier les paramètres ou déplacer le coffre', icon = 'pen-to-square', onSelect = function() openStashEdit(stash) end },
            { title = 'Téléporter', description = 'Se téléporter au coffre', icon = 'location-arrow', onSelect = function()
                TriggerServerEvent('dc_stash:teleport', stash.stash_name)
            end },
            { title = 'Supprimer', description = 'Supprimer définitivement le coffre', icon = 'trash', iconColor = 'red', onSelect = function()
                local alert = lib.alertDialog({ header = 'Confirmation', content = ('Supprimer définitivement le coffre "%s" ? Son contenu d’inventaire ne sera pas supprimé automatiquement.'):format(stash.label), centered = true, cancel = true })
                if alert == 'confirm' then TriggerServerEvent('dc_stash:delete', stash.stash_name) end
            end }
        }
    })
    lib.showContext('dc_stash_actions')
end

local function openStashManage(stashes)
    local options = {}
    for _, stash in ipairs(stashes or {}) do
        local c = decodeCoords(stash.coords)
        if c then
        local access = stash.access_type == 'job' and ('Jobs : %s'):format(jobsToText(stash.job)) or (stash.access_type == 'personal' and 'Personnel (un contenu par joueur)' or 'Public')
        options[#options + 1] = {
            title = stash.label, description = ('%s | Pos : %.2f, %.2f, %.2f'):format(access, c.x, c.y, c.z), icon = 'box-open',
            metadata = { { label = 'Nom technique', value = stash.stash_name }, { label = 'Slots', value = stash.slots }, { label = 'Poids', value = stash.weight } },
            onSelect = function() openStashActions(stash) end
        }
        end
    end
    if #options == 0 then options[1] = { title = 'Aucun coffre créé', description = ('Utilisez /%s pour en créer un.'):format(Config.Commands.create), icon = 'circle-info', disabled = true } end
    lib.registerContext({ id = 'dc_stash_manage', title = 'Gestion des coffres', options = options })
    lib.showContext('dc_stash_manage')
end

RegisterCommand(Config.Commands.create, function()
    ESX.TriggerServerCallback('dc_stash:getJobs', function(jobs)
        if type(jobs) ~= 'table' then return ESX.ShowNotification('Accès admin requis.') end
        JobOptions = jobs
        openCreateDialog()
    end)
end, false)

RegisterCommand(Config.Commands.manage, function()
    ESX.TriggerServerCallback('dc_stash:getAdminStashes', function(stashes)
        if type(stashes) ~= 'table' then return ESX.ShowNotification('Accès admin requis.') end
        openStashManage(stashes)
    end)
end, false)
