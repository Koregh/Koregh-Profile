# Koregh DataService Framework v0.0.1

O DataService é um ecossistema de persistência de dados de integridade para a plataforma Roblox. Ele foi desenvolvido  focando em desacoplamento de módulos, segurança contra duplicação de itens (Session Locking) e conformidade com leis de privacidade e proteção de dados (GDPR).

# Arquitetura do Sistema

O framework é composto por módulos especialistas que garantem a resiliência do ciclo de vida dos dados:
 * Core (init.lua): Gestor de sessões e orquestrador do ciclo de vida do Session Locking.
 * PersistenceHandler: Interface de baixo nível que gerencia as chamadas ao DataStoreService, implementando UpdateAsync com suporte a metadados e filas de concorrência.
 * SessionManager: Sistema de rádio via MessagingService para comunicação inter-servidores e quebra de locks órfãos.
 * DataProcessor: Motor de limpeza e sanitização. Garante que tipos incompatíveis (como Instances ou CFrames) não corrompam o banco de dados.
 * DataReconciler: Algoritmo recursivo que realiza o merge entre saves legados e novas versões de templates.
 * AutoSaver: Scheduler inteligente que distribui requisições de salvamento para otimizar o uso do budget do servidor.
 * BudgetManager: Monitor em tempo real que impede o estrangulamento de requisições por limite de quota.

# Guia de Operação
Inicialização e Carga
local DataService = require(game:GetService("ServerScriptService").DataService)
local session = DataService.new(player.UserId)

-- O motor gerencia automaticamente retentativas e conflitos de servidor
local data = session:Load("User_" .. player.UserId, TEMPLATE, {player.UserId})

Manipulação Segura de Estado
-- Modifica campos específicos com sanitização automática
session:Edit("User_123", "Inventory.Gold", 500)

-- Incremento atômico de valores numéricos
session:Add("User_123", "Stats.Experience", 100)

Encerramento de Sessão
-- Libera o Session Lock e realiza o salvamento final
session:Release("User_123")

#  Créditos e Licença
Este projeto é distribuído sob a Licença MIT.
 * Lógica Original e Core: realkastien
 * Refatoração e Arquitetura: Koregh
 * Data de Refatoração: Janeiro de 2026
 * Link: https://github.com/realkastien/DataSession
