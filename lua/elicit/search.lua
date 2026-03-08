local util = require("elicit.util")

local M = {}

local KINDS = { "form", "gloss", "status", "speaker", "session" }
local KIND_SET = util.to_set(KINDS)

function M.kinds()
	return vim.deepcopy(KINDS)
end

function M.run(kind, query)
	if not KIND_SET[kind] then
		return nil, string.format("invalid search kind '%s'", tostring(kind))
	end

	if util.trim(query) == "" then
		return nil, "search query cannot be empty"
	end

	vim.notify("elicit.nvim: :ElicitSearch is scaffolded in phase 1 and implemented in phase 4.", vim.log.levels.INFO)

	return true
end

return M
