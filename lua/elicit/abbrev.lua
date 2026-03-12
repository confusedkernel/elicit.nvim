local config = require("elicit.config")
local util = require("elicit.util")

local M = {}

local is_list = vim.islist or vim.tbl_islist

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

	for _, alias in pairs(value) do
		local normalized = util.to_trimmed_string(alias)

		if normalized ~= "" then
			local key = string.lower(normalized)

			if key ~= label_key and not seen[key] then
				seen[key] = true
				table.insert(out, normalized)
			end
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

	local label = util.to_trimmed_string(entry.label)

	if label == "" then
		return nil
	end

	local description = util.to_trimmed_string(entry.description)

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

	local labels = vim.tbl_map(tostring, vim.tbl_keys(value))
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
	local mode = string.lower(util.to_trimmed_string(abbrev_cfg.mode or "extend"))

	if mode == "replace" then
		return "replace"
	end

	return "extend"
end

local function resolve_project_path(path)
	local raw = util.to_trimmed_string(path)

	if raw == "" then
		return nil
	end

	if util.is_absolute_path(raw) then
		return util.normalize_path(raw)
	end

	return util.normalize_path(util.join_path(vim.fn.getcwd(), raw))
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

	local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))

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

local function build_set_from(values, defaults, transform)
	if type(values) ~= "table" then
		values = defaults or {}
	end

	local out = {}

	for _, v in pairs(values) do
		local key = transform(tostring(v or ""))

		if key ~= "" then
			out[key] = true
		end
	end

	return out
end

local function build_separator_set(abbrev_cfg)
	local values = abbrev_cfg.separators

	if type(values) ~= "table" then
		values = config.defaults.abbreviations.separators or {}
	end

	local out = {}

	for _, separator in pairs(values) do
		local str = tostring(separator or "")

		for i = 1, #str do
			out[str:sub(i, i)] = true
		end
	end

	return out
end

local function build_gloss_field_set(abbrev_cfg)
	return build_set_from(
		abbrev_cfg.gloss_fields,
		config.defaults.abbreviations.gloss_fields or { "Gloss" },
		function(v) return string.lower(util.trim(v)) end
	)
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

local _cache = { tick = nil, result = nil, err = nil }

function M.invalidate()
	_cache = { tick = nil, result = nil, err = nil }
end

function M.entries()
	local tick = vim.b.changedtick
	if _cache.result and _cache.tick == tick then
		return _cache.result, _cache.err
	end

	local abbrev_cfg = resolve_abbrev_cfg()
	local leipzig, leipzig_err = leipzig_entries(abbrev_cfg)
	local extra = normalize_entries(abbrev_cfg.extra or {}, "extra")
	local project, project_err = project_entries(abbrev_cfg)
	local merged = merge_entries({ leipzig, extra, project })

	local errs = {}
	if leipzig_err then table.insert(errs, leipzig_err) end
	if project_err then table.insert(errs, project_err) end
	local err = #errs > 0 and table.concat(errs, "; ") or nil

	_cache = { tick = tick, result = merged, err = err }

	return merged, err
end

function M.matches(prefix)
	local entries, err = M.entries()
	local needle = string.lower(util.to_trimmed_string(prefix))
	local out = {}

	for _, entry in ipairs(entries) do
		local include = needle == "" or util.starts_with_ignore_case(entry.label, needle)

		if not include then
			for _, alias in ipairs(entry.aliases or {}) do
				if util.starts_with_ignore_case(alias, needle) then
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
