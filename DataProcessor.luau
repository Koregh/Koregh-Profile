--!strict
local Logger = require(script.Parent.Logger)

local DataProcessor = {}

-- [FUNÇÃO AUXILIAR] - Limpa dados que o Roblox não salva (Instâncias, CFrames, etc)
local function Sanitize(value: any): (any, boolean)
    local t = typeof(value)
    if t == "table" then
        local cleaned = {}
        for k, v in pairs(value) do
            if typeof(k) ~= "string" and typeof(k) ~= "number" then continue end
            local cleanV, isValid = Sanitize(v)
            if isValid then cleaned[k] = cleanV end
        end
        return cleaned, true
    elseif t == "string" or t == "number" or t == "boolean" or t == "nil" then
        return value, true
    end
    return nil, false -- Ignora o que for inválido
end

function DataProcessor.GetPath(data: any, path: string, separator: string): (any, string)
    local nodes = path:split(separator)
    local current = data
    for i = 1, #nodes - 1 do
        -- Proteção extra: se o caminho existir mas não for tabela, forçamos virar tabela
        if type(current[nodes[i]]) ~= "table" then 
            current[nodes[i]] = {} 
        end
        current = current[nodes[i]]
    end
    return current, nodes[#nodes]
end

function DataProcessor.Modify(data: any, path: string, value: any, op: "Set" | "Add")
    local container, key = DataProcessor.GetPath(data, path, ".")
    
    -- Limpa o valor antes de aplicar (Essencial para não quebrar o DataStore)
    local cleanValue, isValid = Sanitize(value)
    if not isValid then
        Logger.Warn("Tentativa de modificar dado com tipo inválido: " .. typeof(value), "Processor")
        return container[key]
    end

    if op == "Set" then
        container[key] = cleanValue
    elseif op == "Add" then
        -- Garante que só somamos números
        local currentVal = container[key] or 0
        if typeof(currentVal) == "number" and typeof(cleanValue) == "number" then
            container[key] = currentVal + cleanValue
        else
            Logger.Warn("Tentativa de 'Add' em valor não numérico no caminho: " .. path, "Processor")
        end
    end
    
    return container[key]
end

return DataProcessor
