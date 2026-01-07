--!strict
local DataStoreService = game:GetService("DataStoreService")
local Budget = require(script.Parent.BudgetManager)
local Config = require(script.Parent.Config)
local Logger = require(script.Parent.Logger)

local PersistenceHandler = {}

function PersistenceHandler.Get(storeName: string, scope: string, key: string)
    local store = DataStoreService:GetDataStore(storeName, scope)
    Budget.WaitForBudget(Enum.DataStoreRequestType.GetAsync)
    
    local success, result, info = pcall(function()
        return store:GetAsync(key)
    end)
    
    return success, result, info
end

function PersistenceHandler.Set(storeName: string, scope: string, key: string, data: any, userIds: {number}, isReleasing: boolean)
    local store = DataStoreService:GetDataStore(storeName, scope)
    local options = Instance.new("DataStoreSetOptions")
    
    options:SetMetadata({
        [Config.METADATA_KEY] = isReleasing and "" or game.JobId
    })

    Budget.WaitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
    
    return pcall(function()
        return store:SetAsync(key, data, userIds, options)
    end)
end

return PersistenceHandler
