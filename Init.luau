--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Importação dos Especialistas (Módulos que você criou)
local Config = require(script.Config)
local Logger = require(script.Logger)
local Budget = require(script.BudgetManager)
local Persistence = require(script.PersistenceHandler)
local Session = require(script.SessionManager)
local Processor = require(script.DataProcessor)
local Reconciler = require(script.DataReconciler)

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
        _connections = {}
    }, DataSession)

    -- Escuta pedidos de liberação (Anti-Dupe)
    table.insert(self._connections, Session.Listen(self.SessionID, function(message)
        if message.Type == "RequestRelease" and message.TargetJobId == game.JobId then
            Logger.Warn("Solicitação de liberação externa para: " .. message.Key, "Session")
            self:Release(message.Key)
        end
    end))

    return self
end

-- [MÉTODO LOAD] - Substitui a carga manual por Reconciler + Persistence
function DataSession:Load(storeName: string, key: string, template: {[any]: any}, userIds: {number}?)
    self.Status = "Loading"
    self._userIds = userIds or {}

    -- Busca via PersistenceHandler (Gerencia Pcalls e Metadados)
    local success, rawData, info = Persistence.Get(storeName, self.SessionID, key)
    
    if not success then
        Logger.Critical("Erro crítico no DataStore para a chave: " .. key, "Init")
        return nil
    end

    -- Sincroniza dados antigos com o template novo (SOLID)
    local finalData = Reconciler.Reconcile(rawData or {}, template)
    
    self.Cache[key] = finalData
    self.Status = "Active"
    
    Logger.Info("Dados carregados e sincronizados para: " .. key)
    return finalData
end

-- [MÉTODOS DE MANIPULAÇÃO] - Delega para o DataProcessor
function DataSession:Edit(key: string, path: string, value: any)
    if not self.Cache[key] then return end
    Processor.Modify(self.Cache[key], path, value, "Set")
    self:Replicate(path, value) -- Integração com seu sistema de rede
end

function DataSession:Add(key: string, path: string, amount: number)
    if not self.Cache[key] then return end
    local newValue = Processor.Modify(self.Cache[key], path, amount, "Add")
    self:Replicate(path, newValue)
end

-- [REPLICAÇÃO] - Usa sua lógica de percorrer UserIds
function DataSession:Replicate(path: string, value: any)
    for _, userId in ipairs(self._userIds) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            -- Aqui você chama seu Network v2.1
            -- Network:FireClient(player, "UpdateData", path, value)
        end
    end
end

-- [MÉTODO SAVE] - Delega para o PersistenceHandler
function DataSession:Save(key: string, isReleasing: boolean?)
    if self.Status == "Loading" then return end
    local data = self.Cache[key]
    if not data then return end

    local previousStatus = self.Status
    self.Status = isReleasing and "Releasing" or "Saving"

    -- O PersistenceHandler cuida do SetAsync e Metadados de Lock
    local success, err = Persistence.Set(
        "MainStore", -- Nome da store (pode vir de uma config)
        self.SessionID,
        key,
        data,
        self._userIds,
        isReleasing or false
    )

    if success and isReleasing then
        -- Avisa via MessagingService que o dado está livre
        Session.Broadcast(self.SessionID, {Type = "Released", Key = key, Data = data})
    elseif not success then
        Logger.Critical("Erro ao salvar " .. key .. ": " .. tostring(err), "Init")
    end

    self.Status = previousStatus
end

-- [MÉTODO RELEASE] - Limpeza de memória
function DataSession:Release(key: string)
    self:Save(key, true)
    
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    
    self.Cache[key] = nil
    self.Status = "Idle"
    Logger.Info("Sessão encerrada para: " .. key)
end

return DataSession

