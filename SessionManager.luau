--!strict
-- SessionManager.lua
local MessagingService = game:GetService("MessagingService")
local Logger = require(script.Parent.Logger)
local Config = require(script.Parent.Config)

local SessionManager = {}

-- Tipagem para as mensagens trocadas
export type NetworkMessage = {
    DataStore: string,
    Key: string,
    JobId: string,
    Data: {[string]: any}?
}

-- Assina um tópico para ouvir pedidos de outros servidores
function SessionManager.Listen(topic: string, callback: (NetworkMessage) -> ())
    local success, connection = pcall(function()
        return MessagingService:SubscribeAsync(topic, function(message)
            callback(message.Data)
        end)
    end)

    if not success then
        Logger.Critical("Falha ao conectar ao MessagingService: " .. topic, "SessionManager")
    end
    return connection
end

-- Envia um sinal para outros servidores
function SessionManager.Broadcast(topic: string, payload: NetworkMessage)
    local success, err = pcall(function()
        MessagingService:PublishAsync(topic, payload)
    end)
    
    if not success then
        Logger.Warn("Falha ao transmitir sinal: " .. tostring(err), "SessionManager")
    end
end

return SessionManager
