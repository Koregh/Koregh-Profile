--!strict
-- DataReconciler.lua
local DataReconciler = {}

-- Preenche dados faltantes no perfil do jogador com base em um template
function DataReconciler.Reconcile(target: {[any]: any}, template: {[any]: any}): {[any]: any}
	for key, value in pairs(template) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			DataReconciler.Reconcile(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end

return DataReconciler
