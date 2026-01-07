--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService") -- Adicionado para WipeData

-- Importação dos Módulos
local Config = require(script.Config)
local Logger = require(script.Logger)
local Budget = require(script.BudgetManager)
local Persistence = require(script.PersistenceHandler)
local Session = require(script.SessionManager)
local Processor = require(script.DataProcessor)
local Reconciler = require(script.DataReconciler)
local Signal = require(script.Signal) 
local AutoSaver = require(script.AutoSaver)

local DataSession = {}
DataSession.__index = DataSession

RunService.Stepped:Connect(Budget.Step)
AutoSaver.Start()

function DataSession.new(id: string | number)
    Logger.Info("Criando nova sessão: " .. id)
    
    local self = setmetatable({
        SessionID = tostring(id),
        Status = "Idle",
        Cache = {},
        _userIds = {},
        _connections = {},
        _storeName = "MainStore",
        
        OnSave = Signal.new(),
        OnLoad = Signal.new(),
        OnError = Signal.new()
    }, DataSession)

    table.insert(self._connections, Session.Listen(self.SessionID, function(message)
        if message.Type == "RequestRelease" and (message.TargetJobId == game.JobId or message.TargetJobId == "Any") then
            Logger.Warn("Solicitação de liberação externa para: " .. message.Key, "Session")
            self:Release(message.Key)
        end
    end))

    return self
end

function DataSession:Load(key: string, template: {[any]: any}, userIds: {number}?)
    self.Status = "Loading"
    self._userIds = userIds or {}
    
    local attempts = 0
    local maxAttempts = 5
    local finalData = nil

    repeat
        attempts += 1
        
        local success, result = Persistence.UpdateSafe(
            self._storeName,
            self.SessionID,
            key,
            function(oldData)
                return Reconciler.Reconcile(oldData or {}, template)
            end,
            self._userIds,
            false 
        )

        if success and result then
            finalData = result
            break
        else
            Session.Broadcast(self.SessionID, {
                Type = "RequestRelease", 
                Key = key, 
                TargetJobId = "Any"
            })
            Logger.Warn(`Tentativa {attempts}/{maxAttempts}: Sessão {key} ocupada.`, "Init")
            task.wait(6) 
        end
    until attempts >= maxAttempts

    if not finalData then
        self.OnError:Fire("LoadError", "Conflito de Session Lock ou falha no DataStore")
        return nil
    end

    self.Cache[key] = finalData
    self.Status = "Active"
    
    AutoSaver.RegisterSession(self, key)
    self.OnLoad:Fire(finalData)
    return finalData
end

function DataSession:Save(key: string, isReleasing: boolean?)
    if self.Status == "Idle" then return end
    local data = self.Cache[key]
    if not data then return end

    local previousStatus = self.Status
    self.Status = isReleasing and "Releasing" or "Saving"

    local success, result = Persistence.UpdateSafe(
        self._storeName,
        self.SessionID,
        key,
        function(_) return data end,
        self._userIds,
        isReleasing or false
    )

    if success then
        self.OnSave:Fire(data)
        if isReleasing then
            Session.Broadcast(self.SessionID, {Type = "Released", Key = key, Data = data})
        end
    else
        self.OnError:Fire("SaveError", result)
        Logger.Critical("Erro ao salvar: " .. tostring(result))
    end

    if not isReleasing then
        self.Status = previousStatus
    end
end

-- GDPR: DIREITO DE SER ESQUECIDO --
-- Este método apaga os dados permanentemente do DataStore
function DataSession:WipeData(key: string)
    Logger.Warn("Iniciando remoção permanente de dados (GDPR): " .. key)
    
    local success, err = pcall(function()
        local store = DataStoreService:GetDataStore(self._storeName)
        store:RemoveAsync(key)
    end)
    
    if success then
        Logger.Info("Dados apagados com sucesso para a chave: " .. key)
    else
        Logger.Critical("Falha ao apagar dados (GDPR): " .. tostring(err))
    end
    return success
end

function DataSession:Edit(key: string, path: string, value: any)
    if self.Status ~= "Active" or not self.Cache[key] then return end
    Processor.Modify(self.Cache[key], path, value, "Set")
end

function DataSession:Add(key: string, path: string, amount: number)
    if self.Status ~= "Active" or not self.Cache[key] then return end
    Processor.Modify(self.Cache[key], path, amount, "Add")
end

function DataSession:Release(key: string)
    if self.Status == "Idle" or self.Status == "Releasing" then return end
    
    Logger.Info("Liberando sessão: " .. key)
    AutoSaver.UnregisterSession(key)
    
    -- Realiza o último salvamento com a flag isReleasing = true
    self:Save(key, true)
    
    -- Limpa conexões após o salvamento
    for _, conn in ipairs(self._connections) do
        if typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        elseif typeof(conn) == "table" and conn.Disconnect then
            conn:Disconnect()
        end
    end
    table.clear(self._connections)
    
    self.Cache[key] = nil
    self.Status = "Idle"
    Logger.Info("Sessão finalizada: " .. key)
end

return DataSession

