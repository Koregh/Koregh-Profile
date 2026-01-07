--!strict
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Config = require(script.Config)
local Logger = require(script.Logger)
local Budget = require(script.BudgetManager)
local Persistence = require(script.PersistenceHandler)
local Session = require(script.SessionManager)
local Processor = require(script.DataProcessor)
local Reconciler = require(script.DataReconciler)

local DataSession = {}
DataSession.__index = DataSession

RunService.Stepped:Connect(Budget.Step)

function DataSession.new(id: string | number)
    return setmetatable({
        SessionID = tostring(id),
        Status = "Idle",
        Cache = {},
        _userIds = {},
        _connections = {},
        _storeName = "MainData"
    }, DataSession)
end

-- [MÉTODO LOAD] - Agora com Retentativas e Session Locking Real
function DataSession:Load(key: string, template: {[any]: any}, userIds: {number}?)
    self.Status = "Loading"
    self._userIds = userIds or {}
    
    local attempts = 0
    local maxAttempts = 5 -- Inspirado no ProfileStore
    local loadedData = nil

    repeat
        attempts += 1
        
        -- O UpdateSafe agora garante atomicidade (não deixa dois servidores lerem ao mesmo tempo)
        local success, result = Persistence.UpdateSafe(
            self._storeName,
            self.SessionID,
            key,
            function(oldData)
                -- Se houver dados e eles estiverem bloqueados por outro servidor,
                -- o UpdateSafe (que atualizamos antes) retornará nil internamente.
                return oldData or Reconciler.Reconcile({}, template)
            end,
            self._userIds,
            false -- isReleasing
        )

        if success and result then
            loadedData = result
            break
        else
            Logger.Warn(`Conflito de sessão para {key}. Tentativa {attempts}/{maxAttempts}...`, "Init")
            -- O ProfileStore espera um tempo (LOAD_REPEAT_PERIOD) antes de tentar de novo
            task.wait(6) 
            
            -- Avisa o outro servidor para ele soltar o dado (MessagingService)
            Session.Broadcast(self.SessionID, {
                Type = "RequestRelease", 
                Key = key, 
                TargetJobId = "Any" -- Ou o JobId que estava no metadado se você o capturar
            })
        end
    until attempts >= maxAttempts

    if not loadedData then
        Logger.Critical(`Não foi possível assumir o controle da sessão: {key}`, "Init")
        return nil
    end

    self.Cache[key] = loadedData
    self.Status = "Active"
    return loadedData
end

-- [MÉTODO SAVE] - Agora usa UpdateSafe para garantir integridade
function DataSession:Save(key: string)
    if self.Status ~= "Active" then return end
    local data = self.Cache[key]
    if not data then return end

    -- Em vez de SetAsync, usamos UpdateSafe para não atropelar locks
    Persistence.UpdateSafe(
        self._storeName,
        self.SessionID,
        key,
        function(_) return data end,
        self._userIds,
        false
    )
end

-- [MÉTODO RELEASE] - Limpeza de lock igual ao ProfileStore
function DataSession:Release(key: string)
    if self.Status == "Idle" then return end
    
    Logger.Info("Finalizando sessão e limpando Lock: " .. key)
    
    local success = Persistence.UpdateSafe(
        self._storeName,
        self.SessionID,
        key,
        function(_) return self.Cache[key] end,
        self._userIds,
        true -- Define isReleasing como true para limpar o JobId no DataStore
    )

    if success then
        for _, conn in ipairs(self._connections) do conn:Disconnect() end
        table.clear(self._connections)
        self.Cache[key] = nil
        self.Status = "Idle"
    end
end

-- [MANIPULAÇÃO]
function DataSession:Edit(key: string, path: string, value: any)
    if self.Status ~= "Active" then return end
    Processor.Modify(self.Cache[key], path, value, "Set")
end

function DataSession:Add(key: string, path: string, amount: number)
    if self.Status ~= "Active" then return end
    Processor.Modify(self.Cache[key], path, amount, "Add")
end

return DataSession

