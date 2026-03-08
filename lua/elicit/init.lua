local config = require("elicit.config")
local util = require("elicit.util")

local M = {}

local commands_registered = false

local function notify_error(message)
	vim.notify("elicit.nvim: " .. tostring(message), vim.log.levels.ERROR)
end

local function run_action(fn, ...)
	local ok, result, err = pcall(fn, ...)

	if not ok then
		notify_error(result)
		return nil
	end

	if result == nil and err then
		notify_error(err)
		return nil
	end

	return result
end

local function filter_by_prefix(values, prefix)
	local out = {}

	for _, value in ipairs(values) do
		if prefix == "" or util.starts_with(value, prefix) then
			table.insert(out, value)
		end
	end

	return out
end

local function complete_search(arg_lead, cmd_line)
	local words = util.split_words(cmd_line)
	local trailing_space = cmd_line:match("%s$") ~= nil

	if #words == 1 then
		return filter_by_prefix(require("elicit.search").kinds(), arg_lead)
	end

	if #words == 2 and not trailing_space then
		return filter_by_prefix(require("elicit.search").kinds(), arg_lead)
	end

	return {}
end

local function complete_export(arg_lead, cmd_line)
	local words = util.split_words(cmd_line)
	local trailing_space = cmd_line:match("%s$") ~= nil

	if #words == 1 then
		return filter_by_prefix(require("elicit.export").formats(), arg_lead)
	end

	if #words == 2 and not trailing_space then
		return filter_by_prefix(require("elicit.export").formats(), arg_lead)
	end

	if (#words == 2 and trailing_space) or (#words == 3 and not trailing_space) then
		return filter_by_prefix(require("elicit.export").scopes(), arg_lead)
	end

	return {}
end

function M._register_commands()
	if commands_registered then
		return
	end

	vim.api.nvim_create_user_command("ElicitNewSession", function(args)
		run_action(require("elicit.session").new_session, args.args)
	end, {
		nargs = "?",
		complete = "file",
		desc = "Create a new elicitation session file",
	})

	vim.api.nvim_create_user_command("ElicitNewExample", function()
		run_action(require("elicit.example").insert_example)
	end, {
		nargs = 0,
		desc = "Insert a new elicitation example block",
	})

	vim.api.nvim_create_user_command("ElicitValidate", function()
		run_action(require("elicit.validate").run)
	end, {
		nargs = 0,
		desc = "Validate current elicitation session",
	})

	vim.api.nvim_create_user_command("ElicitSearch", function(args)
		local kind = args.fargs[1]
		local query = util.concat_from(args.fargs, 2, " ")

		run_action(require("elicit.search").run, kind, query)
	end, {
		nargs = "+",
		complete = complete_search,
		desc = "Search elicitation corpus",
	})

	vim.api.nvim_create_user_command("ElicitExport", function(args)
		if #args.fargs < 2 then
			notify_error("usage: :ElicitExport <format> <scope> [value]")
			return
		end

		local format_name = args.fargs[1]
		local scope = args.fargs[2]
		local value = util.concat_from(args.fargs, 3, " ")

		run_action(require("elicit.export").run, format_name, scope, value)
	end, {
		nargs = "+",
		complete = complete_export,
		desc = "Export elicitation data",
	})

	commands_registered = true
end

function M.setup(opts)
	config.setup(opts or {})
	M._register_commands()
end

function M._bootstrap()
	config.setup({})
	M._register_commands()
end

function M.get_config()
	return config.get()
end

function M.get_corpus_glob()
	return config.corpus_glob(config.get())
end

function M.parse_buffer(bufnr)
	return require("elicit.parser").parse_buffer(bufnr)
end

return M
