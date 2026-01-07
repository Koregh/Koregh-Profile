--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Importação dos Módulos Especialistas
local Config = require(script.Config)
local Logger = require(script.Logger)
local Budget = require(script.BudgetManager)
local Persistence = require(script.PersistenceHandler)
local Session = require(script.SessionManager)
local Processor = require(script.DataProcessor)
local Reconciler = require(script.DataReconciler)
local Signal = require(script.Signal) 
local AutoSaver = require(script.AutoSaver) -- Certifica-te que este módulo existe

local DataSession = {}
DataSession.__index = DataSession

-- Inicia o scheduler de budget e o motor de Auto-Save
RunService.Stepped:Connect(Budget.Step)
AutoSaver.Start()

-- [CONSTRUTOR]
function DataSession.new(id: string | number)
    Logger.Info("Criando nova sessão: " .. id)
    
    local self = setmetatable({
        SessionID = tostring(id),
        Status = "Idle",
        
        Cache = {},
        _userIds = {},
        _connections = {},
        _storeName = "MainStore",
        
        -- Eventos (Nível ProfileStore)
        OnSave = Signal.new(),
        OnLoad = Signal.new(),
        OnError = Signal.new()
    }, DataSession)

    -- Escuta pedidos de liberação (Session Locking/Anti-Dupe)
    table.insert(self._connections, Session.Listen(self.SessionID, function(message)
        if message.Type == "RequestRelease" and (message.TargetJobId == game.JobId or message.TargetJobId == "Any") then
            Logger.Warn("Solicitação de liberação externa para: " .. message.Key, "Session")
            self:Release(message.Key)
        end
    end))

    return self
end

-- [MÉTODO LOAD] - Com Retry e Session Locking Atômico
function DataSession:Load(key: string, template: {[any]: any}, userIds: {number}?)
    self.Status = "Loading"
    self._userIds = userIds or {}
    
    local attempts = 0
    local maxAttempts = 5
    local finalData = nil

    repeat
        attempts += 1
        
        -- Tenta carregar e "trancar" a sessão usando o UpdateSafe
        local success, result = Persistence.UpdateSafe(
            self._storeName,
            self.SessionID,
            key,
            function(oldData)
                -- Reconcilia dados antigos com o novo template
                return Reconciler.Reconcile(oldData or {}, template)
            end,
            self._userIds,
            false -- isReleasing = false (estamos a ocupar)
        )

        if success and result then
            finalData = result
            break
        else
            -- Se falhar (lock ocupado), avisa o outro servidor via MessagingService
            Session.Broadcast(self.SessionID, {
                Type = "RequestRelease", 
                Key = key, 
                TargetJobId = "Any"
            })
            Logger.Warn(`Tentativa {attempts}/{maxAttempts}: Sessão {key} ocupada por outro servidor.`, "Init")
            task.wait(6) -- Delay de segurança inspirado no ProfileStore
        end
    until attempts >= maxAttempts

    if not finalData then
        self.OnError:Fire("LoadError", "Conflito de Session Lock ou falha no DataStore")
        return nil
    end

    self.Cache[key] = finalData
    self.Status = "Active"
    
    -- Registra no AutoSaver automaticamente após carregar com sucesso
    AutoSaver.RegisterSession(self, key)
    
    self.OnLoad:Fire(finalData)
    return finalData
end

-- [MÉTODO SAVE] - Atômico e resiliente
function DataSession:Save(key: string, isReleasing: boolean?)
    if self.Status == "Loading" or self.Status == "Idle" then return end
    local data = self.Cache[key]
    if not data then return end

    local previousStatus = self.Status
    self.Status = isReleasing and "Releasing" or "Saving"

    -- Salva garantindo que o Lock ainda nos pertence
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
    end

    self.Status = previousStatus
end

-- [MÉTODOS DE MANIPULAÇÃO]
function DataSession:Edit(key: string, path: string, value: any)
    if self.Status ~= "Active" or not self.Cache[key] then return end
    Processor.Modify(self.Cache[key], path, value, "Set")
    -- self:Replicate(path, value) -- Se tiveres sistema de rede integrado
end

function DataSession:Add(key: string, path: string, amount: number)
    if self.Status ~= "Active" or not self.Cache[key] then return end
    Processor.Modify(self.Cache[key], path, amount, "Add")
end

-- [MÉTODO RELEASE]
function DataSession:Release(key: string)
    if self.Status == "Idle" then return end
    
    -- Remove do AutoSaver primeiro para evitar conflitos no fecho
    AutoSaver.UnregisterSession(key)
    
    self:Save(key, true)
    
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    table.clear(self._connections)
    
    self.Cache[key] = nil
    self.Status = "Idle"
    Logger.Info("Sessão encerrada e Lock removido: " .. key)
end

return DataSession

