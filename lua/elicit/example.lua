local config = require("elicit.config")
local parser = require("elicit.parser")
local util = require("elicit.util")

local M = {}

local function default_example_field_value(field_name, example_cfg)
	local lowered = string.lower(field_name)

	if lowered == "status" then
		local cycle = example_cfg.status_cycle or {}
		return cycle[1] or "draft"
	end

	return ""
end

local function normalize_language_id(frontmatter_data)
	local raw = frontmatter_data.language
	local value = util.trim(type(raw) == "string" and raw or tostring(raw or ""))

	if value == "" then
		return "LID"
	end

	value = value:gsub("%s+", "-")
	value = value:gsub("[^%w_%-]", "")
	value = value:upper()

	if value == "" then
		return "LID"
	end

	return value
end

local function normalize_compact_date(frontmatter_data)
	local raw = frontmatter_data.date
	local value = util.trim(type(raw) == "string" and raw or tostring(raw or ""))
	local digits = value:gsub("%D", "")

	if #digits >= 8 then
		return digits:sub(1, 8)
	end

	return os.date("%Y%m%d")
end

local function build_counter_pattern(format_string)
	local i = 1
	local parts = { "^" }
	local has_counter = false

	while i <= #format_string do
		if format_string:sub(i, i + 2) == "LID" then
			table.insert(parts, ".-")
			i = i + 3
		elseif format_string:sub(i, i + 7) == "YYYYMMDD" then
			table.insert(parts, "%d%d%d%d%d%d%d%d")
			i = i + 8
		else
			local run = format_string:match("^N+", i)

			if run then
				if not has_counter then
					table.insert(parts, "(%d+)")
					has_counter = true
				else
					table.insert(parts, "%d+")
				end

				i = i + #run
			else
				local char = format_string:sub(i, i)
				table.insert(parts, util.escape_lua_pattern(char))
				i = i + 1
			end
		end
	end

	table.insert(parts, "$")

	return table.concat(parts), has_counter
end

local function next_counter_from_examples(example_cfg, examples)
	local format_string = example_cfg.id_format or "LID-YYYYMMDD-NNN"
	local pattern, has_counter = build_counter_pattern(format_string)

	if not has_counter then
		return nil
	end

	local max_counter = 0

	for _, example in ipairs(examples or {}) do
		local captured = tostring(example.id or ""):match(pattern)
		local value = tonumber(captured)

		if value and value > max_counter then
			max_counter = value
		end
	end

	return max_counter + 1
end

local function format_example_id(example_cfg, tokens, counter)
	local format_string = example_cfg.id_format or "LID-YYYYMMDD-NNN"
	local counter_index = 0
	local counter_replacements = {}

	local template = format_string:gsub("N+", function(run)
		counter_index = counter_index + 1

		if counter ~= nil then
			counter_replacements[counter_index] = string.format("%0" .. #run .. "d", counter)
		else
			counter_replacements[counter_index] = run
		end

		return string.format("@@ELICIT_COUNTER_%d@@", counter_index)
	end)

	template = template:gsub("LID", tokens.lid)
	template = template:gsub("YYYYMMDD", tokens.yyyymmdd)

	template = template:gsub("@@ELICIT_COUNTER_(%d+)@@", function(index)
		return counter_replacements[tonumber(index)] or ""
	end)

	return template
end

local function build_example_block_lines(example_id, example_cfg)
	local lines = { string.format("## %s", example_id) }
	local fields = example_cfg.fields or {}

	for _, field in ipairs(fields) do
		local value = default_example_field_value(field, example_cfg)

		if value == "" then
			table.insert(lines, string.format("- %s:", field))
		else
			table.insert(lines, string.format("- %s: %s", field, value))
		end
	end

	return lines
end

local function line_at(bufnr, index)
	if index < 0 then
		return nil
	end

	local out = vim.api.nvim_buf_get_lines(bufnr, index, index + 1, false)

	if #out == 0 then
		return nil
	end

	return out[1]
end

local function insert_lines_in_buffer(lines, parsed)
	local bufnr = 0

	if not vim.bo[bufnr].modifiable then
		return nil, "current buffer is not modifiable"
	end

	if vim.bo[bufnr].readonly then
		return nil, "current buffer is readonly"
	end

	local current_cursor = vim.api.nvim_win_get_cursor(0)
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
	local start_index = current_cursor[1]
	local block_lines = vim.deepcopy(lines)

	if parsed.frontmatter and parsed.frontmatter.found and parsed.frontmatter.end_line then
		if current_cursor[1] <= parsed.frontmatter.end_line then
			start_index = parsed.frontmatter.end_line
		end
	end

	if line_count == 1 and first_line == "" then
		start_index = 0
		vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, block_lines)
	else
		local previous_line = line_at(bufnr, start_index - 1) or ""
		local next_line = line_at(bufnr, start_index)
		local payload = {}

		if util.trim(previous_line) ~= "" then
			table.insert(payload, "")
		end

		for _, line in ipairs(block_lines) do
			table.insert(payload, line)
		end

		if next_line ~= nil and util.trim(next_line) ~= "" then
			table.insert(payload, "")
		end

		block_lines = payload
		vim.api.nvim_buf_set_lines(bufnr, start_index, start_index, false, payload)
	end

	local heading_offset = 1

	if block_lines[1] == "" then
		heading_offset = 2
	end

	vim.api.nvim_win_set_cursor(0, { start_index + heading_offset, 0 })

	return true
end

function M.insert_example()
	local cfg = config.get()
	local example_cfg = cfg.example or {}
	local parsed = parser.parse_buffer(0)
	local frontmatter_data = parsed.frontmatter and parsed.frontmatter.data or {}
	local lid = normalize_language_id(frontmatter_data)
	local yyyymmdd = normalize_compact_date(frontmatter_data)
	local counter = next_counter_from_examples(example_cfg, parsed.examples)
	local example_id = format_example_id(example_cfg, {
		lid = lid,
		yyyymmdd = yyyymmdd,
	}, counter)
	local block_lines = build_example_block_lines(example_id, example_cfg)
	local ok, err = insert_lines_in_buffer(block_lines, parsed)

	if not ok then
		return nil, err
	end

	vim.notify(string.format("elicit.nvim: inserted %s", example_id), vim.log.levels.INFO)

	return example_id
end

return M
