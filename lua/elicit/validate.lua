local config = require("elicit.config")
local parser = require("elicit.parser")
local util = require("elicit.util")

local M = {}

local function is_list(value)
	if vim.islist then
		return vim.islist(value)
	end

	if vim.tbl_islist then
		return vim.tbl_islist(value)
	end

	return false
end

local function normalize_list(values)
	if type(values) ~= "table" then
		return {}
	end

	if not is_list(values) then
		return {}
	end

	return values
end

local function split_tokens(value, delimiter)
	local text = util.trim(tostring(value or ""))

	if text == "" then
		return {}
	end

	local pattern = tostring(delimiter or "%s+")
	local ok, match_start, match_end = pcall(string.find, "", pattern)

	if not ok then
		return nil, string.format("invalid validation.delimiter pattern '%s'", pattern)
	end

	if match_start and match_end then
		return nil, "validation.delimiter pattern cannot match empty text"
	end

	local tokens = {}
	local index = 1

	while true do
		local found_ok, start_pos, end_pos = pcall(string.find, text, pattern, index)

		if not found_ok then
			return nil, string.format("invalid validation.delimiter pattern '%s'", pattern)
		end

		if not start_pos then
			local tail = util.trim(text:sub(index))

			if tail ~= "" then
				table.insert(tokens, tail)
			end

			break
		end

		local token = util.trim(text:sub(index, start_pos - 1))

		if token ~= "" then
			table.insert(tokens, token)
		end

		index = end_pos + 1

		if index > #text then
			break
		end
	end

	return tokens
end

local function find_placeholder_marker(value, placeholders)
	local text = tostring(value or "")
	local lowered_text = text:lower()
	local question_token = lowered_text:match("%f[%S]%?%f[%s]") or lowered_text:match("^%?%f[%s]") or lowered_text:match("%f[%S]%?$")

	for _, marker in ipairs(placeholders) do
		local trimmed = util.trim(tostring(marker))

		if trimmed ~= "" then
			local lowered_marker = trimmed:lower()

			if lowered_marker == "?" then
				if util.trim(lowered_text) == "?" or question_token then
					return trimmed
				end
			elseif lowered_marker:match("^%w+$") then
				local token_pattern = "%f[%w]" .. util.escape_lua_pattern(lowered_marker) .. "%f[^%w]"

				if lowered_text:match(token_pattern) then
					return trimmed
				end
			elseif lowered_text:find(lowered_marker, 1, true) then
				return trimmed
			end
		end
	end

	return nil
end

local function push_issue(issues, bufnr, lnum, message, issue_type)
	table.insert(issues, {
		bufnr = bufnr,
		lnum = lnum,
		col = 1,
		text = message,
		type = issue_type,
	})
end

local function each_example_field(example, example_cfg, callback)
	local seen = {}

	for _, field_name in ipairs(example_cfg.fields or {}) do
		if example.fields[field_name] ~= nil then
			callback(field_name, example.fields[field_name])
			seen[field_name] = true
		end
	end

	local extras = {}

	for field_name, _ in pairs(example.fields or {}) do
		if not seen[field_name] then
			table.insert(extras, field_name)
		end
	end

	table.sort(extras)

	for _, field_name in ipairs(extras) do
		callback(field_name, example.fields[field_name])
	end
end

function M.run()
	local cfg = config.get()
	local validation_cfg = cfg.validation or {}
	local example_cfg = cfg.example or {}
	local parsed = parser.parse_buffer(0)
	local delimiter = validation_cfg.delimiter or "%s+"
	local required_fields = normalize_list(example_cfg.required_fields)
	local placeholders = normalize_list(validation_cfg.placeholders)
	local issues = {}
	local bufnr = parsed.bufnr or 0

	if parsed.frontmatter and parsed.frontmatter.error then
		push_issue(issues, bufnr, parsed.frontmatter.start_line or 1, parsed.frontmatter.error, "E")
	end

	for _, example in ipairs(parsed.examples or {}) do
		local example_id = util.trim(tostring(example.id or ""))

		if example_id == "" then
			example_id = "<unknown-id>"
		end

		local segmentation = example.fields and example.fields.Segmentation or ""
		local gloss = example.fields and example.fields.Gloss or ""
		local segmentation_tokens, segmentation_err = split_tokens(segmentation, delimiter)

		if not segmentation_tokens then
			return nil, segmentation_err
		end

		local gloss_tokens, gloss_err = split_tokens(gloss, delimiter)

		if not gloss_tokens then
			return nil, gloss_err
		end

		if #segmentation_tokens ~= #gloss_tokens then
			local mismatch_line = example.field_lines.Segmentation or example.field_lines.Gloss or example.start_line
			local mismatch_message = string.format("%s: Segmentation/Gloss token count mismatch (%d vs %d)", example_id, #segmentation_tokens, #gloss_tokens)
			push_issue(issues, bufnr, mismatch_line, mismatch_message, "E")
		end

		for _, required_field in ipairs(required_fields) do
			local value = ""

			if example.fields and example.fields[required_field] ~= nil then
				value = tostring(example.fields[required_field])
			end

			if util.trim(value) == "" then
				local required_line = example.field_lines[required_field] or example.start_line
				local required_message = string.format("%s: required field '%s' is empty", example_id, required_field)
				push_issue(issues, bufnr, required_line, required_message, "E")
			end
		end

		each_example_field(example, example_cfg, function(field_name, value)
			local marker = find_placeholder_marker(value, placeholders)

			if marker then
				local field_line = example.field_lines[field_name] or example.start_line
				local marker_message = string.format("%s: placeholder '%s' found in %s", example_id, marker, field_name)
				push_issue(issues, bufnr, field_line, marker_message, "W")
			end
		end)
	end

	table.sort(issues, function(left, right)
		if left.lnum == right.lnum then
			if left.type == right.type then
				return left.text < right.text
			end

			return left.type < right.type
		end

		return left.lnum < right.lnum
	end)

	vim.fn.setqflist({}, " ", {
		title = "elicit.nvim validation",
		items = issues,
	})

	if #issues == 0 then
		pcall(vim.cmd, "cclose")
		vim.notify("elicit.nvim: validation passed (no issues found)", vim.log.levels.INFO)
		return true
	end

	vim.cmd("copen")
	vim.notify(string.format("elicit.nvim: validation found %d issue%s", #issues, #issues == 1 and "" or "s"), vim.log.levels.WARN)

	return issues
end

return M
