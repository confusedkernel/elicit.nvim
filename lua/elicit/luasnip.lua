local config = require("elicit.config")
local example = require("elicit.example")
local session = require("elicit.session")
local util = require("elicit.util")

local M = {}
local retry_group = vim.api.nvim_create_augroup("ElicitLuaSnipSync", { clear = true })
local retry_registered = false

local function normalize_list(value)
	if type(value) ~= "table" then
		return {}
	end

	if vim.islist then
		if not vim.islist(value) then
			return {}
		end
	elseif vim.tbl_islist and not vim.tbl_islist(value) then
		return {}
	end

	return value
end

local function normalize_filetypes(value)
	local out = {}

	for _, item in ipairs(normalize_list(value)) do
		local ft = util.trim(tostring(item or ""))

		if ft ~= "" then
			table.insert(out, ft)
		end
	end

	return out
end

local function resolve_snippet_filetypes(snippet_cfg)
	local filetypes = normalize_filetypes(snippet_cfg.filetypes)

	if #filetypes == 0 then
		return { "markdown" }
	end

	return filetypes
end

local function clear_retry_autocmds()
	if not retry_registered then
		return
	end

	retry_registered = false
	pcall(vim.api.nvim_clear_autocmds, { group = retry_group })
end

local function ensure_retry_autocmds()
	if retry_registered then
		return
	end

	retry_registered = true

	vim.api.nvim_create_autocmd({ "InsertEnter", "BufEnter", "FileType" }, {
		group = retry_group,
		callback = function()
			local synced, err = M.sync()

			if synced == true or synced == false then
				clear_retry_autocmds()
				return
			end

			if err ~= "LuaSnip is not available" then
				clear_retry_autocmds()
			end
		end,
	})
end

local function example_snippet_fields(example_cfg)
	local out = {}

	for _, field_name in ipairs(example_cfg.fields or {}) do
		table.insert(out, {
			name = field_name,
			default = example.default_field_value(field_name),
		})
	end

	return out
end

local function session_snippet_fields(session_cfg)
	local out = {}

	for _, field in ipairs(session.frontmatter_fields(session_cfg)) do
		table.insert(out, {
			name = field.name,
			default = field.scalar,
		})
	end

	return out
end

local function build_example_nodes(ls, fields, static_id)
	local nodes = {
		ls.text_node("## "),
	}

	if static_id then
		table.insert(nodes, ls.text_node(static_id))
	else
		table.insert(
			nodes,
			ls.function_node(function()
				return example.next_example_id(0)
			end, {})
		)
	end

	local index = 1

	for _, field in ipairs(fields) do
		table.insert(nodes, ls.text_node({ "", string.format("- %s: ", field.name) }))
		table.insert(nodes, ls.insert_node(index, field.default))
		index = index + 1
	end

	table.insert(nodes, ls.insert_node(0))

	return nodes
end

local function build_session_nodes(ls, fields)
	local nodes = {
		ls.text_node("---"),
	}

	local index = 1

	for _, field in ipairs(fields) do
		table.insert(nodes, ls.text_node({ "", string.format("%s: ", field.name) }))
		table.insert(nodes, ls.insert_node(index, field.default))
		index = index + 1
	end

	table.insert(nodes, ls.text_node({ "", "---", "" }))
	table.insert(nodes, ls.insert_node(0))

	return nodes
end

local function register_example_snippet(ls, trigger, fields, filetypes)
	for _, ft in ipairs(filetypes) do
		ls.add_snippets(ft, {
			ls.snippet({
				trig = trigger,
				name = "Elicit example",
				dscr = "Insert an elicitation example block",
				wordTrig = true,
			}, build_example_nodes(ls, fields)),
		}, {
			key = "elicit-example-snippet-" .. ft,
		})
	end
end

local function register_session_snippet(ls, trigger, fields, filetypes)
	for _, ft in ipairs(filetypes) do
		ls.add_snippets(ft, {
			ls.snippet({
				trig = trigger,
				name = "Elicit session",
				dscr = "Insert elicitation session frontmatter",
				wordTrig = true,
			}, build_session_nodes(ls, fields)),
		}, {
			key = "elicit-session-snippet-" .. ft,
		})
	end
end

local function sync_example_snippet(ls, example_cfg, snippet_cfg)
	if snippet_cfg.enable ~= true then
		return false
	end

	local trigger = util.trim(tostring(snippet_cfg.trigger or ""))

	if trigger == "" then
		return nil, "example.luasnip.trigger cannot be empty when snippet integration is enabled"
	end

	local fields = example_snippet_fields(example_cfg)

	if #fields == 0 then
		return nil, "example.fields is empty; cannot build LuaSnip snippet"
	end

	register_example_snippet(ls, trigger, fields, resolve_snippet_filetypes(snippet_cfg))

	return true
end

local function sync_session_snippet(ls, session_cfg, snippet_cfg)
	if snippet_cfg.enable ~= true then
		return false
	end

	local trigger = util.trim(tostring(snippet_cfg.trigger or ""))

	if trigger == "" then
		return nil, "session.luasnip.trigger cannot be empty when snippet integration is enabled"
	end

	local fields = session_snippet_fields(session_cfg)

	if #fields == 0 then
		return nil, "session.fields is empty; cannot build LuaSnip snippet"
	end

	register_session_snippet(ls, trigger, fields, resolve_snippet_filetypes(snippet_cfg))

	return true
end

function M.sync()
	local cfg = config.get()
	local example_cfg = cfg.example or {}
	local session_cfg = cfg.session or {}
	local example_snippet_cfg = example_cfg.luasnip or {}
	local session_snippet_cfg = session_cfg.luasnip or {}

	if example_snippet_cfg.enable ~= true and session_snippet_cfg.enable ~= true then
		clear_retry_autocmds()
		return false
	end

	local ok, ls = pcall(require, "luasnip")

	if not ok then
		ensure_retry_autocmds()
		return nil, "LuaSnip is not available"
	end

	local synced_any = false

	local example_synced, example_err = sync_example_snippet(ls, example_cfg, example_snippet_cfg)

	if example_synced == nil then
		clear_retry_autocmds()
		return nil, example_err
	end

	if example_synced then
		synced_any = true
	end

	local session_synced, session_err = sync_session_snippet(ls, session_cfg, session_snippet_cfg)

	if session_synced == nil then
		clear_retry_autocmds()
		return nil, session_err
	end

	if session_synced then
		synced_any = true
	end

	clear_retry_autocmds()

	return synced_any
end

function M.expand_example(example_id)
	local ok, ls = pcall(require, "luasnip")

	if not ok then
		return nil, "LuaSnip is not available"
	end

	local cfg = config.get()
	local example_cfg = cfg.example or {}
	local fields = example_snippet_fields(example_cfg)

	if #fields == 0 then
		return nil, "example.fields is empty; cannot build LuaSnip snippet"
	end

	local nodes = build_example_nodes(ls, fields, example_id)

	local snip = ls.snippet({
		trig = "",
		name = "Elicit example",
		dscr = "Insert an elicitation example block",
	}, nodes)

	ls.snip_expand(snip)

	return true
end

function M.expand_session()
	local ok, ls = pcall(require, "luasnip")

	if not ok then
		return nil, "LuaSnip is not available"
	end

	local cfg = config.get()
	local session_cfg = cfg.session or {}
	local fields = session_snippet_fields(session_cfg)

	if #fields == 0 then
		return nil, "session.fields is empty; cannot build LuaSnip snippet"
	end

	local nodes = build_session_nodes(ls, fields)

	local snip = ls.snippet({
		trig = "",
		name = "Elicit session",
		dscr = "Insert elicitation session frontmatter",
	}, nodes)

	ls.snip_expand(snip)

	return true
end

return M
