local config = require("elicit.config")
local util = require("elicit.util")

local M = {}

local function is_list(value)
	if type(value) ~= "table" then
		return false
	end

	if vim.islist then
		return vim.islist(value)
	end

	if vim.tbl_islist then
		return vim.tbl_islist(value)
	end

	local max_index = 0

	for key, _ in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end

		if key > max_index then
			max_index = key
		end
	end

	for index = 1, max_index do
		if value[index] == nil then
			return false
		end
	end

	return true
end

local function normalize_aliases(value, label)
	local out = {}
	local seen = {}
	local label_key = string.lower(label)

	if type(value) == "string" then
		value = { value }
	end

	if type(value) ~= "table" then
		return out
	end

	local function push(alias)
		local normalized = util.trim(tostring(alias or ""))

		if normalized == "" then
			return
		end

		local key = string.lower(normalized)

		if key == label_key or seen[key] then
			return
		end

		seen[key] = true
		table.insert(out, normalized)
	end

	if is_list(value) then
		for _, alias in ipairs(value) do
			push(alias)
		end
	else
		for _, alias in pairs(value) do
			push(alias)
		end
	end

	return out
end

local function normalize_entry(raw)
	local entry

	if type(raw) == "string" then
		entry = { label = raw }
	elseif type(raw) == "table" then
		if raw.label ~= nil then
			entry = raw
		elseif is_list(raw) then
			entry = {
				label = raw[1],
				description = raw[2],
				aliases = raw[3],
			}
		else
			return nil
		end
	else
		return nil
	end

	local label = util.trim(tostring(entry.label or ""))

	if label == "" then
		return nil
	end

	local description = util.trim(tostring(entry.description or ""))

	if description == "" then
		description = nil
	end

	return {
		label = label,
		description = description,
		aliases = normalize_aliases(entry.aliases, label),
	}
end

local function normalize_entries(value, source)
	local out = {}

	if type(value) ~= "table" then
		return out
	end

	if is_list(value) then
		for _, item in ipairs(value) do
			local normalized = normalize_entry(item)

			if normalized then
				normalized.source = source
				table.insert(out, normalized)
			end
		end

		return out
	end

	local labels = {}

	for label, _ in pairs(value) do
		table.insert(labels, tostring(label))
	end

	table.sort(labels)

	for _, label in ipairs(labels) do
		local item = value[label]
		local normalized

		if type(item) == "table" and item.label == nil then
			local merged = vim.deepcopy(item)
			merged.label = label
			normalized = normalize_entry(merged)
		elseif type(item) == "string" then
			normalized = normalize_entry({ label = label, description = item })
		else
			normalized = normalize_entry(item)
		end

		if normalized then
			normalized.source = source
			table.insert(out, normalized)
		end
	end

	return out
end

local function resolve_abbrev_cfg()
	local cfg = config.get()
	return cfg.abbreviations or {}
end

local function resolve_mode(abbrev_cfg)
	local mode = string.lower(util.trim(tostring(abbrev_cfg.mode or "extend")))

	if mode == "replace" then
		return "replace"
	end

	return "extend"
end

local function resolve_project_path(path)
	local raw = util.trim(tostring(path or ""))

	if raw == "" then
		return nil
	end

	if util.is_absolute_path(raw) then
		return util.normalize_path(raw)
	end

	return util.normalize_path(util.join_path(vim.fn.getcwd(), raw))
end

local function decode_json(content)
	if vim.json and vim.json.decode then
		return pcall(vim.json.decode, content)
	end

	return pcall(vim.fn.json_decode, content)
end

local function project_entries(abbrev_cfg)
	local path = resolve_project_path(abbrev_cfg.path)

	if not path or not util.file_exists(path) then
		return {}
	end

	if not string.lower(path):match("%.json$") then
		return {}, string.format("abbreviations.path must be a .json file: %s", path)
	end

	local read_ok, lines = pcall(vim.fn.readfile, path)

	if not read_ok then
		return {}, string.format("failed to read abbreviations.path: %s", tostring(lines))
	end

	local decode_ok, decoded = decode_json(table.concat(lines, "\n"))

	if not decode_ok or type(decoded) ~= "table" then
		return {}, string.format("failed to parse abbreviations.path as JSON: %s", path)
	end

	return normalize_entries(decoded, "project")
end

local function leipzig_entries(abbrev_cfg)
	if abbrev_cfg.use_leipzig == false or resolve_mode(abbrev_cfg) == "replace" then
		return {}
	end

	local ok, data = pcall(require, "elicit.data.leipzig")

	if not ok then
		return {}, tostring(data)
	end

	return normalize_entries(data, "leipzig")
end

local function merge_entries(sets)
	local merged = {}
	local key_to_index = {}

	for _, entries in ipairs(sets) do
		for _, entry in ipairs(entries) do
			local key = string.lower(entry.label)
			local existing = key_to_index[key]
			local value = vim.deepcopy(entry)

			if existing then
				merged[existing] = value
			else
				key_to_index[key] = #merged + 1
				table.insert(merged, value)
			end
		end
	end

	return merged
end

local function build_separator_set(abbrev_cfg)
	local out = {}
	local separators = abbrev_cfg.separators

	if type(separators) ~= "table" then
		separators = config.defaults.abbreviations.separators or {}
	end

	for _, separator in pairs(separators) do
		local value = tostring(separator or "")

		for index = 1, #value do
			out[value:sub(index, index)] = true
		end
	end

	return out
end

local function build_gloss_field_set(abbrev_cfg)
	local out = {}
	local fields = abbrev_cfg.gloss_fields

	if type(fields) ~= "table" then
		fields = config.defaults.abbreviations.gloss_fields or { "Gloss" }
	end

	for _, field in pairs(fields) do
		local normalized = string.lower(util.trim(tostring(field or "")))

		if normalized ~= "" then
			out[normalized] = true
		end
	end

	return out
end

local function resolve_position(bufnr, row, col)
	local current = bufnr or 0
	local cursor = vim.api.nvim_win_get_cursor(0)

	return current, row or cursor[1], col or cursor[2]
end

local function line_context(bufnr, row, col, abbrev_cfg)
	local current, resolved_row, resolved_col = resolve_position(bufnr, row, col)
	local line_count = vim.api.nvim_buf_line_count(current)

	if resolved_row < 1 or resolved_row > line_count then
		return nil
	end

	local line = vim.api.nvim_buf_get_lines(current, resolved_row - 1, resolved_row, false)[1] or ""
	local field_name = line:match("^%-%s*([^:]+):")

	if not field_name then
		return nil
	end

	local normalized_field = string.lower(util.trim(field_name))

	if not build_gloss_field_set(abbrev_cfg)[normalized_field] then
		return nil
	end

	local colon_index = line:find(":", 1, true)

	if not colon_index then
		return nil
	end

	local bounded_col = math.max(0, math.min(resolved_col, #line))

	return {
		line = line,
		row = resolved_row,
		col = bounded_col,
		colon = colon_index,
	}
end

local function starts_with_ignore_case(value, prefix)
	return string.lower(value):sub(1, #prefix) == prefix
end

function M.entries()
	local abbrev_cfg = resolve_abbrev_cfg()
	local leipzig, leipzig_err = leipzig_entries(abbrev_cfg)
	local extra = normalize_entries(abbrev_cfg.extra or {}, "extra")
	local project, project_err = project_entries(abbrev_cfg)
	local merged = merge_entries({ leipzig, extra, project })
	local err

	if leipzig_err and project_err then
		err = string.format("%s; %s", leipzig_err, project_err)
	elseif leipzig_err then
		err = leipzig_err
	elseif project_err then
		err = project_err
	end

	return merged, err
end

function M.matches(prefix)
	local entries, err = M.entries()
	local needle = string.lower(util.trim(tostring(prefix or "")))
	local out = {}

	for _, entry in ipairs(entries) do
		local include = needle == "" or starts_with_ignore_case(entry.label, needle)

		if not include then
			for _, alias in ipairs(entry.aliases or {}) do
				if starts_with_ignore_case(alias, needle) then
					include = true
					break
				end
			end
		end

		if include then
			table.insert(out, entry)
		end
	end

	return out, err
end

function M.in_gloss_context(bufnr, row, col)
	local state = line_context(bufnr, row, col, resolve_abbrev_cfg())

	if not state then
		return false
	end

	return state.col >= state.colon
end

function M.current_prefix(bufnr, row, col)
	local abbrev_cfg = resolve_abbrev_cfg()
	local state = line_context(bufnr, row, col, abbrev_cfg)

	if not state or state.col < state.colon then
		return ""
	end

	local segment = state.line:sub(state.colon + 1, state.col)
	local separators = build_separator_set(abbrev_cfg)
	local start_index = 1

	for index = #segment, 1, -1 do
		if separators[segment:sub(index, index)] then
			start_index = index + 1
			break
		end
	end

	return util.trim(segment:sub(start_index))
end

return M
