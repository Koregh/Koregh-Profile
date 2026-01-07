--!strict
-- DataService / DataReconciler.lua
local DataReconciler = {}

-- Preenche dados faltantes no perfil do jogador com base em um template
function DataReconciler.Reconcile(target: {[any]: any}?, template: {[any]: any}): {[any]: any}
	-- Se o alvo for nulo (jogador novo), retornamos uma cópia do template
	if not target then
		return table.clone(template)
	end

	for key, value in pairs(template) do
		if type(value) == "table" then
			-- Se no dado do jogador não for uma tabela, criamos uma
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			-- Chama recursivamente para tabelas aninhadas
			DataReconciler.Reconcile(target[key], value)
		elseif target[key] == nil then
			-- Só preenche se a chave realmente não existir
			target[key] = value
		end
	end
	
	return target
end

return DataReconciler

