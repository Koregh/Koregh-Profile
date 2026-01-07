--!strict
local DataStoreService = game:GetService("DataStoreService")
local Budget = require(script.Parent.BudgetManager)
local Config = require(script.Parent.Config)
local Logger = require(script.Parent.Logger)

local PersistenceHandler = {}

-- Fila de concorrência (Impede que 2 threads no mesmo servidor tentem salvar o mesmo player)
local UpdateQueue: {[string]: {thread}} = {}

local function WaitInQueue(key: string)
	if not UpdateQueue[key] then
		UpdateQueue[key] = {}
		return
	end
	table.insert(UpdateQueue[key], coroutine.running())
	coroutine.yield()
end

local function NextInQueue(key: string)
	local queue = UpdateQueue[key]
	if queue and #queue > 0 then
		local nextThread = table.remove(queue, 1)
		task.spawn(nextThread)
	else
		UpdateQueue[key] = nil
	end
end

-- [UPDATE SAFE] - Sincronizado com o Init.lua
function PersistenceHandler.UpdateSafe(
	storeName: string, 
	jobId: string, -- Recebe o JobId da sessão para o Lock
	key: string, 
	transformFunc: (any) -> any, 
	userIds: {number}?, 
	isReleasing: boolean
)
	local store = DataStoreService:GetDataStore(storeName) -- Usamos apenas o Name para centralizar
	
	WaitInQueue(key) 

	Budget.WaitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
	
	local success, result = pcall(function()
		return store:UpdateAsync(key, function(oldData, keyInfo)
			-- 1. LÓGICA DE SESSION LOCK (Anti-Dupe)
			if keyInfo then
				local metadata = keyInfo:GetMetadata()
				local currentLock = metadata[Config.METADATA_KEY]
				
				-- Se o Lock pertence a outro JobId e não está vazio, abortamos
				if currentLock and currentLock ~= "" and currentLock ~= jobId then
					Logger.Warn("Acesso Negado: Chave " .. key .. " está trancada por " .. tostring(currentLock), "Persistence")
					return nil -- Aborta o Update sem salvar
				end
			end

			-- 2. TRANSFORMAÇÃO DOS DADOS (Reconciler ou Save)
			local newData = transformFunc(oldData)
			
			-- 3. CONFIGURAÇÃO DE METADADOS E GDPR
			local options = Instance.new("DataStoreSetOptions")
			
			-- O segredo do Lock: Se estivermos a dar Release, limpamos o metadado
			options:SetMetadata({
				[Config.METADATA_KEY] = isReleasing and "" or jobId
			})
			
			-- Vínculo legal de UserIds (DIREITO DE SER ESQUECIDO)
			if userIds and #userIds > 0 then
				options:SetSetUserIds(userIds) -- O método correto do Roblox para GDPR
			end

			return newData, userIds, options
		end)
	end)
	
	NextInQueue(key) 
	
	if not success then
		Logger.Critical("Falha crítica no DataStore: " .. tostring(result), "Persistence")
	end

	return success, result
end

return PersistenceHandler

