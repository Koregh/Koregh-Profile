--!strict
local DataStoreService = game:GetService("DataStoreService")
local Budget = require(script.Parent.BudgetManager)
local Config = require(script.Parent.Config)
local Logger = require(script.Parent.Logger)

local PersistenceHandler = {}

-- Fila de concorrência (Impede que 2 salvamentos da mesma chave se atropelem)
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

-- [GET] - Agora retorna o KeyInfo para verificarmos o Lock no Init
function PersistenceHandler.Get(storeName: string, scope: string, key: string)
	local store = DataStoreService:GetDataStore(storeName, scope)
	Budget.WaitForBudget(Enum.DataStoreRequestType.GetAsync)
	
	local success, result, info = pcall(function()
		return store:GetAsync(key)
	end)
	
	return success, result, info
end

-- [UPDATE SAFE] - O substituto Senior do SetAsync
function PersistenceHandler.UpdateSafe(
	storeName: string, 
	scope: string, 
	key: string, 
	transformFunc: (any) -> any, 
	userIds: {number}?, 
	isReleasing: boolean
)
	local store = DataStoreService:GetDataStore(storeName, scope)
	
	WaitInQueue(key) -- Entra na fila (SOLID: Ordem de execução)

	Budget.WaitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)
	
	local success, result = pcall(function()
		return store:UpdateAsync(key, function(oldData, keyInfo)
			-- Lógica de Session Lock (Igual ao ProfileStore)
			if keyInfo then
				local metadata = keyInfo:GetMetadata()
				local currentLock = metadata[Config.METADATA_KEY]
				
				-- Se outro servidor assumiu o lock e não estamos forçando a entrada, aborta
				if currentLock and currentLock ~= "" and currentLock ~= game.JobId then
					Logger.Warn("Tentativa de sobrescrever Lock de outro servidor: " .. key, "Persistence")
					return nil -- Cancela o UpdateAsync sem erro, mas sem salvar
				end
			end

			-- Executa a transformação dos dados
			local newData = transformFunc(oldData)
			
			-- Configura os Metadados para o próximo salvamento
			local options = Instance.new("DataStoreSetOptions")
			options:SetMetadata({
				[Config.METADATA_KEY] = isReleasing and "" or game.JobId
			})
			
			-- O UpdateAsync permite associar UserIds para GDPR
			if userIds then
				options:SetSetUserIds(userIds)
			end

			return newData, userIds, options
		end)
	end)
	
	NextInQueue(key) -- Libera a fila para o próximo processo
	
	if not success then
		Logger.Critical("Falha no UpdateSafe: " .. tostring(result), "Persistence")
	end

	return success, result
end

return PersistenceHandler

