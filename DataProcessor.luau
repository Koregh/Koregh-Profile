--!strict
local DataProcessor = {}

function DataProcessor.GetPath(data: any, path: string, separator: string): (any, string)
    local nodes = path:split(separator)
    local current = data
    for i = 1, #nodes - 1 do
        if type(current[nodes[i]]) ~= "table" then current[nodes[i]] = {} end
        current = current[nodes[i]]
    end
    return current, nodes[#nodes]
end

function DataProcessor.Modify(data: any, path: string, value: any, op: "Set" | "Add")
    local container, key = DataProcessor.GetPath(data, path, ".")
    if op == "Set" then
        container[key] = value
    elseif op == "Add" then
        container[key] = (container[key] or 0) + value
    end
    return container[key]
end

return DataProcessor
