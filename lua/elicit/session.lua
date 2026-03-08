local config = require("elicit.config")
local util = require("elicit.util")

local M = {}
local is_list = vim.islist or vim.tbl_islist

local function yaml_quote(value)
	local escaped = tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"')
	return string.format('"%s"', escaped)
end

local function yaml_scalar(value)
	local value_type = type(value)

	if value_type == "string" then
		if value == "" then
			return '""'
		end

		if value:match("^[%w_%-%.]+$") then
			return value
		end

		return yaml_quote(value)
	end

	if value_type == "number" or value_type == "boolean" then
		return tostring(value)
	end

	if value_type == "table" then
		if not is_list(value) then
			return "{}"
		end

		if #value == 0 then
			return "[]"
		end

		local encoded = {}

		for _, item in ipairs(value) do
			local item_type = type(item)

			if item_type == "string" then
				table.insert(encoded, yaml_quote(item))
			elseif item_type == "number" or item_type == "boolean" then
				table.insert(encoded, tostring(item))
			else
				table.insert(encoded, yaml_quote(tostring(item)))
			end
		end

		return string.format("[%s]", table.concat(encoded, ", "))
	end

	if value == nil then
		return '""'
	end

	return yaml_quote(tostring(value))
end

local function default_value(field, session_defaults)
	if session_defaults[field] ~= nil then
		return vim.deepcopy(session_defaults[field])
	end

	if field == "date" then
		return util.today()
	end

	if field == "session" then
		return 1
	end

	if field == "tags" then
		return {}
	end

	return ""
end

local function build_frontmatter_lines(session_cfg)
	local fields = session_cfg.fields or {}
	local defaults = session_cfg.defaults or {}
	local lines = { "---" }

	for _, field in ipairs(fields) do
		local value = default_value(field, defaults)
		table.insert(lines, string.format("%s: %s", field, yaml_scalar(value)))
	end

	table.insert(lines, "---")
	table.insert(lines, "")

	return lines
end

local function resolve_session_dir(session_cfg)
	local cwd = vim.fn.getcwd()
	local raw_dir = util.trim(session_cfg.dir or "")

	if raw_dir == "" then
		raw_dir = "sessions"
	end

	if util.is_absolute_path(raw_dir) then
		return util.normalize_path(raw_dir)
	end

	return util.normalize_path(util.join_path(cwd, raw_dir))
end

local function default_session_filename(session_dir)
	local date = util.today()
	local base = string.format("session-%s", date)
	local index = 1

	while true do
		local suffix = index == 1 and "" or string.format("-%02d", index)
		local candidate = util.join_path(session_dir, base .. suffix .. ".md")

		if not util.file_exists(candidate) then
			return candidate
		end

		index = index + 1
	end
end

local function resolve_target_path(session_dir, name)
	local raw_name = util.trim(name or "")

	if raw_name == "" then
		return default_session_filename(session_dir)
	end

	if raw_name:sub(-1) == "/" then
		return nil, "session filename cannot end with '/'"
	end

	if not raw_name:match("%.md$") then
		raw_name = raw_name .. ".md"
	end

	if util.is_absolute_path(raw_name) then
		return util.normalize_path(raw_name)
	end

	return util.normalize_path(util.join_path(session_dir, raw_name))
end

function M.new_session(name)
	local cfg = config.get()
	local session_cfg = cfg.session or {}
	local session_dir = resolve_session_dir(session_cfg)

	local mkdir_ok = vim.fn.mkdir(session_dir, "p")

	if mkdir_ok == 0 and vim.fn.isdirectory(session_dir) ~= 1 then
		return nil, string.format("failed to create session directory: %s", session_dir)
	end

	local target_path, path_err = resolve_target_path(session_dir, name)

	if not target_path then
		return nil, path_err
	end

	if util.file_exists(target_path) then
		return nil, string.format("session file already exists: %s", target_path)
	end

	local parent_dir = util.dirname(target_path)
	local parent_ok = vim.fn.mkdir(parent_dir, "p")

	if parent_ok == 0 and vim.fn.isdirectory(parent_dir) ~= 1 then
		return nil, string.format("failed to create parent directory: %s", parent_dir)
	end

	local lines = build_frontmatter_lines(session_cfg)
	local write_ok, write_err = pcall(vim.fn.writefile, lines, target_path)

	if not write_ok then
		return nil, string.format("failed to write session file: %s", tostring(write_err))
	end

	vim.cmd.edit(vim.fn.fnameescape(target_path))
	vim.notify(string.format("elicit.nvim: created session %s", target_path), vim.log.levels.INFO)

	return target_path
end

return M
