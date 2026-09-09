Config = {}
local ESX = exports['es_extended']:getSharedObject()

-- ESX groups allowed to CREATE/DELETE stashes
Config.AllowedGroups = {
    admin = true,
    superadmin = true
}

Config.DefaultSlots = 50
Config.DefaultWeight = 100000
Config.DefaultDistance = 2.0

-- Server-side limits. These values are enforced even if a client bypasses the UI.
Config.Limits = {
    minSlots = 1,
    maxSlots = 500,
    minWeight = 1000,
    maxWeight = 5000000,
    minDistance = 1.0,
    maxDistance = 10.0,
    maxGrade = 50,
    maxJobs = 20
}

-- Extra margin added to the interaction distance for the server proximity check.
Config.ServerDistanceTolerance = 1.0

-- Inventory backend: 'auto', 'ox' or 'qs'.
-- In auto mode, ox_inventory is preferred when both inventories are running.
Config.Inventory = 'auto'
Config.OxInventoryResource = 'ox_inventory'
Config.QSInventoryResource = 'qs-inventory'
Config.QSStashPrefix = 'Stash_'

Config.Commands = {
    create = 'stashcreate',
    manage = 'managestash'
}

Config.Target = {
  width = 1.2,
  length = 1.2,
  minZ = -0.9,
  maxZ = 0.9
}

-- notifications (ESX)
Config.Notify = function(_, msg)
  ESX.ShowNotification(msg)
end
