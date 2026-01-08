--!strict
local MessagingService = game:GetService("MessagingService")
local Logger = require(script.Parent.Logger)
local Config = require(script.Parent.Config)

local SessionManager = {}

-- Tipagem estrita para evitar erros de comunicação
export type NetworkMessage = {
    Type: "RequestRelease" | "Released" | "GlobalUpdate",
    SessionID: string,
    TargetJobId: string, 
    SourceJobId: string,
    Key: string,
    Data: any?
}

local TOPIC_NAME = "Persistence_Global_Comm"

-- Ouve e filtra mensagens que não são para este servidor
function SessionManager.Listen(sessionId: string, callback: (NetworkMessage) -> ())
    local success, connection = pcall(function()
        return MessagingService:SubscribeAsync(TOPIC_NAME, function(receipt)
            local message: NetworkMessage = receipt.Data
            
            -- IMPORTANTE! SÓ processa se:
            --  For para este Jogador/Sessão
            --  Não for uma mensagem que este próprio servidor enviou
            --  For direcionada para este JobId ou para "Any"
            if tostring(message.SessionID) == tostring(sessionId) then
                if message.SourceJobId ~= game.JobId then
                    if message.TargetJobId == game.JobId or message.TargetJobId == "Any" then
                        callback(message)
                    end
                end
            end
        end)
    end)

    if not success then
        Logger.Critical("Falha ao assinar MessagingService para: " .. sessionId, "Session")
    end
    
    return connection
end

--  Envia comandos para os outros servidores
function SessionManager.Broadcast(sessionId: string, payload: {Type: string, Key: string, TargetJobId: string?, Data: any?})
    local fullPayload: NetworkMessage = {
        Type = payload.Type,
        SessionID = tostring(sessionId),
        Key = payload.Key,
        TargetJobId = payload.TargetJobId or "Any",
        SourceJobId = game.JobId,
        Data = payload.Data
    }

    local success, err = pcall(function()
        MessagingService:PublishAsync(TOPIC_NAME, fullPayload)
    end)
    
    if not success then
        Logger.Warn(`Erro ao transmitir {payload.Type} para {sessionId}: {err}`, "Session")
    end
end

return SessionManager
