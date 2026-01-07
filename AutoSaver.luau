--!strict
local Logger = require(script.Parent.Logger)

local AutoSaver = {}

local activeSessions = {} -- Lista de sessões para salvar
local isRunning = false
local SAVE_INTERVAL = 300 -- 5 minutos para dar a volta completa em todos os players

function AutoSaver.RegisterSession(session: any, key: string)
    table.insert(activeSessions, { session = session, key = key })
    Logger.Info("Sessão registrada no Auto-Save: " .. key)
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
            if #activeSessions > 0 then
                -- Calcula o tempo de espera entre cada player para distribuir os 5 minutos
                -- Se tiver 50 players, salva um a cada 6 segundos.
                local waitTime = math.max(SAVE_INTERVAL / #activeSessions, 2) 
                
                for _, entry in ipairs(activeSessions) do
                    if entry.session.Status == "Active" then
                        entry.session:Save(entry.key)
                    end
                    task.wait(waitTime)
                end
            else
                task.wait(10) -- Se não houver ninguém, espera 10s e checa de novo
            end
        end
    end)
end

return AutoSaver
