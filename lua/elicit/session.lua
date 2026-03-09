local config = require("elicit.config")
local parser = require("elicit.parser")
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

local function resolve_session_cfg()
	local cfg = config.get()
	return cfg.session or {}
end

local function frontmatter_fields(session_cfg)
	local fields = session_cfg.fields or {}
	local defaults = session_cfg.defaults or {}
	local out = {}

	for _, field in ipairs(fields) do
		local value = default_value(field, defaults)

		table.insert(out, {
			name = field,
			scalar = yaml_scalar(value),
		})
	end

	return out
end

local function build_frontmatter_lines(session_cfg)
	local lines = { "---" }

	for _, field in ipairs(frontmatter_fields(session_cfg)) do
		table.insert(lines, string.format("%s: %s", field.name, field.scalar))
	end

	table.insert(lines, "---")
	table.insert(lines, "")

	return lines
end

local function check_buffer_writable(bufnr)
	if not vim.bo[bufnr].modifiable then
		return nil, "current buffer is not modifiable"
	end

	if vim.bo[bufnr].readonly then
		return nil, "current buffer is readonly"
	end

	return true
end

local function prepare_snippet_position(bufnr)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""

	if line_count == 1 and first_line == "" then
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		return true
	end

	if util.trim(first_line) == "" then
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		return true
	end

	vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })

	return true
end

local function prepend_frontmatter_lines(lines)
	local bufnr = 0
	local writable, writable_err = check_buffer_writable(bufnr)

	if not writable then
		return nil, writable_err
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
	local payload = vim.deepcopy(lines)

	if line_count == 1 and first_line == "" then
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, payload)
	else
		if util.trim(first_line) == "" and payload[#payload] == "" then
			table.remove(payload, #payload)
		end

		vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, payload)
	end

	local cursor_line = math.min(#payload >= 2 and 2 or 1, vim.api.nvim_buf_line_count(bufnr))
	vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })

	return true
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

function M.frontmatter_fields(session_cfg_override)
	local session_cfg = session_cfg_override or resolve_session_cfg()
	return frontmatter_fields(session_cfg)
end

function M.frontmatter_lines(session_cfg_override)
	local session_cfg = session_cfg_override or resolve_session_cfg()
	return build_frontmatter_lines(session_cfg)
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

function M.init_session()
	local bufnr = 0
	local writable, writable_err = check_buffer_writable(bufnr)

	if not writable then
		return nil, writable_err
	end

	local parsed = parser.parse_buffer(bufnr)

	if parsed.frontmatter and parsed.frontmatter.error then
		return nil, parsed.frontmatter.error
	end

	if parsed.frontmatter and parsed.frontmatter.found then
		return nil, "current buffer already has frontmatter"
	end

	local cfg = config.get()
	local session_cfg = cfg.session or {}
	local snippet_cfg = session_cfg.luasnip or {}

	if snippet_cfg.enable then
		local ok, integration = pcall(require, "elicit.luasnip")

		if ok then
			local changedtick_before = vim.api.nvim_buf_get_changedtick(bufnr)
			prepare_snippet_position(bufnr)

			local expanded, expand_err = integration.expand_session()

			if expanded then
				vim.notify("elicit.nvim: initialized session frontmatter", vim.log.levels.INFO)
				return true
			end

			vim.notify(
				string.format("elicit.nvim: LuaSnip expand failed (%s), falling back", expand_err or "unknown"),
				vim.log.levels.WARN
			)

			if vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick_before then
				local undo_ok = pcall(vim.cmd, "silent! undo")

				if not undo_ok then
					return nil, "LuaSnip expand failed and undo failed"
				end
			end
		end
	end

	local lines = build_frontmatter_lines(session_cfg)
	local inserted, insert_err = prepend_frontmatter_lines(lines)

	if not inserted then
		return nil, insert_err
	end

	vim.notify("elicit.nvim: initialized session frontmatter", vim.log.levels.INFO)

	return true
end

return M
