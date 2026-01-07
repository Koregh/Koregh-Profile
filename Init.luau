--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Importação dos Especialistas
local Config = require(script.Config)
local Logger = require(script.Logger)
local Budget = require(script.BudgetManager)
local Persistence = require(script.PersistenceHandler)
local Session = require(script.SessionManager)
local Processor = require(script.DataProcessor)
local Reconciler = require(script.DataReconciler)
local Signal = require(script.Signal) -- O novo módulo que você criou

local DataSession = {}
DataSession.__index = DataSession

-- Conecta o scheduler de performance de forma limpa
RunService.Stepped:Connect(Budget.Step)

-- [CONSTRUTOR]
function DataSession.new(id: string | number)
    Logger.Info("Iniciando nova sessão: " .. id)
    
    local self = setmetatable({
        SessionID = tostring(id),
        Status = "Idle",
        
        Cache = {},
        _userIds = {},
        _connections = {},
        _storeName = "MainStore",
        
        -- Eventos Estilo ProfileStore
        OnSave = Signal.new(),
        OnLoad = Signal.new(),
        OnError = Signal.new()
    }, DataSession)

    -- Escuta pedidos de liberação (Anti-Dupe/Session Locking)
    table.insert(self._connections, Session.Listen(self.SessionID, function(message)
        if message.Type == "RequestRelease" and (message.TargetJobId == game.JobId or message.TargetJobId == "Any") then
            Logger.Warn("Solicitação de liberação externa para: " .. message.Key, "Session")
            self:Release(message.Key)
        end
    end))

    return self
end

-- [MÉTODO LOAD] - Agora com Retry e Session Locking
function DataSession:Load(key: string, template: {[any]: any}, userIds: {number}?)
    self.Status = "Loading"
    self._userIds = userIds or {}
    
    local attempts = 0
    local maxAttempts = 5
    local finalData = nil

    repeat
        attempts += 1
        
        -- Tentativa atômica de carregar e travar a sessão (UpdateSafe)
        local success, result = Persistence.UpdateSafe(
            self._storeName,
            self.SessionID,
            key,
            function(oldData)
                -- Se não existe, usa template; se existe, o Reconciler limpa
                return Reconciler.Reconcile(oldData or {}, template)
            end,
            self._userIds,
            false -- isReleasing = false (estamos ocupando)
        )

        if success and result then
            finalData = result
            break
        else
            -- Se falhou ou o Lock estava com outro JobId, avisamos o outro servidor
            Session.Broadcast(self.SessionID, {
                Type = "RequestRelease", 
                Key = key, 
                TargetJobId = "Any"
            })
            Logger.Warn(`Sessão {key} ocupada. Tentativa {attempts}/{maxAttempts}...`, "Init")
            task.wait(6) -- Tempo de espera entre retentativas (igual ao ProfileStore)
        end
    until attempts >= maxAttempts

    if not finalData then
        self.OnError:Fire("LoadError", "Session Lock Conflict or DataStore Failure")
        Logger.Critical("Não foi possível assumir a sessão para: " .. key, "Init")
        return nil
    end

    self.Cache[key] = finalData
    self.Status = "Active"
    self.OnLoad:Fire(finalData)
    
    Logger.Info("Dados carregados com sucesso para: " .. key)
    return finalData
end

-- [MÉTODO SAVE] - Agora Atômico e Seguro
function DataSession:Save(key: string, isReleasing: boolean?)
    if self.Status == "Loading" or self.Status == "Idle" then return end
    local data = self.Cache[key]
    if not data then return end

    local previousStatus = self.Status
    self.Status = isReleasing and "Releasing" or "Saving"

    -- Usa UpdateSafe para garantir que não sobrescrevemos um Lock alheio
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
        Logger.Critical("Erro ao salvar " .. key, "Init")
    end

    self.Status = previousStatus
end

-- [MÉTODOS DE MANIPULAÇÃO]
function DataSession:Edit(key: string, path: string, value: any)
    if self.Status ~= "Active" or not self.Cache[key] then return end
    Processor.Modify(self.Cache[key], path, value, "Set")
    self:Replicate(path, value)
end

function DataSession:Add(key: string, path: string, amount: number)
    if self.Status ~= "Active" or not self.Cache[key] then return end
    local newValue = Processor.Modify(self.Cache[key], path, amount, "Add")
    self:Replicate(path, newValue)
end

-- [REPLICAÇÃO]
function DataSession:Replicate(path: string, value: any)
    for _, userId in ipairs(self._userIds) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            -- Network:FireClient(player, "UpdateData", path, value)
        end
    end
end

-- [MÉTODO RELEASE]
function DataSession:Release(key: string)
    self:Save(key, true)
    
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    table.clear(self._connections)
    
    self.Cache[key] = nil
    self.Status = "Idle"
    Logger.Info("Sessão encerrada com segurança: " .. key)
end

return DataSession

