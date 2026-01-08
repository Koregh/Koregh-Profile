--!strict
local Logger = require(script.Parent.Logger)

local AutoSaver = {}

type SessionEntry = { session: any, key: string }

local activeSessions: {SessionEntry} = {} 
local isRunning = false
local SAVE_INTERVAL = 300 -- 5 minutos

function AutoSaver.RegisterSession(session: any, key: string)
	-- Evita duplicatas se o Load for chamado duas vezes
	for _, entry in ipairs(activeSessions) do
		if entry.key == key then return end
	end
	
	table.insert(activeSessions, { session = session, key = key })
	Logger.Info("Sessão registrada no Auto-Save: " .. key, "AutoSaver")
end

function AutoSaver.UnregisterSession(key: string)
	for i, entry in ipairs(activeSessions) do
		if entry.key == key then
			table.remove(activeSessions, i)
			break
		end
	end
end

function AutoSaver.Start()
	if isRunning then return end
	isRunning = true
	
	task.spawn(function()
		while isRunning do
			local count = #activeSessions
			
			if count > 0 then
				-- Distribui o tempo para não estourar o Budget do DataStore
				local waitTime = math.max(SAVE_INTERVAL / count, 2) 
				
				-- Itera de trás para frente para evitar bugs de remoção de tabela durante o loop
				for i = count, 1, -1 do
					local entry = activeSessions[i]
					
					-- Verifica se a sessão ainda é válida e está ativa
					if entry and entry.session and entry.session.Status == "Active" then
						-- Roda o Save em uma thread separada para o waitTime ser preciso
						task.spawn(function()
							entry.session:Save(entry.key)
						end)
					end
					
					task.wait(waitTime)
				end
			else
				task.wait(10)
			end
		end
	end)
end

return AutoSaver

