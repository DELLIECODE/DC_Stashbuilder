local ESX = exports.es_extended:getSharedObject()
local requestTimes = {}
local limits = Config.Limits or {}

local function clamp(value, fallback, minimum, maximum, integer)
    local number = tonumber(value) or fallback
    if number ~= number or number == math.huge or number == -math.huge then number = fallback end
    number = math.max(minimum, math.min(maximum, number))
    return integer and math.floor(number) or number
end

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function cleanName(value)
    local name = trim(value):lower():gsub('%s+', '_'):gsub('[^%w_-]', '_'):gsub('_+', '_')
    name = name:sub(1, 64):gsub('^_+', ''):gsub('_+$', '')
    return name ~= '' and name or nil
end

local function cleanLabel(value, fallback)
    local label = trim(value):gsub('[%c]', '')
    if label == '' then label = tostring(fallback or 'Coffre') end
    return label:sub(1, 64)
end

local function normalizeCoords(value)
    if type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    local heading = tonumber(value.heading) or 0.0
    for _, number in ipairs({ x, y, z, heading }) do
        if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then return nil end
    return { x = x, y = y, z = z, heading = heading % 360.0 }
end

local function decodeCoords(value)
    local ok, decoded = pcall(json.decode, value)
    return ok and normalizeCoords(decoded) or nil
end

local function notify(src, notificationType, message)
    TriggerClientEvent('dc_stash:notify', src, notificationType, message)
end

local function isRateLimited(src, action, delay)
    local now = GetGameTimer()
    requestTimes[src] = requestTimes[src] or {}
    local previous = requestTimes[src][action]
    if previous and now >= previous and now - previous < delay then return true end
    requestTimes[src][action] = now
    return false
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

local function isAdmin(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    return Config.AllowedGroups[xPlayer.getGroup()] == true
end

local function playerIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if xPlayer then
        if type(xPlayer.getIdentifier) == 'function' then return tostring(xPlayer.getIdentifier()) end
        if xPlayer.identifier then return tostring(xPlayer.identifier) end
    end
    local license = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license')
    return tostring(license or src)
end

local function jobRules(value, defaultGrade)
    local rules, seen = {}, {}
    local function add(name, grade)
        name = cleanName(name)
        if name and not seen[name] and #rules < (limits.maxJobs or 20) then
            rules[#rules + 1] = { name = name, grade = clamp(grade, defaultGrade or 0, 0, limits.maxGrade or 50, true) }
            seen[name] = true
        end
    end
    if type(value) == 'table' then
        for _, rule in ipairs(value) do
            if type(rule) == 'table' then add(rule.name, rule.grade) else add(rule, defaultGrade) end
        end
    elseif type(value) == 'string' then
        local ok, decoded = pcall(json.decode, value)
        if ok and type(decoded) == 'table' then return jobRules(decoded, defaultGrade) end
        for rule in value:gmatch('[^,]+') do
            local name, grade = rule:match('^%s*(.-)%s*:%s*(%d+)%s*$')
            add(name or rule, grade or defaultGrade)
        end
    end
    return rules
end

local function mergedJobRules(jobs, customRules, defaultGrade)
    local rules = jobRules(jobs, defaultGrade)
    local index = {}
    for i, rule in ipairs(rules) do index[rule.name] = i end
    for _, custom in ipairs(jobRules(customRules, defaultGrade)) do
        if index[custom.name] then
            rules[index[custom.name]].grade = custom.grade
        elseif #rules < (limits.maxJobs or 20) then
            rules[#rules + 1] = custom
            index[custom.name] = #rules
        end
    end
    return rules
end

local function canOpenStash(src, row)
    if row.access_type == 'public' then return true end

    if row.access_type == 'job' then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end

        local jobName = xPlayer.job and xPlayer.job.name or nil
        local grade = xPlayer.job and xPlayer.job.grade or 0

        for _, rule in ipairs(jobRules(row.job, row.min_grade)) do
            if jobName == rule.name and grade >= rule.grade then return true end
        end
        return false
    end

    if row.access_type == 'personal' then return true end

    return false
end

local function isNearStash(src, row)
    local coords = decodeCoords(row.coords)
    if not coords then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then return false end
    local playerCoords = GetEntityCoords(ped)
    local maximumDistance = clamp(row.distance, Config.DefaultDistance, limits.minDistance or 1.0, limits.maxDistance or 10.0, false)
        + clamp(Config.ServerDistanceTolerance, 1.0, 0.0, 5.0, false)
    local dx, dy, dz = playerCoords.x - coords.x, playerCoords.y - coords.y, playerCoords.z - coords.z
    return (dx * dx + dy * dy + dz * dz) <= maximumDistance * maximumDistance
end

local function registerStash(row)
    local inventory = getInventory()
    if inventory == 'qs' then return true end
    if inventory ~= 'ox' then
        print('[dc_stash] Aucun inventaire compatible n’est démarré.')
        return false
    end

    local coords = decodeCoords(row.coords)
    if not coords then
        print(('[dc_stash] Coordonnées invalides pour le coffre "%s".'):format(row.stash_name or 'unknown'))
        return false
    end
    local groups = nil
    local owner = row.access_type == 'personal'
    local label = cleanLabel(row.label, row.stash_name)
    local slots = clamp(row.slots, Config.DefaultSlots, limits.minSlots or 1, limits.maxSlots or 500, true)
    local weight = clamp(row.weight, Config.DefaultWeight, limits.minWeight or 1000, limits.maxWeight or 5000000, true)

    if row.access_type == 'job' and row.job and row.job ~= '' then
        groups = {}
        for _, rule in ipairs(jobRules(row.job, row.min_grade)) do groups[rule.name] = rule.grade end
    end

    local ok, err = pcall(function()
        exports.ox_inventory:RegisterStash(row.stash_name, label, slots, weight, owner, groups, coords)
    end)
    if not ok then
        print(('[dc_stash] Impossible d’enregistrer le coffre ox_inventory "%s": %s'):format(row.stash_name, err))
    end
    return ok
end

local function registerQSStash(src, row)
    if getInventory() ~= 'qs' then return false end
    local prefix = tostring(Config.QSStashPrefix or 'Stash_')
    local baseId = row.personalKey or row.stash_name
    local rawId = tostring(baseId)
    local stashId = rawId:sub(1, #prefix) == prefix and rawId or (prefix .. rawId)
    local slots = clamp(row.slots, Config.DefaultSlots, limits.minSlots or 1, limits.maxSlots or 500, true)
    local weight = clamp(row.weight, Config.DefaultWeight, limits.minWeight or 1000, limits.maxWeight or 5000000, true)
    local ok, response = pcall(function()
        return exports[Config.QSInventoryResource]:RegisterStash(src, stashId, slots, weight)
    end)
    if not ok or response == false then
        print(('[dc_stash] Impossible d’enregistrer le coffre QS "%s": %s'):format(row.stash_name, response or 'unknown'))
        return false
    end
    row.qsStashId = stashId
    return true
end

local function fetchAll()
    local ok, rows = pcall(function() return MySQL.query.await('SELECT * FROM dc_stashes', {}) end)
    if not ok then
        print(('[dc_stash] Lecture SQL impossible : %s'):format(rows or 'unknown'))
        return {}
    end
    return rows or {}
end

local function publicRows(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do
        result[#result + 1] = {
            stash_name = row.stash_name,
            label = row.label,
            coords = row.coords,
            distance = row.distance
        }
    end
    return result
end

local function broadcastAll()
    TriggerClientEvent('dc_stash:sync', -1, publicRows(fetchAll()))
end

ESX.RegisterServerCallback('dc_stash:getJobs', function(source, cb)
    if not isAdmin(source) then return cb(false) end
    local options = {}
    for name, job in pairs(ESX.GetJobs() or {}) do
        options[#options + 1] = { value = name, label = job.label or name }
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    cb(options)
end)

ESX.RegisterServerCallback('dc_stash:getAdminStashes', function(source, cb)
    if not isAdmin(source) then return cb(false) end
    if isRateLimited(source, 'adminStashes', 500) then return cb(false) end
    cb(fetchAll())
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() and res ~= Config.OxInventoryResource and res ~= Config.QSInventoryResource then return end
    Wait(500)

    local rows = fetchAll()
    if getInventory() == 'ox' then
        for _, r in ipairs(rows) do
            registerStash(r)
        end
    elseif not getInventory() then
        print('[dc_stash] Aucun inventaire compatible n’est démarré. Les coffres seront enregistrés dès son démarrage.')
    end

    TriggerClientEvent('dc_stash:sync', -1, publicRows(rows))
end)

RegisterNetEvent('dc_stash:requestSync', function()
    local src = source
    if isRateLimited(src, 'sync', 1000) then return end
    TriggerClientEvent('dc_stash:sync', src, publicRows(fetchAll()))
end)

AddEventHandler('playerDropped', function()
    requestTimes[source] = nil
end)

RegisterNetEvent('dc_stash:create', function(data)
    local src = source
    if not isAdmin(src) then
        notify(src, 'error', 'Accès admin requis')
        return
    end
    if isRateLimited(src, 'create', 1000) then return end

    if not data or type(data) ~= 'table' then return end
    local name = cleanName(data.name)
    local coords = normalizeCoords(data.coords)
    if not name or not coords then return notify(src, 'error', 'Nom ou coordonnées invalides.') end

    local label = cleanLabel(data.label, name)
    local slots = clamp(data.slots, Config.DefaultSlots, limits.minSlots or 1, limits.maxSlots or 500, true)
    local weight = clamp(data.weight, Config.DefaultWeight, limits.minWeight or 1000, limits.maxWeight or 5000000, true)
    local distance = clamp(data.distance, Config.DefaultDistance, limits.minDistance or 1.0, limits.maxDistance or 10.0, false)

    local access_type = data.access_type == 'job' and 'job' or (data.access_type == 'personal' and 'personal' or 'public')
    local rules = mergedJobRules(data.jobs or data.job, data.jobRules, data.min_grade)
    local job = access_type == 'job' and json.encode(rules) or nil
    local min_grade = clamp(data.min_grade, 0, 0, limits.maxGrade or 50, true)

    if access_type == 'job' and #rules == 0 then
        notify(src, 'error', 'Tu dois renseigner le job pour un stash réservé aux métiers.')
        return
    end

    local createdBy = playerIdentifier(src):sub(1, 64)

    local ok, result = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO dc_stashes
            (stash_name, label, slots, weight, coords, distance, access_type, job, min_grade, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            name,
            label,
            slots,
            weight,
            json.encode(coords),
            distance,
            access_type,
            job,
            min_grade,
            createdBy
        })

    end)

    if not ok or not result then
        print(('[dc_stash] Création SQL impossible pour "%s": %s'):format(name, result or 'unknown'))
        notify(src, 'error', 'Impossible de créer ce coffre. Vérifiez que son nom est unique.')
        return
    end

    local row = MySQL.single.await('SELECT * FROM dc_stashes WHERE stash_name = ?', { name })
    if row then registerStash(row) end

    notify(src, 'success', ('Coffre créé : %s'):format(label))
    broadcastAll()
end)

RegisterNetEvent('dc_stash:open', function(stashName)
    local src = source
    if isRateLimited(src, 'open', 400) then return end
    if type(stashName) ~= 'string' or #stashName < 1 or #stashName > 64 then return end

    local row = MySQL.single.await('SELECT * FROM dc_stashes WHERE stash_name = ?', { stashName })
    if not row then return end

    if not canOpenStash(src, row) then
        notify(src, 'error', 'Accès refusé')
        return
    end

    if not isNearStash(src, row) then
        notify(src, 'error', 'Vous êtes trop loin de ce coffre.')
        return
    end

    if row.access_type == 'personal' then
        row.personalKey = ('%s:%s'):format(row.stash_name, playerIdentifier(src))
    end

    local inventory = getInventory()
    if not inventory then return notify(src, 'error', 'Aucun inventaire compatible n’est démarré.') end
    if inventory == 'qs' and not registerQSStash(src, row) then
        return notify(src, 'error', 'Impossible d’enregistrer ce coffre dans qs-inventory.')
    end
    TriggerClientEvent('dc_stash:clientOpen', src, row)
end)

RegisterNetEvent('dc_stash:update', function(stashName, data)
    local src = source
    if not isAdmin(src) then return notify(src, 'error', 'Accès admin requis') end
    if isRateLimited(src, 'update', 750) then return end
    if type(stashName) ~= 'string' or #stashName < 1 or #stashName > 64 then return end
    local row = MySQL.single.await('SELECT * FROM dc_stashes WHERE stash_name = ?', { stashName })
    if not row or type(data) ~= 'table' then return end

    local accessType = data.access_type == 'job' and 'job' or (data.access_type == 'personal' and 'personal' or 'public')
    local rules = mergedJobRules(data.jobs or data.job, data.jobRules, data.min_grade)
    local job = accessType == 'job' and json.encode(rules) or nil
    if accessType == 'job' and #rules == 0 then return notify(src, 'error', 'Tu dois renseigner au moins un métier.') end
    local normalizedCoords = data.coords and normalizeCoords(data.coords) or decodeCoords(row.coords)
    if not normalizedCoords then return notify(src, 'error', 'Coordonnées invalides.') end
    local label = cleanLabel(data.label, row.label)
    local slots = clamp(data.slots, row.slots, limits.minSlots or 1, limits.maxSlots or 500, true)
    local weight = clamp(data.weight, row.weight, limits.minWeight or 1000, limits.maxWeight or 5000000, true)
    local distance = clamp(data.distance, row.distance, limits.minDistance or 1.0, limits.maxDistance or 10.0, false)
    local minGrade = clamp(data.min_grade, row.min_grade or 0, 0, limits.maxGrade or 50, true)

    local ok, affected = pcall(function()
        return MySQL.update.await([[UPDATE dc_stashes SET label = ?, slots = ?, weight = ?, coords = ?, distance = ?, access_type = ?, job = ?, min_grade = ? WHERE stash_name = ?]], {
            label, slots, weight, json.encode(normalizedCoords), distance, accessType, job, minGrade, stashName
        })
    end)
    if not ok then
        print(('[dc_stash] Mise à jour SQL impossible pour "%s": %s'):format(stashName, affected or 'unknown'))
        return notify(src, 'error', 'Impossible de modifier ce coffre.')
    end
    local updated = MySQL.single.await('SELECT * FROM dc_stashes WHERE stash_name = ?', { stashName })
    if updated then registerStash(updated) end
    notify(src, 'success', ('Coffre modifié : %s'):format(stashName))
    broadcastAll()
end)

RegisterNetEvent('dc_stash:teleport', function(stashName)
    local src = source
    if not isAdmin(src) or isRateLimited(src, 'teleport', 1000) then return end
    if type(stashName) ~= 'string' or #stashName < 1 or #stashName > 64 then return end
    local row = MySQL.single.await('SELECT coords FROM dc_stashes WHERE stash_name = ?', { stashName })
    local coords = row and decodeCoords(row.coords) or nil
    if not coords then return notify(src, 'error', 'Téléportation impossible.') end
    TriggerClientEvent('dc_stash:teleportApproved', src, coords)
end)

RegisterNetEvent('dc_stash:delete', function(stashName)
    local src = source
    if not isAdmin(src) then return notify(src, 'error', 'Accès admin requis') end
    if isRateLimited(src, 'delete', 750) then return end
    if type(stashName) ~= 'string' or #stashName < 1 or #stashName > 64 then return end
    local affected = MySQL.update.await('DELETE FROM dc_stashes WHERE stash_name = ?', { stashName })
    if not affected or affected < 1 then return notify(src, 'error', 'Coffre introuvable') end
    notify(src, 'success', ('Coffre supprimé : %s'):format(stashName))
    broadcastAll()
end)
