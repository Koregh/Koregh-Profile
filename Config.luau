--!strict
-- Config.lua
return {
	-- Segurança de Dados
	SESSION_LOCK_EXPIRE = 120,    -- Tempo (s) para considerar um lock expirado
	CROSS_SERVER_TIMEOUT = 7,     -- Tempo de espera pelo MessagingService
	
	-- Tentativas de Conexão
	LOAD_TRY_AMOUNT = 5,
	LOAD_RETRY_TIME = 3,
	
	-- Configurações de Ambiente
	STUDIO_SAVE = true,           -- Salvar dados enquanto testa no Studio?
	GAME_SAVE = true,
	
	-- Tags de Metadados
	METADATA_KEY = "SessionLock"
}
