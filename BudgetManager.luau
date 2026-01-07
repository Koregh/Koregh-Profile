--!strict
local DataStoreService = game:GetService("DataStoreService")
local Logger = require(script.Parent.Logger)

local BudgetManager = {}
local Waitlist: {[Enum.DataStoreRequestType]: {thread}} = {}

for _, item in Enum.DataStoreRequestType:GetEnumItems() do
	Waitlist[item] = {}
end

function BudgetManager.WaitForBudget(requestType: Enum.DataStoreRequestType)
	local budget = DataStoreService:GetRequestBudgetForRequestType(requestType)
	
	if budget <= 0 then
		Logger.Warn("Budget esgotado para " .. requestType.Name .. ". Entrando na fila.", "BudgetManager")
		table.insert(Waitlist[requestType], coroutine.running())
		coroutine.yield()
	end
end

-- Iniciado pelo init.lua
function BudgetManager.Step()
	for requestType, threads in Waitlist do
		if #threads > 0 and DataStoreService:GetRequestBudgetForRequestType(requestType) > 0 then
			local t = table.remove(threads, 1)
			if t then coroutine.resume(t) end
		end
	end
end

return BudgetManager
