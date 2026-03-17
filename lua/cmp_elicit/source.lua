local abbrev = require("elicit.abbrev")
local config = require("elicit.config")
local util = require("elicit.util")

local source = {}

local seen_errors = {}

local function notify_warn_once(message)
	local text = util.to_trimmed_string(message)

	if text == "" or seen_errors[text] then
		return
	end

	seen_errors[text] = true

	vim.schedule(function()
		if vim.notify_once then
			vim.notify_once("elicit.nvim: " .. text, vim.log.levels.WARN)
		else
			vim.notify("elicit.nvim: " .. text, vim.log.levels.WARN)
		end
	end)
end

local function current_position(params)
	local context = params and params.context or {}
	local cursor = context.cursor or {}

	return context.bufnr or 0, cursor.row or 1, math.max((cursor.col or 1) - 1, 0)
end

local function matched_alias(entry, prefix)
	local needle = string.lower(util.to_trimmed_string(prefix))

	for _, alias in ipairs(entry.aliases or {}) do
		if util.starts_with_ignore_case(alias, needle) then
			return alias
		end
	end

	return nil
end

local function documentation_for(entry)
	local lines = { string.format("`%s`", entry.label) }

	if entry.description then
		table.insert(lines, "")
		table.insert(lines, entry.description)
	end

	if entry.aliases and #entry.aliases > 0 then
		table.insert(lines, "")
		table.insert(lines, "Aliases: `" .. table.concat(entry.aliases, "`, `") .. "`")
	end

	if entry.source then
		table.insert(lines, "")
		table.insert(lines, "Source: `" .. entry.source .. "`")
	end

	return {
		kind = "markdown",
		value = table.concat(lines, "\n"),
	}
end

source.new = function()
	return setmetatable({}, { __index = source })
end

function source:is_available()
	local abbrev_cfg = (config.get().abbreviations or {})
	local cmp_cfg = abbrev_cfg.cmp or {}

	if cmp_cfg.enable ~= true then
		return false
	end

	return abbrev.in_gloss_context()
end

function source:get_debug_name()
	return "elicit"
end

function source:get_keyword_pattern()
	return [[\k\+]]
end

function source:complete(params, callback)
	local bufnr, row, col = current_position(params)

	if not abbrev.in_gloss_context(bufnr, row, col) then
		callback({ items = {}, isIncomplete = false })
		return
	end

	local prefix = abbrev.current_prefix(bufnr, row, col)

	if prefix == "" then
		callback({ items = {}, isIncomplete = false })
		return
	end

	local entries, err = abbrev.matches(prefix)

	if err then
		notify_warn_once(err)
	end

	local kind = vim.lsp.protocol.CompletionItemKind.EnumMember
	local items = {}

	for _, entry in ipairs(entries) do
		local alias = matched_alias(entry, prefix)
		local filter_text = alias or entry.label

		table.insert(items, {
			label = entry.label,
			kind = kind,
			insertText = entry.label,
			filterText = filter_text,
			detail = entry.description,
			documentation = documentation_for(entry),
			menu = entry.source and ("[" .. entry.source .. "]") or nil,
			dup = 0,
		})
	end

	callback({
		items = items,
		isIncomplete = false,
	})
end

return source
