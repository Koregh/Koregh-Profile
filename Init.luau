--!strict
local RunService = game:GetService("RunService")
local Config = require(script.Config)
local Logger = require(script.Logger)
local Budget = require(script.BudgetManager)

local DataSession = {}
DataSession.__index = DataSession

-- Conecta o scheduler de forma limpa
RunService.Stepped:Connect(Budget.Step)

function DataSession.new(id: string | number)
    Logger.Info("Iniciando nova sessão: " .. id)
    -- ... lógica de criação
end
