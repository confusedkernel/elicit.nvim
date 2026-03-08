local util = require("elicit.util")

local M = {}

local FORMATS = { "markdown", "typst", "json" }
local SCOPES = { "example", "session", "status" }

local FORMAT_SET = util.to_set(FORMATS)
local SCOPE_SET = util.to_set(SCOPES)

function M.formats()
	return vim.deepcopy(FORMATS)
end

function M.scopes()
	return vim.deepcopy(SCOPES)
end

function M.run(format_name, scope, _value)
	if not FORMAT_SET[format_name] then
		return nil, string.format("invalid export format '%s'", tostring(format_name))
	end

	if not SCOPE_SET[scope] then
		return nil, string.format("invalid export scope '%s'", tostring(scope))
	end

	vim.notify("elicit.nvim: :ElicitExport is scaffolded in phase 1 and implemented in phase 5.", vim.log.levels.INFO)

	return true
end

return M
