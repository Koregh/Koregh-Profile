--!strict
local Logger = {}

local PREFIX = "[DATA-SERVICE]"
local DEBUG_MODE = true

function Logger.Info(msg: string)
	print(string.format("%s %s", PREFIX, msg))
end

function Logger.Warn(msg: string, context: string?)
	warn(string.format("%s [%s] %s", PREFIX, context or "GENERIC", msg))
end

function Logger.Error(msg: string, context: string)
	error(string.format("%s Critical Error in [%s]: %s", PREFIX, context, msg))
end

return Logger
