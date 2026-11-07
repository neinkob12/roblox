--!strict
-- Run a function protected: an error is logged with a label instead of killing the caller's loop.
-- Use it for every "one failure must not stop the whole loop" call site.
--
--   Safe.Run("DairyService price roll", rollPrice)
--   Safe.Run("CanService tick", tickPlayer, player)

local Safe = {}

function Safe.Run(label: string, fn: (...any) -> ...any, ...: any): boolean
	-- the cast keeps luau-lsp happy for functions that return nothing
	local ok, err = pcall(fn :: any, ...)
	if not ok then
		-- "failed" is what the boot test's health check greps for, so a loop error never hides
		warn(`[{label}] failed: {err}`)
	end
	return ok
end

return Safe
