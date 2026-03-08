local util = require("elicit.util")

local M = {}

local function parse_list(raw)
	local inner = util.trim(raw:sub(2, -2))

	if inner == "" then
		return {}
	end

	local out = {}

	for item in string.gmatch(inner, "([^,]+)") do
		local value = util.trim(item)
		value = value:gsub('^"(.*)"$', "%1")
		value = value:gsub("^'(.*)'$", "%1")
		table.insert(out, value)
	end

	return out
end

local function parse_scalar(raw)
	local value = util.trim(raw)

	if value == "" then
		return ""
	end

	if value == "true" then
		return true
	end

	if value == "false" then
		return false
	end

	if value == "[]" then
		return {}
	end

	if value:match("^%[.*%]$") then
		return parse_list(value)
	end

	if value:match('^".*"$') then
		return value:sub(2, -2)
	end

	if value:match("^'.*'$") then
		return value:sub(2, -2)
	end

	local numeric = tonumber(value)

	if numeric then
		return numeric
	end

	return value
end

function M.parse_frontmatter(lines)
	if lines[1] ~= "---" then
		return {
			found = false,
			start_line = nil,
			end_line = nil,
			data = {},
		}
	end

	local close_line = nil

	for i = 2, #lines do
		if util.trim(lines[i]) == "---" then
			close_line = i
			break
		end
	end

	if not close_line then
		return {
			found = false,
			start_line = 1,
			end_line = nil,
			data = {},
			error = "frontmatter start marker found without a closing marker",
		}
	end

	local data = {}

	for i = 2, close_line - 1 do
		local key, raw = lines[i]:match("^([%w_%-]+):%s*(.-)%s*$")

		if key then
			data[key] = parse_scalar(raw)
		end
	end

	return {
		found = true,
		start_line = 1,
		end_line = close_line,
		data = data,
	}
end

function M.parse_examples(lines)
	local examples = {}
	local i = 1

	while i <= #lines do
		local heading = lines[i]:match("^##%s+(.+)$")

		if not heading then
			i = i + 1
		else
			local block = {
				id = util.trim(heading),
				start_line = i,
				end_line = i,
				fields = {},
				field_lines = {},
			}

			i = i + 1

			while i <= #lines and not lines[i]:match("^##%s+") do
				local field, value = lines[i]:match("^%-%s*([^:]+):%s*(.*)$")

				if field then
					local name = util.trim(field)
					block.fields[name] = value or ""
					block.field_lines[name] = i
				end

				block.end_line = i
				i = i + 1
			end

			table.insert(examples, block)
		end
	end

	return examples
end

function M.parse_lines(lines, path)
	local frontmatter = M.parse_frontmatter(lines)
	local examples = M.parse_examples(lines)

	return {
		path = path,
		lines = lines,
		frontmatter = frontmatter,
		examples = examples,
	}
end

function M.parse_buffer(bufnr)
	local current = bufnr or 0
	local lines = vim.api.nvim_buf_get_lines(current, 0, -1, false)
	local path = vim.api.nvim_buf_get_name(current)
	local parsed = M.parse_lines(lines, path)

	parsed.bufnr = current

	return parsed
end

function M.parse_file(path)
	local ok, lines = pcall(vim.fn.readfile, path)

	if not ok then
		return nil, lines
	end

	return M.parse_lines(lines, path)
end

return M
