--!strict
-- DataService / MessageManager.lua
local MessageManager = {}

-- Estrutura de uma mensagem: {Id: number, Type: string, Data: any}

function MessageManager.Add(currentData: any, messageType: string, messageData: any)
    if not currentData._globalMessages then
        currentData._globalMessages = {}
    end
    
    local newMessage = {
        Id = os.time() + math.random(1, 1000),
        Type = messageType,
        Data = messageData
    }
    
    table.insert(currentData._globalMessages, newMessage)
end

function MessageManager.Process(session: any, key: string, callback: (message: any) -> boolean)
    local data = session.Cache[key]
    if not data or not data._globalMessages then return end
    
    -- Percorremos de trás para frente para poder remover mensagens processadas
    for i = #data._globalMessages, 1, -1 do
        local msg = data._globalMessages[i]
        local success = callback(msg) -- Se o jogo processar com sucesso, removemos da fila
        
        if success then
            table.remove(data._globalMessages, i)
        end
    end
end

return MessageManager
