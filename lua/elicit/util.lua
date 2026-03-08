local M = {}

local LUA_PATTERN_MAGIC = "([%(%)%.%%%+%-%*%?%[%]%^%$])"

function M.trim(value)
	if value == nil then
		return ""
	end

	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

function M.join_path(...)
	local parts = { ... }
	local cleaned = {}

	for _, part in ipairs(parts) do
		if part and part ~= "" then
			local normalized = part:gsub("/+$", "")
			table.insert(cleaned, normalized)
		end
	end

	return table.concat(cleaned, "/")
end

function M.escape_lua_pattern(text)
	return (tostring(text or ""):gsub(LUA_PATTERN_MAGIC, "%%%1"))
end

function M.is_absolute_path(path)
	local value = tostring(path or "")

	if value == "" then
		return false
	end

	if value:sub(1, 1) == "/" then
		return true
	end

	if value:match("^%a:[/\\]") then
		return true
	end

	return false
end

function M.normalize_path(path)
	local normalized = vim.fn.fnamemodify(path, ":p")

	if #normalized > 1 then
		normalized = normalized:gsub("/+$", "")
	end

	return normalized
end

function M.dirname(path)
	return vim.fn.fnamemodify(path, ":h")
end

function M.file_exists(path)
	return vim.fn.filereadable(path) == 1
end

function M.split_words(text)
	local out = {}

	for word in string.gmatch(text or "", "%S+") do
		table.insert(out, word)
	end

	return out
end

function M.concat_from(list, index, separator)
	local out = {}

	for i = index, #list do
		table.insert(out, list[i])
	end

	return table.concat(out, separator or " ")
end

function M.to_set(list)
	local out = {}

	for _, item in ipairs(list or {}) do
		out[item] = true
	end

	return out
end

function M.today()
	return os.date("%Y-%m-%d")
end

return M
