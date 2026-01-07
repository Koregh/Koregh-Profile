--!strict
-- DataManager.lua
-- Script de inicialização/exemplo.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Referência ao seu módulo DataService (init.lua)
local DataService = require(ServerScriptService.DataService) 

-- Definição do Template (Dados Iniciais, altere/modifique ao seu critério)
local DATA_TEMPLATE = {
	Coins = 100,
	Level = 1,
	Inventory = { "Wooden Sword" },
	Settings = {
		Music = true,
		Volume = 10
	}
}

-- Tabela para rastrear sessões ativas no servidor
local Sessions = {}

-- Função de Entrada
local function OnPlayerAdded(player: Player)
	local session = DataService.new(player.UserId)
	Sessions[player.UserId] = session

	-- Caso algo dê errado no motor
	session.OnError:Connect(function(errType, message)
		warn(`[DataError] {player.Name} ({errType}): {message}`)
	end)

	-- Tenta carregar o perfil
	local key = "Player_" .. player.UserId
	local successData = session:Load(key, DATA_TEMPLATE, {player.UserId})

	if not successData then
		-- Se não carregar após os retries, expulsamos por segurança (Anti-Data-Loss)
		player:Kick("Seus dados não puderam ser carregados com segurança. Por favor, reconecte.")
		return
	end

	print(`[DataService] Perfil de {player.Name} carregado com sucesso.`)
end

-- Função de Saída 
local function OnPlayerRemoving(player: Player)
	local session = Sessions[player.UserId]
	if session then
		local key = "Player_" .. player.UserId
		session:Release(key) -- Isso salva e libera o Lock para outros servidores
		Sessions[player.UserId] = nil
	end
end

--  BindToClose 
-- Garante que todos os dados salvem se o servidor for desligado pela Roblox
game:BindToClose(function()
	print("[DataService] Servidor fechando, salvando sessões restantes...")
	
	for userId, session in pairs(Sessions) do
		task.spawn(function()
			local key = "Player_" .. userId
			session:Release(key)
		end)
	end

	-- Espera técnica para dar tempo ao DataStore de responder antes do processo morrer
	local start = tick()
	while tick() - start < 20 do
		local count = 0
		for _ in pairs(Sessions) do count += 1 end
		if count == 0 then break end
		task.wait(0.5)
	end
	print("[DataService] Todas as sessões salvas.")
end)

-- Inicialização das Conexões
Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

-- Trata jogadores que entraram antes do script rodar (Otimo para FakePlayers)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(OnPlayerAdded, player)
end
